--[[--
Life Tracker plugin for KOReader.

An ADHD-friendly bullet journal style planner with:
- Quest management (daily, weekly, monthly)
- Energy-based task filtering
- Visual timeline by time of day
- Reminders with gentle notifications
- Journal with mood tracking and insights
- KOReader reading stats integration
- GitHub-style activity heatmap
- Lock screen dashboard option

@module koplugin.lifetracker
--]]

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

-- Plugin modules (lazy loaded)
local Data, Settings, Quests, Dashboard, Timeline, Reminders, Journal, ReadingStats

local LifeTracker = WidgetContainer:extend{
    name = "lifetracker",
    is_doc_only = false,
    reminder_timer_active = false,  -- Track if timer is running
}

function LifeTracker:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    -- Start reminder check timer
    self:scheduleReminderCheck()

    -- Seed random number generator for unique ID generation
    math.randomseed(os.time())
end

function LifeTracker:onDispatcherRegisterActions()
    Dispatcher:registerAction("lifetracker_dashboard", {
        category = "none",
        event = "ShowLifeTrackerDashboard",
        title = _("Life Tracker Dashboard"),
        general = true,
    })
    Dispatcher:registerAction("lifetracker_quests", {
        category = "none",
        event = "ShowLifeTrackerQuests",
        title = _("Life Tracker Quests"),
        general = true,
    })
    Dispatcher:registerAction("lifetracker_timeline", {
        category = "none",
        event = "ShowLifeTrackerTimeline",
        title = _("Life Tracker Timeline"),
        general = true,
    })
end

function LifeTracker:addToMainMenu(menu_items)
    menu_items.lifetracker = {
        text = _("Life Tracker"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Dashboard"),
                callback = function()
                    self:showDashboard()
                end,
            },
            {
                text = _("Quests"),
                callback = function()
                    self:showQuests()
                end,
            },
            {
                text = _("Timeline"),
                callback = function()
                    self:showTimeline()
                end,
            },
            {
                text = _("Reminders"),
                callback = function()
                    self:showReminders()
                end,
            },
            {
                text = _("Journal"),
                callback = function()
                    self:showJournal()
                end,
            },
            {
                text = "─────────────",
                enabled = false,
            },
            {
                text = _("Settings"),
                callback = function()
                    self:showSettings()
                end,
            },
        },
    }
end

-- Lazy load Data module
function LifeTracker:getData()
    if not Data then
        Data = require("modules/data")
    end
    return Data
end

-- Lazy load Settings module
function LifeTracker:getSettings()
    if not Settings then
        Settings = require("modules/settings")
    end
    return Settings
end

-- Lazy load ReadingStats module
function LifeTracker:getReadingStats()
    if not ReadingStats then
        ReadingStats = require("modules/reading_stats")
    end
    return ReadingStats
end

function LifeTracker:showDashboard()
    if not Dashboard then
        Dashboard = require("modules/dashboard")
    end
    Dashboard:show(self.ui)
end

function LifeTracker:showQuests()
    if not Quests then
        Quests = require("modules/quests")
    end
    Quests:show(self.ui)
end

function LifeTracker:showTimeline()
    if not Timeline then
        Timeline = require("modules/timeline")
    end
    Timeline:show(self.ui)
end

function LifeTracker:showReminders()
    if not Reminders then
        Reminders = require("modules/reminders")
    end
    Reminders:show(self.ui)
end

function LifeTracker:showJournal()
    if not Journal then
        Journal = require("modules/journal")
    end
    Journal:show(self.ui)
end

function LifeTracker:showSettings()
    self:getSettings():show(self.ui)
end

-- Dispatcher event handlers
function LifeTracker:onShowLifeTrackerDashboard()
    self:showDashboard()
    return true
end

function LifeTracker:onShowLifeTrackerQuests()
    self:showQuests()
    return true
end

function LifeTracker:onShowLifeTrackerTimeline()
    self:showTimeline()
    return true
end

--[[--
Schedule periodic reminder checks.
Checks every minute for due reminders.
--]]
function LifeTracker:scheduleReminderCheck()
    if self.reminder_timer_active then
        return  -- Already scheduled
    end
    self.reminder_timer_active = true
    self:doReminderCheck()
end

function LifeTracker:doReminderCheck()
    if not self.reminder_timer_active then
        return  -- Timer was stopped
    end

    self:checkReminders()

    -- Schedule next check (60 seconds)
    UIManager:scheduleIn(60, function()
        self:doReminderCheck()
    end)
end

function LifeTracker:stopReminderCheck()
    self.reminder_timer_active = false
end

--[[--
Check for due reminders and show notifications.
--]]
function LifeTracker:checkReminders()
    if not Reminders then
        Reminders = require("modules/reminders")
    end

    local due_reminders = Reminders:checkDueReminders()
    for _, reminder in ipairs(due_reminders) do
        Reminders:showNotification(reminder)
    end
end

--[[--
Handle suspend event (device going to sleep).
KOReader calls this automatically on WidgetContainer plugins.
--]]
function LifeTracker:onSuspend()
    -- Log reading stats before suspend
    self:getReadingStats():logCurrentStats(self.ui)
end

--[[--
Handle resume event (device waking up).
KOReader calls this automatically on WidgetContainer plugins.
Shows dashboard as wake screen if enabled.
--]]
function LifeTracker:onResume()
    local settings = self:getData():loadUserSettings()
    if settings and settings.lock_screen_dashboard then
        -- Small delay to let KOReader finish resuming
        UIManager:scheduleIn(0.5, function()
            self:showDashboard()
        end)
    end
end

--[[--
Called when document is closed.
Log reading stats.
--]]
function LifeTracker:onCloseDocument()
    self:getReadingStats():logCurrentStats(self.ui)
end

--[[--
Save data on KOReader settings flush.
--]]
function LifeTracker:onFlushSettings()
    -- Log reading stats
    self:getReadingStats():logCurrentStats(self.ui)

    -- Flush all data
    local data = self:getData()
    data:flushAll()

    -- Create daily auto-backup (keeps last 7 days)
    data:autoBackup(7)
end

--[[--
Called when plugin is disabled or KOReader exits.
Clean up timer to prevent memory leak.
--]]
function LifeTracker:onCloseWidget()
    self:stopReminderCheck()
end

return LifeTracker
