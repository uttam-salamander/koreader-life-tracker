--[[--
Timeline module for Life Tracker.
Visual day view with quests grouped by time-of-day slots.
@module lifetracker.timeline
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
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

-- Touch target height for quest items
local TOUCH_TARGET_HEIGHT = 44

--[[--
Show the timeline view for today.
--]]
function Timeline:show(ui)
    self.ui = ui
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

    local content = VerticalGroup:new{ align = "left" }

    -- Header with date
    local date_str = os.date("%A, %B %d")
    table.insert(content, TextWidget:new{
        text = "TODAY - " .. date_str,
        face = Font:getFace("tfont", 20),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Get settings and quests
    local settings = Data:loadUserSettings()
    local time_slots = (settings and settings.time_slots) or {"Morning", "Afternoon", "Evening", "Night"}
    local today_quests = self:getTodayQuests()

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
        table.insert(content, TextWidget:new{
            text = string.upper(slot),
            face = Font:getFace("tfont", 16),
            bold = true,
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })

        -- Quest items for this slot
        if #slot_quests == 0 then
            table.insert(content, TextWidget:new{
                text = "  (no quests)",
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.gray(0.4),
            })
        else
            for _, quest in ipairs(slot_quests) do
                local symbol = quest.completed and "[X]" or "[ ]"
                local text = quest.title
                if quest.completed then
                    completed_quests = completed_quests + 1
                end

                -- Create tappable quest row
                local quest_row = FrameContainer:new{
                    width = content_width,
                    height = TOUCH_TARGET_HEIGHT,
                    padding = Size.padding.small,
                    bordersize = 0,
                    background = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE,
                    TextWidget:new{
                        text = string.format("  %s %s", symbol, text),
                        face = Font:getFace("cfont", 16),
                        fgcolor = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK,
                    },
                }

                -- Store quest info for tap handling
                table.insert(self.quest_touch_areas, {
                    quest = quest,
                })

                table.insert(content, quest_row)
            end
        end
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
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

    -- Wrap in InputContainer for gestures
    self.timeline_widget = InputContainer:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        ges_events = {},
        main_layout,
    }

    -- Setup quest tap handlers
    self:setupQuestTapHandlers()

    -- Swipe gestures (leave top 10% for KOReader menu)
    local top_safe_zone = math.floor(screen_height * 0.1)
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
            UIManager:close(self.timeline_widget)
            return true
        end
        return false
    end

    UIManager:show(self.timeline_widget)
end

--[[--
Setup tap handlers for quest items.
--]]
function Timeline:setupQuestTapHandlers()
    -- Quest items start after header (approximately Y = 100)
    local quest_y = 100
    local quest_height = TOUCH_TARGET_HEIGHT + Size.padding.small

    for idx, quest_info in ipairs(self.quest_touch_areas) do
        local gesture_name = "QuestTap_" .. idx
        self.timeline_widget.ges_events[gesture_name] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large,
                    y = quest_y + (idx - 1) * quest_height,
                    w = Screen:getWidth() - Navigation.TAB_WIDTH - Size.padding.large * 2,
                    h = quest_height,
                },
            },
        }

        local timeline = self
        local quest = quest_info.quest
        self.timeline_widget["on" .. gesture_name] = function()
            timeline:showQuestActions(quest)
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

    if quest_type then
        if quest.completed then
            Data:uncompleteQuest(quest_type, quest.id)
        else
            Data:completeQuest(quest_type, quest.id)
        end

        -- Refresh timeline
        if self.timeline_widget then
            UIManager:close(self.timeline_widget)
        end
        self:showTimelineView()
    end
end

--[[--
Get all quests that should appear today.
--]]
function Timeline:getTodayQuests()
    local all_quests = Data:loadAllQuests()
    if not all_quests then return {} end

    local today_quests = {}

    -- Daily quests - always show
    for _, quest in ipairs(all_quests.daily or {}) do
        table.insert(today_quests, quest)
    end

    -- Weekly quests
    for _, quest in ipairs(all_quests.weekly or {}) do
        table.insert(today_quests, quest)
    end

    -- Monthly quests
    for _, quest in ipairs(all_quests.monthly or {}) do
        table.insert(today_quests, quest)
    end

    return today_quests
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
