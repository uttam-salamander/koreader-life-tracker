--[[--
Sleep Screen module for Life Tracker.
Displays a static dashboard as the device screensaver during sleep.

This module creates a non-interactive, battery-efficient version of the dashboard
that displays when the device goes to sleep. It shows:
- Today's greeting and quote
- Energy level
- Daily progress
- Current streak
- Activity heatmap

@module lifetracker.sleep_screen
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local HorizontalSpan = require("ui/widget/horizontalspan")

local Data = require("modules/data")
local UIConfig = require("modules/ui_config")
local ReadingStats = require("modules/reading_stats")

local SleepScreen = {}

-- Widget reference for cleanup
SleepScreen.widget = nil

--[[--
Get time-based greeting.
@treturn string Greeting message
--]]
function SleepScreen:getGreeting()
    local hour = tonumber(os.date("%H"))
    if hour < 12 then
        return _("Good Morning!")
    elseif hour < 17 then
        return _("Good Afternoon!")
    elseif hour < 21 then
        return _("Good Evening!")
    else
        return _("Good Night!")
    end
end

--[[--
Get daily quest completion statistics.
Counts ALL daily quests (not filtered by energy) to match quest list display.
@treturn table {total, completed} counts
--]]
function SleepScreen:getDailyQuestStats()
    local all_quests = Data:loadAllQuests()

    if not all_quests or not all_quests.daily then
        return { total = 0, completed = 0 }
    end

    local today = os.date("%Y-%m-%d")
    local total = #all_quests.daily
    local completed = 0

    -- Count completed quests for today
    for _, quest in ipairs(all_quests.daily) do
        if Data:isQuestCompletedOnDate(quest, today) then
            completed = completed + 1
        end
    end

    return { total = total, completed = completed }
end

--[[--
Build a compact heatmap for the sleep screen.
@tparam number width Available width
@treturn Widget Heatmap widget
--]]
function SleepScreen:buildCompactHeatmap(_width)
    local cell_size = Screen:scaleBySize(8)
    local cell_gap = Screen:scaleBySize(2)
    local weeks_to_show = 12
    local days_per_week = 7

    -- Get activity data
    local activity_data = {}

    for i = (weeks_to_show * 7 - 1), 0, -1 do
        local date = os.date("%Y-%m-%d", os.time() - i * 86400)
        local day_log = Data:getDayLog(date)
        if day_log and day_log.quest_completions then
            activity_data[date] = day_log.quest_completions
        else
            activity_data[date] = 0
        end
    end

    -- Build heatmap grid
    local rows = {}
    for day = 1, days_per_week do
        local row = HorizontalGroup:new{ align = "center" }
        for week = 1, weeks_to_show do
            local days_ago = (weeks_to_show - week) * 7 + (days_per_week - day)
            local date = os.date("%Y-%m-%d", os.time() - days_ago * 86400)
            local count = activity_data[date] or 0

            -- Determine cell color based on activity
            local bg_color
            if count == 0 then
                bg_color = Blitbuffer.COLOR_LIGHT_GRAY
            elseif count <= 2 then
                bg_color = Blitbuffer.gray(0.6)
            elseif count <= 4 then
                bg_color = Blitbuffer.gray(0.4)
            else
                bg_color = Blitbuffer.gray(0.2)
            end

            -- FrameContainer needs a child widget
            local cell = FrameContainer:new{
                width = cell_size,
                height = cell_size,
                padding = 0,
                margin = 0,
                bordersize = 0,
                background = bg_color,
                VerticalSpan:new{ width = 0 },  -- Empty child
            }

            table.insert(row, cell)
            if week < weeks_to_show then
                table.insert(row, FrameContainer:new{
                    width = cell_gap,
                    height = cell_size,
                    padding = 0,
                    margin = 0,
                    bordersize = 0,
                    background = Blitbuffer.COLOR_WHITE,
                    VerticalSpan:new{ width = 0 },  -- Empty child
                })
            end
        end
        table.insert(rows, row)
        if day < days_per_week then
            table.insert(rows, VerticalSpan:new{ width = cell_gap })
        end
    end

    -- Build vertical group from rows
    local heatmap = VerticalGroup:new{ align = "center" }
    for _, row in ipairs(rows) do
        table.insert(heatmap, row)
    end
    return heatmap
end

--[[--
Build compact reading stats for sleep screen (Today + Week).
@param content_width number Width of content area
@treturn Widget|nil Reading stats widget or nil
--]]
function SleepScreen:buildReadingStats(content_width)
    local today_db = ReadingStats:getTodayStatsFromDB()
    local week_db = ReadingStats:getWeekStatsFromDB()

    local today_pages = today_db.pages or 0
    local today_time = ReadingStats:formatTime(today_db.time or 0)
    local week_pages = week_db.pages or 0
    local week_time = ReadingStats:formatTime(week_db.time or 0)

    -- Skip if no reading data
    if today_pages == 0 and week_pages == 0 then
        return nil
    end

    local stats_group = VerticalGroup:new{align = "center"}

    table.insert(stats_group, TextWidget:new{
        text = _("Reading"),
        face = UIConfig:getFont("tfont", 16),
        fgcolor = Blitbuffer.gray(0.3),
    })
    table.insert(stats_group, VerticalSpan:new{width = Size.padding.small})

    -- Two-column layout: Today | This Week
    local half_width = math.floor(content_width / 2) - Size.padding.small

    local today_col = VerticalGroup:new{align = "center"}
    table.insert(today_col, TextWidget:new{
        text = _("Today"),
        face = UIConfig:getFont("cfont", 12),
        fgcolor = Blitbuffer.gray(0.5),
    })
    table.insert(today_col, TextWidget:new{
        text = string.format("%d pg", today_pages),
        face = UIConfig:getFont("tfont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(today_col, TextWidget:new{
        text = today_time,
        face = UIConfig:getFont("cfont", 11),
        fgcolor = Blitbuffer.gray(0.5),
    })

    local week_col = VerticalGroup:new{align = "center"}
    table.insert(week_col, TextWidget:new{
        text = _("This Week"),
        face = UIConfig:getFont("cfont", 12),
        fgcolor = Blitbuffer.gray(0.5),
    })
    table.insert(week_col, TextWidget:new{
        text = string.format("%d pg", week_pages),
        face = UIConfig:getFont("tfont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(week_col, TextWidget:new{
        text = week_time,
        face = UIConfig:getFont("cfont", 11),
        fgcolor = Blitbuffer.gray(0.5),
    })

    local row = HorizontalGroup:new{align = "center"}
    table.insert(row, CenterContainer:new{
        dimen = Geom:new{w = half_width, h = Screen:scaleBySize(50)},
        today_col,
    })
    table.insert(row, HorizontalSpan:new{width = Size.padding.default})
    table.insert(row, CenterContainer:new{
        dimen = Geom:new{w = half_width, h = Screen:scaleBySize(50)},
        week_col,
    })

    table.insert(stats_group, row)
    return stats_group
end

--[[--
Filter quests by energy level (same logic as dashboard).
@param quests table Array of quest objects
@param energy_level string Current energy level
@param today string Today's date string
@treturn table Filtered quests array
--]]
function SleepScreen:filterQuestsByEnergy(quests, energy_level, today)
    local filtered = {}
    local categories = {"Energetic", "Average", "Down"}

    -- Build energy level index (lower index = higher energy)
    local energy_index = {}
    for i, cat in ipairs(categories) do
        energy_index[cat] = i
    end

    local current_level = energy_index[energy_level] or 2  -- Default to middle
    local is_high_energy = (current_level == 1)

    for _, quest in ipairs(quests) do
        -- Skip quests that were skipped TODAY
        if quest.skipped_date == today then
            goto continue
        end

        local required_level = energy_index[quest.energy_required] or 0  -- 0 for "Any"

        -- Show if:
        -- 1. energy_required == "Any" or not set
        -- 2. High energy day (show everything)
        -- 3. Quest energy <= current energy
        if required_level == 0 or is_high_energy or required_level >= current_level then
            table.insert(filtered, quest)
        end

        ::continue::
    end

    return filtered
end

--[[--
Build the static sleep screen content.
@treturn Widget The sleep screen content widget
--]]
function SleepScreen:buildContent()
    local screen_width = Screen:getWidth()
    local content_width = screen_width - Size.padding.large * 4
    local user_settings = Data:loadUserSettings()

    local content = VerticalGroup:new{ align = "center" }

    -- ===== Greeting =====
    table.insert(content, TextWidget:new{
        text = self:getGreeting(),
        face = UIConfig:getFont("tfont", 28),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    })

    -- ===== Quote =====
    local quote = Data:getRandomQuote()
    if quote then
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        table.insert(content, TextWidget:new{
            text = "\"" .. quote .. "\"",
            face = UIConfig:getFont("cfont", 14),
            fgcolor = Blitbuffer.gray(0.4),
            max_width = content_width,
        })
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large * 2 })

    -- ===== Energy Level =====
    local today_energy = user_settings.today_energy or "Normal"
    table.insert(content, TextWidget:new{
        text = string.format(_("Energy: %s"), today_energy),
        face = UIConfig:getFont("cfont", 16),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Daily Progress =====
    local daily_stats = self:getDailyQuestStats()
    local progress_pct = daily_stats.total > 0 and (daily_stats.completed / daily_stats.total) or 0

    table.insert(content, TextWidget:new{
        text = string.format(_("Today: %d/%d quests"), daily_stats.completed, daily_stats.total),
        face = UIConfig:getFont("cfont", 16),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })

    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- Progress bar
    local progress_width = math.min(content_width * 0.8, Screen:scaleBySize(300))
    local progress_bar = ProgressWidget:new{
        width = progress_width,
        height = Screen:scaleBySize(16),
        percentage = progress_pct,
    }
    table.insert(content, CenterContainer:new{
        dimen = Geom:new{ w = content_width, h = progress_bar:getSize().h },
        progress_bar,
    })

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Reading Stats (Today + Week) =====
    local reading_stats = self:buildReadingStats(content_width)
    if reading_stats then
        table.insert(content, reading_stats)
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    end

    -- ===== Daily Quests Summary (OPTIMIZED: limit to 3 incomplete) =====
    -- Sleep screen runs on every suspend - minimize compute cost
    local all_quests = Data:loadAllQuests()
    if all_quests and all_quests.daily and #all_quests.daily > 0 then
        local today = os.date("%Y-%m-%d")
        -- today_energy already defined above

        -- Pre-compute energy context once (supports custom categories)
        local energy_categories = user_settings.energy_categories or {"Energetic", "Average", "Down"}
        local energy_index = {}
        for i, cat in ipairs(energy_categories) do
            energy_index[cat] = i
        end
        local current_level = energy_index[today_energy] or 2  -- Default to middle
        local is_high_energy = (current_level == 1)

        -- OPTIMIZED: Single pass to count and collect incomplete quests
        local incomplete_quests = {}
        local completed_count = 0
        local total_count = 0

        for _, quest in ipairs(all_quests.daily) do
            -- Skip quests that were skipped today
            if quest.skipped_date ~= today then
                -- Energy filter using index (handles custom categories)
                local required_level = energy_index[quest.energy_required] or 0  -- 0 for "Any"
                local passes = quest.energy_required == "Any" or
                               not quest.energy_required or
                               is_high_energy or
                               required_level >= current_level

                if passes then
                    total_count = total_count + 1
                    if Data:isQuestCompletedOnDate(quest, today) then
                        completed_count = completed_count + 1
                    else
                        -- Only collect up to 3 incomplete quests for display
                        if #incomplete_quests < 3 then
                            table.insert(incomplete_quests, quest)
                        end
                    end
                end
            end
        end

        if total_count > 0 then
            table.insert(content, TextWidget:new{
                text = string.format(_("Today's Quests (%d/%d)"), completed_count, total_count),
                face = UIConfig:getFont("tfont", 16),
                fgcolor = Blitbuffer.gray(0.3),
            })
            table.insert(content, VerticalSpan:new{ width = Size.padding.small })

            -- Show up to 3 incomplete quests only (battery optimization)
            for _, quest in ipairs(incomplete_quests) do
                local quest_text = "[ ] " .. (quest.title or "Untitled")
                if #quest_text > 35 then
                    quest_text = quest_text:sub(1, 32) .. "..."
                end
                table.insert(content, TextWidget:new{
                    text = quest_text,
                    face = UIConfig:getFont("cfont", 15),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
            end

            -- Show remaining count if more than 3 incomplete
            local remaining = total_count - completed_count - #incomplete_quests
            if remaining > 0 then
                table.insert(content, TextWidget:new{
                    text = string.format(_("... +%d more"), remaining),
                    face = UIConfig:getFont("cfont", 13),
                    fgcolor = Blitbuffer.gray(0.5),
                })
            elseif completed_count == total_count then
                table.insert(content, TextWidget:new{
                    text = _("✓ All done!"),
                    face = UIConfig:getFont("cfont", 15),
                    fgcolor = Blitbuffer.gray(0.4),
                })
            end
        end
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Reminders =====
    local reminders = Data:loadReminders()
    if reminders and #reminders > 0 then
        -- Filter enabled reminders
        local enabled_reminders = {}
        for _, reminder in ipairs(reminders) do
            if reminder.enabled then
                table.insert(enabled_reminders, reminder)
            end
        end

        if #enabled_reminders > 0 then
            table.insert(content, TextWidget:new{
                text = _("Reminders"),
                face = UIConfig:getFont("tfont", 14),
                fgcolor = Blitbuffer.gray(0.3),
            })
            table.insert(content, VerticalSpan:new{ width = Size.padding.small })

            -- Show up to 4 reminders
            local reminder_count = 0
            for _, reminder in ipairs(enabled_reminders) do
                if reminder_count >= 4 then break end

                local reminder_text = (reminder.time or "") .. " - " .. (reminder.message or "Reminder")

                -- Truncate long reminders
                if #reminder_text > 35 then
                    reminder_text = reminder_text:sub(1, 32) .. "..."
                end

                table.insert(content, TextWidget:new{
                    text = reminder_text,
                    face = UIConfig:getFont("cfont", 12),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
                reminder_count = reminder_count + 1
            end

            if #enabled_reminders > 4 then
                table.insert(content, TextWidget:new{
                    text = string.format(_("... and %d more"), #enabled_reminders - 4),
                    face = UIConfig:getFont("cfont", 11),
                    fgcolor = Blitbuffer.gray(0.5),
                })
            end
        end
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Separator =====
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = progress_width, h = Size.line.medium },
        background = Blitbuffer.gray(0.6),
    })

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Streak =====
    local streak = (user_settings.streak_data and user_settings.streak_data.current) or 0
    local streak_text = string.format(_("Streak: %d day%s"), streak, streak == 1 and "" or "s")

    table.insert(content, TextWidget:new{
        text = streak_text,
        face = UIConfig:getFont("tfont", 22),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    })

    -- Milestone message
    local milestone_text = nil
    if streak == 7 then
        milestone_text = _("One week strong!")
    elseif streak == 30 then
        milestone_text = _("One month champion!")
    elseif streak == 100 then
        milestone_text = _("100 days - Incredible!")
    elseif streak >= 365 then
        milestone_text = _("A year of dedication!")
    end

    if milestone_text then
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        table.insert(content, TextWidget:new{
            text = milestone_text,
            face = UIConfig:getFont("cfont", 14),
            fgcolor = Blitbuffer.gray(0.4),
        })
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large * 2 })

    -- ===== Heatmap =====
    table.insert(content, TextWidget:new{
        text = _("Activity"),
        face = UIConfig:getFont("tfont", 16),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    local heatmap = self:buildCompactHeatmap(content_width)
    table.insert(content, CenterContainer:new{
        dimen = Geom:new{ w = content_width, h = heatmap:getSize().h },
        heatmap,
    })

    table.insert(content, VerticalSpan:new{ width = Size.padding.large * 3 })

    -- ===== Time =====
    local current_time = os.date("%H:%M")
    table.insert(content, TextWidget:new{
        text = current_time,
        face = UIConfig:getFont("tfont", 36),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    })

    -- ===== Date =====
    local current_date = os.date("%A, %B %d")
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    table.insert(content, TextWidget:new{
        text = current_date,
        face = UIConfig:getFont("cfont", 16),
        fgcolor = Blitbuffer.gray(0.3),
    })

    return content
end

--[[--
Create the sleep screen widget.
This is a screensaver-style widget that intercepts all input to wake the device.
@treturn Widget The sleep screen widget
--]]
function SleepScreen:createWidget()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Build content
    local content = self:buildContent()

    -- Center content on screen
    local centered_content = CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = screen_height },
        content,
    }

    -- Wrap in frame with white background
    local frame = FrameContainer:new{
        width = screen_width,
        height = screen_height,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        centered_content,
    }

    -- Create input container that handles wake gestures
    local widget = InputContainer:new{
        name = "LifeTrackerSleepScreen",
        modal = true,  -- Stay on top
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        frame,
    }

    -- Setup tap to wake
    if Device:isTouchDevice() then
        widget.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0,
                    y = 0,
                    w = screen_width,
                    h = screen_height,
                },
            },
        }
    end

    -- Setup key to wake
    if Device:hasKeys() then
        widget.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end

    -- Handle tap - close sleep screen
    function widget:onTap()
        SleepScreen:close()
        return true
    end

    -- Handle key press - close sleep screen
    function widget:onAnyKeyPressed()
        SleepScreen:close()
        return true
    end

    -- Handle explicit close request
    function widget:onClose()
        SleepScreen:close()
        return true
    end

    -- Handle resume event (device waking up)
    function widget:onResume()
        -- Device is waking - close the sleep screen
        SleepScreen:close()
        return true
    end

    return widget
end

--[[--
Show the sleep screen.
Called when the device goes to sleep.
--]]
function SleepScreen:show()
    -- Don't show if already showing
    if self.widget then
        return
    end

    -- Create and show the widget
    self.widget = self:createWidget()
    UIManager:show(self.widget)

    -- Force a full screen refresh for e-ink
    UIManager:setDirty(self.widget, function()
        return "full", self.widget.dimen
    end)
end

--[[--
Close the sleep screen.
Called when device wakes or user taps/presses key.
--]]
function SleepScreen:close()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil

        -- Broadcast that we're out of sleep screen
        UIManager:broadcastEvent(Event:new("OutOfScreenSaver"))

        -- Full refresh to clear
        UIManager:setDirty(nil, "full")
    end
end

--[[--
Check if sleep screen is enabled in settings.
@treturn boolean True if enabled
--]]
function SleepScreen:isEnabled()
    local user_settings = Data:loadUserSettings()
    return user_settings and user_settings.sleep_screen_enabled
end

return SleepScreen
