--[[--
Quest UI Helpers module for Life Tracker.
Provides button factories and common UI builders for quest rows.
Used by dashboard, quests, and timeline modules.

@module lifetracker.quest_ui_helpers
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen

local UIConfig = require("modules/ui_config")

local QuestUI = {}

-- ============================================================================
-- Constants (from UIConfig for consistency)
-- ============================================================================

-- Get scaled dimensions from UIConfig
function QuestUI.getSmallButtonWidth()
    return UIConfig:dim("small_button_width")
end

function QuestUI.getButtonWidth()
    return UIConfig:dim("button_width")
end

function QuestUI.getProgressWidth()
    return UIConfig:dim("progress_width")
end

function QuestUI.getRowHeight()
    return UIConfig:dim("touch_target_height")
end

function QuestUI.getButtonGap()
    return UIConfig:dim("button_gap") or Screen:scaleBySize(4)
end

-- ============================================================================
-- Button Factory Functions
-- ============================================================================

--[[--
Create a minus button for progressive quests.
@param callback function The callback when button is pressed
@return Button The minus button widget
--]]
function QuestUI.createMinusButton(callback)
    return Button:new{
        text = "−",
        width = QuestUI.getSmallButtonWidth(),
        max_width = QuestUI.getSmallButtonWidth(),
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("button_icon") or 16,
        text_font_bold = true,
        callback = callback,
    }
end

--[[--
Create a plus button for progressive quests.
@param callback function The callback when button is pressed
@param enabled bool Whether the button is enabled (default true)
@return Button The plus button widget
--]]
function QuestUI.createPlusButton(callback, enabled)
    if enabled == nil then enabled = true end
    return Button:new{
        text = "+",
        width = QuestUI.getSmallButtonWidth(),
        max_width = QuestUI.getSmallButtonWidth(),
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("button_icon") or 16,
        text_font_bold = true,
        enabled = enabled,
        callback = callback,
    }
end

--[[--
Create a Done/Complete button for binary quests.
@param callback function The callback when button is pressed
@param is_completed bool Whether the quest is already completed
@return Button The done button widget
--]]
function QuestUI.createDoneButton(callback, is_completed)
    local text = is_completed and "X" or "Done"
    return Button:new{
        text = text,
        width = QuestUI.getButtonWidth(),
        max_width = QuestUI.getButtonWidth(),
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("button_primary") or 12,
        text_font_bold = true,
        callback = callback,
    }
end

--[[--
Create a Skip/Undo button for quests.
@param callback function The callback when button is pressed
@param text string Button text ("Skip" or "Undo")
@return Button The skip button widget
--]]
function QuestUI.createSkipButton(callback, text)
    text = text or "Skip"
    return Button:new{
        text = text,
        width = QuestUI.getButtonWidth(),
        max_width = QuestUI.getButtonWidth(),
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("button_secondary") or 10,
        text_font_bold = false,
        callback = callback,
    }
end

-- ============================================================================
-- Progress Display Builder
-- ============================================================================

--[[--
Build a progress display for progressive quests.
Shows current/target progress with optional unit.

@param current number Current progress value
@param target number Target progress value
@param completed bool Whether the quest is completed
@param options table Optional: {show_unit, unit, width, height}
@return FrameContainer The progress display widget
--]]
function QuestUI.buildProgressDisplay(current, target, completed, options)
    options = options or {}
    local width = options.width or QuestUI.getProgressWidth()
    local height = options.height or (QuestUI.getRowHeight() - 4)

    local pct = math.min(1, current / target)
    local progress_bg = completed and Blitbuffer.gray(0.7) or Blitbuffer.gray(1 - pct * 0.5)

    local progress_text = string.format("%d/%d", current, target)
    if options.show_unit and options.unit then
        -- Truncate unit to 4 characters
        progress_text = progress_text .. " " .. options.unit:sub(1, 4)
    end

    return FrameContainer:new{
        width = width,
        height = height,
        padding = 2,
        bordersize = 1,
        background = progress_bg,
        CenterContainer:new{
            dimen = Geom:new{w = width - 6, h = height - 6},
            TextWidget:new{
                text = progress_text,
                face = UIConfig:getFont("cfont", UIConfig:fontSize("progress") or 11),
                bold = completed,
            },
        },
    }
end

-- ============================================================================
-- Quest Title Builder
-- ============================================================================

--[[--
Build a quest title widget.
Optionally includes streak count.

@param quest table The quest object
@param options table {show_streak, max_width, text_color}
@return TextWidget The title widget
--]]
function QuestUI.buildQuestTitle(quest, options)
    options = options or {}

    local quest_text = quest.title
    if options.show_streak and quest.streak and quest.streak > 0 then
        quest_text = quest_text .. string.format(" (%d)", quest.streak)
    end

    return TextWidget:new{
        text = quest_text,
        face = UIConfig:getFont("cfont", UIConfig:fontSize("body_small") or 13),
        fgcolor = options.text_color or UIConfig:color("foreground"),
        max_width = options.max_width,
    }
end

-- ============================================================================
-- Quest Row Assemblers
-- ============================================================================

--[[--
Assemble a progressive quest row.
Layout: [−] [progress] [+] [Title]

@param quest table The quest object
@param options table {content_width, show_streak, status_bg, text_color}
@param callbacks table {on_minus, on_plus}
@return HorizontalGroup The row content
--]]
function QuestUI.assembleProgressiveRow(quest, options, callbacks)
    local content_width = options.content_width
    local SMALL_BUTTON_WIDTH = QuestUI.getSmallButtonWidth()
    local PROGRESS_WIDTH = QuestUI.getProgressWidth()
    local BUTTON_GAP = QuestUI.getButtonGap()
    local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - BUTTON_GAP * 2 - Size.padding.small

    local current = quest.progress_current or 0
    local target = quest.progress_target or 1

    return HorizontalGroup:new{
        align = "center",
        QuestUI.createMinusButton(callbacks.on_minus),
        HorizontalSpan:new{ width = BUTTON_GAP },
        QuestUI.buildProgressDisplay(current, target, quest.completed, {
            show_unit = options.show_unit,
            unit = quest.progress_unit,
        }),
        HorizontalSpan:new{ width = BUTTON_GAP },
        QuestUI.createPlusButton(callbacks.on_plus, not quest.completed),
        HorizontalSpan:new{ width = Size.padding.small },
        FrameContainer:new{
            width = title_width,
            height = QuestUI.getRowHeight(),
            padding = Size.padding.small,
            bordersize = 0,
            background = options.status_bg,
            QuestUI.buildQuestTitle(quest, {
                show_streak = options.show_streak,
                max_width = title_width - Size.padding.small * 2,
                text_color = options.text_color,
            }),
        },
    }
end

--[[--
Assemble a binary quest row.
Layout: [Done] [Skip] [Title]

@param quest table The quest object
@param options table {content_width, show_streak, status_bg, text_color, skip_text}
@param callbacks table {on_complete, on_skip}
@return HorizontalGroup The row content
--]]
function QuestUI.assembleBinaryRow(quest, options, callbacks)
    local content_width = options.content_width
    local BUTTON_GAP = QuestUI.getButtonGap()
    local title_width = content_width - QuestUI.getButtonWidth() * 2 - BUTTON_GAP - Size.padding.small

    return HorizontalGroup:new{
        align = "center",
        QuestUI.createDoneButton(callbacks.on_complete, quest.completed),
        HorizontalSpan:new{ width = BUTTON_GAP },
        QuestUI.createSkipButton(callbacks.on_skip, options.skip_text or "Skip"),
        HorizontalSpan:new{ width = Size.padding.small },
        FrameContainer:new{
            width = title_width,
            height = QuestUI.getRowHeight(),
            padding = Size.padding.small,
            bordersize = 0,
            background = options.status_bg,
            QuestUI.buildQuestTitle(quest, {
                show_streak = options.show_streak,
                max_width = title_width - Size.padding.small * 2,
                text_color = options.text_color,
            }),
        },
    }
end

--[[--
Build a complete quest row with frame container.
Determines layout based on quest.is_progressive.

@param quest table The quest object
@param options table {content_width, show_streak, show_unit, skip_text}
@param callbacks table {on_complete, on_skip, on_minus, on_plus}
@return FrameContainer The complete quest row widget
--]]
function QuestUI.buildQuestRow(quest, options, callbacks)
    local colors = UIConfig:getColors() or {}
    local default_bg = Blitbuffer.COLOR_WHITE
    local default_fg = Blitbuffer.COLOR_BLACK

    local status_bg = (quest.completed and (colors.completed_bg or default_bg)) or (colors.background or default_bg)
    local text_color = (quest.completed and (colors.muted or default_fg)) or (colors.foreground or default_fg)

    local row_options = {
        content_width = options.content_width,
        show_streak = options.show_streak,
        show_unit = options.show_unit,
        skip_text = options.skip_text,
        status_bg = status_bg,
        text_color = text_color,
    }

    local row
    if quest.is_progressive then
        row = QuestUI.assembleProgressiveRow(quest, row_options, {
            on_minus = callbacks.on_minus,
            on_plus = callbacks.on_plus,
        })
    else
        row = QuestUI.assembleBinaryRow(quest, row_options, {
            on_complete = callbacks.on_complete,
            on_skip = callbacks.on_skip,
        })
    end

    return FrameContainer:new{
        width = options.content_width,
        height = QuestUI.getRowHeight(),
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

return QuestUI
