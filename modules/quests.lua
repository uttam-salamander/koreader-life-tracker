--[[--
Quests module for Life Tracker.
Manages quest CRUD, list views, and completion with cross-off gesture.

@module lifetracker.quests
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Data = require("modules/data")

local Quests = {}

-- Current view state
Quests.current_type = "daily"  -- daily, weekly, monthly

--[[--
Show the quests menu with type tabs.
@tparam table ui The UI manager reference
--]]
function Quests:show(ui)
    self.ui = ui
    self:showQuestList()
end

--[[--
Show quest list for current type.
--]]
function Quests:showQuestList()
    local quests = Data:loadAllQuests()
    local user_settings = Data:loadUserSettings()
    local quest_list = quests[self.current_type] or {}

    local items = {}

    -- Type selector tabs
    table.insert(items, {
        text = self:getTypeTabsText(),
        callback = function()
            self:showTypeSelector()
        end,
    })

    -- Separator
    table.insert(items, {
        text = "─────────────────────────────",
        enabled = false,
    })

    -- Quest items
    if #quest_list == 0 then
        table.insert(items, {
            text = _("No quests yet. Add one!"),
            enabled = false,
        })
    else
        for _, quest in ipairs(quest_list) do
            local status_icon = quest.completed and "✓" or "○"
            local time_slot_abbr = self:getTimeSlotAbbr(quest.time_slot, user_settings.time_slots)
            local energy_abbr = self:getEnergyAbbr(quest.energy_required)

            -- Format: ○ Quest title [M] [Avg]
            local display_text = string.format("%s %s [%s] [%s]",
                status_icon,
                quest.title,
                time_slot_abbr,
                energy_abbr
            )

            -- Add streak info if > 0
            local mandatory_text = ""
            if quest.streak and quest.streak > 0 then
                mandatory_text = string.format("🔥 %d", quest.streak)
            end

            table.insert(items, {
                text = display_text,
                mandatory = mandatory_text,
                quest = quest,
                callback = function()
                    self:showQuestActions(quest)
                end,
                hold_callback = function()
                    self:showQuestActions(quest)
                end,
            })
        end
    end

    -- Separator
    table.insert(items, {
        text = "─────────────────────────────",
        enabled = false,
    })

    -- Add new quest button
    table.insert(items, {
        text = _("[+] Add New Quest"),
        callback = function()
            self:showAddQuestDialog()
        end,
    })

    -- Legend
    table.insert(items, {
        text = _("Legend: ○=pending ✓=done"),
        enabled = false,
    })

    local menu
    menu = Menu:new{
        title = string.format(_("Quests - %s"), self:getTypeDisplayName()),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    self.menu = menu
    UIManager:show(menu)
end

--[[--
Get abbreviated time slot name.
--]]
function Quests:getTimeSlotAbbr(slot, _time_slots)
    if not slot then return "?" end
    -- Return first letter of each word
    local abbr = ""
    for word in slot:gmatch("%S+") do
        abbr = abbr .. word:sub(1, 1):upper()
    end
    return abbr ~= "" and abbr or slot:sub(1, 1):upper()
end

--[[--
Get abbreviated energy level.
--]]
function Quests:getEnergyAbbr(energy)
    if not energy then return "Any" end
    if energy == "Any" or energy == "" then return "Any" end
    return energy:sub(1, 3)
end

--[[--
Get display text for type tabs.
--]]
function Quests:getTypeTabsText()
    local types = {"daily", "weekly", "monthly"}
    local parts = {}
    for _, t in ipairs(types) do
        if t == self.current_type then
            table.insert(parts, "[" .. t:upper() .. "]")
        else
            table.insert(parts, t)
        end
    end
    return table.concat(parts, "  ")
end

--[[--
Get display name for current type.
--]]
function Quests:getTypeDisplayName()
    local names = {
        daily = _("Daily"),
        weekly = _("Weekly"),
        monthly = _("Monthly"),
    }
    return names[self.current_type] or self.current_type
end

--[[--
Show type selector dialog.
--]]
function Quests:showTypeSelector()
    local dialog
    dialog = ButtonDialog:new{
        title = _("Quest Type"),
        buttons = {
            {{
                text = _("Daily"),
                callback = function()
                    UIManager:close(dialog)
                    self.current_type = "daily"
                    if self.menu then UIManager:close(self.menu) end
                    self:showQuestList()
                end,
            }},
            {{
                text = _("Weekly"),
                callback = function()
                    UIManager:close(dialog)
                    self.current_type = "weekly"
                    if self.menu then UIManager:close(self.menu) end
                    self:showQuestList()
                end,
            }},
            {{
                text = _("Monthly"),
                callback = function()
                    UIManager:close(dialog)
                    self.current_type = "monthly"
                    if self.menu then UIManager:close(self.menu) end
                    self:showQuestList()
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
Show actions for a quest (complete, edit, delete).
--]]
function Quests:showQuestActions(quest)
    local complete_text = quest.completed and _("Mark Incomplete") or _("✓ Complete (swipe right)")

    local dialog
    dialog = ButtonDialog:new{
        title = quest.title,
        buttons = {
            {{
                text = complete_text,
                callback = function()
                    UIManager:close(dialog)
                    self:toggleQuestComplete(quest)
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
        -- Update streak
        local today = Data:getCurrentDate()
        local quests = Data:loadAllQuests()
        for _, q in ipairs(quests[self.current_type]) do
            if q.id == quest.id then
                -- Check if streak continues
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

        -- Update daily log for analytics
        self:updateDailyLog()

        -- Update global streak
        self:updateGlobalStreak()

        UIManager:show(InfoMessage:new{
            text = _("Quest completed! 🎉"),
            timeout = 1,
        })
    end

    -- Refresh list
    if self.menu then UIManager:close(self.menu) end
    self:showQuestList()
end

--[[--
Update global streak data.
--]]
function Quests:updateGlobalStreak()
    local user_settings = Data:loadUserSettings()
    local today = Data:getCurrentDate()

    if user_settings.streak_data.last_completed_date == today then
        -- Already counted today
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
This enables the heatmap and journal analytics.
--]]
function Quests:updateDailyLog()
    local today = Data:getCurrentDate()
    local quests = Data:loadAllQuests()
    local logs = Data:loadDailyLogs()

    -- Guard against nil data (corrupted files)
    if not quests then
        return  -- Can't update log without quest data
    end
    if not logs then
        logs = {}  -- Start fresh if logs are corrupted
    end

    -- Count today's quests
    local total = 0
    local completed = 0

    for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for _, quest in ipairs(quests[quest_type] or {}) do
            -- Count quests that should appear today
            -- For simplicity, count all active quests
            total = total + 1
            if quest.completed and quest.completed_date == today then
                completed = completed + 1
            end
        end
    end

    -- Update or create log entry
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
        energy_required = "Any",
    }
    self:showQuestTitleInput(false)
end

--[[--
Show edit quest dialog.
--]]
function Quests:showEditQuestDialog(quest)
    self.editing_quest = quest
    self.new_quest = {
        title = quest.title,
        time_slot = quest.time_slot,
        energy_required = quest.energy_required,
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
Show energy level selector.
--]]
function Quests:showEnergySelector(is_edit)
    local user_settings = Data:loadUserSettings()
    local buttons = {}

    -- "Any" option - show on all energy levels
    table.insert(buttons, {{
        text = _("Any (always show)"),
        callback = function()
            self.new_quest.energy_required = "Any"
            UIManager:close(self.energy_dialog)
            self:saveQuest(is_edit)
        end,
    }})

    -- Energy categories
    for _, energy in ipairs(user_settings.energy_categories) do
        table.insert(buttons, {{
            text = energy,
            callback = function()
                self.new_quest.energy_required = energy
                UIManager:close(self.energy_dialog)
                self:saveQuest(is_edit)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(self.energy_dialog)
        end,
    }})

    self.energy_dialog = ButtonDialog:new{
        title = _("On what kind of day?"),
        buttons = buttons,
    }
    UIManager:show(self.energy_dialog)
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
        })
        UIManager:show(InfoMessage:new{
            text = _("Quest added!"),
            timeout = 2,
        })
    end

    -- Refresh list
    if self.menu then UIManager:close(self.menu) end
    self:showQuestList()
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
                    if self.menu then UIManager:close(self.menu) end
                    self:showQuestList()
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Get quests filtered by energy level for today.
@tparam string energy_level Current energy level
@treturn table Filtered quests from all types
--]]
function Quests:getFilteredQuestsForToday(energy_level)
    local quests = Data:loadAllQuests()
    if not quests then
        return {}  -- No quests data available
    end

    local user_settings = Data:loadUserSettings()
    local filtered = {}

    -- If energy level not set (first-time user), show all quests
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

    -- Get highest energy level from settings (first in list)
    -- When at highest energy, user sees ALL quests regardless of requirement
    local highest_energy = user_settings.energy_categories and user_settings.energy_categories[1] or "Energetic"
    local is_high_energy = (energy_level == highest_energy)

    -- For daily quests
    for _, quest in ipairs(quests.daily or {}) do
        if not quest.completed then
            if quest.energy_required == "Any" or
               quest.energy_required == energy_level or
               is_high_energy then  -- High energy sees all
                table.insert(filtered, quest)
            end
        end
    end

    -- Weekly quests also show on dashboard
    for _, quest in ipairs(quests.weekly or {}) do
        if not quest.completed then
            if quest.energy_required == "Any" or
               quest.energy_required == energy_level or
               is_high_energy then
                table.insert(filtered, quest)
            end
        end
    end

    return filtered
end

return Quests
