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
local UIConfig = require("modules/ui_config")

local Settings = {}

--[[--
Show the settings menu.
@tparam table ui The UI manager reference
--]]
function Settings:show(ui)
    self.ui = ui
    local user_settings = Data:loadUserSettings()

    local menu
    menu = Menu:new{
        title = _("Life Tracker Settings"),
        item_table = {
            {
                text = _("Open Dashboard"),
                callback = function()
                    UIManager:close(menu)
                    local Dashboard = require("modules/dashboard")
                    Dashboard:show(ui)
                end,
                help_text = _("Go to the Life Tracker dashboard"),
            },
            {
                text = _("Energy Categories"),
                callback = function()
                    UIManager:close(menu)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
                help_text = _("Customize your energy level options"),
            },
            {
                text = _("Time Slots"),
                callback = function()
                    UIManager:close(menu)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
                help_text = _("Customize time of day categories"),
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
                text = _("Large Touch Targets"),
                checked_func = function()
                    return user_settings.large_touch_targets == true
                end,
                callback = function()
                    user_settings.large_touch_targets = not user_settings.large_touch_targets
                    Data:saveUserSettings(user_settings)
                    -- Invalidate UIConfig dimensions to apply changes
                    UIConfig:invalidateDimensions()
                    UIManager:close(menu)
                    self:show(ui)
                end,
                help_text = _("Increase button sizes for easier tapping"),
            },
            {
                text = _("High Contrast Mode"),
                checked_func = function()
                    return user_settings.high_contrast == true
                end,
                callback = function()
                    user_settings.high_contrast = not user_settings.high_contrast
                    Data:saveUserSettings(user_settings)
                    -- Update color scheme
                    UIConfig:updateColorScheme()
                    UIManager:close(menu)
                    self:show(ui)
                end,
                help_text = _("Use stronger contrast for better visibility"),
            },
            {
                text = _("Daily Quotes"),
                callback = function()
                    UIManager:close(menu)
                    self:showQuotesMenu(ui, user_settings)
                end,
                help_text = _("Manage inspirational quotes shown on dashboard"),
            },
            {
                text = _("Backup Data"),
                callback = function()
                    UIManager:close(menu)
                    self:createBackup(ui)
                end,
                help_text = _("Export all data to a backup file"),
            },
            {
                text = _("Restore Data"),
                callback = function()
                    UIManager:close(menu)
                    self:showRestoreMenu(ui)
                end,
                help_text = _("Restore data from a backup file"),
            },
            {
                text = _("Reset All Data"),
                callback = function()
                    UIManager:close(menu)
                    self:confirmResetData(ui)
                end,
                help_text = _("Delete all quests, reminders, and logs"),
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
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
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
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
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
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
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
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
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

-- ============================================
-- Daily Quotes Functions
-- ============================================

-- Maximum quote length
local MAX_QUOTE_LENGTH = 200

--[[--
Show quotes management menu.
--]]
function Settings:showQuotesMenu(ui, user_settings)
    local items = {}

    -- Current quotes
    local quotes = user_settings.quotes or {}
    for i, quote in ipairs(quotes) do
        -- Truncate long quotes for menu display
        local display_text = quote
        if #quote > 50 then
            display_text = quote:sub(1, 47) .. "..."
        end
        table.insert(items, {
            text = display_text,
            callback = function()
                self:showQuoteOptions(ui, user_settings, i)
            end,
        })
    end

    -- Add new quote option
    table.insert(items, {
        text = _("[+] Add New Quote"),
        callback = function()
            self:addNewQuote(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Daily Quotes"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:show(ui)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show options for a specific quote (edit/delete).
--]]
function Settings:showQuoteOptions(ui, user_settings, index)
    local quote = user_settings.quotes[index]
    local dialog
    dialog = ButtonDialog:new{
        title = quote,
        buttons = {
            {{
                text = _("Edit"),
                callback = function()
                    UIManager:close(dialog)
                    self:editQuote(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    table.remove(user_settings.quotes, index)
                    Data:saveUserSettings(user_settings)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote deleted"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
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
Add a new quote.
--]]
function Settings:addNewQuote(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("Add Quote"),
        input = "",
        input_hint = _("Enter your quote (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    local quote = Data:sanitizeTextInput(dialog:getInputText(), MAX_QUOTE_LENGTH)
                    if not quote or quote == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a quote"),
                            timeout = 2,
                        })
                        return
                    end
                    if not user_settings.quotes then
                        user_settings.quotes = {}
                    end
                    table.insert(user_settings.quotes, quote)
                    Data:saveUserSettings(user_settings)
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote added!"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Edit an existing quote.
--]]
function Settings:editQuote(ui, user_settings, index)
    local dialog
    dialog = InputDialog:new{
        title = _("Edit Quote"),
        input = user_settings.quotes[index],
        input_hint = _("Enter your quote (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local quote = Data:sanitizeTextInput(dialog:getInputText(), MAX_QUOTE_LENGTH)
                    if not quote or quote == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a quote"),
                            timeout = 2,
                        })
                        return
                    end
                    user_settings.quotes[index] = quote
                    Data:saveUserSettings(user_settings)
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote updated!"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- Backup & Restore Functions
-- ============================================

--[[--
Create a backup of all plugin data.
--]]
function Settings:createBackup(ui)
    local ok, result = Data:exportBackupToFile()

    if ok then
        -- Extract just the filename for display
        local filename = result:match("([^/]+)$")
        UIManager:show(InfoMessage:new{
            text = _("Backup created successfully!\n\nFile: ") .. filename,
            timeout = 5,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Backup failed: ") .. (result or "Unknown error"),
            timeout = 5,
        })
    end
    self:show(ui)
end

--[[--
Show menu to restore from available backups.
--]]
function Settings:showRestoreMenu(ui)
    local backups = Data:listBackups()

    if #backups == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No backups found.\n\nCreate a backup first using 'Backup Data'."),
            timeout = 4,
        })
        self:show(ui)
        return
    end

    local items = {}
    local menu
    local navigating_away = false  -- Flag to prevent close_callback from showing settings

    for __, backup in ipairs(backups) do
        -- Format size in KB
        local size_kb = string.format("%.1f KB", (backup.size or 0) / 1024)
        table.insert(items, {
            text = backup.created_at .. " (" .. size_kb .. ")",
            callback = function()
                navigating_away = true
                UIManager:close(menu)
                self:confirmRestore(ui, backup)
            end,
            hold_callback = function()
                navigating_away = true
                UIManager:close(menu)
                self:showBackupOptions(ui, backup)
            end,
        })
    end

    menu = Menu:new{
        title = _("Select Backup to Restore"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            if not navigating_away then
                self:show(ui)
            end
        end,
    }
    UIManager:show(menu)
end

--[[--
Show options for a backup (restore or delete).
--]]
function Settings:showBackupOptions(ui, backup)
    local dialog
    dialog = ButtonDialog:new{
        title = backup.created_at,
        buttons = {
            {{
                text = _("Restore"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmRestore(ui, backup)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmDeleteBackup(ui, backup)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showRestoreMenu(ui)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Confirm restoration from a backup.
--]]
function Settings:confirmRestore(ui, backup)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Restore from backup?\n\nThis will replace all current data with:\n") .. backup.created_at,
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showRestoreMenu(ui)
                end,
            }},
            {{
                text = _("Restore"),
                callback = function()
                    UIManager:close(dialog)
                    local ok, result = Data:importBackupFromFile(backup.filepath)
                    if ok then
                        UIManager:show(InfoMessage:new{
                            text = _("Data restored successfully!"),
                            timeout = 3,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Restore failed: ") .. (result or "Unknown error"),
                            timeout = 5,
                        })
                    end
                    self:show(ui)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Confirm deletion of a backup file.
--]]
function Settings:confirmDeleteBackup(ui, backup)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Delete backup?"),
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showRestoreMenu(ui)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    local ok = Data:deleteBackup(backup.filepath)
                    if ok then
                        UIManager:show(InfoMessage:new{
                            text = _("Backup deleted"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Failed to delete backup"),
                            timeout = 3,
                        })
                    end
                    self:showRestoreMenu(ui)
                end,
            }},
        },
    }
    UIManager:show(dialog)
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
