--[[--
Timeline module for Life Tracker.
Visual day view with quests grouped by time-of-day slots.
@module lifetracker.timeline
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
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

local Timeline = {}

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
    local content = VerticalGroup:new{ align = "left" }

    -- Header with date
    local date_str = os.date("%A, %B %d")
    table.insert(content, TextWidget:new{
        text = "TODAY - " .. date_str,
        face = Font:getFace("tfont", 20),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })

    -- Get settings and quests
    local settings = Data:loadSettings()
    local time_slots = settings.time_slots or {"Morning", "Afternoon", "Evening", "Night"}
    local today_quests = self:getTodayQuests()

    -- Track completion stats
    local total_quests = 0
    local completed_quests = 0

    -- Build time slot sections
    for _, slot in ipairs(time_slots) do
        local slot_quests = self:getQuestsForSlot(today_quests, slot)
        total_quests = total_quests + #slot_quests

        -- Slot header
        table.insert(content, LineWidget:new{
            dimen = { w = screen_width - 40, h = 2 },
            background = 0x000000,
        })
        table.insert(content, TextWidget:new{
            text = "═══ " .. string.upper(slot) .. " ═══",
            face = Font:getFace("tfont", 16),
            bold = true,
        })
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

        -- Quest items for this slot
        if #slot_quests == 0 then
            table.insert(content, TextWidget:new{
                text = "  (no quests)",
                face = Font:getFace("cfont", 14),
                fgcolor = 0x666666,
            })
        else
            for _, quest in ipairs(slot_quests) do
                local symbol = quest.completed and "✓" or "○"
                local text = quest.title
                if quest.completed then
                    text = "~~" .. text .. "~~"
                    completed_quests = completed_quests + 1
                end

                table.insert(content, TextWidget:new{
                    text = "  " .. symbol .. " " .. text,
                    face = Font:getFace("cfont", 16),
                    fgcolor = quest.completed and 0x888888 or 0x000000,
                })
            end
        end
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })
    end

    -- Progress footer
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - 40, h = 1 },
        background = 0x888888,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local progress_pct = total_quests > 0 and math.floor((completed_quests / total_quests) * 100) or 0
    table.insert(content, TextWidget:new{
        text = string.format("Progress: %d/%d (%d%%)", completed_quests, total_quests, progress_pct),
        face = Font:getFace("tfont", 16),
        bold = true,
    })

    -- Build scrollable container
    local frame = FrameContainer:new{
        width = screen_width,
        height = Screen:getHeight(),
        padding = Size.padding.large,
        bordersize = 0,
        background = 0xFFFFFF,
        content,
    }

    -- Wrap in InputContainer for gestures
    local container = InputContainer:new{
        dimen = Screen:getSize(),
        ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = frame.dimen,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = frame.dimen,
                },
            },
        },
        frame,
    }

    function container:onTap()
        self:showQuestActions()
        return true
    end

    function container:onSwipe(_, ges)
        if ges.direction == "east" then
            -- Swipe right to go back
            UIManager:close(self)
            return true
        end
        return false
    end

    function container:showQuestActions()
        local buttons = {
            {
                {
                    text = _("Complete Quest"),
                    callback = function()
                        UIManager:close(self.action_dialog)
                        Timeline:showQuestPicker("complete")
                    end,
                },
            },
            {
                {
                    text = _("View by Date"),
                    callback = function()
                        UIManager:close(self.action_dialog)
                        Timeline:showDatePicker()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(self.action_dialog)
                        UIManager:close(self)
                    end,
                },
            },
        }

        self.action_dialog = ButtonDialog:new{
            buttons = buttons,
        }
        UIManager:show(self.action_dialog)
    end

    self.timeline_widget = container
    UIManager:show(container)
end

--[[--
Get all quests that should appear today.
Includes daily quests, weekly quests (on their days), monthly quests (on their days).
--]]
function Timeline:getTodayQuests()
    local all_quests = Data:loadAllQuests()
    local today_quests = {}
    local today = os.date("*t")
    local day_of_week = today.wday  -- 1=Sunday, 7=Saturday
    local day_of_month = today.day

    -- Daily quests - always show
    for _, quest in ipairs(all_quests.daily or {}) do
        if not quest.completed then
            table.insert(today_quests, quest)
        end
    end

    -- Weekly quests - show on configured days (or all days if not configured)
    for _, quest in ipairs(all_quests.weekly or {}) do
        if not quest.completed then
            -- For simplicity, show all weekly quests (can add day filtering later)
            table.insert(today_quests, quest)
        end
    end

    -- Monthly quests - show on configured days (or all days if not configured)
    for _, quest in ipairs(all_quests.monthly or {}) do
        if not quest.completed then
            -- For simplicity, show all monthly quests (can add day filtering later)
            table.insert(today_quests, quest)
        end
    end

    -- Also check for completed quests today (to show them crossed off)
    local today_date = os.date("%Y-%m-%d")
    for quest_type, quests in pairs(all_quests) do
        for _, quest in ipairs(quests) do
            if quest.completed and quest.completed_date == today_date then
                -- Already in list or add
                local found = false
                for _, tq in ipairs(today_quests) do
                    if tq.id == quest.id then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(today_quests, quest)
                end
            end
        end
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

--[[--
Show picker to select a quest to complete.
--]]
function Timeline:showQuestPicker(action)
    local today_quests = self:getTodayQuests()
    local incomplete = {}

    for _, quest in ipairs(today_quests) do
        if not quest.completed then
            table.insert(incomplete, quest)
        end
    end

    if #incomplete == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("All quests completed! 🎉"),
        })
        return
    end

    local buttons = {}
    for _, quest in ipairs(incomplete) do
        table.insert(buttons, {
            {
                text = quest.title,
                callback = function()
                    UIManager:close(self.picker_dialog)
                    self:completeQuest(quest)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.picker_dialog)
            end,
        },
    })

    self.picker_dialog = ButtonDialog:new{
        title = _("Select Quest to Complete"),
        buttons = buttons,
    }
    UIManager:show(self.picker_dialog)
end

--[[--
Complete a quest and refresh the timeline.
--]]
function Timeline:completeQuest(quest)
    -- Determine quest type
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
        Data:completeQuest(quest_type, quest.id)

        -- Refresh timeline
        if self.timeline_widget then
            UIManager:close(self.timeline_widget)
        end
        self:showTimelineView()
    end
end

--[[--
Show date picker to view timeline for a different date.
--]]
function Timeline:showDatePicker()
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Date navigation coming soon.\nCurrently showing today's timeline."),
    })
end

return Timeline
