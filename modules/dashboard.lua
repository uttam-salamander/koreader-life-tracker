--[[--
Dashboard module for Life Tracker.
Morning check-in, filtered quests, streak meter, heatmap, and reading stats.

@module lifetracker.dashboard
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")

local Data = require("modules/data")
local Quests = require("modules/quests")
local Navigation = require("modules/navigation")
local HorizontalGroup = require("ui/widget/horizontalgroup")

local Dashboard = {}

--[[--
Show the dashboard.
@tparam table ui The UI manager reference
--]]
function Dashboard:show(ui)
    self.ui = ui
    self.user_settings = Data:loadUserSettings()
    local today = Data:getCurrentDate()

    -- Check if we need morning check-in
    if self.user_settings.today_date ~= today then
        self:showMorningCheckIn()
    else
        self:showDashboardView()
    end
end

--[[--
Show morning check-in dialog.
--]]
function Dashboard:showMorningCheckIn()
    local greeting = self:getTimeBasedGreeting()
    local buttons = {}

    for _, energy in ipairs(self.user_settings.energy_categories) do
        table.insert(buttons, {{
            text = energy,
            callback = function()
                self:setTodayEnergy(energy)
                UIManager:close(self.checkin_dialog)
                self:showDashboardView()
            end,
        }})
    end

    self.checkin_dialog = ButtonDialog:new{
        title = greeting .. "\n\n" .. _("How are you feeling today?"),
        buttons = buttons,
    }
    UIManager:show(self.checkin_dialog)
end

--[[--
Get time-based greeting.
--]]
function Dashboard:getTimeBasedGreeting()
    local hour = tonumber(os.date("%H"))
    if hour < 12 then
        return _("☀ Good Morning!")
    elseif hour < 17 then
        return _("🌤 Good Afternoon!")
    elseif hour < 21 then
        return _("🌆 Good Evening!")
    else
        return _("🌙 Good Night!")
    end
end

--[[--
Set today's energy level.
--]]
function Dashboard:setTodayEnergy(energy)
    local today = Data:getCurrentDate()
    self.user_settings.today_energy = energy
    self.user_settings.today_date = today
    Data:saveUserSettings(self.user_settings)

    -- Log the day
    local existing_log = Data:getDayLog(today) or {}
    existing_log.energy_level = energy
    existing_log.date = today
    Data:logDay(today, existing_log)
end

--[[--
Show the main dashboard view.
--]]
function Dashboard:showDashboardView()
    local screen_width = Screen:getWidth()
    local content = VerticalGroup:new{ align = "left" }

    -- Greeting and energy level
    local greeting = self:getTimeBasedGreeting()
    table.insert(content, TextWidget:new{
        text = greeting,
        face = Font:getFace("tfont", 24),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- Current energy display
    local energy_text = string.format(_("Energy: %s"), self.user_settings.today_energy or "Not set")
    table.insert(content, TextWidget:new{
        text = energy_text,
        face = Font:getFace("cfont", 16),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - Size.padding.large * 2, h = Size.line.thick },
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- Today's Quests header
    local filtered_quests = Quests:getFilteredQuestsForToday(self.user_settings.today_energy)
    local quest_header = string.format(_("Today's Quests (%d)"), #filtered_quests)
    table.insert(content, TextWidget:new{
        text = quest_header,
        face = Font:getFace("tfont", 18),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- Quest list (max 5)
    local shown = 0
    for _, quest in ipairs(filtered_quests) do
        if shown >= 5 then break end
        local status = quest.completed and "✓" or "○"
        local slot_abbr = Quests:getTimeSlotAbbr(quest.time_slot, self.user_settings.time_slots)
        local quest_text = string.format("%s [%s] %s", status, slot_abbr, quest.title)
        table.insert(content, TextWidget:new{
            text = quest_text,
            face = Font:getFace("cfont", 14),
        })
        shown = shown + 1
    end

    if #filtered_quests == 0 then
        table.insert(content, TextWidget:new{
            text = _("No quests for your energy level!"),
            face = Font:getFace("cfont", 14),
        })
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - Size.padding.large * 2, h = Size.line.thick },
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- Streak display
    local streak = self.user_settings.streak_data.current or 0
    local streak_text = string.format(_("🔥 Streak: %d days"), streak)
    table.insert(content, TextWidget:new{
        text = streak_text,
        face = Font:getFace("tfont", 18),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - Size.padding.large * 2, h = Size.line.thick },
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- Activity Heatmap header
    table.insert(content, TextWidget:new{
        text = _("Quest Activity (Last 12 Weeks)"),
        face = Font:getFace("tfont", 16),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- Heatmap
    local heatmap_widget = self:buildHeatmapWidget()
    if heatmap_widget then
        table.insert(content, heatmap_widget)
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- Legend
    table.insert(content, TextWidget:new{
        text = _("░=0  ▒=1-2  ▓=3+  completions/day"),
        face = Font:getFace("cfont", 12),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - Size.padding.large * 2, h = Size.line.thick },
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- Reading stats
    local reading_stats = self:getReadingStats()
    table.insert(content, TextWidget:new{
        text = _("📖 Today's Reading"),
        face = Font:getFace("tfont", 16),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    if reading_stats then
        local stats_text = string.format(_("Pages: %d  |  Time: %s"),
            reading_stats.pages or 0,
            self:formatReadingTime(reading_stats.time or 0)
        )
        table.insert(content, TextWidget:new{
            text = stats_text,
            face = Font:getFace("cfont", 14),
        })
        if reading_stats.current_book then
            table.insert(content, TextWidget:new{
                text = string.format(_("Currently: \"%s\""), reading_stats.current_book),
                face = Font:getFace("cfont", 12),
            })
        end
    else
        table.insert(content, TextWidget:new{
            text = _("No reading data available"),
            face = Font:getFace("cfont", 14),
        })
    end

    -- Calculate content width (leave room for navigation tabs)
    local tab_width = Navigation.TAB_WIDTH
    local content_width = screen_width - tab_width

    -- Wrap content in frame
    local padded_content = FrameContainer:new{
        width = content_width,
        height = Screen:getHeight(),
        padding = Size.padding.large,
        bordersize = 0,
        content,
    }

    -- Build navigation tabs
    local nav_tabs = Navigation:buildTabColumn("dashboard", Screen:getHeight())

    -- Main layout: content left, tabs right
    local main_layout = HorizontalGroup:new{
        align = "top",
        padded_content,
        nav_tabs,
    }

    -- Wrap in frame
    local full_screen = FrameContainer:new{
        width = screen_width,
        height = Screen:getHeight(),
        padding = 0,
        bordersize = 0,
        background = 0xFFFFFF,
        main_layout,
    }

    -- Create input container for gestures
    self.dashboard_widget = InputContainer:new{
        dimen = Screen:getSize(),
        full_screen,
    }

    -- Add swipe to navigate
    self.dashboard_widget.ges_events = {
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dashboard_widget.dimen,
            },
        },
    }

    -- Store ui reference for navigation
    local ui = self.ui

    self.dashboard_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            -- Swipe right to close
            UIManager:close(self.dashboard_widget)
            return true
        end
        return false
    end

    -- Set tab change callback
    Navigation.on_tab_change = function(tab_id)
        UIManager:close(self.dashboard_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    UIManager:show(self.dashboard_widget)
end

--[[--
Build the GitHub-style heatmap widget.
--]]
function Dashboard:buildHeatmapWidget()
    local logs = Data:loadDailyLogs()
    local today = os.time()
    local weeks = 12
    local days_per_week = 7

    -- Build heatmap string (text-based for e-ink)
    local lines = {}
    for day = 0, days_per_week - 1 do
        local row = ""
        for week = weeks - 1, 0, -1 do
            local date_time = today - (week * 7 + (6 - day)) * 86400
            local date_str = os.date("%Y-%m-%d", date_time)
            local log = logs[date_str]
            local count = 0
            if log and log.quests_completed then
                count = log.quests_completed
            end

            -- Choose character based on completion count
            if count == 0 then
                row = row .. "░"
            elseif count <= 2 then
                row = row .. "▒"
            else
                row = row .. "▓"
            end
        end
        table.insert(lines, row)
    end

    local heatmap_text = table.concat(lines, "\n")
    return TextWidget:new{
        text = heatmap_text,
        face = Font:getFace("cfont", 12),
    }
end

--[[--
Get reading statistics from KOReader.
--]]
function Dashboard:getReadingStats()
    -- Try to access KOReader's statistics plugin
    if self.ui and self.ui.statistics then
        local stats = self.ui.statistics
        local pages = 0
        local time = 0
        local current_book = nil

        if stats.getTodayPages then
            pages = stats:getTodayPages()
        end
        if stats.getTodayReadingTime then
            time = stats:getTodayReadingTime()
        end
        if self.ui.document then
            local props = self.ui.document:getProps()
            if props then
                current_book = props.title
            end
        end

        return {
            pages = pages,
            time = time,
            current_book = current_book,
        }
    end

    -- Fallback: check if we have a document open
    if self.ui and self.ui.document then
        local props = self.ui.document:getProps()
        return {
            pages = 0,
            time = 0,
            current_book = props and props.title or nil,
        }
    end

    return nil
end

--[[--
Format reading time from seconds.
--]]
function Dashboard:formatReadingTime(seconds)
    if not seconds or seconds == 0 then
        return "0m"
    end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    else
        return string.format("%dm", mins)
    end
end

return Dashboard
