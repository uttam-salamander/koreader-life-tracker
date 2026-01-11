--[[--
Quests module for Life Tracker.
Manages quest CRUD, list views, and completion with inline buttons.

@module lifetracker.quests
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
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
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
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")
local Celebration = require("modules/celebration")

local Quests = {}

-- UI Constants (scaled via UIConfig)
local function getQuestRowHeight()
    return UIConfig:dim("row_height")
end

local function getButtonWidth()
    return UIConfig:dim("button_width")
end

local function getTypeTabHeight()
    return UIConfig:dim("type_tab_height")
end

local function getTypeTabWidth()
    return UIConfig:dim("type_tab_width")
end

local function getSmallButtonWidth()
    return UIConfig:dim("small_button_width")
end

local function getProgressWidth()
    return UIConfig:dim("progress_width")
end

-- Current view state
Quests.current_type = "daily"

--[[--
Show the quests view.
@tparam table ui The UI manager reference
--]]
function Quests:show(ui)
    self.ui = ui
    self:showQuestsView()
end

--[[--
Build the quests view with proper navigation.
--]]
function Quests:showQuestsView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top ~10% for menu gesture
    -- Title can be in this zone (non-interactive), but gesture handlers must not be
    local top_safe_zone = UIConfig:getTopSafeZone()

    -- Track visual Y position starting from frame padding
    local visual_y = Size.padding.large

    -- Main content
    local content = VerticalGroup:new{ align = "left" }

    -- Header (in top zone - non-interactive, standardized page title)
    local title_widget = TextWidget:new{
        text = _("Quests"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    }
    table.insert(content, title_widget)
    visual_y = visual_y + title_widget:getSize().h

    -- Add spacer to push interactive content below top_safe_zone
    local spacer_needed = top_safe_zone - visual_y
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
        visual_y = visual_y + spacer_needed
    end
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("md") })
    visual_y = visual_y + UIConfig:spacing("md")

    -- All interactive content starts here (below top_safe_zone)
    self.current_y = visual_y

    -- Type tabs (Daily / Weekly / Monthly) - inline, no dialog
    self.type_tabs_y = self.current_y
    local type_tabs = self:buildTypeTabs()
    table.insert(content, type_tabs)
    self.current_y = self.current_y + getTypeTabHeight()
    table.insert(content, VerticalSpan:new{ width = UIConfig:spacing("md") })
    self.current_y = self.current_y + UIConfig:spacing("md")

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    self.current_y = self.current_y + Size.line.thick
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    self.current_y = self.current_y + Size.padding.small

    -- Quest list starting position
    self.quest_list_start_y = self.current_y

    -- Quest list
    local quests = Data:loadAllQuests()
    local quest_list = quests[self.current_type] or {}
    local quests_module = self

    if #quest_list == 0 then
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
        self.current_y = self.current_y + Size.padding.large
        table.insert(content, TextWidget:new{
            text = _("No quests yet. Add one below!"),
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.gray(0.5),
        })
        self.current_y = self.current_y + 20
    else
        for _, quest in ipairs(quest_list) do
            local quest_row = self:buildQuestRow(quest, content_width)
            table.insert(content, quest_row)
            self.current_y = self.current_y + getQuestRowHeight() + 2
        end
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    self.current_y = self.current_y + Size.padding.large

    -- Add quest button using Button widget with callback
    local add_button = Button:new{
        text = _("[+] Add New Quest"),
        width = content_width,
        max_width = content_width,
        bordersize = 2,
        margin = 0,
        padding = Size.padding.default,
        text_font_face = "cfont",
        text_font_size = 16,
        text_font_bold = true,
        callback = function()
            quests_module:showAddQuestDialog()
        end,
    }
    table.insert(content, add_button)

    -- Wrap content
    local padded_content = FrameContainer:new{
        width = screen_width - Navigation.TAB_WIDTH,
        height = screen_height,
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    -- Navigation setup
    local ui = self.ui

    local function on_tab_change(tab_id)
        UIManager:close(quests_module.quests_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("quests", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create main layout
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        padded_content,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Standard InputContainer
    self.quests_widget = InputContainer:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        ges_events = {},
        main_layout,
    }

    -- Setup gesture handlers using shared helpers
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = top_safe_zone,
    }
    UIHelpers.setupCornerGestures(self.quests_widget, self, gesture_dims)
    UIHelpers.setupSwipeToClose(self.quests_widget, function()
        UIManager:close(self.quests_widget)
    end, gesture_dims)

    UIManager:show(self.quests_widget)
end

--[[--
Build type tabs (Daily / Weekly / Monthly) using Button widgets.
--]]
function Quests:buildTypeTabs()
    local types = {
        {id = "daily", label = "Daily"},
        {id = "weekly", label = "Weekly"},
        {id = "monthly", label = "Monthly"},
    }
    local quests_module = self

    local tabs = HorizontalGroup:new{ align = "center" }
    local BUTTON_GAP = UIConfig:dim("button_gap") or 4

    for idx, type_info in ipairs(types) do
        local is_active = (type_info.id == self.current_type)

        -- Create Button with callback
        local tab_button = Button:new{
            text = type_info.label,
            width = getTypeTabWidth(),
            max_width = getTypeTabWidth(),
            bordersize = is_active and 2 or 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 14,
            text_font_bold = is_active,
            preselect = is_active,  -- Inverts display for active tab
            callback = function()
                quests_module:switchType(type_info.id)
            end,
        }

        table.insert(tabs, tab_button)
        if idx < #types then
            table.insert(tabs, HorizontalSpan:new{ width = BUTTON_GAP })
        end
    end

    return tabs
end

--[[--
Build a single quest row with inline buttons.
Supports both binary (OK/Skip) and progressive (+/-) quests.
Uses Button widgets with callbacks for tap handling.
--]]
function Quests:buildQuestRow(quest, content_width)
    local today = os.date("%Y-%m-%d")
    local colors = UIConfig:getColors()
    local quests_module = self

    local status_bg = (quest.completed and colors.completed_bg) or colors.background
    local text_color = (quest.completed and colors.muted) or colors.foreground

    -- Check if progressive quest needs daily reset
    if quest.is_progressive and quest.progress_last_date ~= today then
        quest.progress_current = 0
    end

    local row
    local BUTTON_GAP = UIConfig:dim("button_gap") or 2

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10 pages] [+] [Title]
        local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
        local PROGRESS_WIDTH = getProgressWidth()
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - BUTTON_GAP * 2 - Size.padding.small

        -- Title text
        local title_widget = TextWidget:new{
            text = quest.title,
            face = Font:getFace("cfont", 13),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Minus button with callback
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
                quests_module:decrementQuestProgress(quest)
            end,
        }

        -- Progress display (non-interactive)
        local current = quest.progress_current or 0
        local target = quest.progress_target or 1
        local pct = math.min(1, current / target)
        local progress_bg = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.gray(1 - pct * 0.5)
        local progress_text = string.format("%d/%d", current, target)
        if quest.progress_unit then
            progress_text = progress_text .. " " .. quest.progress_unit:sub(1, 4)
        end

        local progress_display = FrameContainer:new{
            width = PROGRESS_WIDTH,
            height = getQuestRowHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = progress_bg,
            CenterContainer:new{
                dimen = Geom:new{w = PROGRESS_WIDTH - 6, h = getQuestRowHeight() - 10},
                TextWidget:new{
                    text = progress_text,
                    face = Font:getFace("cfont", 11),
                    bold = quest.completed,
                },
            },
        }

        -- Plus button with callback
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
            enabled = not quest.completed,
            callback = function()
                quests_module:incrementQuestProgress(quest)
            end,
        }

        row = HorizontalGroup:new{
            align = "center",
            minus_button,
            HorizontalSpan:new{ width = BUTTON_GAP },
            progress_display,
            HorizontalSpan:new{ width = BUTTON_GAP },
            plus_button,
            HorizontalSpan:new{ width = Size.padding.small },
            FrameContainer:new{
                width = title_width,
                height = getQuestRowHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    else
        -- Binary quest layout: [Done] [Skip] [Title]
        local title_width = content_width - getButtonWidth() * 2 - BUTTON_GAP - Size.padding.small

        -- Title text
        local title_widget = TextWidget:new{
            text = quest.title,
            face = Font:getFace("cfont", 14),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Complete button with callback
        local complete_text = quest.completed and "X" or "Done"
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
                quests_module:toggleQuestComplete(quest)
            end,
        }

        -- Skip button with callback
        local skip_button = Button:new{
            text = "Skip",
            width = getButtonWidth(),
            max_width = getButtonWidth(),
            bordersize = 1,
            margin = 0,
            padding = Size.padding.small,
            text_font_face = "cfont",
            text_font_size = 10,
            text_font_bold = false,
            callback = function()
                quests_module:skipQuest(quest)
            end,
        }

        row = HorizontalGroup:new{
            align = "center",
            complete_button,
            HorizontalSpan:new{ width = BUTTON_GAP },
            skip_button,
            HorizontalSpan:new{ width = Size.padding.small },
            FrameContainer:new{
                width = title_width,
                height = getQuestRowHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    end

    return FrameContainer:new{
        width = content_width,
        height = getQuestRowHeight(),
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

--[[--
Switch quest type (Daily/Weekly/Monthly).
Called by type tab Button callbacks.
--]]
function Quests:switchType(type_id)
    if type_id ~= self.current_type then
        self.current_type = type_id
        if self.quests_widget then
            UIManager:close(self.quests_widget)
        end
        self:showQuestsView()
    end
end


--[[--
Show actions for a quest (edit, delete, view details).
--]]
function Quests:showQuestActions(quest)
    local dialog
    dialog = ButtonDialog:new{
        title = quest.title,
        buttons = {
            {{
                text = _("View Details"),
                callback = function()
                    UIManager:close(dialog)
                    self:showQuestDetails(quest)
                end,
            }},
            {{
                text = _("Edit"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEditQuestDialog(quest)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmDeleteQuest(quest)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Show quest details with 30-day heatmap.
--]]
function Quests:showQuestDetails(quest)
    -- Build 30-day completion heatmap
    local heatmap = self:buildQuestHeatmap(quest)

    local energy_text = quest.energy_required or "Any"
    if type(energy_text) == "table" then
        energy_text = table.concat(energy_text, ", ")
    end

    local time_slot = quest.time_slot or "Any time"
    local quest_type = self.current_type:sub(1,1):upper() .. self.current_type:sub(2)

    local details = string.format(
        "%s\n\nTime: %s\nEnergy: %s\nType: %s\n\n30-Day Activity:\n%s",
        quest.title,
        time_slot,
        energy_text,
        quest_type,
        heatmap
    )

    UIManager:show(InfoMessage:new{
        text = details,
        width = Screen:getWidth() * 0.85,
    })
end

--[[--
Build a 30-day heatmap for a specific quest.
--]]
function Quests:buildQuestHeatmap(quest)
    local today = os.time()
    local lines = {}

    -- Build 30 days in 6 rows of 5
    for week = 0, 5 do
        local row = ""
        for day = 0, 4 do
            local day_offset = week * 5 + day
            if day_offset >= 30 then break end

            local date_time = today - (29 - day_offset) * 86400
            local date_str = os.date("%Y-%m-%d", date_time)

            -- Check if this quest was completed on this day
            local completed = false
            if quest.completed_date == date_str then
                completed = true
            end

            row = row .. (completed and "#" or ".")
        end
        if row ~= "" then
            table.insert(lines, row)
        end
    end

    return table.concat(lines, "\n")
end

--[[--
Toggle quest completion status.
--]]
function Quests:toggleQuestComplete(quest)
    local was_completed = quest.completed
    if quest.completed then
        Data:uncompleteQuest(self.current_type, quest.id)
    else
        local today = Data:getCurrentDate()
        local quests = Data:loadAllQuests()

        for _, q in ipairs(quests[self.current_type]) do
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
        Data:saveAllQuests(quests)

        self:updateDailyLog()
        self:updateGlobalStreak()
    end

    -- Refresh
    UIManager:close(self.quests_widget)
    self:showQuestsView()
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

--[[--
Skip a quest (mark as skipped for today without breaking streak).
--]]
function Quests:skipQuest(quest)
    local today = Data:getCurrentDate()
    local quests = Data:loadAllQuests()

    for _, q in ipairs(quests[self.current_type]) do
        if q.id == quest.id then
            q.skipped_date = today
            break
        end
    end
    Data:saveAllQuests(quests)

    UIManager:show(InfoMessage:new{
        text = _("Quest skipped for today"),
        timeout = 1,
    })

    -- Refresh
    UIManager:close(self.quests_widget)
    self:showQuestsView()
    UIManager:setDirty("all", "ui")
end

--[[--
Increment progress for a progressive quest.
--]]
function Quests:incrementQuestProgress(quest)
    local updated = Data:incrementQuestProgress(self.current_type, quest.id)
    if updated then
        -- Refresh
        UIManager:close(self.quests_widget)
        self:showQuestsView()
        UIManager:setDirty("all", "ui")

        if updated.completed then
            self:updateDailyLog()
            self:updateGlobalStreak()
            UIManager:nextTick(function()
                Celebration:showCompletion()
            end)
        end
    end
end

--[[--
Decrement progress for a progressive quest.
--]]
function Quests:decrementQuestProgress(quest)
    local updated = Data:decrementQuestProgress(self.current_type, quest.id)
    if updated then
        -- Refresh
        UIManager:close(self.quests_widget)
        self:showQuestsView()
        UIManager:setDirty("all", "ui")
    end
end

--[[--
Show input dialog for manually setting progress.
--]]
function Quests:showProgressInput(quest)
    local target = quest.progress_target or 1
    local dialog
    dialog = InputDialog:new{
        title = string.format(_("Set Progress for '%s'"), quest.title),
        input = tostring(quest.progress_current or 0),
        input_hint = string.format(_("Enter 0-%d %s"),
            target,
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
                    -- Validate numeric input
                    local value = Data:validateNumericInput(dialog:getInputText(), 0, target)
                    if not value then
                        UIManager:show(InfoMessage:new{
                            text = string.format(_("Please enter a number between 0 and %d"), target),
                            timeout = 2,
                        })
                        return
                    end
                    local updated = Data:setQuestProgress(self.current_type, quest.id, math.floor(value))
                    local quest_completed = updated and updated.completed
                    UIManager:close(dialog)
                    -- Refresh
                    UIManager:close(self.quests_widget)
                    self:showQuestsView()
                    UIManager:setDirty("all", "ui")

                    if quest_completed then
                        self:updateDailyLog()
                        self:updateGlobalStreak()
                        UIManager:nextTick(function()
                            Celebration:showCompletion()
                        end)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Update global streak data.
--]]
function Quests:updateGlobalStreak()
    local user_settings = Data:loadUserSettings()
    local today = Data:getCurrentDate()

    if user_settings.streak_data.last_completed_date == today then
        return
    end

    local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
    if user_settings.streak_data.last_completed_date == yesterday then
        user_settings.streak_data.current = user_settings.streak_data.current + 1
    else
        user_settings.streak_data.current = 1
    end

    if user_settings.streak_data.current > user_settings.streak_data.longest then
        user_settings.streak_data.longest = user_settings.streak_data.current
    end

    user_settings.streak_data.last_completed_date = today
    Data:saveUserSettings(user_settings)
end

--[[--
Update daily log with quest completion stats.
--]]
function Quests:updateDailyLog()
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
Show add quest dialog.
--]]
function Quests:showAddQuestDialog()
    self.new_quest = {
        title = "",
        time_slot = nil,
        energy_required = {},  -- Multi-select array
        category = nil,        -- Quest category
        is_progressive = false, -- Progressive quest flag
        progress_target = nil,  -- Target for progressive quests
        progress_unit = nil,    -- Unit for progressive quests
    }
    self:showQuestTitleInput(false)
end

--[[--
Show edit quest dialog.
--]]
function Quests:showEditQuestDialog(quest)
    self.editing_quest = quest
    local energy = quest.energy_required
    if type(energy) == "string" then
        energy = energy == "Any" and {} or {energy}
    end
    self.new_quest = {
        title = quest.title,
        time_slot = quest.time_slot,
        energy_required = energy or {},
        category = quest.category,
        is_progressive = quest.is_progressive or false,
        progress_target = quest.progress_target,
        progress_unit = quest.progress_unit,
    }
    self:showQuestTitleInput(true)
end

-- Maximum quest title length
local MAX_QUEST_TITLE_LENGTH = 200

--[[--
Show title input step.
--]]
function Quests:showQuestTitleInput(is_edit)
    local dialog
    dialog = InputDialog:new{
        title = is_edit and _("Edit Quest") or _("New Quest"),
        input = self.new_quest.title,
        input_hint = _("Quest title (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Next: Time Slot"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize input to remove control characters
                    local title = Data:sanitizeTextInput(dialog:getInputText(), MAX_QUEST_TITLE_LENGTH)
                    if not title or title == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a title"),
                            timeout = 2,
                        })
                        return
                    end
                    if #title > MAX_QUEST_TITLE_LENGTH then
                        UIManager:show(InfoMessage:new{
                            text = string.format(_("Title too long (%d chars). Max is %d."), #title, MAX_QUEST_TITLE_LENGTH),
                            timeout = 3,
                        })
                        return
                    end
                    self.new_quest.title = title
                    UIManager:close(dialog)
                    self:showTimeSlotSelector(is_edit)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Show time slot selector.
--]]
function Quests:showTimeSlotSelector(is_edit)
    local user_settings = Data:loadUserSettings()
    local buttons = {}

    for _, slot in ipairs(user_settings.time_slots) do
        table.insert(buttons, {{
            text = slot,
            callback = function()
                self.new_quest.time_slot = slot
                UIManager:close(self.time_slot_dialog)
                self:showEnergySelector(is_edit)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(self.time_slot_dialog)
        end,
    }})

    self.time_slot_dialog = ButtonDialog:new{
        title = _("When do you want to tackle this?"),
        buttons = buttons,
    }
    UIManager:show(self.time_slot_dialog)
end

--[[--
Show energy level selector (multi-select).
--]]
function Quests:showEnergySelector(is_edit)
    self.selected_energies = {}
    -- Copy existing selections
    for _, e in ipairs(self.new_quest.energy_required or {}) do
        self.selected_energies[e] = true
    end
    self:showEnergySelectorWithSelection(is_edit)
end

function Quests:showEnergySelectorWithSelection(is_edit)
    local user_settings = Data:loadUserSettings()
    local buttons = {}

    -- "Any" option (mutually exclusive with specific selections)
    local any_selected = next(self.selected_energies) == nil
    table.insert(buttons, {{
        text = (any_selected and "[X] " or "[ ] ") .. _("Any (always show)"),
        callback = function()
            self.selected_energies = {}  -- Clear all
            UIManager:close(self.energy_dialog)
            self:showEnergySelectorWithSelection(is_edit)
        end,
    }})

    -- Energy categories (multi-select)
    for _, energy in ipairs(user_settings.energy_categories) do
        local selected = self.selected_energies[energy] and "[X] " or "[ ] "
        table.insert(buttons, {{
            text = selected .. energy,
            callback = function()
                if self.selected_energies[energy] then
                    self.selected_energies[energy] = nil
                else
                    self.selected_energies[energy] = true
                end
                UIManager:close(self.energy_dialog)
                self:showEnergySelectorWithSelection(is_edit)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Next: Category"),
        callback = function()
            -- Convert to array
            local energies = {}
            for e, _ in pairs(self.selected_energies) do
                table.insert(energies, e)
            end
            self.new_quest.energy_required = #energies > 0 and energies or "Any"
            UIManager:close(self.energy_dialog)
            self:showCategorySelector(is_edit)
        end,
    }})

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(self.energy_dialog)
        end,
    }})

    self.energy_dialog = ButtonDialog:new{
        title = _("On what kind of day? (multi-select)"),
        buttons = buttons,
    }
    UIManager:show(self.energy_dialog)
end

--[[--
Show category selector.
--]]
function Quests:showCategorySelector(is_edit)
    local user_settings = Data:loadUserSettings()
    local buttons = {}

    -- "None" option
    local none_selected = self.new_quest.category == nil
    table.insert(buttons, {{
        text = (none_selected and "[X] " or "[ ] ") .. _("None (uncategorized)"),
        callback = function()
            self.new_quest.category = nil
            UIManager:close(self.category_dialog)
            self:showQuestTypeSelector(is_edit)
        end,
    }})

    -- Category options
    for _, cat in ipairs(user_settings.quest_categories or {}) do
        local selected = self.new_quest.category == cat
        table.insert(buttons, {{
            text = (selected and "[X] " or "[ ] ") .. cat,
            callback = function()
                self.new_quest.category = cat
                UIManager:close(self.category_dialog)
                self:showQuestTypeSelector(is_edit)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(self.category_dialog)
        end,
    }})

    self.category_dialog = ButtonDialog:new{
        title = _("What area of life is this?"),
        buttons = buttons,
    }
    UIManager:show(self.category_dialog)
end

--[[--
Show quest type selector (Binary vs Progressive).
--]]
function Quests:showQuestTypeSelector(is_edit)
    local dialog
    dialog = ButtonDialog:new{
        title = _("How do you complete this quest?"),
        buttons = {
            {{
                text = self.new_quest.is_progressive and "[ ] " .. _("One-time (Done/Skip)") or "[X] " .. _("One-time (Done/Skip)"),
                callback = function()
                    self.new_quest.is_progressive = false
                    UIManager:close(dialog)
                    self:saveQuest(is_edit)
                end,
            }},
            {{
                text = self.new_quest.is_progressive and "[X] " .. _("Progressive (+/- buttons)") or "[ ] " .. _("Progressive (+/- buttons)"),
                callback = function()
                    self.new_quest.is_progressive = true
                    UIManager:close(dialog)
                    self:showProgressTargetInput(is_edit)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Show progress target input for progressive quests.
--]]
function Quests:showProgressTargetInput(is_edit)
    local dialog
    dialog = InputDialog:new{
        title = _("Daily Target"),
        input = self.new_quest.progress_target and tostring(self.new_quest.progress_target) or "10",
        input_hint = _("How many per day? (e.g., 10)"),
        input_type = "number",
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Next: Unit"),
                is_enter_default = true,
                callback = function()
                    -- Validate numeric input with bounds
                    local target = Data:validateNumericInput(dialog:getInputText(), 1, 100000)
                    if not target then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a valid number between 1 and 100,000"),
                            timeout = 2,
                        })
                        return
                    end
                    self.new_quest.progress_target = math.floor(target)
                    UIManager:close(dialog)
                    self:showProgressUnitInput(is_edit)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Show progress unit input for progressive quests.
--]]
function Quests:showProgressUnitInput(is_edit)
    local dialog
    dialog = InputDialog:new{
        title = _("Unit of Progress"),
        input = self.new_quest.progress_unit or "pages",
        input_hint = _("What are you counting? (e.g., pages, reps, minutes)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Save Quest"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize unit input
                    local unit = Data:sanitizeTextInput(dialog:getInputText(), 50)
                    if unit == "" then
                        unit = "units"
                    end
                    self.new_quest.progress_unit = unit
                    UIManager:close(dialog)
                    self:saveQuest(is_edit)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Save the quest (new or edited).
--]]
function Quests:saveQuest(is_edit)
    if is_edit and self.editing_quest then
        Data:updateQuest(self.current_type, self.editing_quest.id, {
            title = self.new_quest.title,
            time_slot = self.new_quest.time_slot,
            energy_required = self.new_quest.energy_required,
            category = self.new_quest.category,
            is_progressive = self.new_quest.is_progressive,
            progress_target = self.new_quest.progress_target,
            progress_unit = self.new_quest.progress_unit,
        })
        UIManager:show(InfoMessage:new{
            text = _("Quest updated!"),
            timeout = 2,
        })
    else
        Data:addQuest(self.current_type, {
            title = self.new_quest.title,
            time_slot = self.new_quest.time_slot,
            energy_required = self.new_quest.energy_required,
            category = self.new_quest.category,
            is_progressive = self.new_quest.is_progressive,
            progress_target = self.new_quest.progress_target,
            progress_unit = self.new_quest.progress_unit,
        })
        UIManager:show(InfoMessage:new{
            text = _("Quest added!"),
            timeout = 2,
        })
    end

    -- Refresh - close old widget and show new one with proper dirty refresh
    if self.quests_widget then
        UIManager:close(self.quests_widget)
    end
    self:showQuestsView()
    -- Force a full UI refresh to ensure the new widget renders correctly
    UIManager:setDirty("all", "ui")
end

--[[--
Confirm quest deletion.
--]]
function Quests:confirmDeleteQuest(quest)
    local dialog
    dialog = ButtonDialog:new{
        title = string.format(_("Delete '%s'?"), quest.title),
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    Data:deleteQuest(self.current_type, quest.id)
                    UIManager:show(InfoMessage:new{
                        text = _("Quest deleted"),
                        timeout = 2,
                    })
                    if self.quests_widget then
                        UIManager:close(self.quests_widget)
                    end
                    self:showQuestsView()
                    UIManager:setDirty("all", "ui")
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Get quests filtered by energy level for today.
--]]
function Quests:getFilteredQuestsForToday(energy_level)
    local quests = Data:loadAllQuests()
    if not quests then return {} end

    local user_settings = Data:loadUserSettings()
    local filtered = {}

    if not energy_level then
        for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
            for _, quest in ipairs(quests[quest_type] or {}) do
                if not quest.completed then
                    table.insert(filtered, quest)
                end
            end
        end
        return filtered
    end

    local highest_energy = user_settings.energy_categories and user_settings.energy_categories[1] or "Energetic"
    local is_high_energy = (energy_level == highest_energy)

    for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for _, quest in ipairs(quests[quest_type] or {}) do
            if not quest.completed then
                local energy_req = quest.energy_required
                local matches = false

                if energy_req == "Any" or energy_req == nil then
                    matches = true
                elseif type(energy_req) == "table" then
                    for _, e in ipairs(energy_req) do
                        if e == energy_level or is_high_energy then
                            matches = true
                            break
                        end
                    end
                elseif energy_req == energy_level or is_high_energy then
                    matches = true
                end

                if matches then
                    table.insert(filtered, quest)
                end
            end
        end
    end

    return filtered
end

return Quests
