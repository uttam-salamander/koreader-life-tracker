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
local Event = require("ui/event")
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

local Timeline = {}

-- UI Constants (scaled via UIConfig)
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
Dispatch a corner gesture to the user's configured action.
@tparam string gesture_name The gesture name (e.g., "tap_top_left_corner")
@treturn bool True if gesture was handled
--]]
function Timeline:dispatchCornerGesture(gesture_name)
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

    -- Fallback to common corner actions
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
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top 1/8 (12.5%) for menu gesture
    local top_safe_zone = math.floor(screen_height / 8)

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
        face = Font:getFace("tfont", 18),
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
        background = is_today and Blitbuffer.gray(0.95) or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = date_width - Size.padding.small * 2, h = getTouchTargetHeight() - Size.padding.small * 2},
            TextWidget:new{
                text = header_text,
                face = Font:getFace("cfont", 14),
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
    self.nav_row_y = top_safe_zone  -- Y position of nav row (below top zone)

    table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    self.current_y = self.current_y + Size.padding.small

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
    for __, slot in ipairs(time_slots) do
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
            for __, quest in ipairs(slot_quests) do
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

    -- Wrap content in scrollable container
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local scroll_height = screen_height

    local inner_frame = FrameContainer:new{
        width = scroll_width - scrollbar_width,
        height = math.max(scroll_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
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

    -- Set show_parent for ScrollableContainer refresh
    self.scrollable_container.show_parent = self.timeline_widget

    -- Store top_safe_zone for gesture handlers
    self.top_safe_zone = top_safe_zone

    -- Setup quest tap handlers (below top zone)
    self:setupQuestTapHandlers()

    -- Date navigation tap handlers
    -- Nav row is BELOW top_safe_zone to avoid corner gesture conflicts
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

    -- KOReader gesture zone dimensions
    local corner_size = math.floor(screen_width / 8)
    local corner_height = math.floor(screen_height / 8)

    -- Top CENTER zone - Opens KOReader menu
    self.timeline_widget.ges_events.TopCenterTap = {
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
    self.timeline_widget.onTopCenterTap = function()
        if self.ui and self.ui.menu then
            self.ui.menu:onShowMenu()
        else
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Corner tap handlers
    self.timeline_widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.timeline_widget.onTopLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_top_left_corner")
    end

    self.timeline_widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.timeline_widget.onTopRightCornerTap = function()
        return self:dispatchCornerGesture("tap_top_right_corner")
    end

    self.timeline_widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.timeline_widget.onBottomLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_left_corner")
    end

    self.timeline_widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.timeline_widget.onBottomRightCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_right_corner")
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

-- UI Constants for progressive quests (must match dashboard.lua)
local SMALL_BUTTON_WIDTH = getSmallButtonWidth()
local PROGRESS_WIDTH = getProgressWidth()  -- Matches dashboard for consistent tap zones

--[[--
Build a single quest row with OK/Skip buttons (binary) or +/-/Skip buttons (progressive).
--]]
function Timeline:buildQuestRow(quest, content_width)
    local today = os.date("%Y-%m-%d")
    local status_bg = quest.completed and Blitbuffer.gray(0.9) or Blitbuffer.COLOR_WHITE
    local text_color = quest.completed and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

    -- Check if progressive quest needs daily reset
    if quest.is_progressive and quest.progress_last_date ~= today then
        quest.progress_current = 0
    end

    local row

    if quest.is_progressive then
        -- Progressive quest layout: [−] [3/10] [+] [Skip] [Title]
        local title_width = content_width - SMALL_BUTTON_WIDTH * 2 - PROGRESS_WIDTH - getButtonWidth() - 6 - Size.padding.small

        local title_widget = TextWidget:new{
            text = quest.title,
            face = Font:getFace("cfont", 13),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Minus button
        local minus_button = FrameContainer:new{
            width = SMALL_BUTTON_WIDTH,
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "−",
                    face = Font:getFace("cfont", 16),
                    bold = true,
                },
            },
        }

        -- Progress display
        local current = quest.progress_current or 0
        local target = quest.progress_target or 1
        local pct = math.min(1, current / target)
        local progress_bg = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.gray(1 - pct * 0.5)
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
                    bold = quest.completed,
                },
            },
        }

        -- Plus button
        local plus_button = FrameContainer:new{
            width = SMALL_BUTTON_WIDTH,
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = SMALL_BUTTON_WIDTH - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "+",
                    face = Font:getFace("cfont", 16),
                    bold = true,
                },
            },
        }

        -- Skip button for progressive quests
        local skip_button = FrameContainer:new{
            width = getButtonWidth(),
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = getButtonWidth() - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = "Skip",
                    face = Font:getFace("cfont", 10),
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
            HorizontalSpan:new{ width = 2 },
            skip_button,
            HorizontalSpan:new{ width = Size.padding.small },
            FrameContainer:new{
                width = title_width,
                height = getTouchTargetHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    else
        -- Binary quest layout: [OK] [Skip] [Title]
        local title_width = content_width - getButtonWidth() * 2 - Size.padding.small * 3

        local title_widget = TextWidget:new{
            text = quest.title,
            face = Font:getFace("cfont", 14),
            fgcolor = text_color,
            max_width = title_width - Size.padding.small * 2,
        }

        -- Complete button (OK or X if already completed)
        local complete_text = quest.completed and "X" or "OK"
        local complete_button = FrameContainer:new{
            width = getButtonWidth(),
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = quest.completed and Blitbuffer.gray(0.7) or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = getButtonWidth() - 6, h = getTouchTargetHeight() - 10},
                TextWidget:new{
                    text = complete_text,
                    face = Font:getFace("cfont", 12),
                    bold = true,
                },
            },
        }

        -- Skip button
        local skip_button = FrameContainer:new{
            width = getButtonWidth(),
            height = getTouchTargetHeight() - 4,
            padding = 2,
            bordersize = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{w = getButtonWidth() - 6, h = getTouchTargetHeight() - 10},
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
                height = getTouchTargetHeight(),
                padding = Size.padding.small,
                bordersize = 0,
                background = status_bg,
                title_widget,
            },
        }
    end

    return FrameContainer:new{
        width = content_width,
        height = getTouchTargetHeight(),
        padding = 0,
        bordersize = 1,
        background = status_bg,
        row,
    }
end

--[[--
Setup tap handlers for quest items.
Handles both binary (OK/Skip) and progressive (+/-/Skip) quest layouts.
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
                    h = getTouchTargetHeight(),
                },
            },
        }

        local timeline = self
        local quest = quest_info.quest

        self.timeline_widget["on" .. row_gesture] = function(_, _, ges)
            local tap_x = ges.pos.x - Size.padding.large

            if quest.is_progressive then
                -- Progressive quest layout: [−](35) [progress](60) [+](35) [Skip](50) [Title]
                -- Positions: 0-35, 37-97, 99-134, 136-186, 186+
                if tap_x < SMALL_BUTTON_WIDTH then
                    -- Minus button
                    timeline:decrementQuestProgress(quest)
                elseif tap_x < SMALL_BUTTON_WIDTH + 2 + PROGRESS_WIDTH then
                    -- Progress display - show manual input
                    timeline:showProgressInput(quest)
                elseif tap_x < SMALL_BUTTON_WIDTH * 2 + 4 + PROGRESS_WIDTH then
                    -- Plus button
                    timeline:incrementQuestProgress(quest)
                elseif tap_x < SMALL_BUTTON_WIDTH * 2 + 6 + PROGRESS_WIDTH + getButtonWidth() then
                    -- Skip button
                    timeline:skipQuest(quest)
                else
                    -- Title area
                    timeline:showQuestActions(quest)
                end
            else
                -- Binary quest: Buttons are on LEFT: OK (0-11%), Skip (11-22%), Title (22%+)
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
        for __, q in ipairs(quests) do
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
        for __, q in ipairs(quests) do
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
                    UIManager:show(InfoMessage:new{
                        text = _("Quest completed!"),
                        timeout = 1,
                    })
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

    local today = os.date("%Y-%m-%d")
    local quests = {}

    -- Helper to clone quest with date-appropriate completion status
    local function cloneQuestForDate(quest)
        local clone = {}
        for k, v in pairs(quest) do
            clone[k] = v
        end

        -- For past/future dates, check if completed_date matches view date
        if date_str ~= today then
            -- Only show completed if it was completed ON this date
            if clone.completed and clone.completed_date == date_str then
                clone.completed = true
            else
                clone.completed = false
            end
        end
        -- For today: use current completion status as-is

        return clone
    end

    -- Daily quests - always show
    for __, quest in ipairs(all_quests.daily or {}) do
        table.insert(quests, cloneQuestForDate(quest))
    end

    -- Weekly quests - show for all days
    for __, quest in ipairs(all_quests.weekly or {}) do
        table.insert(quests, cloneQuestForDate(quest))
    end

    -- Monthly quests
    for __, quest in ipairs(all_quests.monthly or {}) do
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
    for __, quest in ipairs(quests) do
        if quest.time_slot == slot then
            table.insert(slot_quests, quest)
        end
    end
    return slot_quests
end

return Timeline
