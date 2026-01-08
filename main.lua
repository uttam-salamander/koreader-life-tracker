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

@module koplugin.lifetracker
--]]

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

-- Plugin modules (lazy loaded)
local Data, Settings, Quests, Dashboard, Timeline, Reminders, Journal

local LifeTracker = WidgetContainer:extend{
    name = "lifetracker",
    is_doc_only = false,
}

function LifeTracker:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
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
        -- Timeline module not yet implemented
        UIManager:show(InfoMessage:new{
            text = _("Timeline - Phase 4"),
        })
        return
    end
    Timeline:show(self.ui)
end

function LifeTracker:showReminders()
    if not Reminders then
        -- Reminders module not yet implemented
        UIManager:show(InfoMessage:new{
            text = _("Reminders - Phase 5"),
        })
        return
    end
    Reminders:show(self.ui)
end

function LifeTracker:showJournal()
    if not Journal then
        -- Journal module not yet implemented
        UIManager:show(InfoMessage:new{
            text = _("Journal - Phase 6"),
        })
        return
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

-- Save data on KOReader settings flush
function LifeTracker:onFlushSettings()
    local data = self:getData()
    data:flushAll()
end

return LifeTracker
