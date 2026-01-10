--[[--
Dashboard module for Life Tracker.
Morning check-in, filtered quests, streak meter, heatmap, and reading stats.

@module lifetracker.dashboard
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
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

local function getButtonWidth()
    return UIConfig:dim("button_width")
end

local function getSmallButtonWidth()
    return UIConfig:dim("small_button_width")
end

local function getProgressWidth()
    return UIConfig:dim("progress_width")
end

--[[--
Dispatch a corner gesture to the user's configured action.
KOReader stores gesture settings in the gestures module.
@tparam string gesture_name The gesture name (e.g., "tap_top_left_corner")
@treturn bool True if gesture was handled
--]]
function Dashboard:dispatchCornerGesture(gesture_name)
    -- Try to access KOReader's gesture module for user settings
    if self.ui and self.ui.gestures then
        local gesture_manager = self.ui.gestures
        -- Check if user has a gesture configured
        local settings = gesture_manager.gestures or {}
        local action = settings[gesture_name]
        if action then
            -- Dispatch the action
            local Dispatcher = require("dispatcher")
            Dispatcher:execute(action)
            return true
        end
    end

    -- Fallback: try common corner actions directly via event
    -- Users often set top-right to toggle frontlight
    if gesture_name == "tap_top_right_corner" then
        -- Toggle frontlight is common setting
        self.ui:handleEvent(Event:new("ToggleFrontlight"))
        return true
    elseif gesture_name == "tap_top_left_corner" then
        -- Bookmark toggle is another common setting
        self.ui:handleEvent(Event:new("ToggleBookmark"))
        return true
    end

    -- No action configured, let gesture pass through
    return false
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

    -- Filter by energy and count
    local filtered = self:filterQuestsByEnergy(all_quests.daily, today_energy)
    for __, quest in ipairs(filtered) do
        total = total + 1
        if quest.completed then
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
    if self.dashboard_widget then
        UIManager:close(self.dashboard_widget)
    end
    self:showDashboardView()
end

--[[--
Show the main dashboard view.
--]]
function Dashboard:showDashboardView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top 1/8 (12.5%) for menu gesture
    -- Title text can be in this zone (non-interactive), but gesture handlers must not be
    local top_safe_zone = math.floor(screen_height / 8)

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
            fgcolor = colors.muted,
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

    -- ===== Energy Level Tabs (visual only, taps handled separately) =====
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
        fgcolor = Blitbuffer.gray(0.3),
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
                fgcolor = Blitbuffer.gray(0.3),
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

    -- Store quest positions for touch handling
    self.quest_touch_areas = {}

    -- Daily Quests section (with time slot breakdown)
    local daily_section = self:buildQuestSectionWithTimeSlots("Daily Quests", all_quests.daily or {}, today_energy, "daily", time_slots)
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
            self:formatReadingTime(reading_stats.time or 0)
        )
        table.insert(content, TextWidget:new{
            text = stats_text,
            face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
            fgcolor = UIConfig:color("foreground"),
        })
    end

    -- ===== Wrap content in scrollable container =====
    -- Calculate visible scroll area (account for scrollbar)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local scroll_height = screen_height

    -- Wrap content in a frame with padding and minimum height to fill viewport
    -- Inner frame is narrower to leave room for scrollbar
    local inner_frame = FrameContainer:new{
        width = scroll_width - scrollbar_width,
        height = math.max(scroll_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    -- Scrollable container as the outer wrapper
    local padded_content = ScrollableContainer:new{
        dimen = Geom:new{ w = scroll_width, h = scroll_height },
        inner_frame,
    }
    -- Store reference to set show_parent after widget creation
    self.scrollable_container = padded_content

    -- ===== Create main container with gestures =====
    local ui = self.ui
    local dashboard = self

    -- Tab change callback
    local function on_tab_change(tab_id)
        UIManager:close(dashboard.dashboard_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("dashboard", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create the main layout with content and navigation
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        padded_content,
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

    -- Add energy tab tap handlers (below top zone)
    self:setupEnergyTapHandlers()

    -- Add quest tap handlers (below top zone)
    self:setupQuestTapHandlers()

    -- KOReader gesture zone dimensions (from defaults.lua)
    -- DTAP_ZONE_MENU: {x = 0, y = 0, w = 1, h = 1/8} - top full width
    -- Corner zones: 1/8 x 1/8 in each corner
    local corner_size = math.floor(screen_width / 8)
    local corner_height = math.floor(screen_height / 8)

    -- Top CENTER zone tap handler - Opens KOReader menu (excludes corners)
    self.dashboard_widget.ges_events.TopCenterTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = corner_size,  -- Start after top-left corner
                y = 0,
                w = screen_width - corner_size * 2,  -- Exclude both corners
                h = top_safe_zone,
            },
        },
    }
    self.dashboard_widget.onTopCenterTap = function()
        -- Show KOReader's reader menu by sending event
        if self.ui and self.ui.menu then
            self.ui.menu:onShowMenu()
        else
            -- Fallback: send event through UI manager
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Top-left corner tap handler - Dispatch to user's corner action
    self.dashboard_widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = 0,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    self.dashboard_widget.onTopLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_top_left_corner")
    end

    -- Top-right corner tap handler - Dispatch to user's corner action
    self.dashboard_widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = screen_width - corner_size,
                y = 0,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    self.dashboard_widget.onTopRightCornerTap = function()
        return self:dispatchCornerGesture("tap_top_right_corner")
    end

    -- Bottom-left corner tap handler
    self.dashboard_widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = screen_height - corner_height,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    self.dashboard_widget.onBottomLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_left_corner")
    end

    -- Bottom-right corner tap handler
    self.dashboard_widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = screen_width - corner_size,
                y = screen_height - corner_height,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    self.dashboard_widget.onBottomRightCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_right_corner")
    end

    self.dashboard_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            -- Only capture swipes below top 1/8 zone (leave for KOReader)
            range = Geom:new{
                x = 0,
                y = top_safe_zone,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height - top_safe_zone,
            },
        },
    }
    self.dashboard_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            UIManager:close(self.dashboard_widget)
            return true
        end
        return false
    end

    UIManager:show(self.dashboard_widget)
end

--[[--
Build visual energy tabs (without gesture handling - that's done separately).
--]]
function Dashboard:buildEnergyTabsVisual()
    local categories = self.user_settings.energy_categories or {"Low", "Normal", "Energetic"}
    local current_energy = self.user_settings.today_energy or categories[2]

    local tabs = HorizontalGroup:new{ align = "center" }
    self.energy_tab_positions = {}

    local x_offset = Size.padding.large

    local colors = UIConfig:getColors()

    for idx, energy in ipairs(categories) do
        local is_active = (energy == current_energy)

        -- High contrast styling for e-ink (night mode aware)
        local bg_color = is_active and colors.active_bg or colors.inactive_bg
        local fg_color = is_active and colors.active_fg or colors.inactive_fg

        local label = TextWidget:new{
            text = energy,
            face = UIConfig:getFont("cfont", 16),
            fgcolor = fg_color,
            bold = is_active,
        }

        local tab_frame = FrameContainer:new{
            width = getEnergyTabWidth(),
            height = getEnergyTabHeight(),
            padding = Size.padding.small,
            bordersize = is_active and Size.border.thick or Size.border.thin,
            background = bg_color,
            CenterContainer:new{
                dimen = Geom:new{w = getEnergyTabWidth() - Size.padding.small * 2, h = getEnergyTabHeight() - Size.padding.small * 2},
                label,
            },
        }

        -- Store position for tap handling (approximate, will be adjusted)
        self.energy_tab_positions[idx] = {
            x = x_offset,
            y = 0,  -- Will be set during tap handler setup
            w = getEnergyTabWidth(),
            h = getEnergyTabHeight(),
            energy = energy,
        }
        x_offset = x_offset + getEnergyTabWidth() + 2

        table.insert(tabs, tab_frame)
    end

    return tabs
end

--[[--
Setup tap handlers for energy tabs.
--]]
function Dashboard:setupEnergyTapHandlers()
    local categories = self.user_settings.energy_categories or {"Low", "Normal", "Energetic"}

    -- Energy tabs use tracked Y position
    local energy_y = self.energy_tabs_y or (Size.padding.large + 30 + Size.padding.default)
    local x_offset = Size.padding.large

    for idx, energy in ipairs(categories) do
        local gesture_name = "EnergyTap_" .. idx
        self.dashboard_widget.ges_events[gesture_name] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = x_offset,
                    y = energy_y,
                    w = getEnergyTabWidth(),
                    h = getEnergyTabHeight(),
                },
            },
        }

        local dashboard = self
        local energy_level = energy
        self.dashboard_widget["on" .. gesture_name] = function()
            dashboard:setTodayEnergy(energy_level)
            return true
        end

        x_offset = x_offset + getEnergyTabWidth() + 2
    end
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
    for __, quest in ipairs(filtered) do
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
    for __, slot in ipairs(time_slots) do
        local slot_quests = quests_by_slot[slot]
        if slot_quests and #slot_quests > 0 then
            -- Time slot sub-header (18px height)
            table.insert(section, TextWidget:new{
                text = slot,
                face = Font:getFace("cfont", 12),
                fgcolor = Blitbuffer.gray(0.4),
            })
            self.current_y = self.current_y + 18

            for __, quest in ipairs(slot_quests) do
                if shown >= 8 then break end
                local quest_row = self:buildQuestRow(quest, quest_type)
                table.insert(section, quest_row)
                shown = shown + 1
            end
        end
    end

    -- Show quests without time slot
    if #other_quests > 0 and shown < 8 then
        for __, quest in ipairs(other_quests) do
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
    for __, quest in ipairs(filtered) do
        if shown >= 5 then break end
        local quest_row = self:buildQuestRow(quest, quest_type)
        table.insert(section, quest_row)
        shown = shown + 1
    end

    return section
end

--[[--
Build a single quest row for the dashboard with inline OK/Skip buttons.
Tracks Y position for gesture handling.
--]]
function Dashboard:buildQuestRow(quest, quest_type)
    local content_width = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2
    local today = os.date("%Y-%m-%d")

    local status_bg = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE
    local text_color = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

    -- Check if progressive quest needs daily reset
    if quest.is_progressive and quest.progress_last_date ~= today then
        quest.progress_current = 0
    end

    local row

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10] [+] [Title]
        local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
        local PROGRESS_WIDTH = getProgressWidth()
        -- Total buttons/spans: scaled values for button and progress widths
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - 4 - Size.padding.small

        -- Quest title with optional streak and category
        local quest_text = quest.title
        if quest.streak and quest.streak > 0 then
            quest_text = quest_text .. string.format(" (%d)", quest.streak)
        end

        local title_widget = TextWidget:new{
            text = quest_text,
            face = Font:getFace("cfont", 13),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Minus button
        local minus_button = FrameContainer:new{
            width = SMALL_BUTTON_WIDTH,
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "−",
                    face = Font:getFace("cfont", 16),
                    bold = true,
                },
            },
        }

        -- Progress display
        local current = quest.progress_current or 0
        local target = quest.progress_target or 1
        local pct = math.min(1, current / target)
        local progress_bg = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.gray(1 - pct * 0.5)
        local progress_text = string.format("%d/%d", current, target)

        local progress_display = FrameContainer:new{
            width = PROGRESS_WIDTH,
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = progress_bg,
            CenterContainer:new{
                dimen = Geom:new{w = PROGRESS_WIDTH - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = progress_text,
                    face = Font:getFace("cfont", 11),
                    bold = quest.completed,
                },
            },
        }

        -- Plus button
        local plus_button = FrameContainer:new{
            width = SMALL_BUTTON_WIDTH,
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "+",
                    face = Font:getFace("cfont", 16),
                    bold = true,
                },
            },
        }

        row = HorizontalGroup:new{
            align = "center",
            minus_button,
            HorizontalSpan:new{ width = 2 },
            progress_display,
            HorizontalSpan:new{ width = 2 },
            plus_button,
            HorizontalSpan:new{ width = Size.padding.small },
            FrameContainer:new{
                width = title_width,
                height = getTouchTargetHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    else
        -- Binary quest layout: [OK] [Skip] [Title]
        local title_width = content_width - getButtonWidth() * 2 - Size.padding.small * 3

        -- Quest title with optional streak
        local quest_text = quest.title
        if quest.streak and quest.streak > 0 then
            quest_text = quest_text .. string.format(" (%d)", quest.streak)
        end

        local title_widget = TextWidget:new{
            text = quest_text,
            face = Font:getFace("cfont", 14),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Complete button (OK or X if already completed)
        local complete_text = quest.completed and "X" or "OK"
        local complete_button = FrameContainer:new{
            width = getButtonWidth(),
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = getButtonWidth() - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = complete_text,
                    face = Font:getFace("cfont", 12),
                    bold = true,
                },
            },
        }

        -- Skip button
        local skip_button = FrameContainer:new{
            width = getButtonWidth(),
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = getButtonWidth() - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "Skip",
                    face = Font:getFace("cfont", 10),
                },
            },
        }

        row = HorizontalGroup:new{
            align = "center",
            complete_button,
            HorizontalSpan:new{ width = 2 },
            skip_button,
            HorizontalSpan:new{ width = Size.padding.small },
            FrameContainer:new{
                width = title_width,
                height = getTouchTargetHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    end

    local quest_row = FrameContainer:new{
        width = content_width,
        height = getTouchTargetHeight(),
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }

    -- Store quest info with current Y position for tap handling
    table.insert(self.quest_touch_areas, {
        quest = quest,
        quest_type = quest_type,
        y = self.current_y,  -- Track actual Y position
    })

    -- Update Y tracker
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
Setup tap handlers for quest items.
Uses single tap handler per row, determines action by X position.
--]]
function Dashboard:setupQuestTapHandlers()
    local content_width = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2

    for idx, quest_info in ipairs(self.quest_touch_areas) do
        -- Use stored Y position for this specific row
        local row_y = quest_info.y

        -- Single tap handler for entire row - determine action by X position
        local row_gesture = "QuestRow_" .. idx
        self.dashboard_widget.ges_events[row_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large,
                    y = row_y,
                    w = content_width,
                    h = getTouchTargetHeight(),
                },
            },
        }

        local dashboard = self
        local quest = quest_info.quest
        local quest_type = quest_info.quest_type

        self.dashboard_widget["on" .. row_gesture] = function(_, _, ges)
            local logger = require("logger")

            local tap_x = ges.pos.x - Size.padding.large  -- Relative to content start
            local row_width = content_width

            if quest.is_progressive then
                -- Progressive quest layout: [−] [3/10] [+] [Title]
                -- Layout: minus + span(2) + progress + span(2) + plus + span(padding.small) + title
                local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
                local PROGRESS_WIDTH = getProgressWidth()

                if tap_x < SMALL_BUTTON_WIDTH then
                    -- Minus button
                    logger.info("-> MINUS detected")
                    dashboard:decrementQuestProgress(quest, quest_type)
                elseif tap_x < SMALL_BUTTON_WIDTH + 2 + PROGRESS_WIDTH then
                    -- Progress display - show manual input
                    logger.info("-> PROGRESS detected")
                    dashboard:showProgressInput(quest, quest_type)
                elseif tap_x < SMALL_BUTTON_WIDTH * 2 + 2 + PROGRESS_WIDTH + 2 then
                    -- Plus button
                    logger.info("-> PLUS detected")
                    dashboard:incrementQuestProgress(quest, quest_type)
                else
                    -- Title area
                    logger.info("-> TITLE detected")
                    dashboard:showQuestActions(quest, quest_type)
                end
            else
                -- Binary quest: Buttons are on LEFT: OK (0-11%), Skip (11-22%), Title (22%+)
                local tap_percent = tap_x / row_width

                logger.info("Quest tap: x=", ges.pos.x, "relative=", tap_x, "percent=", tap_percent)

                if tap_percent < 0.11 then
                    -- Leftmost ~11% = OK button (50px / ~462px)
                    logger.info("-> OK detected")
                    dashboard:toggleQuestComplete(quest, quest_type)
                elseif tap_percent < 0.22 then
                    -- Next ~11% = Skip button
                    logger.info("-> SKIP detected")
                    dashboard:skipQuest(quest, quest_type)
                else
                    -- Right 78% = Title area
                    logger.info("-> TITLE detected")
                    dashboard:showQuestActions(quest, quest_type)
                end
            end
            return true
        end
    end
end

--[[--
Skip a quest for today.
--]]
function Dashboard:skipQuest(quest, quest_type)
    local today = Data:getCurrentDate()
    local all_quests = Data:loadAllQuests()

    for __, q in ipairs(all_quests[quest_type] or {}) do
        if q.id == quest.id then
            q.skipped_date = today
            break
        end
    end

    Data:saveAllQuests(all_quests)

    -- Refresh dashboard
    if self.dashboard_widget then
        UIManager:close(self.dashboard_widget)
    end
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
        if self.dashboard_widget then
            UIManager:close(self.dashboard_widget)
        end
        self:showDashboardView()
        UIManager:setDirty("all", "ui")

        if updated.completed then
            -- Update daily log for heatmap
            self:updateDailyLog()
            UIManager:nextTick(function()
                UIManager:show(InfoMessage:new{
                    text = _("Quest completed!"),
                    timeout = 1,
                })
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
        if self.dashboard_widget then
            UIManager:close(self.dashboard_widget)
        end
        self:showDashboardView()
        UIManager:setDirty("all", "ui")
    end
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

    for __, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for __, quest in ipairs(quests[quest_type] or {}) do
            total = total + 1
            if quest.completed and quest.completed_date == today then
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
                        if self.dashboard_widget then
                            UIManager:close(self.dashboard_widget)
                        end
                        self:showDashboardView()
                        UIManager:setDirty("all", "ui")

                        if updated and updated.completed then
                            self:updateDailyLog()
                            UIManager:nextTick(function()
                                UIManager:show(InfoMessage:new{
                                    text = _("Quest completed!"),
                                    timeout = 1,
                                })
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
Show actions dialog for a quest.
--]]
function Dashboard:showQuestActions(quest, quest_type)
    local complete_text = quest.completed and _("Mark Incomplete") or _("Mark Complete")

    local buttons = {
        {{
            text = complete_text,
            callback = function()
                UIManager:close(self.action_dialog)
                self:toggleQuestComplete(quest, quest_type)
            end,
        }},
        {{
            text = _("View Details"),
            callback = function()
                UIManager:close(self.action_dialog)
                self:showQuestDetails(quest, quest_type)
            end,
        }},
        {{
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.action_dialog)
            end,
        }},
    }

    self.action_dialog = ButtonDialog:new{
        title = quest.title,
        buttons = buttons,
    }
    UIManager:show(self.action_dialog)
end

--[[--
Toggle quest completion status.
--]]
function Dashboard:toggleQuestComplete(quest, quest_type)
    local message
    if quest.completed then
        Data:uncompleteQuest(quest_type, quest.id)
        message = _("Quest marked incomplete")
    else
        -- Complete the quest
        local today = Data:getCurrentDate()
        local all_quests = Data:loadAllQuests()

        for __, q in ipairs(all_quests[quest_type] or {}) do
            if q.id == quest.id then
                -- Update streak
                if q.completed_date then
                    local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
                    if q.completed_date == yesterday then
                        q.streak = (q.streak or 0) + 1
                    elseif q.completed_date ~= today then
                        q.streak = 1
                    end
                else
                    q.streak = 1
                end
                q.completed = true
                q.completed_date = today
                break
            end
        end

        Data:saveAllQuests(all_quests)
        Quests:updateDailyLog()
        Quests:updateGlobalStreak()
        message = _("Quest completed!")
    end

    -- Refresh dashboard
    if self.dashboard_widget then
        UIManager:close(self.dashboard_widget)
    end
    self:showDashboardView()

    -- Force immediate screen refresh
    UIManager:setDirty("all", "ui")

    -- Schedule feedback message for next tick to ensure dashboard renders first
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = message,
            timeout = 1,
        })
    end)
end

--[[--
Show detailed quest information.
--]]
function Dashboard:showQuestDetails(quest, quest_type)
    local streak_text = quest.streak and quest.streak > 0
        and string.format(_("Current streak: %d days"), quest.streak)
        or _("No streak yet")

    local energy_text = quest.energy_required or "Any"
    local time_slot = quest.time_slot or "Any time"

    local details = string.format(
        "%s\n\nTime: %s\nEnergy: %s\n%s\n\nType: %s",
        quest.title,
        time_slot,
        energy_text,
        streak_text,
        quest_type:sub(1,1):upper() .. quest_type:sub(2)
    )

    UIManager:show(InfoMessage:new{
        text = details,
        width = Screen:getWidth() * 0.8,
    })
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
                fgcolor = Blitbuffer.gray(0.4),
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
        fgcolor = Blitbuffer.gray(0.3),
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
