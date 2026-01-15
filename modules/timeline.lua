--[[--
Timeline module for Life Tracker.
Visual day view with quests grouped by time-of-day slots.
@module lifetracker.timeline
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local Data = require("modules/data")
local Navigation = require("modules/navigation")
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")
local Celebration = require("modules/celebration")
local QuestRow = require("modules/quest_row")

local Timeline = {}

-- UI Constants (scaled via UIConfig)
local function getTouchTargetHeight()
    return UIConfig:dim("touch_target_height")
end

--[[--
Show the timeline view for a specific date (defaults to today).
--]]
function Timeline:show(ui, date)
    self.ui = ui
    self.view_date = date or os.date("%Y-%m-%d")
    self:showTimelineView()
end

--[[--
Navigate to a different day.
@param offset Number of days to move (negative for past, positive for future)
--]]
function Timeline:navigateDay(offset)
    -- Parse current view_date
    local year, month, day = self.view_date:match("(%d+)-(%d+)-(%d+)")
    local current_time = os.time({year = tonumber(year) or 2025, month = tonumber(month) or 1, day = tonumber(day) or 1})

    -- Calculate new date
    local new_time = current_time + (offset * 86400)
    self.view_date = os.date("%Y-%m-%d", new_time)

    -- Refresh view
    if self.timeline_widget then
        UIManager:close(self.timeline_widget)
    end
    self:showTimelineView()
    UIManager:setDirty("all", "ui")
end

--[[--
Show date picker dialog to select a specific date.
Uses KOReader's DateTimeWidget for day/month/year selection.
--]]
function Timeline:showDatePicker()
    -- Parse current view_date
    local year, month, day = self.view_date:match("(%d+)-(%d+)-(%d+)")

    local date_widget = DateTimeWidget:new{
        year = tonumber(year) or tonumber(os.date("%Y")),
        month = tonumber(month) or tonumber(os.date("%m")),
        day = tonumber(day) or tonumber(os.date("%d")),
        ok_text = _("Go to Date"),
        title_text = _("Select Date"),
        callback = function(time)
            -- Format selected date
            self.view_date = string.format("%04d-%02d-%02d", time.year, time.month, time.day)
            -- Refresh view
            if self.timeline_widget then
                UIManager:close(self.timeline_widget)
            end
            self:showTimelineView()
            UIManager:setDirty("all", "ui")
        end
    }
    UIManager:show(date_widget)
end

--[[--
Build and display the timeline view.
Groups quests by time slot (Morning, Afternoon, Evening, Night).
--]]
function Timeline:showTimelineView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = UIConfig:getPaddedContentWidth()

    -- KOReader reserves top ~10% for menu gesture
    local top_safe_zone = UIConfig:getTopSafeZone()

    local content = VerticalGroup:new{ align = "left" }

    -- Header title (in top zone - non-interactive)
    local is_today = self.view_date == os.date("%Y-%m-%d")
    local view_time = os.time({
        year = tonumber(self.view_date:sub(1,4)) or 2025,
        month = tonumber(self.view_date:sub(6,7)) or 1,
        day = tonumber(self.view_date:sub(9,10)) or 1
    })
    local display_date = os.date("%A, %B %d", view_time)

    table.insert(content, TextWidget:new{
        text = _("Timeline"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    })

    -- Add spacer to push interactive content below top_safe_zone
    local header_height = 24
    local spacer_needed = top_safe_zone - Size.padding.large - header_height
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
    end

    -- === INTERACTIVE AREA STARTS HERE (below top_safe_zone) ===
    self.current_y = top_safe_zone

    -- Date navigation row: [<] [DATE] [>]
    local NAV_BUTTON_WIDTH = UIConfig:scale(44)
    local date_width = content_width - NAV_BUTTON_WIDTH * 2 - Size.padding.small * 4

    -- Previous day button
    local prev_button = FrameContainer:new{
        width = NAV_BUTTON_WIDTH,
        height = getTouchTargetHeight(),
        padding = Size.padding.small,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = NAV_BUTTON_WIDTH - Size.padding.small * 2, h = getTouchTargetHeight() - Size.padding.small * 2},
            TextWidget:new{
                text = "◀",
                face = Font:getFace("tfont", 18),
                bold = true,
            },
        },
    }

    -- Date display (tappable to open date picker)
    local header_text = is_today and ("TODAY - " .. display_date) or display_date
    local date_display = FrameContainer:new{
        width = date_width,
        height = getTouchTargetHeight(),
        padding = Size.padding.small,
        bordersize = 1,
        background = is_today and Blitbuffer.gray(0.65) or Blitbuffer.COLOR_WHITE,  -- Visible gray for today
        CenterContainer:new{
            dimen = Geom:new{w = date_width - Size.padding.small * 2, h = getTouchTargetHeight() - Size.padding.small * 2},
            TextWidget:new{
                text = header_text,
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.COLOR_BLACK,  -- Explicit black text
                bold = is_today,
            },
        },
    }

    -- Next day button
    local next_button = FrameContainer:new{
        width = NAV_BUTTON_WIDTH,
        height = getTouchTargetHeight(),
        padding = Size.padding.small,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = NAV_BUTTON_WIDTH - Size.padding.small * 2, h = getTouchTargetHeight() - Size.padding.small * 2},
            TextWidget:new{
                text = "▶",
                face = Font:getFace("tfont", 18),
                bold = true,
            },
        },
    }

    local nav_row = HorizontalGroup:new{ align = "center" }
    table.insert(nav_row, prev_button)
    table.insert(nav_row, HorizontalSpan:new{ width = Size.padding.small })
    table.insert(nav_row, date_display)
    table.insert(nav_row, HorizontalSpan:new{ width = Size.padding.small })
    table.insert(nav_row, next_button)

    table.insert(content, nav_row)
    self.current_y = self.current_y + getTouchTargetHeight()

    -- Store nav button positions for tap handling (relative to content start)
    self.nav_button_x = {
        prev_start = Size.padding.large,
        prev_end = Size.padding.large + NAV_BUTTON_WIDTH,
        date_start = Size.padding.large + NAV_BUTTON_WIDTH + Size.padding.small,
        date_end = Size.padding.large + NAV_BUTTON_WIDTH + Size.padding.small + date_width,
        next_start = Size.padding.large + NAV_BUTTON_WIDTH + Size.padding.small + date_width + Size.padding.small,
        next_end = content_width + Size.padding.large,
    }
    self.nav_button_width = NAV_BUTTON_WIDTH
    self.date_display_width = date_width
    -- Y position of nav row in screen coordinates (account for frame padding)
    self.nav_row_y = top_safe_zone + Size.padding.large

    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("md") })
    self.current_y = self.current_y + UIConfig:spacing("md")

    -- Get settings and quests
    local settings = Data:loadUserSettings()
    local time_slots = (settings and settings.time_slots) or {"Morning", "Afternoon", "Evening", "Night"}
    local today_quests = self:getQuestsForDate(self.view_date)

    -- Track completion stats
    local total_quests = 0
    local completed_quests = 0

    -- Build time slot sections
    for _, slot in ipairs(time_slots) do
        local slot_quests = self:getQuestsForSlot(today_quests, slot)
        total_quests = total_quests + #slot_quests

        -- Slot header with separator line
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = content_width, h = 2 },
            background = UIConfig:color("foreground"),
        })
        self.current_y = self.current_y + 2
        table.insert(content, TextWidget:new{
            text = slot,  -- Title case (e.g., "Morning" not "MORNING")
            face = UIConfig:getFont("tfont", UIConfig:fontSize("section_header")),
            fgcolor = UIConfig:color("foreground"),
            bold = true,
        })
        self.current_y = self.current_y + 22
        table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("sm") })
        self.current_y = self.current_y + UIConfig:spacing("sm")

        -- Quest items for this slot
        if #slot_quests == 0 then
            -- Friendly empty state message
            local empty_messages = {
                Morning = "No morning tasks",
                Afternoon = "Afternoon is free",
                Evening = "No evening tasks",
                Night = "Rest well tonight",
            }
            table.insert(content, TextWidget:new{
                text = "  " .. (empty_messages[slot] or "No tasks"),
                face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
                fgcolor = UIConfig:color("muted"),
            })
            self.current_y = self.current_y + 20
        else
            for _, quest in ipairs(slot_quests) do
                if Data:isQuestCompletedOnDate(quest, self.view_date) then
                    completed_quests = completed_quests + 1
                end

                -- Build quest row with Button widgets (tap handling is built-in)
                local quest_row = self:buildQuestRow(quest, content_width)
                table.insert(content, quest_row)
                self.current_y = self.current_y + getTouchTargetHeight() + 2
            end
        end
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- Progress footer
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    local progress_pct = total_quests > 0 and math.floor((completed_quests / total_quests) * 100) or 0
    table.insert(content, TextWidget:new{
        text = string.format("Progress: %d/%d (%d%%)", completed_quests, total_quests, progress_pct),
        face = Font:getFace("tfont", 16),
        bold = true,
    })

    -- Wrap content in scrollable container with page padding
    local scroll_width = UIConfig:getScrollWidth()
    local scroll_height = screen_height
    local page_padding = UIConfig:getPagePadding()

    local inner_frame = FrameContainer:new{
        width = scroll_width,
        height = math.max(scroll_height, content:getSize().h + page_padding * 2),
        padding = page_padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    local padded_content = ScrollableContainer:new{
        dimen = Geom:new{ w = scroll_width, h = scroll_height },
        inner_frame,
    }
    self.scrollable_container = padded_content

    -- Setup navigation
    local timeline = self
    local ui = self.ui

    local function on_tab_change(tab_id)
        UIManager:close(timeline.timeline_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("timeline", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create the main layout with full-screen white background to prevent bleed-through
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
        padded_content,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Standard InputContainer
    self.timeline_widget = InputContainer:new{
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
    self.scrollable_container.show_parent = self.timeline_widget

    -- Store top_safe_zone for gesture handlers
    self.top_safe_zone = top_safe_zone

    -- Quest buttons use Button widgets with built-in callbacks - no separate handlers needed

    -- Date navigation tap handlers
    -- Nav row is BELOW top_safe_zone to avoid corner gesture conflicts
    -- NOTE: self.nav_row_y is already in screen coordinates (self.current_y starts at Size.padding.large)
    local nav_row_y = self.nav_row_y
    local nav_row_height = getTouchTargetHeight()

    -- Previous day button tap
    self.timeline_widget.ges_events.PrevDayTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = self.nav_button_x.prev_start,
                y = nav_row_y,
                w = self.nav_button_width,
                h = nav_row_height,
            },
        },
    }
    self.timeline_widget.onPrevDayTap = function()
        self:navigateDay(-1)
        return true
    end

    -- Date display tap (opens date picker)
    self.timeline_widget.ges_events.DatePickerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = self.nav_button_x.date_start,
                y = nav_row_y,
                w = self.date_display_width,
                h = nav_row_height,
            },
        },
    }
    self.timeline_widget.onDatePickerTap = function()
        self:showDatePicker()
        return true
    end

    -- Next day button tap
    self.timeline_widget.ges_events.NextDayTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = self.nav_button_x.next_start,
                y = nav_row_y,
                w = self.nav_button_width,
                h = nav_row_height,
            },
        },
    }
    self.timeline_widget.onNextDayTap = function()
        self:navigateDay(1)
        return true
    end

    -- Setup corner gesture handlers using shared helper
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = top_safe_zone,
    }
    UIHelpers.setupCornerGestures(self.timeline_widget, self, gesture_dims)

    -- Custom swipe handler for day navigation (not close)
    self.timeline_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = Geom:new{
                x = 0,
                y = top_safe_zone,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height - top_safe_zone,
            },
        },
    }
    self.timeline_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            -- Swipe right: previous day
            self:navigateDay(-1)
            return true
        elseif ges.direction == "west" then
            -- Swipe left: next day
            self:navigateDay(1)
            return true
        end
        return false
    end

    UIManager:show(self.timeline_widget)
end

--[[--
Build a single quest row using the shared QuestRow component.
For skipped quests, shows "Undo" button instead of "Skip".
--]]
function Timeline:buildQuestRow(quest, content_width)
    local timeline = self
    local view_date = self.view_date or os.date("%Y-%m-%d")

    -- Check if this quest is skipped for the viewed date
    local is_skipped = (quest.skipped_date == view_date)

    -- Find quest type for callbacks
    local quest_type = nil
    local all_quests = Data:loadAllQuests()
    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    return QuestRow.build(quest, {
        quest_type = quest_type or "daily",
        content_width = content_width,
        date = view_date,
        show_streak = false,  -- Timeline doesn't show streaks
        callbacks = {
            skip_text = is_skipped and "Undo" or "Skip",
            on_complete = function(q)
                timeline:toggleQuestComplete(q)
            end,
            on_skip = function(q)
                if is_skipped then
                    timeline:unskipQuest(q)
                else
                    timeline:skipQuest(q)
                end
            end,
            on_plus = function(q)
                timeline:incrementQuestProgress(q)
            end,
            on_minus = function(q)
                timeline:decrementQuestProgress(q)
            end,
            on_refresh = function()
                if timeline.timeline_widget then
                    UIManager:close(timeline.timeline_widget)
                end
                timeline:showTimelineView()
            end,
        },
    })
end

--[[--
Show actions for a quest.
--]]
function Timeline:showQuestActions(quest)
    local is_completed = Data:isQuestCompletedOnDate(quest, self.view_date)
    local complete_text = is_completed and _("Mark Incomplete") or _("Mark Complete")

    local buttons = {
        {{
            text = complete_text,
            callback = function()
                UIManager:close(self.action_dialog)
                self:toggleQuestComplete(quest)
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
Toggle quest completion.
--]]
function Timeline:toggleQuestComplete(quest)
    -- Find quest type
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    local was_completed = Data:isQuestCompletedOnDate(quest, self.view_date)
    if quest_type then
        if was_completed then
            -- Pass view_date so we uncomplete the specific date being viewed
            Data:uncompleteQuest(quest_type, quest.id, self.view_date)
        else
            -- Pass view_date so completion is recorded for the date being viewed
            Data:completeQuest(quest_type, quest.id, self.view_date)
        end

        -- Refresh timeline
        if self.timeline_widget then
            UIManager:close(self.timeline_widget)
        end
        self:showTimelineView()

        -- Force immediate screen refresh
        UIManager:setDirty("all", "ui")

        -- Show feedback
        UIManager:nextTick(function()
            if was_completed then
                UIManager:show(InfoMessage:new{
                    text = _("Quest marked incomplete"),
                    timeout = 1,
                })
            else
                Celebration:showCompletion()
            end
        end)
    end
end

--[[--
Skip a quest for today.
--]]
function Timeline:skipQuest(quest)
    -- Use view_date so skip is recorded for the date being viewed
    local skip_date = self.view_date or Data:getCurrentDate()
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                q.skipped_date = skip_date
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    if quest_type then
        Data:saveAllQuests(all_quests)

        -- Refresh timeline
        if self.timeline_widget then
            UIManager:close(self.timeline_widget)
        end
        self:showTimelineView()

        -- Force immediate screen refresh
        UIManager:setDirty("all", "ui")

        -- Show feedback
        UIManager:nextTick(function()
            UIManager:show(InfoMessage:new{
                text = _("Quest skipped for today"),
                timeout = 1,
            })
        end)
    end
end

--[[--
Unskip a quest (restore it to dashboard).
--]]
function Timeline:unskipQuest(quest)
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                q.skipped_date = nil  -- Clear skipped status
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    if quest_type then
        Data:saveAllQuests(all_quests)

        -- Refresh timeline
        if self.timeline_widget then
            UIManager:close(self.timeline_widget)
        end
        self:showTimelineView()

        -- Force screen refresh
        UIManager:setDirty("all", "ui")

        -- Show feedback
        UIManager:nextTick(function()
            UIManager:show(InfoMessage:new{
                text = _("Quest restored to dashboard"),
                timeout = 1,
            })
        end)
    end
end

--[[--
Increment progress for a progressive quest.
--]]
function Timeline:incrementQuestProgress(quest)
    -- Find quest type
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    if quest_type then
        local updated = Data:incrementQuestProgress(quest_type, quest.id)
        if updated then
            -- Refresh timeline
            if self.timeline_widget then
                UIManager:close(self.timeline_widget)
            end
            self:showTimelineView()
            UIManager:setDirty("all", "ui")

            if updated.completed then
                UIManager:nextTick(function()
                    Celebration:showCompletion()
                end)
            end
        end
    end
end

--[[--
Decrement progress for a progressive quest.
--]]
function Timeline:decrementQuestProgress(quest)
    -- Find quest type
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    if quest_type then
        local updated = Data:decrementQuestProgress(quest_type, quest.id)
        if updated then
            -- Refresh timeline
            if self.timeline_widget then
                UIManager:close(self.timeline_widget)
            end
            self:showTimelineView()
            UIManager:setDirty("all", "ui")
        end
    end
end

--[[--
Show input dialog for manually setting progress.
--]]
function Timeline:showProgressInput(quest)
    -- Find quest type
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                quest_type = qtype
                break
            end
        end
        if quest_type then break end
    end

    if not quest_type then return end

    local InputDialog = require("ui/widget/inputdialog")
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
                        Data:setQuestProgress(quest_type, quest.id, value)
                        UIManager:close(dialog)

                        -- Refresh timeline
                        if self.timeline_widget then
                            UIManager:close(self.timeline_widget)
                        end
                        self:showTimelineView()
                        UIManager:setDirty("all", "ui")
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
Get all quests that should appear on a specific date with correct completion status.
@param date_str Date in YYYY-MM-DD format
@treturn table List of quest copies with date-appropriate completion status
--]]
function Timeline:getQuestsForDate(date_str)
    local all_quests = Data:loadAllQuests()
    if not all_quests then return {} end

    local quests = {}

    -- Helper to clone quest with date-appropriate completion status
    local function cloneQuestForDate(quest)
        local clone = {}
        for k, v in pairs(quest) do
            clone[k] = v
        end

        -- Check if quest was completed ON this specific date using completion history
        clone.completed = Data:isQuestCompletedOnDate(quest, date_str)

        return clone
    end

    -- Daily quests - always show
    for _, quest in ipairs(all_quests.daily or {}) do
        table.insert(quests, cloneQuestForDate(quest))
    end

    -- Weekly quests - show for all days
    for _, quest in ipairs(all_quests.weekly or {}) do
        table.insert(quests, cloneQuestForDate(quest))
    end

    -- Monthly quests
    for _, quest in ipairs(all_quests.monthly or {}) do
        table.insert(quests, cloneQuestForDate(quest))
    end

    return quests
end

-- Legacy function for backward compatibility
function Timeline:getTodayQuests()
    return self:getQuestsForDate(os.date("%Y-%m-%d"))
end

--[[--
Filter quests by time slot.
--]]
function Timeline:getQuestsForSlot(quests, slot)
    local slot_quests = {}
    for _, quest in ipairs(quests) do
        if quest.time_slot == slot then
            table.insert(slot_quests, quest)
        end
    end
    return slot_quests
end

return Timeline
