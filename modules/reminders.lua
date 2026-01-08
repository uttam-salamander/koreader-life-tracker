--[[--
Reminders module for Life Tracker.
Time-based reminders with gentle notifications.
@module lifetracker.reminders
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")

local Data = require("modules/data")

local Reminders = {}

-- Day abbreviations
local DAY_NAMES = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local DAY_FULL = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

--[[--
Show the reminders view.
--]]
function Reminders:show(ui)
    self.ui = ui
    self:showRemindersList()
end

--[[--
Display the list of reminders.
--]]
function Reminders:showRemindersList()
    local reminders = Data:loadReminders()
    local screen_width = Screen:getWidth()

    -- Build menu items
    local menu_items = {}

    -- Active reminders section
    local active_count = 0
    for _, reminder in ipairs(reminders) do
        if reminder.active then
            active_count = active_count + 1
            local repeat_text = self:formatRepeatDays(reminder.repeat_days)
            local time_text = reminder.time or "??:??"

            table.insert(menu_items, {
                text = string.format("⏰ %s  %s  [%s]", time_text, reminder.title, repeat_text),
                callback = function()
                    self:showReminderActions(reminder)
                end,
            })
        end
    end

    -- Inactive reminders section
    local inactive_count = 0
    for _, reminder in ipairs(reminders) do
        if not reminder.active then
            inactive_count = inactive_count + 1
            if inactive_count == 1 then
                -- Add separator before inactive
                table.insert(menu_items, {
                    text = "─── Inactive ───",
                    callback = function() end,
                })
            end

            table.insert(menu_items, {
                text = string.format("  %s  %s", reminder.time or "??:??", reminder.title),
                callback = function()
                    self:showReminderActions(reminder)
                end,
            })
        end
    end

    -- Upcoming today section
    local upcoming = self:getUpcomingToday(reminders)
    if #upcoming > 0 then
        table.insert(menu_items, 1, {
            text = "─── Upcoming Today ───",
            callback = function() end,
        })
        for i, reminder in ipairs(upcoming) do
            local time_until = self:formatTimeUntil(reminder.time)
            table.insert(menu_items, i + 1, {
                text = string.format("  → %s  %s (%s)", reminder.time, reminder.title, time_until),
                callback = function()
                    self:showReminderActions(reminder)
                end,
            })
        end
    end

    -- Add button at the end
    table.insert(menu_items, {
        text = "[+] Add New Reminder",
        callback = function()
            self:showAddReminder()
        end,
    })

    -- Show menu
    local menu = Menu:new{
        title = _("Reminders"),
        item_table = menu_items,
        width = screen_width,
        height = Screen:getHeight(),
        show_parent = self.ui,
        onMenuHold = function(item)
            -- Long press to delete
            if item.reminder then
                self:confirmDelete(item.reminder)
            end
        end,
    }

    menu.close_callback = function()
        UIManager:close(menu)
    end

    self.menu = menu
    UIManager:show(menu)
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
    for _, day in ipairs(repeat_days) do
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
    for _, day in ipairs(repeat_days) do
        if not weekends[day] then
            is_weekends = false
            break
        end
    end
    if is_weekends and #repeat_days == 2 then
        return "Weekends"
    end

    -- Otherwise list abbreviated days
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

    for _, reminder in ipairs(reminders) do
        if reminder.active then
            -- Check if reminder is scheduled for today
            local is_today = false
            if not reminder.repeat_days or #reminder.repeat_days == 0 then
                is_today = true  -- One-time reminders show today
            else
                for _, day in ipairs(reminder.repeat_days) do
                    if day == today_abbr then
                        is_today = true
                        break
                    end
                end
            end

            if is_today and reminder.time then
                -- Parse time
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

    -- Sort by time
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
            return string.format("in %d hour%s", hours, hours > 1 and "s" or "")
        end
    end
end

--[[--
Show actions for a reminder (edit, toggle, delete).
--]]
function Reminders:showReminderActions(reminder)
    local toggle_text = reminder.active and _("Disable") or _("Enable")

    local buttons = {
        {
            {
                text = _("Edit"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:showEditReminder(reminder)
                end,
            },
        },
        {
            {
                text = toggle_text,
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:toggleReminder(reminder)
                end,
            },
        },
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:confirmDelete(reminder)
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.action_dialog)
                end,
            },
        },
    }

    self.action_dialog = ButtonDialog:new{
        title = reminder.title,
        buttons = buttons,
    }
    UIManager:show(self.action_dialog)
end

--[[--
Show dialog to add a new reminder.
--]]
function Reminders:showAddReminder()
    -- Step 1: Get title
    self.add_dialog = InputDialog:new{
        title = _("New Reminder"),
        input_hint = _("What do you want to remember?"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.add_dialog)
                    end,
                },
                {
                    text = _("Next"),
                    callback = function()
                        local title = self.add_dialog:getInputText()
                        UIManager:close(self.add_dialog)
                        if title and title ~= "" then
                            self:showTimeInput(title)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.add_dialog)
    self.add_dialog:onShowKeyboard()
end

--[[--
Step 2: Get time for reminder.
--]]
function Reminders:showTimeInput(title)
    self.time_dialog = InputDialog:new{
        title = _("Set Time"),
        input_hint = _("HH:MM (24-hour format)"),
        input = "08:00",
        buttons = {
            {
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(self.time_dialog)
                        self:showAddReminder()
                    end,
                },
                {
                    text = _("Next"),
                    callback = function()
                        local time = self.time_dialog:getInputText()
                        UIManager:close(self.time_dialog)
                        if time and time:match("^%d%d?:%d%d$") then
                            self:showRepeatDays(title, time)
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter time in HH:MM format"),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.time_dialog)
    self.time_dialog:onShowKeyboard()
end

--[[--
Step 3: Select repeat days.
--]]
function Reminders:showRepeatDays(title, time)
    local buttons = {
        {
            {
                text = _("Daily"),
                callback = function()
                    UIManager:close(self.days_dialog)
                    self:createReminder(title, time, {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"})
                end,
            },
        },
        {
            {
                text = _("Weekdays (Mon-Fri)"),
                callback = function()
                    UIManager:close(self.days_dialog)
                    self:createReminder(title, time, {"Mon", "Tue", "Wed", "Thu", "Fri"})
                end,
            },
        },
        {
            {
                text = _("Weekends (Sat-Sun)"),
                callback = function()
                    UIManager:close(self.days_dialog)
                    self:createReminder(title, time, {"Sat", "Sun"})
                end,
            },
        },
        {
            {
                text = _("Once (no repeat)"),
                callback = function()
                    UIManager:close(self.days_dialog)
                    self:createReminder(title, time, {})
                end,
            },
        },
        {
            {
                text = _("Custom Days..."),
                callback = function()
                    UIManager:close(self.days_dialog)
                    self:showCustomDays(title, time)
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.days_dialog)
                end,
            },
        },
    }

    self.days_dialog = ButtonDialog:new{
        title = _("Repeat"),
        buttons = buttons,
    }
    UIManager:show(self.days_dialog)
end

--[[--
Show custom day selection.
--]]
function Reminders:showCustomDays(title, time)
    local selected_days = {}

    local function toggleDay(day)
        if selected_days[day] then
            selected_days[day] = nil
        else
            selected_days[day] = true
        end
        -- Refresh dialog to show updated selection
        UIManager:close(self.custom_dialog)
        self:showCustomDaysWithSelection(title, time, selected_days)
    end

    self:showCustomDaysWithSelection(title, time, selected_days)
end

function Reminders:showCustomDaysWithSelection(title, time, selected_days)
    local buttons = {}

    for i, day in ipairs(DAY_FULL) do
        local abbr = DAY_NAMES[i]
        local selected = selected_days[abbr] and "✓ " or "  "
        table.insert(buttons, {
            {
                text = selected .. day,
                callback = function()
                    if selected_days[abbr] then
                        selected_days[abbr] = nil
                    else
                        selected_days[abbr] = true
                    end
                    UIManager:close(self.custom_dialog)
                    self:showCustomDaysWithSelection(title, time, selected_days)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Done"),
            callback = function()
                UIManager:close(self.custom_dialog)
                local days = {}
                for _, abbr in ipairs(DAY_NAMES) do
                    if selected_days[abbr] then
                        table.insert(days, abbr)
                    end
                end
                self:createReminder(title, time, days)
            end,
        },
    })

    self.custom_dialog = ButtonDialog:new{
        title = _("Select Days"),
        buttons = buttons,
    }
    UIManager:show(self.custom_dialog)
end

--[[--
Create the reminder and save.
--]]
function Reminders:createReminder(title, time, repeat_days)
    Data:addReminder({
        title = title,
        time = time,
        repeat_days = repeat_days,
        active = true,
    })

    UIManager:show(InfoMessage:new{
        text = _("Reminder added!"),
    })

    -- Refresh list
    if self.menu then
        UIManager:close(self.menu)
    end
    self:showRemindersList()
end

--[[--
Show edit dialog for a reminder.
--]]
function Reminders:showEditReminder(reminder)
    self.edit_dialog = InputDialog:new{
        title = _("Edit Reminder"),
        input = reminder.title,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.edit_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local new_title = self.edit_dialog:getInputText()
                        UIManager:close(self.edit_dialog)
                        if new_title and new_title ~= "" then
                            Data:updateReminder(reminder.id, {title = new_title})
                            if self.menu then
                                UIManager:close(self.menu)
                            end
                            self:showRemindersList()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.edit_dialog)
    self.edit_dialog:onShowKeyboard()
end

--[[--
Toggle reminder active state.
--]]
function Reminders:toggleReminder(reminder)
    Data:updateReminder(reminder.id, {active = not reminder.active})

    if self.menu then
        UIManager:close(self.menu)
    end
    self:showRemindersList()
end

--[[--
Confirm deletion of a reminder.
--]]
function Reminders:confirmDelete(reminder)
    local buttons = {
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.confirm_dialog)
                end,
            },
            {
                text = _("Delete"),
                callback = function()
                    UIManager:close(self.confirm_dialog)
                    Data:deleteReminder(reminder.id)
                    if self.menu then
                        UIManager:close(self.menu)
                    end
                    self:showRemindersList()
                end,
            },
        },
    }

    self.confirm_dialog = ButtonDialog:new{
        title = string.format(_("Delete '%s'?"), reminder.title),
        buttons = buttons,
    }
    UIManager:show(self.confirm_dialog)
end

--[[--
Check for due reminders (called periodically by main plugin).
Returns reminders that should fire now.
--]]
function Reminders:checkDueReminders()
    local reminders = Data:loadReminders()
    local now = os.date("*t")
    local current_time = string.format("%02d:%02d", now.hour, now.min)
    local today_abbr = DAY_NAMES[now.wday]
    local today_date = os.date("%Y-%m-%d")

    local due = {}

    for _, reminder in ipairs(reminders) do
        if reminder.active and reminder.time == current_time then
            -- Check if should fire today
            local should_fire = false
            if not reminder.repeat_days or #reminder.repeat_days == 0 then
                -- One-time reminder - check if already triggered
                if reminder.last_triggered ~= today_date then
                    should_fire = true
                end
            else
                -- Repeating reminder - check if today is in repeat days
                for _, day in ipairs(reminder.repeat_days) do
                    if day == today_abbr then
                        -- Check if already triggered today
                        if reminder.last_triggered ~= today_date then
                            should_fire = true
                        end
                        break
                    end
                end
            end

            if should_fire then
                table.insert(due, reminder)
                -- Mark as triggered today
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
    -- Gentle, encouraging notification
    UIManager:show(InfoMessage:new{
        text = string.format("🔔 %s\n\nTime for: %s", reminder.time, reminder.title),
        timeout = 10,  -- Auto-dismiss after 10 seconds
    })
end

return Reminders
