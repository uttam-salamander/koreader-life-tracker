--[[--
Shared Quest Row UI component.
Provides consistent quest row rendering and operations across all modules.
Handles quest completion, skip, and progress internally.

@module lifetracker.quest_row
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local _ = require("gettext")

local logger = require("logger")

local Data = require("modules/data")
local UIConfig = require("modules/ui_config")
local Celebration = require("modules/celebration")

local QuestRow = {}

-- Debounce tracking to prevent race conditions from rapid taps
local _last_action_time = 0
local DEBOUNCE_MS = 300  -- Minimum ms between actions

local function log(...)
    logger.info("QuestRow:", ...)
end

--[[--
Check if enough time has passed since last action (debounce).
Uses wall clock time (os.time) instead of CPU time (os.clock) since
CPU time stops during device suspend on e-ink devices.
@return boolean True if action should proceed, false if debounced
--]]
local function checkDebounce()
    local now = os.time() * 1000  -- Wall clock time in milliseconds
    if now - _last_action_time < DEBOUNCE_MS then
        log("Action debounced - too fast")
        return false
    end
    _last_action_time = now
    return true
end

--[[--
Toggle quest completion and refresh the view.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param date string Date to toggle completion for
@param on_refresh function Callback to refresh the view
--]]
function QuestRow.handleComplete(quest, quest_type, date, on_refresh)
    -- Debounce to prevent race condition from rapid taps
    if not checkDebounce() then return end

    -- Validate quest parameter
    if not quest or not quest.id then
        log("handleComplete called with invalid quest")
        return
    end

    local was_completed = Data:isQuestCompletedOnDate(quest, date)

    if was_completed then
        Data:uncompleteQuest(quest_type, quest.id, date)
    else
        -- Data:completeQuest now handles streak calculation atomically
        Data:completeQuest(quest_type, quest.id, date)
    end

    -- Refresh view
    if on_refresh then
        on_refresh()
    end

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

--[[--
Skip a quest for the given date.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param date string Date to skip for
@param on_refresh function Callback to refresh the view
--]]
function QuestRow.handleSkip(quest, quest_type, date, on_refresh)
    if not quest or not quest.id then
        log("handleSkip called with invalid quest")
        return
    end

    local quests = Data:loadAllQuests()
    for _, q in ipairs(quests[quest_type] or {}) do
        if q.id == quest.id then
            q.skipped_date = date
            break
        end
    end
    Data:saveAllQuests(quests)

    if on_refresh then
        on_refresh()
    end

    UIManager:show(InfoMessage:new{
        text = _("Quest skipped for today"),
        timeout = 1,
    })
end

--[[--
Unskip a quest (clear skipped status).
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param on_refresh function Callback to refresh the view
--]]
function QuestRow.handleUnskip(quest, quest_type, on_refresh)
    if not quest or not quest.id then
        log("handleUnskip called with invalid quest")
        return
    end

    local quests = Data:loadAllQuests()
    for _, q in ipairs(quests[quest_type] or {}) do
        if q.id == quest.id then
            q.skipped_date = nil
            break
        end
    end
    Data:saveAllQuests(quests)

    if on_refresh then
        on_refresh()
    end

    UIManager:show(InfoMessage:new{
        text = _("Quest restored"),
        timeout = 1,
    })
end

--[[--
Increment progress for a progressive quest.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param on_refresh function Callback to refresh the view
--]]
function QuestRow.handlePlus(quest, quest_type, on_refresh)
    -- Debounce to prevent race condition from rapid taps
    if not checkDebounce() then return end

    if not quest or not quest.id then
        log("handlePlus called with invalid quest")
        return
    end

    local updated = Data:incrementQuestProgress(quest_type, quest.id)

    if updated then
        if on_refresh then
            on_refresh()
        end

        if updated.completed then
            UIManager:nextTick(function()
                Celebration:showCompletion()
            end)
        end
    end
end

--[[--
Decrement progress for a progressive quest.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param on_refresh function Callback to refresh the view
--]]
function QuestRow.handleMinus(quest, quest_type, on_refresh)
    -- Debounce to prevent race condition from rapid taps
    if not checkDebounce() then return end

    if not quest or not quest.id then
        log("handleMinus called with invalid quest")
        return
    end

    local updated = Data:decrementQuestProgress(quest_type, quest.id)
    if updated and on_refresh then
        on_refresh()
    end
end

-- Dimension helpers
local function getTouchTargetHeight()
    return UIConfig:dim("touch_target_height")
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
Build a 30-day heatmap string for a specific quest.
@param quest table The quest object
@return string ASCII heatmap representation
--]]
function QuestRow.buildQuestHeatmap(quest)
    if not quest then return "No data" end

    local today = os.time()
    local lines = {}

    -- Build 30 days in 5 rows of 6
    for row = 0, 4 do
        local line = ""
        for col = 0, 5 do
            local day_offset = row * 6 + col
            if day_offset >= 30 then break end

            local date_time = today - (29 - day_offset) * 86400
            local date_str = os.date("%Y-%m-%d", date_time)

            local completed = Data:isQuestCompletedOnDate(quest, date_str)
            line = line .. (completed and "■ " or "□ ")
        end
        if line ~= "" then
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

--[[--
Show quest details dialog with heatmap and action buttons.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param options table Options {on_refresh}
@param date string|nil Date context (defaults to today)
--]]
function QuestRow.showDetailsDialog(quest, quest_type, options, date)
    local check_date = date or os.date("%Y-%m-%d")
    local on_refresh = options and options.on_refresh
    local is_completed = Data:isQuestCompletedOnDate(quest, check_date)

    -- Build heatmap
    local heatmap = QuestRow.buildQuestHeatmap(quest)

    -- Build info text
    local streak_text = quest.streak and quest.streak > 0
        and string.format("Streak: %d days", quest.streak)
        or "No streak yet"

    local energy_text = quest.energy_required or "Any"
    local time_slot = quest.time_slot or "Any time"
    local category = quest.category or "None"

    local info_text = string.format(
        "Time: %s | Energy: %s | %s\nCategory: %s | Type: %s",
        time_slot,
        energy_text,
        streak_text,
        category,
        quest_type:sub(1,1):upper() .. quest_type:sub(2)
    )

    local details = string.format(
        "%s\n\nLast 30 days:\n%s\n\n%s",
        quest.title,
        heatmap,
        info_text
    )

    local complete_text = is_completed and _("Mark Incomplete") or _("Mark Complete")

    local dialog
    local buttons = {
        {{
            text = complete_text,
            callback = function()
                UIManager:close(dialog)
                QuestRow.handleComplete(quest, quest_type, check_date, on_refresh)
            end,
        }},
        {{
            text = _("Edit Quest"),
            callback = function()
                UIManager:close(dialog)
                QuestRow.showEditDialog(quest, quest_type, on_refresh)
            end,
        }},
        {{
            text = _("Delete Quest"),
            callback = function()
                UIManager:close(dialog)
                QuestRow.showDeleteConfirmation(quest, quest_type, on_refresh)
            end,
        }},
        {{
            text = _("Close"),
            callback = function()
                UIManager:close(dialog)
            end,
        }},
    }

    dialog = ButtonDialog:new{
        title = details,
        title_align = "left",
        buttons = buttons,
        width = Screen:getWidth() * 0.9,
    }
    UIManager:show(dialog)
    return dialog
end

--[[--
Show edit dialog for a quest.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param on_refresh function|nil Callback to refresh the view after edit
--]]
function QuestRow.showEditDialog(quest, quest_type, on_refresh)
    local edit_dialog
    edit_dialog = InputDialog:new{
        title = _("Edit Quest Title"),
        input = quest.title,
        input_hint = _("Enter quest title"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(edit_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_title = edit_dialog:getInputText()
                        if new_title and new_title ~= "" then
                            local all_quests = Data:loadAllQuests()
                            for _, q in ipairs(all_quests[quest_type] or {}) do
                                if q.id == quest.id then
                                    q.title = new_title
                                    break
                                end
                            end
                            Data:saveAllQuests(all_quests)
                            UIManager:close(edit_dialog)

                            if on_refresh then
                                on_refresh()
                            end

                            UIManager:show(InfoMessage:new{
                                text = _("Quest updated"),
                                timeout = 1,
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
    return edit_dialog
end

--[[--
Show delete confirmation dialog.
@param quest table The quest object
@param quest_type string "daily", "weekly", or "monthly"
@param on_refresh function|nil Callback to refresh the view after delete
--]]
function QuestRow.showDeleteConfirmation(quest, quest_type, on_refresh)
    local confirm_dialog
    confirm_dialog = ButtonDialog:new{
        title = string.format(_("Delete \"%s\"?"), quest.title),
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(confirm_dialog)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(confirm_dialog)

                    local all_quests = Data:loadAllQuests()
                    local quests_list = all_quests[quest_type] or {}
                    for i, q in ipairs(quests_list) do
                        if q.id == quest.id then
                            table.remove(quests_list, i)
                            break
                        end
                    end
                    Data:saveAllQuests(all_quests)

                    if on_refresh then
                        on_refresh()
                    end

                    UIManager:show(InfoMessage:new{
                        text = _("Quest deleted"),
                        timeout = 1,
                    })
                end,
            }},
        },
    }
    UIManager:show(confirm_dialog)
    return confirm_dialog
end

--[[--
Build a quest row widget.
@param quest table The quest object
@param options table Options:
  - quest_type: string "daily", "weekly", or "monthly"
  - content_width: number Available width
  - date: string|nil Date context (defaults to today)
  - show_streak: boolean Show streak in title (default true)
  - is_skipped: boolean Whether quest is skipped (for showing Undo button)
  - on_refresh: function Callback to refresh the view after operations
@return Widget The quest row widget
--]]
function QuestRow.build(quest, options)
    if not quest or not quest.id then
        log("build called with invalid quest")
        return nil
    end

    options = options or {}
    local quest_type = options.quest_type or "daily"
    local content_width = options.content_width or (Screen:getWidth() - Size.padding.large * 2)
    local check_date = options.date or os.date("%Y-%m-%d")
    local show_streak = options.show_streak ~= false
    local is_skipped = options.is_skipped or false
    local on_refresh = options.on_refresh
    local colors = UIConfig:getColors()

    -- Check completion status for the given date
    local is_completed = Data:isQuestCompletedOnDate(quest, check_date)
    local status_bg = (is_completed and colors.completed_bg) or colors.background
    local text_color = (is_completed and colors.muted) or colors.foreground

    -- Build quest title with optional streak
    local quest_text = quest.title
    if show_streak and quest.streak and quest.streak > 0 then
        quest_text = quest_text .. string.format(" (%d)", quest.streak)
    end

    local row
    local BUTTON_GAP = UIConfig:dim("button_gap") or 2

    -- Title tap handler shows details dialog
    local function on_title_tap()
        QuestRow.showDetailsDialog(quest, quest_type, {
            on_refresh = on_refresh,
        }, check_date)
    end

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10] [+] [Title]
        local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
        local PROGRESS_WIDTH = getProgressWidth()
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - BUTTON_GAP * 2 - Size.padding.small

        -- Progress values for display and button states
        -- Check if progress should be reset for new day (display only, Data layer handles actual reset)
        local today = os.date("%Y-%m-%d")
        local current = (quest.progress_last_date == today) and (quest.progress_current or 0) or 0
        local target = quest.progress_target or 1
        local progress_complete = current >= target

        -- Minus button
        local minus_button = Button:new{
            text = "−",
            width = SMALL_BUTTON_WIDTH,
            max_width = SMALL_BUTTON_WIDTH,
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("button_icon"),
            text_font_bold = true,
            callback = function()
                QuestRow.handleMinus(quest, quest_type, on_refresh)
            end,
        }

        -- Progress display (guard against division by zero and inf/NaN)
        local pct = target > 0 and math.min(1, current / target) or 0
        -- Explicit guard against inf/NaN from floating point edge cases
        if pct ~= pct or pct == math.huge or pct == -math.huge then pct = 0 end
        local progress_bg = is_completed and Blitbuffer.gray(0.7) or Blitbuffer.gray(1 - pct * 0.5)
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
                    face = UIConfig:getFont("cfont", UIConfig:fontSize("progress")),
                    bold = is_completed,
                },
            },
        }

        -- Plus button - enabled when progress is not yet complete
        local plus_button = Button:new{
            text = "+",
            width = SMALL_BUTTON_WIDTH,
            max_width = SMALL_BUTTON_WIDTH,
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("button_icon"),
            text_font_bold = true,
            enabled = not progress_complete,
            callback = function()
                QuestRow.handlePlus(quest, quest_type, on_refresh)
            end,
        }

        -- Title button (tappable)
        local title_button = Button:new{
            text = quest_text,
            width = title_width,
            max_width = title_width,
            bordersize = 0,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("body_small"),
            text_font_bold = false,
            fgcolor = text_color,
            background = status_bg,
            callback = on_title_tap,
        }

        row = HorizontalGroup:new{
            align = "center",
            minus_button,
            HorizontalSpan:new{ width = BUTTON_GAP },
            progress_display,
            HorizontalSpan:new{ width = BUTTON_GAP },
            plus_button,
            HorizontalSpan:new{ width = Size.padding.small },
            title_button,
        }
    else
        -- Binary quest layout: [Done] [Skip/Undo] [Title]
        local title_width = content_width - getButtonWidth() * 2 - BUTTON_GAP - Size.padding.small

        -- Complete button
        local complete_text = is_completed and "X" or "Done"
        local complete_button = Button:new{
            text = complete_text,
            width = getButtonWidth(),
            max_width = getButtonWidth(),
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("button_primary"),
            text_font_bold = true,
            callback = function()
                QuestRow.handleComplete(quest, quest_type, check_date, on_refresh)
            end,
        }

        -- Skip/Undo button
        local skip_text = is_skipped and "Undo" or "Skip"
        local skip_button = Button:new{
            text = skip_text,
            width = getButtonWidth(),
            max_width = getButtonWidth(),
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("button_secondary"),
            text_font_bold = false,
            callback = function()
                if is_skipped then
                    QuestRow.handleUnskip(quest, quest_type, on_refresh)
                else
                    QuestRow.handleSkip(quest, quest_type, check_date, on_refresh)
                end
            end,
        }

        -- Title button (tappable)
        local title_button = Button:new{
            text = quest_text,
            width = title_width,
            max_width = title_width,
            bordersize = 0,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("body"),
            text_font_bold = false,
            fgcolor = text_color,
            background = status_bg,
            callback = on_title_tap,
        }

        row = HorizontalGroup:new{
            align = "center",
            complete_button,
            HorizontalSpan:new{ width = BUTTON_GAP },
            skip_button,
            HorizontalSpan:new{ width = Size.padding.small },
            title_button,
        }
    end

    -- Wrap in frame container
    return FrameContainer:new{
        width = content_width,
        height = getTouchTargetHeight(),
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

return QuestRow
