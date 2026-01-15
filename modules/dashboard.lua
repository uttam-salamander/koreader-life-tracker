--[[--
Dashboard module for Life Tracker.
Morning check-in, filtered quests, streak meter, heatmap, and reading stats.

@module lifetracker.dashboard
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local HorizontalSpan = require("ui/widget/horizontalspan")

local Data = require("modules/data")
local Quests = require("modules/quests")
local Navigation = require("modules/navigation")
local Reminders = require("modules/reminders")
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")
local Celebration = require("modules/celebration")
local Utils = require("modules/utils")
local QuestRow = require("modules/quest_row")

local Dashboard = {}

-- Get scaled touch target sizes from UIConfig
local function getTouchTargetHeight()
    return UIConfig:dim("touch_target_height")
end

local function getEnergyTabWidth()
    return UIConfig:dim("energy_tab_width")
end

local function getEnergyTabHeight()
    return UIConfig:dim("energy_tab_height")
end

--[[--
Show the dashboard.
@tparam table ui The UI manager reference
--]]
function Dashboard:show(ui)
    self.ui = ui
    self.user_settings = Data:loadUserSettings()
    local today = Data:getCurrentDate()

    -- Update date if new day
    if self.user_settings.today_date ~= today then
        self.user_settings.today_date = today
        -- Set default energy if not set
        if not self.user_settings.today_energy then
            local categories = self.user_settings.energy_categories or {}
            self.user_settings.today_energy = categories[2] or "Normal"
        end
        Data:saveUserSettings(self.user_settings)
    end

    self:showDashboardView()
end

--[[--
Get time-based greeting.
--]]
function Dashboard:getTimeBasedGreeting()
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
@treturn table {total, completed} counts for daily quests
--]]
function Dashboard:getDailyQuestStats()
    local all_quests = Data:loadAllQuests()
    if not all_quests or not all_quests.daily then
        return { total = 0, completed = 0 }
    end

    local total = 0
    local completed = 0
    local today_energy = self.user_settings.today_energy
    local today = Data:getCurrentDate()

    -- Filter by energy and count
    local filtered = self:filterQuestsByEnergy(all_quests.daily, today_energy)
    for _, quest in ipairs(filtered) do
        total = total + 1
        -- Use date-specific completion check (not legacy quest.completed flag)
        if Data:isQuestCompletedOnDate(quest, today) then
            completed = completed + 1
        end
    end

    return { total = total, completed = completed }
end

--[[--
Set today's energy level and refresh dashboard.
Also adds a timestamped mood entry for intra-day tracking.
--]]
function Dashboard:setTodayEnergy(energy)
    local today = Data:getCurrentDate()
    self.user_settings.today_energy = energy
    self.user_settings.today_date = today
    Data:saveUserSettings(self.user_settings)

    -- Log the day (keeps current energy as display value)
    local existing_log = Data:getDayLog(today) or {}
    existing_log.energy_level = energy
    existing_log.date = today
    Data:logDay(today, existing_log)

    -- Also add timestamped mood entry for detailed tracking
    local current_hour = tonumber(os.date("%H"))
    Data:addMoodEntry(today, current_hour, energy, self.user_settings.time_slots)

    -- Refresh dashboard
    UIHelpers.closeWidget(self, "dashboard_widget")
    self:showDashboardView()

    -- Force screen refresh for e-ink
    UIManager:setDirty("all", "ui")
end

--[[--
Show the main dashboard view.
--]]
function Dashboard:showDashboardView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = UIConfig:getPaddedContentWidth()

    -- KOReader reserves top ~10% for menu gesture
    -- Title text can be in this zone (non-interactive), but gesture handlers must not be
    local top_safe_zone = UIConfig:getTopSafeZone()

    -- Track Y position for gesture handling (content starts at top with padding)
    -- Note: top_safe_zone is only for gesture exclusion, not visual layout
    self.current_y = Size.padding.large

    -- Main content group - title can be in top zone (visual only, no gestures there)
    local content = VerticalGroup:new{ align = "left" }

    -- Track visual Y position starting from frame padding
    local visual_y = Size.padding.large

    -- ===== Greeting (in top zone - non-interactive) =====
    local greeting = self:getTimeBasedGreeting()
    local greeting_widget = TextWidget:new{
        text = greeting,
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    }
    table.insert(content, greeting_widget)
    visual_y = visual_y + greeting_widget:getSize().h

    -- ===== Random Quote (below greeting) =====
    local quote = Data:getRandomQuote()
    if quote then
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        visual_y = visual_y + Size.padding.small
        local colors = UIConfig:getColors()
        local quote_widget = TextWidget:new{
            text = "\"" .. quote .. "\"",
            face = UIConfig:getFont("cfont", 14),
            fgcolor = colors.foreground,
            max_width = content_width,
        }
        table.insert(content, quote_widget)
        visual_y = visual_y + quote_widget:getSize().h
    end

    -- Add spacer to push interactive content below top_safe_zone
    local spacer_needed = top_safe_zone - visual_y
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
        visual_y = visual_y + spacer_needed
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    visual_y = visual_y + Size.padding.default

    -- All interactive content starts here (below top_safe_zone)
    self.current_y = visual_y

    -- ===== Energy Level Tabs (using Button widgets with callbacks) =====
    self.energy_tabs_y = self.current_y
    local energy_tabs = self:buildEnergyTabsVisual()
    table.insert(content, energy_tabs)
    self.current_y = self.current_y + getEnergyTabHeight()
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("md") })
    self.current_y = self.current_y + UIConfig:spacing("md")

    -- ===== Daily Progress Bar =====
    local daily_stats = self:getDailyQuestStats()
    local progress_pct = daily_stats.total > 0 and (daily_stats.completed / daily_stats.total) or 0

    -- Progress label
    table.insert(content, TextWidget:new{
        text = string.format(_("Today's Progress: %d/%d"), daily_stats.completed, daily_stats.total),
        face = Font:getFace("cfont", 13),
        fgcolor = UIConfig:color("foreground"),
    })
    self.current_y = self.current_y + 18

    -- Progress bar
    local progress_height = Screen:scaleBySize(12)
    local progress_bar = ProgressWidget:new{
        width = content_width,
        height = progress_height,
        percentage = progress_pct,
        ticks = nil,
        last = nil,
    }
    table.insert(content, progress_bar)
    self.current_y = self.current_y + progress_height
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    self.current_y = self.current_y + Size.padding.default

    -- ===== Separator =====
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    self.current_y = self.current_y + Size.line.thick
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    self.current_y = self.current_y + Size.padding.default

    -- ===== Today's Reminders =====
    local today_reminders = Reminders:getTodayReminders()
    if #today_reminders > 0 then
        table.insert(content, TextWidget:new{
            text = string.format(_("Today's Reminders (%d)"), #today_reminders),
            face = Font:getFace("tfont", 16),
            bold = true,
        })
        self.current_y = self.current_y + 24
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        self.current_y = self.current_y + Size.padding.small

        for i, reminder in ipairs(today_reminders) do
            if i > 3 then break end  -- Show max 3 on dashboard
            local time_text = reminder.time or "??:??"
            local reminder_text = string.format("%s  %s", time_text, reminder.title)
            table.insert(content, TextWidget:new{
                text = reminder_text,
                face = Font:getFace("cfont", 14),
                fgcolor = UIConfig:color("foreground"),
            })
            self.current_y = self.current_y + 20
        end
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- ===== Today's Quests by Type =====
    local all_quests = Data:loadAllQuests() or { daily = {}, weekly = {}, monthly = {} }
    local today_energy = self.user_settings.today_energy
    local time_slots = self.user_settings.time_slots or {"Morning", "Afternoon", "Evening", "Night"}

    -- Store quest list start position for tap handling
    self.quest_list_start_y = self.current_y

    -- Today's Quests section (with time slot breakdown)
    local daily_section = self:buildQuestSectionWithTimeSlots("Today's Quests", all_quests.daily or {}, today_energy, "daily", time_slots)
    if daily_section then
        table.insert(content, daily_section)
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- Weekly Quests section
    local weekly_section = self:buildQuestSection("This Week", all_quests.weekly or {}, today_energy, "weekly")
    if weekly_section then
        table.insert(content, weekly_section)
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- Monthly Quests section
    local monthly_section = self:buildQuestSection("This Month", all_quests.monthly or {}, today_energy, "monthly")
    if monthly_section then
        table.insert(content, monthly_section)
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- ===== Separator =====
    -- Section separator
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("lg") })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = UIConfig:color("muted"),
    })
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("lg") })

    -- ===== Streak Display with Milestone Celebration =====
    local streak = (self.user_settings.streak_data and self.user_settings.streak_data.current) or 0
    local streak_text = string.format(_("Streak: %d day%s"), streak, streak == 1 and "" or "s")

    -- Check for milestone celebrations
    local milestone_text = nil
    if streak == 7 then
        milestone_text = "One week strong!"
    elseif streak == 30 then
        milestone_text = "One month champion!"
    elseif streak == 100 then
        milestone_text = "100 days - Incredible!"
    elseif streak >= 365 then
        milestone_text = "A year of dedication!"
    end

    table.insert(content, TextWidget:new{
        text = streak_text,
        face = UIConfig:getFont("tfont", UIConfig:fontSize("section_header") + 2),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    })

    -- Show milestone celebration if applicable
    if milestone_text then
        table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("xs") })
        table.insert(content, TextWidget:new{
            text = milestone_text,
            face = UIConfig:getFont("cfont", UIConfig:fontSize("caption")),
            fgcolor = UIConfig:color("muted"),
        })
    end
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("lg") })

    -- ===== Heatmap =====
    table.insert(content, TextWidget:new{
        text = _("Activity (12 Weeks)"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("section_header")),
        fgcolor = UIConfig:color("foreground"),
    })
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("sm") })

    local heatmap_widget = self:buildDynamicHeatmap(content_width)
    if heatmap_widget then
        table.insert(content, heatmap_widget)
    end
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("lg") })

    -- ===== Reading Stats =====
    local reading_stats = self:getReadingStats()
    if reading_stats then
        -- Section separator
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = content_width, h = 1 },
            background = UIConfig:color("muted"),
        })
        table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("md") })
        table.insert(content, TextWidget:new{
            text = _("Today's Reading"),
            face = UIConfig:getFont("tfont", UIConfig:fontSize("section_header")),
            fgcolor = UIConfig:color("foreground"),
        })
        table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("xs") })
        local stats_text = string.format(_("Pages: %d | Time: %s"),
            reading_stats.pages or 0,
            Utils.formatReadingTime(reading_stats.time or 0)
        )
        table.insert(content, TextWidget:new{
            text = stats_text,
            face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
            fgcolor = UIConfig:color("foreground"),
        })
    end

    -- ===== Wrap content in scrollable container =====
    local scroll_width = UIConfig:getScrollWidth()
    local page_padding = UIConfig:getPagePadding()

    -- Wrap content in scrollable frame with page padding
    local inner_frame = FrameContainer:new{
        width = scroll_width,
        height = math.max(screen_height, content:getSize().h + page_padding * 2),
        padding = page_padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = scroll_width, h = screen_height},
        inner_frame,
    }
    self.scrollable_container = scrollable

    -- ===== Create main container with gestures =====
    local ui = self.ui
    local dashboard = self

    -- Tab change callback
    local function on_tab_change(tab_id)
        UIHelpers.closeWidget(dashboard, "dashboard_widget")
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("dashboard", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create the main layout with content and navigation
    -- Full-screen white background prevents underlying content from showing through scrollbar gaps
    local white_bg = FrameContainer:new{
        width = screen_width,
        height = screen_height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{},  -- Empty child required by FrameContainer
    }
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        white_bg,
        scrollable,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Standard InputContainer for gestures
    self.dashboard_widget = InputContainer:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        ges_events = {},
        main_layout,
    }

    -- Set show_parent for ScrollableContainer refresh
    self.scrollable_container.show_parent = self.dashboard_widget

    -- Store top_safe_zone for gesture handlers
    self.top_safe_zone = top_safe_zone

    -- Setup corner gesture handlers using shared helper
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = top_safe_zone,
    }
    UIHelpers.setupCornerGestures(self.dashboard_widget, self, gesture_dims)

    -- Setup swipe-to-close gesture
    UIHelpers.setupSwipeToClose(self.dashboard_widget, function()
        UIHelpers.closeWidget(dashboard, "dashboard_widget")
    end, gesture_dims)

    UIManager:show(self.dashboard_widget)
end

--[[--
Build energy tabs using Button widgets with callbacks.
Tap handling is built-in via Button callbacks - no separate gesture handlers needed.
--]]
function Dashboard:buildEnergyTabsVisual()
    local categories = self.user_settings.energy_categories or {"Low", "Normal", "Energetic"}
    local current_energy = self.user_settings.today_energy or categories[2]
    local dashboard = self

    local tabs = HorizontalGroup:new{ align = "center" }

    for _, energy in ipairs(categories) do
        local is_active = (energy == current_energy)

        -- Create a Button widget with built-in tap handling
        local energy_button = Button:new{
            text = energy,
            width = getEnergyTabWidth(),
            max_width = getEnergyTabWidth(),
            bordersize = is_active and Size.border.thick or Size.border.thin,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 16,
            text_font_bold = is_active,
            preselect = is_active,  -- Inverts display for active tab
            callback = function()
                dashboard:setTodayEnergy(energy)
            end,
        }

        table.insert(tabs, energy_button)
        table.insert(tabs, HorizontalSpan:new{ width = UIConfig:dim("row_gap") })
    end

    return tabs
end

--[[--
Build a quest section with header and quest items grouped by time slots.
Tracks Y positions for gesture handling.
--]]
function Dashboard:buildQuestSectionWithTimeSlots(title, quests, today_energy, quest_type, time_slots)
    if not quests or #quests == 0 then
        return nil
    end

    -- Filter quests by energy level
    local filtered = self:filterQuestsByEnergy(quests, today_energy)
    if #filtered == 0 then
        return nil
    end

    local section = VerticalGroup:new{ align = "left" }

    -- Section header (24px height)
    table.insert(section, TextWidget:new{
        text = string.format("%s (%d)", title, #filtered),
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    self.current_y = self.current_y + 24
    table.insert(section, VerticalSpan:new{ width = Size.padding.small })
    self.current_y = self.current_y + Size.padding.small

    -- Group quests by time slot
    local quests_by_slot = {}
    local other_quests = {}
    for _, quest in ipairs(filtered) do
        if quest.time_slot then
            if not quests_by_slot[quest.time_slot] then
                quests_by_slot[quest.time_slot] = {}
            end
            table.insert(quests_by_slot[quest.time_slot], quest)
        else
            table.insert(other_quests, quest)
        end
    end

    -- Show quests grouped by time slot
    local shown = 0
    for _, slot in ipairs(time_slots) do
        local slot_quests = quests_by_slot[slot]
        if slot_quests and #slot_quests > 0 then
            -- Time slot sub-header (18px height)
            table.insert(section, TextWidget:new{
                text = slot,
                face = Font:getFace("cfont", 12),
                fgcolor = UIConfig:color("foreground"),
            })
            self.current_y = self.current_y + 18

            for _, quest in ipairs(slot_quests) do
                if shown >= 8 then break end
                local quest_row = self:buildQuestRow(quest, quest_type)
                table.insert(section, quest_row)
                shown = shown + 1
            end
        end
    end

    -- Show quests without time slot
    if #other_quests > 0 and shown < 8 then
        for _, quest in ipairs(other_quests) do
            if shown >= 8 then break end
            local quest_row = self:buildQuestRow(quest, quest_type)
            table.insert(section, quest_row)
            shown = shown + 1
        end
    end

    return section
end

--[[--
Build a quest section with header and quest items (simple, no time slot grouping).
Tracks Y positions for gesture handling.
--]]
function Dashboard:buildQuestSection(title, quests, today_energy, quest_type)
    if not quests or #quests == 0 then
        return nil
    end

    -- Filter quests by energy level
    local filtered = self:filterQuestsByEnergy(quests, today_energy)
    if #filtered == 0 then
        return nil
    end

    local section = VerticalGroup:new{ align = "left" }

    -- Section header (24px height)
    table.insert(section, TextWidget:new{
        text = string.format("%s (%d)", title, #filtered),
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    self.current_y = self.current_y + 24
    table.insert(section, VerticalSpan:new{ width = Size.padding.small })
    self.current_y = self.current_y + Size.padding.small

    -- Quest items (max 5 per section on dashboard)
    local shown = 0
    for _, quest in ipairs(filtered) do
        if shown >= 5 then break end
        local quest_row = self:buildQuestRow(quest, quest_type)
        table.insert(section, quest_row)
        shown = shown + 1
    end

    return section
end

--[[--
Build a single quest row for the dashboard with inline OK/Skip buttons.
Uses shared QuestRow component for consistent UI across modules.
--]]
function Dashboard:buildQuestRow(quest, quest_type)
    local dashboard = self
    local content_width = UIConfig:getScrollWidth()

    local quest_row = QuestRow.build(quest, {
        quest_type = quest_type,
        content_width = content_width,
        show_streak = true,
        on_refresh = function()
            UIHelpers.closeWidget(dashboard, "dashboard_widget")
            dashboard:showDashboardView()
            UIManager:setDirty("all", "ui")
        end,
    })

    -- Update Y tracker (still needed for layout purposes)
    self.current_y = self.current_y + getTouchTargetHeight() + 2

    return quest_row
end

--[[--
Filter quests by energy level and skip status.
Shows quests that require your current energy level OR LESS.
High energy days show all quests.
Filters out quests that were skipped TODAY (they reappear tomorrow).
--]]
function Dashboard:filterQuestsByEnergy(quests, energy_level)
    local filtered = {}
    local user_settings = self.user_settings
    local categories = user_settings.energy_categories or {"Energetic", "Average", "Down"}
    local today = Data:getCurrentDate()

    -- Build energy level index (lower index = higher energy)
    local energy_index = {}
    for i, cat in ipairs(categories) do
        energy_index[cat] = i
    end

    local current_level = energy_index[energy_level] or 2  -- Default to middle
    local is_high_energy = (current_level == 1)

    for _, quest in ipairs(quests) do
        -- Skip quests that were skipped TODAY (they reappear tomorrow)
        if quest.skipped_date == today then
            goto continue
        end

        local required_level = energy_index[quest.energy_required] or 0  -- 0 for "Any"

        -- Show if:
        -- 1. energy_required == "Any" or not set
        -- 2. High energy day (show everything)
        -- 3. Required energy level >= current (i.e., requires same or less energy)
        if quest.energy_required == "Any" or
           not quest.energy_required or
           is_high_energy or
           required_level >= current_level then
            table.insert(filtered, quest)
        end

        ::continue::
    end

    return filtered
end

--[[--
Skip a quest for today.
--]]
function Dashboard:skipQuest(quest, quest_type)
    local today = Data:getCurrentDate()
    local all_quests = Data:loadAllQuests()

    for _, q in ipairs(all_quests[quest_type] or {}) do
        if q.id == quest.id then
            q.skipped_date = today
            break
        end
    end

    Data:saveAllQuests(all_quests)

    -- Refresh dashboard
    UIHelpers.closeWidget(self, "dashboard_widget")
    self:showDashboardView()

    -- Force immediate screen refresh
    UIManager:setDirty("all", "ui")

    -- Schedule feedback message for next tick
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = _("Quest skipped for today"),
            timeout = 1,
        })
    end)
end

--[[--
Increment progress for a progressive quest.
--]]
function Dashboard:incrementQuestProgress(quest, quest_type)
    local updated = Data:incrementQuestProgress(quest_type, quest.id)
    if updated then
        -- Refresh dashboard
        UIHelpers.closeWidget(self, "dashboard_widget")
        self:showDashboardView()
        UIManager:setDirty("all", "ui")

        if updated.completed then
            -- Update daily log for heatmap
            self:updateDailyLog()
            UIManager:nextTick(function()
                Celebration:showCompletion()
            end)
        end
    end
end

--[[--
Decrement progress for a progressive quest.
--]]
function Dashboard:decrementQuestProgress(quest, quest_type)
    local updated = Data:decrementQuestProgress(quest_type, quest.id)
    if updated then
        -- Refresh dashboard
        UIHelpers.closeWidget(self, "dashboard_widget")
        self:showDashboardView()
        UIManager:setDirty("all", "ui")
    end
end

--[[--
Button callback: Handle quest completion toggle.
Called when Done/X button is tapped.
--]]
function Dashboard:handleQuestComplete(quest, quest_type)
    self:toggleQuestComplete(quest, quest_type)
end

--[[--
Button callback: Handle quest skip.
Called when Skip button is tapped.
--]]
function Dashboard:handleQuestSkip(quest, quest_type)
    self:skipQuest(quest, quest_type)
end

--[[--
Button callback: Handle progressive quest minus.
Called when − button is tapped.
--]]
function Dashboard:handleProgressMinus(quest, quest_type)
    self:decrementQuestProgress(quest, quest_type)
end

--[[--
Button callback: Handle progressive quest plus.
Called when + button is tapped.
--]]
function Dashboard:handleProgressPlus(quest, quest_type)
    self:incrementQuestProgress(quest, quest_type)
end

--[[--
Update daily log with quest completion stats (for heatmap).
--]]
function Dashboard:updateDailyLog()
    local today = Data:getCurrentDate()
    local quests = Data:loadAllQuests()
    local logs = Data:loadDailyLogs()

    if not quests then return end
    if not logs then logs = {} end

    local total = 0
    local completed = 0

    for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for _, quest in ipairs(quests[quest_type] or {}) do
            total = total + 1
            -- Use date-specific completion check (not legacy flags)
            if Data:isQuestCompletedOnDate(quest, today) then
                completed = completed + 1
            end
        end
    end

    if not logs[today] then
        logs[today] = {}
    end
    logs[today].quests_total = total
    logs[today].quests_completed = completed

    Data:saveDailyLogs(logs)
end

--[[--
Show input dialog for manually setting progress.
--]]
function Dashboard:showProgressInput(quest, quest_type)
    local dialog
    dialog = InputDialog:new{
        title = string.format(_("Set Progress for '%s'"), quest.title),
        input = tostring(quest.progress_current or 0),
        input_hint = string.format(_("Target: %d %s"),
            quest.progress_target or 1,
            quest.progress_unit or ""),
        input_type = "number",
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Set"),
                is_enter_default = true,
                callback = function()
                    local value = tonumber(dialog:getInputText())
                    if value and value >= 0 then
                        local updated = Data:setQuestProgress(quest_type, quest.id, value)
                        UIManager:close(dialog)

                        -- Refresh dashboard
                        UIHelpers.closeWidget(self, "dashboard_widget")
                        self:showDashboardView()
                        UIManager:setDirty("all", "ui")

                        if updated and updated.completed then
                            self:updateDailyLog()
                            UIManager:nextTick(function()
                                Celebration:showCompletion()
                            end)
                        end
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a valid number"),
                            timeout = 2,
                        })
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Toggle quest completion status.
--]]
function Dashboard:toggleQuestComplete(quest, quest_type)
    local today = Data:getCurrentDate()
    local was_completed = Data:isQuestCompletedOnDate(quest, today)
    if was_completed then
        Data:uncompleteQuest(quest_type, quest.id)
    else
        -- Data:completeQuest handles streak calculation atomically
        Data:completeQuest(quest_type, quest.id, today)
        Quests:updateDailyLog()
        Quests:updateGlobalStreak()
    end

    -- Refresh dashboard
    UIHelpers.closeWidget(self, "dashboard_widget")
    self:showDashboardView()

    -- Force immediate screen refresh
    UIManager:setDirty("all", "ui")

    -- Schedule feedback for next tick to ensure dashboard renders first
    UIManager:nextTick(function()
        if was_completed then
            -- Was completed, now marking incomplete
            UIManager:show(InfoMessage:new{
                text = _("Quest marked incomplete"),
                timeout = 1,
            })
        else
            -- Was incomplete, now completed - show celebration!
            Celebration:showCompletion()
        end
    end)
end

--[[--
Build dynamic heatmap with categories based on actual quest data.
Uses larger font and spaced characters for e-ink readability.
@param content_width number Available width in pixels
--]]
function Dashboard:buildDynamicHeatmap(content_width)
    local logs = Data:loadDailyLogs()
    local today = os.time()
    local total_weeks = 8  -- Reduced from 12 for larger display
    local days_per_week = 7

    -- Larger font for e-ink readability
    local HEATMAP_FONT_SIZE = 18
    local LEGEND_FONT_SIZE = 14

    -- Calculate how many weeks can fit per row with spaced characters
    -- Each block char + space is roughly 24px at font 18
    local char_width = 24
    local weeks_per_row = math.max(4, math.min(math.floor(content_width / char_width), 8))

    -- Find the maximum completions in any day to set dynamic thresholds
    local max_completions = 0
    for day = 0, total_weeks * days_per_week - 1 do
        local date_time = today - day * 86400
        local date_str = os.date("%Y-%m-%d", date_time)
        local log = logs[date_str]
        if log and log.quests_completed then
            max_completions = math.max(max_completions, log.quests_completed)
        end
    end

    -- Set dynamic thresholds (4 levels)
    -- Handle max_completions == 0 explicitly to avoid division issues
    local t1, t2, t3
    if max_completions == 0 then
        -- No data yet - all cells will show as empty
        t1, t2, t3 = 1, 1, 1
    elseif max_completions <= 4 then
        t1, t2, t3 = 1, 2, 3
    else
        t1 = math.ceil(max_completions / 4)
        t2 = math.ceil(max_completions / 2)
        t3 = math.ceil(max_completions * 3 / 4)
    end

    -- Helper to get heat character for a count
    local function get_heat_char(count)
        if count == 0 then
            return "░"
        elseif count <= t1 then
            return "▒"
        elseif count <= t2 then
            return "▓"
        else
            return "█"
        end
    end

    local heatmap_group = VerticalGroup:new{ align = "left" }

    -- Build heatmap in sections (each section is weeks_per_row weeks)
    local num_sections = math.ceil(total_weeks / weeks_per_row)

    for section = 0, num_sections - 1 do
        local start_week = section * weeks_per_row
        local end_week = math.min(start_week + weeks_per_row, total_weeks) - 1

        -- Section label (e.g., "Weeks 1-6" or "Recent")
        local section_label
        if num_sections > 1 then
            local weeks_ago_end = total_weeks - start_week
            local weeks_ago_start = total_weeks - end_week - 1
            if section == num_sections - 1 then
                section_label = string.format("Recent (%d wks)", end_week - start_week + 1)
            else
                section_label = string.format("%d-%d wks ago", weeks_ago_start, weeks_ago_end)
            end
            table.insert(heatmap_group, TextWidget:new{
                text = section_label,
                face = Font:getFace("cfont", 12),
                fgcolor = UIConfig:color("foreground"),
            })
        end

        -- Build rows for this section (7 rows for days of week)
        local lines = {}
        for day = 0, days_per_week - 1 do
            local row = ""
            -- Iterate weeks from oldest to newest within this section
            for week = end_week, start_week, -1 do
                local date_time = today - (week * 7 + (6 - day)) * 86400
                local date_str = os.date("%Y-%m-%d", date_time)
                local log = logs[date_str]
                local count = 0
                if log and log.quests_completed then
                    count = log.quests_completed
                end
                -- Add space after each character for better spacing
                row = row .. get_heat_char(count) .. " "
            end
            table.insert(lines, row)
        end

        local heatmap_text = table.concat(lines, "\n")
        table.insert(heatmap_group, TextWidget:new{
            text = heatmap_text,
            face = Font:getFace("cfont", HEATMAP_FONT_SIZE),
            max_width = content_width,
        })

        -- Add spacing between sections
        if section < num_sections - 1 then
            table.insert(heatmap_group, VerticalSpan:new{ width = Size.padding.default })
        end
    end

    table.insert(heatmap_group, VerticalSpan:new{ width = Size.padding.small })

    -- Dynamic legend (larger for readability)
    local legend = string.format("░ none  ▒ 1-%d  ▓ %d-%d  █ %d+", t1, t1+1, t2, t3)
    table.insert(heatmap_group, TextWidget:new{
        text = legend,
        face = Font:getFace("cfont", LEGEND_FONT_SIZE),
        fgcolor = UIConfig:color("foreground"),
        max_width = content_width,
    })

    return heatmap_group
end

--[[--
Get reading statistics from KOReader.
--]]
function Dashboard:getReadingStats()
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

return Dashboard
