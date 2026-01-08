--[[--
Timeline module for Life Tracker.
Visual day view with quests grouped by time-of-day slots.
@module lifetracker.timeline
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
local HorizontalSpan = require("ui/widget/horizontalspan")
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

local Data = require("modules/data")
local Navigation = require("modules/navigation")

local Timeline = {}

-- UI Constants (match Dashboard)
local TOUCH_TARGET_HEIGHT = 48
local BUTTON_WIDTH = 50

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
    local current_time = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})

    -- Calculate new date
    local new_time = current_time + (offset * 86400)
    self.view_date = os.date("%Y-%m-%d", new_time)

    -- Refresh view
    if self.timeline_widget then
        UIManager:close(self.timeline_widget)
    end
    self:showTimelineView()
end

--[[--
Build and display the timeline view.
Groups quests by time slot (Morning, Afternoon, Evening, Night).
--]]
function Timeline:showTimelineView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top 1/8 (12.5%) for menu gesture
    local top_safe_zone = math.floor(screen_height / 8)

    local content = VerticalGroup:new{ align = "left" }

    -- Header with date (in top zone - non-interactive)
    local is_today = self.view_date == os.date("%Y-%m-%d")
    local view_time = os.time({
        year = tonumber(self.view_date:sub(1,4)),
        month = tonumber(self.view_date:sub(6,7)),
        day = tonumber(self.view_date:sub(9,10))
    })
    local date_str = os.date("%A, %B %d", view_time)
    local header_text = is_today and ("TODAY - " .. date_str) or date_str

    table.insert(content, TextWidget:new{
        text = header_text,
        face = Font:getFace("tfont", 20),
        bold = true,
    })
    -- Navigation hint
    table.insert(content, TextWidget:new{
        text = _("< Swipe to navigate days >"),
        face = Font:getFace("cfont", 12),
        fgcolor = Blitbuffer.gray(0.5),
    })

    -- Add spacer to push interactive content below top_safe_zone
    local header_height = 50  -- Header + nav hint
    local spacer_needed = top_safe_zone - Size.padding.large - header_height
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- All interactive content starts here (below top_safe_zone)
    self.current_y = top_safe_zone + Size.padding.small

    -- Get settings and quests
    local settings = Data:loadUserSettings()
    local time_slots = (settings and settings.time_slots) or {"Morning", "Afternoon", "Evening", "Night"}
    local today_quests = self:getQuestsForDate(self.view_date)

    -- Track completion stats
    local total_quests = 0
    local completed_quests = 0

    -- Store quest positions for tap handling
    self.quest_touch_areas = {}

    -- Build time slot sections
    for _, slot in ipairs(time_slots) do
        local slot_quests = self:getQuestsForSlot(today_quests, slot)
        total_quests = total_quests + #slot_quests

        -- Slot header with separator line
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = content_width, h = 2 },
            background = Blitbuffer.COLOR_BLACK,
        })
        self.current_y = self.current_y + 2
        table.insert(content, TextWidget:new{
            text = string.upper(slot),
            face = Font:getFace("tfont", 16),
            bold = true,
        })
        self.current_y = self.current_y + 22
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        self.current_y = self.current_y + Size.padding.small

        -- Quest items for this slot
        if #slot_quests == 0 then
            table.insert(content, TextWidget:new{
                text = "  (no quests)",
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.gray(0.4),
            })
            self.current_y = self.current_y + 20
        else
            for _, quest in ipairs(slot_quests) do
                if quest.completed then
                    completed_quests = completed_quests + 1
                end

                -- Build modern quest row with OK/Skip buttons
                local quest_row = self:buildQuestRow(quest, content_width)

                -- Store quest info with Y position for tap handling
                table.insert(self.quest_touch_areas, {
                    quest = quest,
                    y = self.current_y,
                })

                table.insert(content, quest_row)
                self.current_y = self.current_y + TOUCH_TARGET_HEIGHT + 2
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

    -- Wrap content in frame
    local padded_content = FrameContainer:new{
        width = screen_width - Navigation.TAB_WIDTH,
        height = screen_height,
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

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

    -- Create the main layout with content and navigation
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
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

    -- Store top_safe_zone for gesture handlers
    self.top_safe_zone = top_safe_zone

    -- Setup quest tap handlers (below top zone)
    self:setupQuestTapHandlers()

    -- Top zone tap handler - CLOSE plugin to access KOReader menu
    local timeline = self
    self.timeline_widget.ges_events.TopTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = 0,
                w = screen_width,
                h = top_safe_zone,
            },
        },
    }
    self.timeline_widget.onTopTap = function()
        UIManager:close(timeline.timeline_widget)
        return true
    end

    self.timeline_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            -- Only capture swipes below top 1/8 zone
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
Build a single quest row with OK/Skip buttons (matches Dashboard style).
--]]
function Timeline:buildQuestRow(quest, content_width)
    local title_width = content_width - BUTTON_WIDTH * 2 - Size.padding.small * 3

    local status_bg = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE
    local text_color = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

    -- Quest title
    local title_widget = TextWidget:new{
        text = quest.title,
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

    -- Put buttons on LEFT for easier tapping, then title
    local row = HorizontalGroup:new{
        align = "center",
        complete_button,
        HorizontalSpan:new{ width = 2 },
        skip_button,
        HorizontalSpan:new{ width = Size.padding.small },
        FrameContainer:new{
            width = title_width,
            height = TOUCH_TARGET_HEIGHT,
            padding = Size.padding.small,
            bordersize = 0,
            background = status_bg,
            title_widget,
        },
    }

    return FrameContainer:new{
        width = content_width,
        height = TOUCH_TARGET_HEIGHT,
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

--[[--
Setup tap handlers for quest items.
Uses same percentage-based detection as Dashboard.
--]]
function Timeline:setupQuestTapHandlers()
    local content_width = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2

    for idx, quest_info in ipairs(self.quest_touch_areas) do
        local row_y = quest_info.y

        -- Single tap handler for entire row - determine action by X position
        local row_gesture = "QuestRow_" .. idx
        self.timeline_widget.ges_events[row_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large,
                    y = row_y,
                    w = content_width,
                    h = TOUCH_TARGET_HEIGHT,
                },
            },
        }

        local timeline = self
        local quest = quest_info.quest

        self.timeline_widget["on" .. row_gesture] = function(_, _, ges)
            -- Buttons are on LEFT: OK (0-11%), Skip (11-22%), Title (22%+)
            local tap_x = ges.pos.x - Size.padding.large
            local tap_percent = tap_x / content_width

            if tap_percent < 0.11 then
                -- Leftmost ~11% = OK button
                timeline:toggleQuestComplete(quest)
            elseif tap_percent < 0.22 then
                -- Next ~11% = Skip button
                timeline:skipQuest(quest)
            else
                -- Right 78% = Title area
                timeline:showQuestActions(quest)
            end
            return true
        end
    end
end

--[[--
Show actions for a quest.
--]]
function Timeline:showQuestActions(quest)
    local complete_text = quest.completed and _("Mark Incomplete") or _("Mark Complete")

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

    local message
    if quest_type then
        if quest.completed then
            Data:uncompleteQuest(quest_type, quest.id)
            message = _("Quest marked incomplete")
        else
            Data:completeQuest(quest_type, quest.id)
            message = _("Quest completed!")
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
            UIManager:show(InfoMessage:new{
                text = message,
                timeout = 1,
            })
        end)
    end
end

--[[--
Skip a quest for today.
--]]
function Timeline:skipQuest(quest)
    local today = Data:getCurrentDate()
    local all_quests = Data:loadAllQuests()
    local quest_type = nil

    for qtype, quests in pairs(all_quests) do
        for _, q in ipairs(quests) do
            if q.id == quest.id then
                q.skipped_date = today
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
Get all quests that should appear on a specific date.
@param date_str Date in YYYY-MM-DD format
--]]
function Timeline:getQuestsForDate(date_str)
    local all_quests = Data:loadAllQuests()
    if not all_quests then return {} end

    local quests = {}

    -- Daily quests - always show
    for _, quest in ipairs(all_quests.daily or {}) do
        table.insert(quests, quest)
    end

    -- Weekly quests - show for all days
    for _, quest in ipairs(all_quests.weekly or {}) do
        -- Show weekly quests for all days of the week
        table.insert(quests, quest)
    end

    -- Monthly quests - check if date is in the current month
    for _, quest in ipairs(all_quests.monthly or {}) do
        table.insert(quests, quest)
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
