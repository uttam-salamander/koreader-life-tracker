--[[--
Reminders module for Life Tracker.
Time-based reminders with gentle notifications.
@module lifetracker.reminders
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

local Reminders = {}

-- UI Constants
local REMINDER_ROW_HEIGHT = 50
local BUTTON_WIDTH = 60

-- Day abbreviations
local DAY_NAMES = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local DAY_FULL = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

--[[--
Dispatch a corner gesture to the user's configured action.
@tparam string gesture_name The gesture name (e.g., "tap_top_left_corner")
@treturn bool True if gesture was handled
--]]
function Reminders:dispatchCornerGesture(gesture_name)
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
Show the reminders view.
--]]
function Reminders:show(ui)
    self.ui = ui
    self:showRemindersView()
end

--[[--
Display the reminders with proper navigation.
--]]
function Reminders:showRemindersView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top 1/8 (12.5%) for menu gesture
    local top_safe_zone = math.floor(screen_height / 8)

    local reminders = Data:loadReminders()

    -- Main content
    local content = VerticalGroup:new{ align = "left" }

    -- Header (in top zone - non-interactive)
    table.insert(content, TextWidget:new{
        text = _("Reminders"),
        face = Font:getFace("tfont", 22),
        bold = true,
    })

    -- Add spacer to push interactive content below top_safe_zone
    local header_height = 30
    local spacer_needed = top_safe_zone - Size.padding.large - header_height
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })

    -- All interactive content starts here (below top_safe_zone)
    self.current_y = top_safe_zone + Size.padding.default

    -- Upcoming Today section
    local upcoming = self:getUpcomingToday(reminders)
    self.upcoming_count = #upcoming
    if #upcoming > 0 then
        table.insert(content, TextWidget:new{
            text = _("Upcoming Today"),
            face = Font:getFace("tfont", 16),
            bold = true,
        })
        self.current_y = self.current_y + 24
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        self.current_y = self.current_y + Size.padding.small

        for __, reminder in ipairs(upcoming) do
            local time_until = self:formatTimeUntil(reminder.time)
            local row = self:buildReminderRow(reminder, content_width, time_until)
            table.insert(content, row)
            self.current_y = self.current_y + REMINDER_ROW_HEIGHT + 2
        end
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        self.current_y = self.current_y + Size.padding.default
    end

    -- Separator
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    self.current_y = self.current_y + Size.line.thick
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    self.current_y = self.current_y + Size.padding.small

    -- Store starting Y for reminder rows
    self.reminder_list_start_y = self.current_y

    -- Active reminders section
    self.reminder_rows = {}
    local active_count = 0
    for __, reminder in ipairs(reminders) do
        if reminder.active then
            active_count = active_count + 1
            local row = self:buildReminderRow(reminder, content_width)
            table.insert(content, row)
            table.insert(self.reminder_rows, {reminder = reminder, y = self.current_y})
            self.current_y = self.current_y + REMINDER_ROW_HEIGHT + 2
        end
    end

    if active_count == 0 then
        table.insert(content, TextWidget:new{
            text = _("No active reminders"),
            face = Font:getFace("cfont", 14),
            fgcolor = Blitbuffer.gray(0.5),
        })
        self.current_y = self.current_y + 20
    end

    -- Inactive reminders
    local inactive_count = 0
    for __, reminder in ipairs(reminders) do
        if not reminder.active then
            if inactive_count == 0 then
                table.insert(content, VerticalSpan:new{ width = Size.padding.default })
                self.current_y = self.current_y + Size.padding.default
                table.insert(content, TextWidget:new{
                    text = _("Inactive"),
                    face = Font:getFace("cfont", 12),
                    fgcolor = Blitbuffer.gray(0.5),
                })
                self.current_y = self.current_y + 18
            end
            inactive_count = inactive_count + 1
            local row = self:buildReminderRow(reminder, content_width, nil, true)
            table.insert(content, row)
            table.insert(self.reminder_rows, {reminder = reminder, y = self.current_y})
            self.current_y = self.current_y + REMINDER_ROW_HEIGHT + 2
        end
    end

    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    self.current_y = self.current_y + Size.padding.large

    -- Store add button Y position
    self.add_button_y = self.current_y

    -- Add reminder button
    local add_button = FrameContainer:new{
        width = content_width,
        height = REMINDER_ROW_HEIGHT,
        padding = Size.padding.small,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = content_width - Size.padding.small * 2, h = REMINDER_ROW_HEIGHT - Size.padding.small * 2},
            TextWidget:new{
                text = _("[+] Add New Reminder"),
                face = Font:getFace("cfont", 16),
                bold = true,
            },
        },
    }
    table.insert(content, add_button)

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

    -- Navigation setup
    local reminders_module = self
    local ui = self.ui

    local function on_tab_change(tab_id)
        UIManager:close(reminders_module.reminders_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("reminders", screen_height)
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
    self.reminders_widget = InputContainer:new{
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
    self.scrollable_container.show_parent = self.reminders_widget

    -- Store top_safe_zone for gesture handlers
    self.top_safe_zone = top_safe_zone

    -- Setup gesture handlers (below top zone)
    self:setupGestureHandlers(content_width)

    -- KOReader gesture zone dimensions
    local corner_size = math.floor(screen_width / 8)
    local corner_height = math.floor(screen_height / 8)

    -- Top CENTER zone - Opens KOReader menu
    self.reminders_widget.ges_events.TopCenterTap = {
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
    self.reminders_widget.onTopCenterTap = function()
        if self.ui and self.ui.menu then
            self.ui.menu:onShowMenu()
        else
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Corner tap handlers
    self.reminders_widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.reminders_widget.onTopLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_top_left_corner")
    end

    self.reminders_widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.reminders_widget.onTopRightCornerTap = function()
        return self:dispatchCornerGesture("tap_top_right_corner")
    end

    self.reminders_widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.reminders_widget.onBottomLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_left_corner")
    end

    self.reminders_widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.reminders_widget.onBottomRightCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_right_corner")
    end

    UIManager:show(self.reminders_widget)
end

--[[--
Build a single reminder row with toggle button.
--]]
function Reminders:buildReminderRow(reminder, content_width, time_until, is_inactive)
    local bg_color = is_inactive and Blitbuffer.gray(0.95) or Blitbuffer.COLOR_WHITE
    local text_color = is_inactive and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_BLACK

    local title_width = content_width - BUTTON_WIDTH - Size.padding.small * 3

    local repeat_text = self:formatRepeatDays(reminder.repeat_days)
    local time_text = reminder.time or "??:??"

    local display_text = string.format("%s  %s  [%s]", time_text, reminder.title, repeat_text)
    if time_until then
        display_text = string.format("%s  %s (%s)", time_text, reminder.title, time_until)
    end

    local title_widget = TextWidget:new{
        text = display_text,
        face = Font:getFace("cfont", 14),
        fgcolor = text_color,
        max_width = title_width - Size.padding.small * 2,
    }

    -- Toggle button
    local toggle_text = reminder.active and "ON" or "OFF"
    local toggle_bg = reminder.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local toggle_fg = reminder.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    local toggle_button = FrameContainer:new{
        width = BUTTON_WIDTH,
        height = REMINDER_ROW_HEIGHT - 4,
        padding = 2,
        bordersize = 1,
        background = toggle_bg,
        CenterContainer:new{
            dimen = Geom:new{w = BUTTON_WIDTH - 6, h = REMINDER_ROW_HEIGHT - 10},
            TextWidget:new{
                text = toggle_text,
                face = Font:getFace("cfont", 12),
                fgcolor = toggle_fg,
                bold = true,
            },
        },
    }

    local row = HorizontalGroup:new{
        align = "center",
        FrameContainer:new{
            width = title_width,
            height = REMINDER_ROW_HEIGHT,
            padding = Size.padding.small,
            bordersize = 0,
            background = bg_color,
            title_widget,
        },
        HorizontalSpan:new{ width = Size.padding.small },
        toggle_button,
    }

    return FrameContainer:new{
        width = content_width,
        height = REMINDER_ROW_HEIGHT,
        padding = 0,
        bordersize = 1,
        background = bg_color,
        row,
    }
end

--[[--
Setup gesture handlers for reminders view.
--]]
function Reminders:setupGestureHandlers(content_width)  -- upcoming not used anymore
    local screen_height = Screen:getHeight()
    local screen_width = Screen:getWidth()
    local reminders_module = self

    -- Reminder row taps - use tracked Y positions
    for idx, row_info in ipairs(self.reminder_rows) do
        local row_y = row_info.y
        local title_width = content_width - BUTTON_WIDTH - Size.padding.small * 3

        -- Title area tap (opens menu)
        local title_gesture = "ReminderTitle_" .. idx
        self.reminders_widget.ges_events[title_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large,
                    y = row_y,
                    w = title_width,
                    h = REMINDER_ROW_HEIGHT,
                },
            },
        }
        local reminder = row_info.reminder
        self.reminders_widget["on" .. title_gesture] = function()
            reminders_module:showReminderActions(reminder)
            return true
        end

        -- Toggle button tap
        local toggle_gesture = "ReminderToggle_" .. idx
        self.reminders_widget.ges_events[toggle_gesture] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Size.padding.large + title_width + Size.padding.small,
                    y = row_y,
                    w = BUTTON_WIDTH,
                    h = REMINDER_ROW_HEIGHT,
                },
            },
        }
        self.reminders_widget["on" .. toggle_gesture] = function()
            reminders_module:toggleReminder(reminder)
            return true
        end
    end

    -- Add button tap - use tracked position
    self.reminders_widget.ges_events.AddReminder = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = Size.padding.large,
                y = self.add_button_y,
                w = content_width,
                h = REMINDER_ROW_HEIGHT,
            },
        },
    }
    self.reminders_widget.onAddReminder = function()
        reminders_module:showAddReminder()
        return true
    end

    -- Swipe to close (leave top 10% for KOReader menu)
    local top_safe_zone = math.floor(screen_height * 0.1)
    self.reminders_widget.ges_events.Swipe = {
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
    self.reminders_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            UIManager:close(reminders_module.reminders_widget)
            return true
        end
        return false
    end
end

--[[--
Format repeat days for display.
--]]
function Reminders:formatRepeatDays(repeat_days)
    if not repeat_days or #repeat_days == 0 then
        return "Once"
    end

    if #repeat_days == 7 then
        return "Daily"
    end

    -- Check for weekdays (Mon-Fri)
    local weekdays = {Mon=true, Tue=true, Wed=true, Thu=true, Fri=true}
    local is_weekdays = true
    for __, day in ipairs(repeat_days) do
        if not weekdays[day] then
            is_weekdays = false
            break
        end
    end
    if is_weekdays and #repeat_days == 5 then
        return "Weekdays"
    end

    -- Check for weekends (Sat-Sun)
    local weekends = {Sat=true, Sun=true}
    local is_weekends = true
    for __, day in ipairs(repeat_days) do
        if not weekends[day] then
            is_weekends = false
            break
        end
    end
    if is_weekends and #repeat_days == 2 then
        return "Weekends"
    end

    return table.concat(repeat_days, "/")
end

--[[--
Get reminders that are upcoming today.
--]]
function Reminders:getUpcomingToday(reminders)
    local now = os.date("*t")
    local current_minutes = now.hour * 60 + now.min
    local today_abbr = DAY_NAMES[now.wday]

    local upcoming = {}

    for __, reminder in ipairs(reminders) do
        if reminder.active then
            local is_today = false
            if not reminder.repeat_days or #reminder.repeat_days == 0 then
                is_today = true
            else
                for __, day in ipairs(reminder.repeat_days) do
                    if day == today_abbr then
                        is_today = true
                        break
                    end
                end
            end

            if is_today and reminder.time then
                local hour, min = reminder.time:match("(%d+):(%d+)")
                if hour and min then
                    local reminder_minutes = tonumber(hour) * 60 + tonumber(min)
                    if reminder_minutes > current_minutes then
                        table.insert(upcoming, reminder)
                    end
                end
            end
        end
    end

    table.sort(upcoming, function(a, b)
        return a.time < b.time
    end)

    return upcoming
end

--[[--
Format time until a reminder.
--]]
function Reminders:formatTimeUntil(time_str)
    if not time_str then return "" end

    local hour, min = time_str:match("(%d+):(%d+)")
    if not hour or not min then return "" end

    local now = os.date("*t")
    local current_minutes = now.hour * 60 + now.min
    local target_minutes = tonumber(hour) * 60 + tonumber(min)
    local diff = target_minutes - current_minutes

    if diff <= 0 then
        return "now"
    elseif diff < 60 then
        return string.format("in %d min", diff)
    else
        local hours = math.floor(diff / 60)
        local mins = diff % 60
        if mins > 0 then
            return string.format("in %dh %dm", hours, mins)
        else
            return string.format("in %dh", hours)
        end
    end
end

--[[--
Show actions for a reminder (edit, toggle, delete).
--]]
function Reminders:showReminderActions(reminder)
    local toggle_text = reminder.active and _("Disable") or _("Enable")

    local dialog
    dialog = ButtonDialog:new{
        title = reminder.title,
        buttons = {
            {{
                text = _("Edit"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEditReminder(reminder)
                end,
            }},
            {{
                text = toggle_text,
                callback = function()
                    UIManager:close(dialog)
                    self:toggleReminder(reminder)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmDelete(reminder)
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

-- Maximum reminder title length
local MAX_REMINDER_TITLE_LENGTH = 200

--[[--
Show dialog to add a new reminder.
--]]
function Reminders:showAddReminder()
    local dialog
    dialog = InputDialog:new{
        title = _("New Reminder"),
        input_hint = _("What do you want to remember? (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Next"),
                callback = function()
                    local title = dialog:getInputText()
                    if not title or title == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a title"),
                            timeout = 2,
                        })
                        return
                    end
                    if #title > MAX_REMINDER_TITLE_LENGTH then
                        UIManager:show(InfoMessage:new{
                            text = string.format(_("Title too long (%d chars). Max is %d."), #title, MAX_REMINDER_TITLE_LENGTH),
                            timeout = 3,
                        })
                        return
                    end
                    UIManager:close(dialog)
                    self:showTimeInput(title)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Validate time string (HH:MM format with bounds checking).
@param time_str string Time to validate
@return boolean, string Valid status and normalized time (HH:MM) or error message
--]]
function Reminders:validateTime(time_str)
    if not time_str then
        return false, _("Please enter a time")
    end

    local hour, min = time_str:match("^(%d%d?):(%d%d)$")
    if not hour or not min then
        return false, _("Please enter time in HH:MM format")
    end

    hour = tonumber(hour)
    min = tonumber(min)

    if hour < 0 or hour > 23 then
        return false, _("Hour must be 00-23")
    end

    if min < 0 or min > 59 then
        return false, _("Minutes must be 00-59")
    end

    -- Return normalized time (always HH:MM with leading zeros)
    return true, string.format("%02d:%02d", hour, min)
end

--[[--
Step 2: Get time for reminder.
--]]
function Reminders:showTimeInput(title)
    local dialog
    dialog = InputDialog:new{
        title = _("Set Time"),
        input_hint = _("HH:MM (24-hour format)"),
        input = "08:00",
        buttons = {{
            {
                text = _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    self:showAddReminder()
                end,
            },
            {
                text = _("Next"),
                callback = function()
                    local time = dialog:getInputText()
                    UIManager:close(dialog)
                    local valid, result = self:validateTime(time)
                    if valid then
                        self:showDateSelection(title, result)
                    else
                        UIManager:show(InfoMessage:new{
                            text = result,
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
Step 3: Select date for reminder.
--]]
function Reminders:showDateSelection(title, time)
    local today = os.date("%Y-%m-%d")
    local tomorrow = os.date("%Y-%m-%d", os.time() + 86400)
    local next_week = os.date("%Y-%m-%d", os.time() + 7 * 86400)

    local dialog
    dialog = ButtonDialog:new{
        title = _("When should this reminder start?"),
        buttons = {
            {{
                text = string.format(_("Today (%s)"), today),
                callback = function()
                    UIManager:close(dialog)
                    self:showRepeatDays(title, time, today)
                end,
            }},
            {{
                text = string.format(_("Tomorrow (%s)"), tomorrow),
                callback = function()
                    UIManager:close(dialog)
                    self:showRepeatDays(title, time, tomorrow)
                end,
            }},
            {{
                text = string.format(_("Next Week (%s)"), next_week),
                callback = function()
                    UIManager:close(dialog)
                    self:showRepeatDays(title, time, next_week)
                end,
            }},
            {{
                text = _("Custom Date..."),
                callback = function()
                    UIManager:close(dialog)
                    self:showCustomDateInput(title, time)
                end,
            }},
            {{
                text = _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeInput(title)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Validate date string (YYYY-MM-DD format with real date checking).
@param date_str string Date to validate
@return boolean, string Valid status and error message if invalid
--]]
function Reminders:validateDate(date_str)
    if not date_str then
        return false, _("Please enter a date")
    end

    local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year or not month or not day then
        return false, _("Please enter date in YYYY-MM-DD format")
    end

    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)

    -- Basic range checks
    if year < 2020 or year > 2100 then
        return false, _("Year must be 2020-2100")
    end

    if month < 1 or month > 12 then
        return false, _("Month must be 01-12")
    end

    if day < 1 or day > 31 then
        return false, _("Day must be 01-31")
    end

    -- Validate actual date by converting to timestamp and back
    local time_table = {year = year, month = month, day = day, hour = 12}
    local timestamp = os.time(time_table)
    local check = os.date("*t", timestamp)

    -- If the date was invalid (e.g., Feb 30), os.time normalizes it
    if check.year ~= year or check.month ~= month or check.day ~= day then
        return false, _("Invalid date (e.g., Feb 30 doesn't exist)")
    end

    return true, nil
end

--[[--
Custom date input.
--]]
function Reminders:showCustomDateInput(title, time)
    local dialog
    dialog = InputDialog:new{
        title = _("Enter Date"),
        input_hint = _("YYYY-MM-DD"),
        input = os.date("%Y-%m-%d"),
        buttons = {{
            {
                text = _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    self:showDateSelection(title, time)
                end,
            },
            {
                text = _("Next"),
                callback = function()
                    local date = dialog:getInputText()
                    UIManager:close(dialog)
                    local valid, err = self:validateDate(date)
                    if valid then
                        self:showRepeatDays(title, time, date)
                    else
                        UIManager:show(InfoMessage:new{
                            text = err,
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
Step 4: Select repeat days.
--]]
function Reminders:showRepeatDays(title, time, start_date)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Repeat"),
        buttons = {
            {{
                text = _("Daily"),
                callback = function()
                    UIManager:close(dialog)
                    self:createReminder(title, time, {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}, start_date)
                end,
            }},
            {{
                text = _("Weekdays (Mon-Fri)"),
                callback = function()
                    UIManager:close(dialog)
                    self:createReminder(title, time, {"Mon", "Tue", "Wed", "Thu", "Fri"}, start_date)
                end,
            }},
            {{
                text = _("Weekends (Sat-Sun)"),
                callback = function()
                    UIManager:close(dialog)
                    self:createReminder(title, time, {"Sat", "Sun"}, start_date)
                end,
            }},
            {{
                text = _("Once (no repeat)"),
                callback = function()
                    UIManager:close(dialog)
                    self:createReminder(title, time, {}, start_date)
                end,
            }},
            {{
                text = _("Custom Days..."),
                callback = function()
                    UIManager:close(dialog)
                    self:showCustomDays(title, time, start_date)
                end,
            }},
            {{
                text = _("Back"),
                callback = function()
                    UIManager:close(dialog)
                    self:showDateSelection(title, time)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Show custom day selection.
--]]
function Reminders:showCustomDays(title, time, start_date)
    self.selected_days = {}
    self.temp_start_date = start_date
    self:showCustomDaysWithSelection(title, time, start_date)
end

function Reminders:showCustomDaysWithSelection(title, time, start_date)
    local buttons = {}

    for i, day in ipairs(DAY_FULL) do
        local abbr = DAY_NAMES[i]
        local selected = self.selected_days[abbr] and "[X] " or "[ ] "
        table.insert(buttons, {{
            text = selected .. day,
            callback = function()
                if self.selected_days[abbr] then
                    self.selected_days[abbr] = nil
                else
                    self.selected_days[abbr] = true
                end
                UIManager:close(self.custom_dialog)
                self:showCustomDaysWithSelection(title, time, start_date)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Done"),
        callback = function()
            UIManager:close(self.custom_dialog)
            local days = {}
            for __, abbr in ipairs(DAY_NAMES) do
                if self.selected_days[abbr] then
                    table.insert(days, abbr)
                end
            end
            self:createReminder(title, time, days, start_date)
        end,
    }})

    self.custom_dialog = ButtonDialog:new{
        title = _("Select Days"),
        buttons = buttons,
    }
    UIManager:show(self.custom_dialog)
end

--[[--
Create the reminder and save.
--]]
function Reminders:createReminder(title, time, repeat_days, start_date)
    Data:addReminder({
        title = title,
        time = time,
        repeat_days = repeat_days,
        start_date = start_date,
        active = true,
    })

    UIManager:show(InfoMessage:new{
        text = _("Reminder added!"),
        timeout = 2,
    })

    -- Refresh
    UIManager:close(self.reminders_widget)
    self:showRemindersView()
end

--[[--
Show edit dialog for a reminder.
--]]
function Reminders:showEditReminder(reminder)
    local dialog
    dialog = InputDialog:new{
        title = _("Edit Reminder"),
        input = reminder.title,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    local new_title = dialog:getInputText()
                    if not new_title or new_title == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a title"),
                            timeout = 2,
                        })
                        return
                    end
                    if #new_title > MAX_REMINDER_TITLE_LENGTH then
                        UIManager:show(InfoMessage:new{
                            text = string.format(_("Title too long (%d chars). Max is %d."), #new_title, MAX_REMINDER_TITLE_LENGTH),
                            timeout = 3,
                        })
                        return
                    end
                    UIManager:close(dialog)
                    Data:updateReminder(reminder.id, {title = new_title})
                    UIManager:close(self.reminders_widget)
                    self:showRemindersView()
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Toggle reminder active state.
--]]
function Reminders:toggleReminder(reminder)
    Data:updateReminder(reminder.id, {active = not reminder.active})

    UIManager:close(self.reminders_widget)
    self:showRemindersView()
end

--[[--
Confirm deletion of a reminder.
--]]
function Reminders:confirmDelete(reminder)
    local dialog
    dialog = ButtonDialog:new{
        title = string.format(_("Delete '%s'?"), reminder.title),
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
                    Data:deleteReminder(reminder.id)
                    UIManager:close(self.reminders_widget)
                    self:showRemindersView()
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Check for due reminders (called periodically by main plugin).
--]]
function Reminders:checkDueReminders()
    local reminders = Data:loadReminders()
    local now = os.date("*t")
    local current_time = string.format("%02d:%02d", now.hour, now.min)
    local today_abbr = DAY_NAMES[now.wday]
    local today_date = os.date("%Y-%m-%d")

    local due = {}

    for __, reminder in ipairs(reminders) do
        if reminder.active and reminder.time == current_time then
            local should_fire = false
            if not reminder.repeat_days or #reminder.repeat_days == 0 then
                if reminder.last_triggered ~= today_date then
                    should_fire = true
                end
            else
                for __, day in ipairs(reminder.repeat_days) do
                    if day == today_abbr then
                        if reminder.last_triggered ~= today_date then
                            should_fire = true
                        end
                        break
                    end
                end
            end

            if should_fire then
                table.insert(due, reminder)
                Data:updateReminder(reminder.id, {last_triggered = today_date})
            end
        end
    end

    return due
end

--[[--
Show a gentle notification for a reminder.
--]]
function Reminders:showNotification(reminder)
    UIManager:show(InfoMessage:new{
        text = string.format("%s\n\nTime for: %s", reminder.time, reminder.title),
        timeout = 10,
    })
end

--[[--
Get today's reminders for dashboard display.
--]]
function Reminders:getTodayReminders()
    local reminders = Data:loadReminders()
    local now = os.date("*t")
    local today_abbr = DAY_NAMES[now.wday]

    local today_reminders = {}

    for __, reminder in ipairs(reminders) do
        if reminder.active then
            local is_today = false
            if not reminder.repeat_days or #reminder.repeat_days == 0 then
                is_today = true
            else
                for __, day in ipairs(reminder.repeat_days) do
                    if day == today_abbr then
                        is_today = true
                        break
                    end
                end
            end

            if is_today then
                table.insert(today_reminders, reminder)
            end
        end
    end

    -- Sort by time
    table.sort(today_reminders, function(a, b)
        return (a.time or "00:00") < (b.time or "00:00")
    end)

    return today_reminders
end

return Reminders
