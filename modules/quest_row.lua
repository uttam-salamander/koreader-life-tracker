--[[--
Shared Quest Row UI component.
Provides consistent quest row rendering across Dashboard, Quests, and Timeline modules.

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

local Data = require("modules/data")
local UIConfig = require("modules/ui_config")

local QuestRow = {}

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
@param callbacks table Callback functions {on_complete, on_edit, on_delete, on_close}
@param date string|nil Date context (defaults to today)
--]]
function QuestRow.showDetailsDialog(quest, quest_type, callbacks, date)
    local check_date = date or os.date("%Y-%m-%d")
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
                if callbacks.on_complete then
                    callbacks.on_complete(quest, quest_type)
                end
            end,
        }},
        {{
            text = _("Edit Quest"),
            callback = function()
                UIManager:close(dialog)
                if callbacks.on_edit then
                    callbacks.on_edit(quest, quest_type)
                else
                    QuestRow.showEditDialog(quest, quest_type, callbacks.on_refresh)
                end
            end,
        }},
        {{
            text = _("Delete Quest"),
            callback = function()
                UIManager:close(dialog)
                if callbacks.on_delete then
                    callbacks.on_delete(quest, quest_type)
                else
                    QuestRow.showDeleteConfirmation(quest, quest_type, callbacks.on_refresh)
                end
            end,
        }},
        {{
            text = _("Close"),
            callback = function()
                UIManager:close(dialog)
                if callbacks.on_close then
                    callbacks.on_close()
                end
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
  - callbacks: table {on_complete, on_skip, on_plus, on_minus, on_title_tap, on_refresh}
@return Widget The quest row widget
--]]
function QuestRow.build(quest, options)
    local quest_type = options.quest_type or "daily"
    local content_width = options.content_width or (Screen:getWidth() - Size.padding.large * 2)
    local check_date = options.date or os.date("%Y-%m-%d")
    local show_streak = options.show_streak ~= false
    local callbacks = options.callbacks or {}
    local colors = UIConfig:getColors()

    -- Check completion status for the given date
    local is_completed = Data:isQuestCompletedOnDate(quest, check_date)
    local status_bg = (is_completed and colors.completed_bg) or colors.background
    local text_color = (is_completed and colors.muted) or colors.foreground

    -- Check if progressive quest needs daily reset
    local today = os.date("%Y-%m-%d")
    if quest.is_progressive and quest.progress_last_date ~= today then
        quest.progress_current = 0
    end

    -- Build quest title with optional streak
    local quest_text = quest.title
    if show_streak and quest.streak and quest.streak > 0 then
        quest_text = quest_text .. string.format(" (%d)", quest.streak)
    end

    local row
    local BUTTON_GAP = UIConfig:dim("button_gap") or 2

    -- Default title tap handler shows details dialog
    local function on_title_tap()
        if callbacks.on_title_tap then
            callbacks.on_title_tap(quest, quest_type)
        else
            QuestRow.showDetailsDialog(quest, quest_type, {
                on_complete = callbacks.on_complete,
                on_edit = callbacks.on_edit,
                on_delete = callbacks.on_delete,
                on_refresh = callbacks.on_refresh,
            }, check_date)
        end
    end

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10] [+] [Title]
        local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
        local PROGRESS_WIDTH = getProgressWidth()
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - BUTTON_GAP * 2 - Size.padding.small

        -- Minus button
        local minus_button = Button:new{
            text = "−",
            width = SMALL_BUTTON_WIDTH,
            max_width = SMALL_BUTTON_WIDTH,
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 16,
            text_font_bold = true,
            callback = function()
                if callbacks.on_minus then
                    callbacks.on_minus(quest, quest_type)
                end
            end,
        }

        -- Progress display
        local current = quest.progress_current or 0
        local target = quest.progress_target or 1
        local pct = math.min(1, current / target)
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
                    face = Font:getFace("cfont", 11),
                    bold = is_completed,
                },
            },
        }

        -- Plus button
        local plus_button = Button:new{
            text = "+",
            width = SMALL_BUTTON_WIDTH,
            max_width = SMALL_BUTTON_WIDTH,
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 16,
            text_font_bold = true,
            enabled = not is_completed,
            callback = function()
                if callbacks.on_plus then
                    callbacks.on_plus(quest, quest_type)
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
            text_font_size = 13,
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
        -- Binary quest layout: [Done] [Skip] [Title]
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
            text_font_size = 12,
            text_font_bold = true,
            callback = function()
                if callbacks.on_complete then
                    callbacks.on_complete(quest, quest_type)
                end
            end,
        }

        -- Skip button
        local skip_text = callbacks.skip_text or "Skip"
        local skip_button = Button:new{
            text = skip_text,
            width = getButtonWidth(),
            max_width = getButtonWidth(),
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 10,
            text_font_bold = false,
            callback = function()
                if callbacks.on_skip then
                    callbacks.on_skip(quest, quest_type)
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
            text_font_size = 14,
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
