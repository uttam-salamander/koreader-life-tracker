--[[--
Settings module for Life Tracker.
Manages user preferences for energy categories, time slots, and display options.

@module lifetracker.settings
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Data = require("modules/data")

local Settings = {}

--[[--
Show the settings menu.
@tparam table ui The UI manager reference
--]]
function Settings:show(ui)
    local user_settings = Data:loadUserSettings()

    local menu
    menu = Menu:new{
        title = _("Life Tracker Settings"),
        item_table = {
            {
                text = _("Energy Categories"),
                callback = function()
                    UIManager:close(menu)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Time Slots"),
                callback = function()
                    UIManager:close(menu)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
            {
                text = _("Lock Screen Dashboard"),
                checked_func = function()
                    return user_settings.lock_screen_dashboard == true
                end,
                callback = function()
                    user_settings.lock_screen_dashboard = not user_settings.lock_screen_dashboard
                    Data:saveUserSettings(user_settings)
                    UIManager:close(menu)
                    self:show(ui)
                end,
                help_text = _("Show dashboard when device wakes from sleep"),
            },
            {
                text = _("Reset All Data"),
                callback = function()
                    UIManager:close(menu)
                    self:confirmResetData(ui)
                end,
            },
        },
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show energy categories configuration.
--]]
function Settings:showEnergyCategoriesMenu(ui, user_settings)
    local items = {}

    -- Current categories
    for i, category in ipairs(user_settings.energy_categories) do
        table.insert(items, {
            text = category,
            callback = function()
                self:editEnergyCategory(ui, user_settings, i)
            end,
        })
    end

    -- Add new category
    table.insert(items, {
        text = _("[+] Add Category"),
        callback = function()
            self:addEnergyCategory(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Energy Categories"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:show(ui)
        end,
    }
    UIManager:show(menu)
end

--[[--
Edit an existing energy category.
--]]
function Settings:editEnergyCategory(ui, user_settings, index)
    local current = user_settings.energy_categories[index]

    local dialog
    dialog = ButtonDialog:new{
        title = current,
        buttons = {
            {{
                text = _("Rename"),
                callback = function()
                    UIManager:close(dialog)
                    self:renameEnergyCategory(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    if #user_settings.energy_categories > 1 then
                        table.remove(user_settings.energy_categories, index)
                        Data:saveUserSettings(user_settings)
                        UIManager:show(InfoMessage:new{
                            text = _("Category deleted"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Cannot delete last category"),
                            timeout = 2,
                        })
                    end
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Rename an energy category.
--]]
function Settings:renameEnergyCategory(ui, user_settings, index)
    local current = user_settings.energy_categories[index]

    local dialog
    dialog = InputDialog:new{
        title = _("Rename Category"),
        input = current,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name and new_name ~= "" then
                        user_settings.energy_categories[index] = new_name
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Add a new energy category.
--]]
function Settings:addEnergyCategory(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("New Energy Category"),
        input = "",
        input_hint = _("e.g., Focused, Tired, Anxious"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name and new_name ~= "" then
                        table.insert(user_settings.energy_categories, new_name)
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Show time slots configuration.
--]]
function Settings:showTimeSlotsMenu(ui, user_settings)
    local items = {}

    -- Current time slots
    for i, slot in ipairs(user_settings.time_slots) do
        table.insert(items, {
            text = slot,
            callback = function()
                self:editTimeSlot(ui, user_settings, i)
            end,
        })
    end

    -- Add new slot
    table.insert(items, {
        text = _("[+] Add Time Slot"),
        callback = function()
            self:addTimeSlot(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Time Slots"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:show(ui)
        end,
    }
    UIManager:show(menu)
end

--[[--
Edit an existing time slot.
--]]
function Settings:editTimeSlot(ui, user_settings, index)
    local current = user_settings.time_slots[index]

    local dialog
    dialog = ButtonDialog:new{
        title = current,
        buttons = {
            {{
                text = _("Rename"),
                callback = function()
                    UIManager:close(dialog)
                    self:renameTimeSlot(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    if #user_settings.time_slots > 1 then
                        table.remove(user_settings.time_slots, index)
                        Data:saveUserSettings(user_settings)
                        UIManager:show(InfoMessage:new{
                            text = _("Time slot deleted"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Cannot delete last time slot"),
                            timeout = 2,
                        })
                    end
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Rename a time slot.
--]]
function Settings:renameTimeSlot(ui, user_settings, index)
    local current = user_settings.time_slots[index]

    local dialog
    dialog = InputDialog:new{
        title = _("Rename Time Slot"),
        input = current,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name and new_name ~= "" then
                        user_settings.time_slots[index] = new_name
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Add a new time slot.
--]]
function Settings:addTimeSlot(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("New Time Slot"),
        input = "",
        input_hint = _("e.g., Early Morning, Late Night"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name and new_name ~= "" then
                        table.insert(user_settings.time_slots, new_name)
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Confirm and reset all plugin data.
--]]
function Settings:confirmResetData(ui)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Reset All Data?"),
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:show(ui)
                end,
            }},
            {{
                text = _("Reset Everything"),
                callback = function()
                    UIManager:close(dialog)
                    -- Reset to defaults
                    Data:saveUserSettings({
                        energy_categories = {"Energetic", "Average", "Down"},
                        time_slots = {"Morning", "Afternoon", "Evening", "Night"},
                        streak_data = {current = 0, longest = 0, last_completed_date = nil},
                        today_energy = nil,
                        today_date = nil,
                        lock_screen_dashboard = false,
                    })
                    Data:saveAllQuests({daily = {}, weekly = {}, monthly = {}})
                    Data:saveDailyLogs({})
                    Data:saveReminders({})
                    UIManager:show(InfoMessage:new{
                        text = _("All data has been reset"),
                        timeout = 3,
                    })
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

return Settings
