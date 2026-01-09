--[[--
Quests module for Life Tracker.
Manages quest CRUD, list views, and completion with inline buttons.

@module lifetracker.quests
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

local Quests = {}

-- UI Constants
local QUEST_ROW_HEIGHT = 50
local BUTTON_WIDTH = 50
local TYPE_TAB_HEIGHT = 40
local TYPE_TAB_WIDTH = 80

-- Current view state
Quests.current_type = "daily"

--[[--
Dispatch a corner gesture to the user's configured action.
@tparam string gesture_name The gesture name (e.g., "tap_top_left_corner")
@treturn bool True if gesture was handled
--]]
function Quests:dispatchCornerGesture(gesture_name)
    if self.ui and self.ui.gestures then
        local gesture_manager = self.ui.gestures
        local settings = gesture_manager.gestures or {}
        local action = settings[gesture_name]
        if action then
            local Dispatcher = require("dispatcher")
            Dispatcher:execute(action)
            return true
        end
    end

    if gesture_name == "tap_top_right_corner" then
        self.ui:handleEvent(Event:new("ToggleFrontlight"))
        return true
    elseif gesture_name == "tap_top_left_corner" then
        self.ui:handleEvent(Event:new("ToggleBookmark"))
        return true
    end

    return false
end

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

    -- Leave top 10% free for KOReader system gestures
    local top_safe_zone = math.floor(screen_height * 0.1)

    -- Track Y position for gesture handling (starts after top safe zone + padding)
    self.current_y = top_safe_zone + Size.padding.large

    -- Main content
    local content = VerticalGroup:new{ align = "left" }

    -- Top spacer for KOReader menu access
    table.insert(content, VerticalSpan:new{ width = top_safe_zone })

    -- Header (approximately 30px height)
    table.insert(content, TextWidget:new{
        text = _("Quests"),
        face = Font:getFace("tfont", 22),
        bold = true,
    })
    self.current_y = self.current_y + 30
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    self.current_y = self.current_y + Size.padding.default

    -- Type tabs (Daily / Weekly / Monthly) - inline, no dialog
    self.type_tabs_y = self.current_y
    local type_tabs = self:buildTypeTabs()
    table.insert(content, type_tabs)
    self.current_y = self.current_y + TYPE_TAB_HEIGHT
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    self.current_y = self.current_y + Size.padding.default

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
    self.quest_rows = {}
    local quests = Data:loadAllQuests()
    local quest_list = quests[self.current_type] or {}

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
        for idx, quest in ipairs(quest_list) do
            local quest_row = self:buildQuestRow(quest, content_width)
            table.insert(content, quest_row)
            table.insert(self.quest_rows, {quest = quest, idx = idx, y = self.current_y})
            self.current_y = self.current_y + QUEST_ROW_HEIGHT + 2
        end
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    self.current_y = self.current_y + Size.padding.large

    -- Add quest button - store its Y position
    self.add_button_y = self.current_y
    local add_button = FrameContainer:new{
        width = content_width,
        height = QUEST_ROW_HEIGHT,
        padding = Size.padding.small,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = content_width - Size.padding.small * 2, h = QUEST_ROW_HEIGHT - Size.padding.small * 2},
            TextWidget:new{
                text = _("[+] Add New Quest"),
                face = Font:getFace("cfont", 16),
                bold = true,
            },
        },
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
    local quests_module = self
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

    -- Setup gesture handlers
    self:setupGestureHandlers(content_width)

    -- KOReader gesture zone dimensions
    local corner_size = math.floor(screen_width / 8)
    local corner_height = math.floor(screen_height / 8)

    -- Top CENTER zone - Opens KOReader menu
    self.quests_widget.ges_events.TopCenterTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = corner_size,
                y = 0,
                w = screen_width - corner_size * 2,
                h = top_safe_zone,
            },
        },
    }
    self.quests_widget.onTopCenterTap = function()
        if self.ui and self.ui.menu then
            self.ui.menu:onShowMenu()
        else
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Corner tap handlers
    self.quests_widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.quests_widget.onTopLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_top_left_corner")
    end

    self.quests_widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.quests_widget.onTopRightCornerTap = function()
        return self:dispatchCornerGesture("tap_top_right_corner")
    end

    self.quests_widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.quests_widget.onBottomLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_left_corner")
    end

    self.quests_widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.quests_widget.onBottomRightCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_right_corner")
    end

    UIManager:show(self.quests_widget)
end

--[[--
Build type tabs (Daily / Weekly / Monthly).
--]]
function Quests:buildTypeTabs()
    local types = {
        {id = "daily", label = "Daily"},
        {id = "weekly", label = "Weekly"},
        {id = "monthly", label = "Monthly"},
    }

    local tabs = HorizontalGroup:new{ align = "center" }
    self.type_tab_positions = {}
    local x_offset = 0

    for idx, type_info in ipairs(types) do
        local is_active = (type_info.id == self.current_type)
        local bg_color = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg_color = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

        local tab = FrameContainer:new{
            width = TYPE_TAB_WIDTH,
            height = TYPE_TAB_HEIGHT,
            padding = Size.padding.small,
            bordersize = is_active and 2 or 1,
            background = bg_color,
            CenterContainer:new{
                dimen = Geom:new{w = TYPE_TAB_WIDTH - Size.padding.small * 2, h = TYPE_TAB_HEIGHT - Size.padding.small * 2},
                TextWidget:new{
                    text = type_info.label,
                    face = Font:getFace("cfont", 14),
                    fgcolor = fg_color,
                    bold = is_active,
                },
            },
        }

        self.type_tab_positions[idx] = {
            x = x_offset + Size.padding.large,
            w = TYPE_TAB_WIDTH,
            type_id = type_info.id,
        }
        x_offset = x_offset + TYPE_TAB_WIDTH + 4

        table.insert(tabs, tab)
        if idx < #types then
            table.insert(tabs, HorizontalSpan:new{ width = 4 })
        end
    end

    return tabs
end

--[[--
Build a single quest row with inline buttons.
Supports both binary (OK/Skip) and progressive (+/-) quests.
--]]
function Quests:buildQuestRow(quest, content_width)
    local today = os.date("%Y-%m-%d")
    local status_bg = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE
    local text_color = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

    -- Check if progressive quest needs daily reset
    if quest.is_progressive and quest.progress_last_date ~= today then
        quest.progress_current = 0
    end

    local row

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10 pages] [+] [Title]
        local SMALL_BUTTON_WIDTH = 35
        local PROGRESS_WIDTH = 80
        -- Total buttons/spans: 35 + 2 + 80 + 2 + 35 + padding.small = 154 + padding.small
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - 4 - Size.padding.small

        -- Build title with category prefix
        local title_text = quest.title
        if quest.category then
            title_text = string.format("[%s] %s", quest.category:sub(1,1), quest.title)
        elseif quest.time_slot then
            title_text = string.format("[%s] %s", quest.time_slot:sub(1,1), quest.title)
        end

        local title_widget = TextWidget:new{
            text = title_text,
            face = Font:getFace("cfont", 13),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Minus button
        local minus_button = FrameContainer:new{
            width = SMALL_BUTTON_WIDTH,
            height = QUEST_ROW_HEIGHT - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = QUEST_ROW_HEIGHT - 10},
                TextWidget:new{
                    text = "−",
                    face = Font:getFace("cfont", 16),
                    bold = true,
                },
            },
        }

        -- Progress display with fill indicator
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
            height = QUEST_ROW_HEIGHT - 4,
            padding = 2,
            bordersize = 1,
            background = progress_bg,
            CenterContainer:new{
                dimen = Geom:new{w = PROGRESS_WIDTH - 6, h = QUEST_ROW_HEIGHT - 10},
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
            height = QUEST_ROW_HEIGHT - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = QUEST_ROW_HEIGHT - 10},
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
                height = QUEST_ROW_HEIGHT,
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    else
        -- Binary quest layout: [OK] [Skip] [Title]
        local title_width = content_width - BUTTON_WIDTH * 2 - Size.padding.small * 4

        -- Build title with category or time slot prefix
        local title_text = quest.title
        if quest.category then
            title_text = string.format("[%s] %s", quest.category:sub(1,1), quest.title)
        elseif quest.time_slot then
            title_text = string.format("[%s] %s", quest.time_slot:sub(1,1), quest.title)
        end

        local title_widget = TextWidget:new{
            text = title_text,
            face = Font:getFace("cfont", 14),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Complete button (checkmark)
        local complete_text = quest.completed and "X" or "OK"
        local complete_button = FrameContainer:new{
            width = BUTTON_WIDTH,
            height = QUEST_ROW_HEIGHT - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = BUTTON_WIDTH - 6, h = QUEST_ROW_HEIGHT - 10},
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
            height = QUEST_ROW_HEIGHT - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = BUTTON_WIDTH - 6, h = QUEST_ROW_HEIGHT - 10},
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
                height = QUEST_ROW_HEIGHT,
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    end

    return FrameContainer:new{
        width = content_width,
        height = QUEST_ROW_HEIGHT,
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

--[[--
Setup gesture handlers for quests view.
--]]
function Quests:setupGestureHandlers(content_width)
    local screen_height = Screen:getHeight()
    local screen_width = Screen:getWidth()
    local quests_module = self

    -- Type tab taps - use tracked position
    local type_y = self.type_tabs_y
    for idx, pos in ipairs(self.type_tab_positions) do
        local gesture_name = "TypeTab_" .. idx
        self.quests_widget.ges_events[gesture_name] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = pos.x,
                    y = type_y,
                    w = pos.w,
                    h = TYPE_TAB_HEIGHT,
                },
            },
        }
        local type_id = pos.type_id
        self.quests_widget["on" .. gesture_name] = function()
            if type_id ~= quests_module.current_type then
                quests_module.current_type = type_id
                UIManager:close(quests_module.quests_widget)
                quests_module:showQuestsView()
            end
            return true
        end
    end

    -- Quest row taps - use tracked Y positions
    -- Layout depends on quest type:
    -- Binary: [OK] [Skip] [Title]
    -- Progressive: [−] [progress] [+] [Title]
    for idx, row_info in ipairs(self.quest_rows) do
        local row_y = row_info.y
        local quest = row_info.quest

        if quest.is_progressive then
            -- Progressive quest layout: [−] [progress] [+] [Title]
            -- Layout: minus(35) + span(2) + progress(80) + span(2) + plus(35) + span(padding.small) + title
            local SMALL_BUTTON_WIDTH = 35
            local PROGRESS_WIDTH = 80
            local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - 4 - Size.padding.small

            -- Minus button tap
            local minus_gesture = "QuestMinus_" .. idx
            self.quests_widget.ges_events[minus_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large,
                        y = row_y,
                        w = SMALL_BUTTON_WIDTH,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. minus_gesture] = function()
                quests_module:decrementQuestProgress(quest)
                return true
            end

            -- Progress display tap (manual input)
            local progress_gesture = "QuestProgress_" .. idx
            self.quests_widget.ges_events[progress_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large + SMALL_BUTTON_WIDTH + 2,
                        y = row_y,
                        w = PROGRESS_WIDTH,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. progress_gesture] = function()
                quests_module:showProgressInput(quest)
                return true
            end

            -- Plus button tap
            local plus_gesture = "QuestPlus_" .. idx
            self.quests_widget.ges_events[plus_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large + SMALL_BUTTON_WIDTH + 2 + PROGRESS_WIDTH + 2,
                        y = row_y,
                        w = SMALL_BUTTON_WIDTH,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. plus_gesture] = function()
                quests_module:incrementQuestProgress(quest)
                return true
            end

            -- Title area tap (opens menu)
            local title_gesture = "QuestTitle_" .. idx
            self.quests_widget.ges_events[title_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large + SMALL_BUTTON_WIDTH * 2 + PROGRESS_WIDTH + 4 + Size.padding.small,
                        y = row_y,
                        w = title_width,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. title_gesture] = function()
                quests_module:showQuestActions(quest)
                return true
            end
        else
            -- Binary quest layout: [OK] [Skip] [Title]
            local title_width = content_width - BUTTON_WIDTH * 2 - Size.padding.small * 4

            -- Complete (OK) button tap - leftmost position
            local complete_gesture = "QuestComplete_" .. idx
            self.quests_widget.ges_events[complete_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large,
                        y = row_y,
                        w = BUTTON_WIDTH,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. complete_gesture] = function()
                quests_module:toggleQuestComplete(quest)
                return true
            end

            -- Skip button tap - after OK button
            local skip_gesture = "QuestSkip_" .. idx
            self.quests_widget.ges_events[skip_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large + BUTTON_WIDTH + 2,
                        y = row_y,
                        w = BUTTON_WIDTH,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. skip_gesture] = function()
                quests_module:skipQuest(quest)
                return true
            end

            -- Title area tap (opens menu) - after both buttons
            local title_gesture = "QuestTitle_" .. idx
            self.quests_widget.ges_events[title_gesture] = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = Size.padding.large + BUTTON_WIDTH * 2 + Size.padding.small + 2,
                        y = row_y,
                        w = title_width,
                        h = QUEST_ROW_HEIGHT,
                    },
                },
            }
            self.quests_widget["on" .. title_gesture] = function()
                quests_module:showQuestActions(quest)
                return true
            end
        end
    end

    -- Add button tap - use tracked position
    self.quests_widget.ges_events.AddQuest = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = Size.padding.large,
                y = self.add_button_y,
                w = content_width,
                h = QUEST_ROW_HEIGHT,
            },
        },
    }
    self.quests_widget.onAddQuest = function()
        quests_module:showAddQuestDialog()
        return true
    end

    -- Swipe to close (leave top 10% for KOReader menu)
    local top_safe_zone = math.floor(screen_height * 0.1)
    self.quests_widget.ges_events.Swipe = {
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
    self.quests_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            UIManager:close(quests_module.quests_widget)
            return true
        end
        return false
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
    if quest.completed then
        Data:uncompleteQuest(self.current_type, quest.id)
        UIManager:show(InfoMessage:new{
            text = _("Quest marked incomplete"),
            timeout = 1,
        })
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

        UIManager:show(InfoMessage:new{
            text = _("Quest completed!"),
            timeout = 1,
        })
    end

    -- Refresh
    UIManager:close(self.quests_widget)
    self:showQuestsView()
    UIManager:setDirty("all", "ui")
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
        if updated.completed then
            self:updateDailyLog()
            self:updateGlobalStreak()
            UIManager:show(InfoMessage:new{
                text = _("Quest completed!"),
                timeout = 1,
            })
        end
        -- Refresh
        UIManager:close(self.quests_widget)
        self:showQuestsView()
        UIManager:setDirty("all", "ui")
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
    local dialog
    dialog = InputDialog:new{
        title = string.format(_("Set Progress for '%s'"), quest.title),
        input = tostring(quest.progress_current or 0),
        input_hint = string.format(_("Current: %d/%d %s"),
            quest.progress_current or 0,
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
                        local updated = Data:setQuestProgress(self.current_type, quest.id, value)
                        if updated then
                            if updated.completed then
                                self:updateDailyLog()
                                self:updateGlobalStreak()
                                UIManager:show(InfoMessage:new{
                                    text = _("Quest completed!"),
                                    timeout = 1,
                                })
                            end
                        end
                        UIManager:close(dialog)
                        -- Refresh
                        UIManager:close(self.quests_widget)
                        self:showQuestsView()
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

--[[--
Show title input step.
--]]
function Quests:showQuestTitleInput(is_edit)
    local dialog
    dialog = InputDialog:new{
        title = is_edit and _("Edit Quest") or _("New Quest"),
        input = self.new_quest.title,
        input_hint = _("Quest title"),
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
                    self.new_quest.title = dialog:getInputText()
                    if self.new_quest.title == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a title"),
                            timeout = 2,
                        })
                        return
                    end
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
                text = self.new_quest.is_progressive and "[ ] " .. _("One-time (OK/Skip)") or "[X] " .. _("One-time (OK/Skip)"),
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
                    local target = tonumber(dialog:getInputText())
                    if not target or target < 1 then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a number greater than 0"),
                            timeout = 2,
                        })
                        return
                    end
                    self.new_quest.progress_target = target
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
                    self.new_quest.progress_unit = dialog:getInputText()
                    if self.new_quest.progress_unit == "" then
                        self.new_quest.progress_unit = "units"
                    end
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

    -- Refresh
    UIManager:close(self.quests_widget)
    self:showQuestsView()
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
                    UIManager:close(self.quests_widget)
                    self:showQuestsView()
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
