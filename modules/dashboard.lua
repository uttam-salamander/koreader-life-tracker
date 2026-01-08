--[[--
Dashboard module for Life Tracker.
Morning check-in, filtered quests, streak meter, heatmap, and reading stats.

@module lifetracker.dashboard
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
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

local Dashboard = {}

-- Touch target sizes (minimum 44px for accessibility)
local TOUCH_TARGET_HEIGHT = 48
local ENERGY_TAB_WIDTH = 90
local ENERGY_TAB_HEIGHT = 44
local BUTTON_WIDTH = 50

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
Set today's energy level and refresh dashboard.
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

    -- Track Y position for gesture handling
    self.current_y = Size.padding.large

    -- Main content group
    local content = VerticalGroup:new{ align = "left" }

    -- ===== Greeting =====
    local greeting = self:getTimeBasedGreeting()
    table.insert(content, TextWidget:new{
        text = greeting,
        face = Font:getFace("tfont", 22),
        bold = true,
    })
    self.current_y = self.current_y + 30
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    self.current_y = self.current_y + Size.padding.default

    -- ===== Energy Level Tabs (visual only, taps handled separately) =====
    self.energy_tabs_y = self.current_y
    local energy_tabs = self:buildEnergyTabsVisual()
    table.insert(content, energy_tabs)
    self.current_y = self.current_y + ENERGY_TAB_HEIGHT
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    self.current_y = self.current_y + Size.padding.large

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
    end

    -- Weekly Quests section
    local weekly_section = self:buildQuestSection("This Week", all_quests.weekly or {}, today_energy, "weekly")
    if weekly_section then
        table.insert(content, weekly_section)
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    end

    -- Monthly Quests section
    local monthly_section = self:buildQuestSection("This Month", all_quests.monthly or {}, today_energy, "monthly")
    if monthly_section then
        table.insert(content, monthly_section)
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    end

    -- ===== Separator =====
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- ===== Streak Display =====
    local streak = (self.user_settings.streak_data and self.user_settings.streak_data.current) or 0
    local streak_text = string.format(_("Streak: %d days"), streak)
    table.insert(content, TextWidget:new{
        text = streak_text,
        face = Font:getFace("tfont", 18),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Heatmap =====
    table.insert(content, TextWidget:new{
        text = _("Activity (12 Weeks)"),
        face = Font:getFace("tfont", 16),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    local heatmap_widget = self:buildDynamicHeatmap()
    if heatmap_widget then
        table.insert(content, heatmap_widget)
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- ===== Reading Stats =====
    local reading_stats = self:getReadingStats()
    if reading_stats then
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = content_width, h = Size.line.medium },
            background = Blitbuffer.gray(0.5),
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        table.insert(content, TextWidget:new{
            text = _("Today's Reading"),
            face = Font:getFace("tfont", 16),
        })
        local stats_text = string.format(_("Pages: %d | Time: %s"),
            reading_stats.pages or 0,
            self:formatReadingTime(reading_stats.time or 0)
        )
        table.insert(content, TextWidget:new{
            text = stats_text,
            face = Font:getFace("cfont", 14),
        })
    end

    -- ===== Wrap content in scrollable frame =====
    local padded_content = FrameContainer:new{
        width = screen_width - Navigation.TAB_WIDTH,
        height = screen_height,
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

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

    -- Wrap in InputContainer for gestures (but allow KOReader top menu)
    self.dashboard_widget = InputContainer:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        ges_events = {},
        main_layout,
    }

    -- Add energy tab tap handlers
    self:setupEnergyTapHandlers()

    -- Add quest tap handlers
    self:setupQuestTapHandlers()

    -- Swipe right to close (but not from top area - leave for KOReader menu)
    local top_safe_zone = math.floor(screen_height * 0.1)
    self.dashboard_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            -- Only capture swipes in the lower 90% of screen
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

    for idx, energy in ipairs(categories) do
        local is_active = (energy == current_energy)

        -- High contrast styling for e-ink
        local bg_color = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg_color = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

        local label = TextWidget:new{
            text = energy,
            face = Font:getFace("cfont", 16),
            fgcolor = fg_color,
            bold = is_active,
        }

        local tab_frame = FrameContainer:new{
            width = ENERGY_TAB_WIDTH,
            height = ENERGY_TAB_HEIGHT,
            padding = Size.padding.small,
            bordersize = is_active and 2 or 1,
            background = bg_color,
            CenterContainer:new{
                dimen = Geom:new{w = ENERGY_TAB_WIDTH - Size.padding.small * 2, h = ENERGY_TAB_HEIGHT - Size.padding.small * 2},
                label,
            },
        }

        -- Store position for tap handling (approximate, will be adjusted)
        self.energy_tab_positions[idx] = {
            x = x_offset,
            y = 0,  -- Will be set during tap handler setup
            w = ENERGY_TAB_WIDTH,
            h = ENERGY_TAB_HEIGHT,
            energy = energy,
        }
        x_offset = x_offset + ENERGY_TAB_WIDTH + 2

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
                    w = ENERGY_TAB_WIDTH,
                    h = ENERGY_TAB_HEIGHT,
                },
            },
        }

        local dashboard = self
        local energy_level = energy
        self.dashboard_widget["on" .. gesture_name] = function()
            dashboard:setTodayEnergy(energy_level)
            return true
        end

        x_offset = x_offset + ENERGY_TAB_WIDTH + 2
    end
end

--[[--
Build a quest section with header and quest items grouped by time slots.
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

    -- Section header
    table.insert(section, TextWidget:new{
        text = string.format("%s (%d)", title, #filtered),
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(section, VerticalSpan:new{ width = Size.padding.small })

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
            -- Time slot sub-header
            table.insert(section, TextWidget:new{
                text = slot,
                face = Font:getFace("cfont", 12),
                fgcolor = Blitbuffer.gray(0.4),
            })

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

    -- Section header
    table.insert(section, TextWidget:new{
        text = string.format("%s (%d)", title, #filtered),
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(section, VerticalSpan:new{ width = Size.padding.small })

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
--]]
function Dashboard:buildQuestRow(quest, quest_type)
    local content_width = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2
    local title_width = content_width - BUTTON_WIDTH * 2 - Size.padding.small * 3

    local status_bg = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE
    local text_color = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

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
        width = BUTTON_WIDTH,
        height = TOUCH_TARGET_HEIGHT - 4,
        padding = 2,
        bordersize = 1,
        background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = BUTTON_WIDTH - 6, h = TOUCH_TARGET_HEIGHT - 10},
            TextWidget:new{
                text = complete_text,
                face = Font:getFace("cfont", 12),
                bold = true,
            },
        },
    }

    -- Skip button
    local skip_button = FrameContainer:new{
        width = BUTTON_WIDTH,
        height = TOUCH_TARGET_HEIGHT - 4,
        padding = 2,
        bordersize = 1,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = BUTTON_WIDTH - 6, h = TOUCH_TARGET_HEIGHT - 10},
            TextWidget:new{
                text = "Skip",
                face = Font:getFace("cfont", 10),
            },
        },
    }

    local row = HorizontalGroup:new{
        align = "center",
        FrameContainer:new{
            width = title_width,
            height = TOUCH_TARGET_HEIGHT,
            padding = Size.padding.small,
            bordersize = 0,
            background = status_bg,
            title_widget,
        },
        HorizontalSpan:new{ width = Size.padding.small },
        complete_button,
        HorizontalSpan:new{ width = 2 },
        skip_button,
    }

    local quest_row = FrameContainer:new{
        width = content_width,
        height = TOUCH_TARGET_HEIGHT,
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }

    -- Store quest info for tap handling
    table.insert(self.quest_touch_areas, {
        quest = quest,
        quest_type = quest_type,
    })

    return quest_row
end

--[[--
Filter quests by energy level.
--]]
function Dashboard:filterQuestsByEnergy(quests, energy_level)
    local filtered = {}
    local user_settings = self.user_settings

    -- Get highest energy level
    local highest_energy = user_settings.energy_categories and user_settings.energy_categories[1] or "Energetic"
    local is_high_energy = (energy_level == highest_energy)

    for _, quest in ipairs(quests) do
        -- Show if: any energy, matches energy, or high energy day
        if quest.energy_required == "Any" or
           quest.energy_required == energy_level or
           is_high_energy or
           not quest.energy_required then
            table.insert(filtered, quest)
        end
    end

    return filtered
end

--[[--
Setup tap handlers for quest items with separate OK/Skip button regions.
--]]
function Dashboard:setupQuestTapHandlers()
    -- Quest sections start at approximately Y = 150 (after greeting + energy tabs + separator + reminders)
    local quest_y = self.quest_list_start_y or 150
    local content_width = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2
    local title_width = content_width - BUTTON_WIDTH * 2 - Size.padding.small * 3
    local quest_height = TOUCH_TARGET_HEIGHT + 2

    for idx, quest_info in ipairs(self.quest_touch_areas) do
        local row_y = quest_y + (idx - 1) * quest_height

        -- Title area tap (opens details/edit menu)
        local title_gesture = "QuestTitle_" .. idx
        self.dashboard_widget.ges_events[title_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large,
                    y = row_y,
                    w = title_width,
                    h = TOUCH_TARGET_HEIGHT,
                },
            },
        }

        local dashboard = self
        local quest = quest_info.quest
        local quest_type = quest_info.quest_type
        self.dashboard_widget["on" .. title_gesture] = function()
            dashboard:showQuestActions(quest, quest_type)
            return true
        end

        -- OK/Complete button tap
        local complete_gesture = "QuestComplete_" .. idx
        self.dashboard_widget.ges_events[complete_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large + title_width + Size.padding.small,
                    y = row_y,
                    w = BUTTON_WIDTH,
                    h = TOUCH_TARGET_HEIGHT,
                },
            },
        }
        self.dashboard_widget["on" .. complete_gesture] = function()
            dashboard:toggleQuestComplete(quest, quest_type)
            return true
        end

        -- Skip button tap
        local skip_gesture = "QuestSkip_" .. idx
        self.dashboard_widget.ges_events[skip_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large + title_width + Size.padding.small + BUTTON_WIDTH + 2,
                    y = row_y,
                    w = BUTTON_WIDTH,
                    h = TOUCH_TARGET_HEIGHT,
                },
            },
        }
        self.dashboard_widget["on" .. skip_gesture] = function()
            dashboard:skipQuest(quest, quest_type)
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

    for _, q in ipairs(all_quests[quest_type] or {}) do
        if q.id == quest.id then
            q.skipped_date = today
            break
        end
    end

    Data:saveAllQuests(all_quests)

    UIManager:show(InfoMessage:new{
        text = _("Quest skipped for today"),
        timeout = 1,
    })

    -- Refresh dashboard
    if self.dashboard_widget then
        UIManager:close(self.dashboard_widget)
    end
    self:showDashboardView()
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
    if quest.completed then
        Data:uncompleteQuest(quest_type, quest.id)
        UIManager:show(InfoMessage:new{
            text = _("Quest marked incomplete"),
            timeout = 1,
        })
    else
        -- Complete the quest
        local today = Data:getCurrentDate()
        local all_quests = Data:loadAllQuests()

        for _, q in ipairs(all_quests[quest_type] or {}) do
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

        UIManager:show(InfoMessage:new{
            text = _("Quest completed!"),
            timeout = 1,
        })
    end

    -- Refresh dashboard
    if self.dashboard_widget then
        UIManager:close(self.dashboard_widget)
    end
    self:showDashboardView()
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
--]]
function Dashboard:buildDynamicHeatmap()
    local logs = Data:loadDailyLogs()
    local today = os.time()
    local weeks = 12
    local days_per_week = 7

    -- Find the maximum completions in any day to set dynamic thresholds
    local max_completions = 0
    for day = 0, weeks * days_per_week - 1 do
        local date_time = today - day * 86400
        local date_str = os.date("%Y-%m-%d", date_time)
        local log = logs[date_str]
        if log and log.quests_completed then
            max_completions = math.max(max_completions, log.quests_completed)
        end
    end

    -- Set dynamic thresholds (4 levels)
    local t1, t2, t3
    if max_completions <= 4 then
        t1, t2, t3 = 1, 2, 3
    else
        t1 = math.ceil(max_completions / 4)
        t2 = math.ceil(max_completions / 2)
        t3 = math.ceil(max_completions * 3 / 4)
    end

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

            -- Choose character based on dynamic thresholds
            if count == 0 then
                row = row .. "░"
            elseif count <= t1 then
                row = row .. "▒"
            elseif count <= t2 then
                row = row .. "▓"
            else
                row = row .. "█"
            end
        end
        table.insert(lines, row)
    end

    local heatmap_text = table.concat(lines, "\n")

    local heatmap_group = VerticalGroup:new{ align = "left" }
    table.insert(heatmap_group, TextWidget:new{
        text = heatmap_text,
        face = Font:getFace("cfont", 12),
    })
    table.insert(heatmap_group, VerticalSpan:new{ width = Size.padding.small })

    -- Dynamic legend
    local legend = string.format("░=0  ▒=1-%d  ▓=%d-%d  █=%d+", t1, t1+1, t2, t3)
    table.insert(heatmap_group, TextWidget:new{
        text = legend,
        face = Font:getFace("cfont", 10),
        fgcolor = Blitbuffer.gray(0.4),
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
