--[[--
Life Tracker plugin for KOReader.

Track reading habits, personal goals, and life metrics alongside your reading.

@module koplugin.lifetracker
--]]

local Dispatcher = require("dispatcher")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template  -- Used for string templating

local LifeTracker = WidgetContainer:extend{
    name = "lifetracker",
    is_doc_only = false,
}

function LifeTracker:init()
    self:loadSettings()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function LifeTracker:loadSettings()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/lifetracker.lua")
    self.data = self.settings:readSetting("tracker_data") or {}
end

function LifeTracker:saveSettings()
    self.settings:saveSetting("tracker_data", self.data)
    self.settings:flush()
end

function LifeTracker:onDispatcherRegisterActions()
    Dispatcher:registerAction("lifetracker_show", {
        category = "none",
        event = "ShowLifeTracker",
        title = _("Show Life Tracker"),
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
                text = _("Add Entry"),
                callback = function()
                    self:addEntry()
                end,
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

function LifeTracker:showDashboard()
    -- TODO: Implement dashboard view
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Life Tracker Dashboard - Coming soon!"),
    })
end

function LifeTracker:addEntry()
    -- TODO: Implement entry addition
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Add Entry - Coming soon!"),
    })
end

function LifeTracker:showSettings()
    -- TODO: Implement settings view
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Settings - Coming soon!"),
    })
end

function LifeTracker:onShowLifeTracker()
    self:showDashboard()
end

return LifeTracker
