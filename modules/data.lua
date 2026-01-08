--[[--
Data persistence module for Life Tracker.
Handles saving and loading all plugin data using LuaSettings.

@module lifetracker.data
--]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
-- local logger = require("logger")  -- Available for debugging

local Data = {}

-- File paths
local DATA_DIR = DataStorage:getSettingsDir()
local SETTINGS_FILE = DATA_DIR .. "/lifetracker_settings.lua"
local QUESTS_FILE = DATA_DIR .. "/lifetracker_quests.lua"
local LOGS_FILE = DATA_DIR .. "/lifetracker_logs.lua"
local REMINDERS_FILE = DATA_DIR .. "/lifetracker_reminders.lua"

-- Cached settings objects
local settings_cache = nil
local quests_cache = nil
local logs_cache = nil
local reminders_cache = nil

--[[--
Get or create the settings file.
@treturn LuaSettings settings object
--]]
function Data:getSettings()
    if not settings_cache then
        settings_cache = LuaSettings:open(SETTINGS_FILE)
    end
    return settings_cache
end

--[[--
Get or create the quests file.
@treturn LuaSettings quests object
--]]
function Data:getQuests()
    if not quests_cache then
        quests_cache = LuaSettings:open(QUESTS_FILE)
    end
    return quests_cache
end

--[[--
Get or create the logs file.
@treturn LuaSettings logs object
--]]
function Data:getLogs()
    if not logs_cache then
        logs_cache = LuaSettings:open(LOGS_FILE)
    end
    return logs_cache
end

--[[--
Get or create the reminders file.
@treturn LuaSettings reminders object
--]]
function Data:getReminders()
    if not reminders_cache then
        reminders_cache = LuaSettings:open(REMINDERS_FILE)
    end
    return reminders_cache
end

-- ============================================
-- Settings Operations
-- ============================================

function Data:loadUserSettings()
    local s = self:getSettings()
    return {
        energy_categories = s:readSetting("energy_categories") or {"Energetic", "Average", "Down"},
        time_slots = s:readSetting("time_slots") or {"Morning", "Afternoon", "Evening", "Night"},
        streak_data = s:readSetting("streak_data") or {
            current = 0,
            longest = 0,
            last_completed_date = nil,
        },
        today_energy = s:readSetting("today_energy") or nil,
        today_date = s:readSetting("today_date") or nil,
    }
end

function Data:saveUserSettings(user_settings)
    local s = self:getSettings()
    s:saveSetting("energy_categories", user_settings.energy_categories)
    s:saveSetting("time_slots", user_settings.time_slots)
    s:saveSetting("streak_data", user_settings.streak_data)
    s:saveSetting("today_energy", user_settings.today_energy)
    s:saveSetting("today_date", user_settings.today_date)
    s:flush()
end

-- ============================================
-- Quest Operations
-- ============================================

function Data:loadAllQuests()
    local q = self:getQuests()
    return {
        daily = q:readSetting("daily") or {},
        weekly = q:readSetting("weekly") or {},
        monthly = q:readSetting("monthly") or {},
    }
end

function Data:saveAllQuests(quests)
    local q = self:getQuests()
    q:saveSetting("daily", quests.daily)
    q:saveSetting("weekly", quests.weekly)
    q:saveSetting("monthly", quests.monthly)
    q:flush()
end

function Data:generateUniqueId()
    -- Use timestamp + random number to prevent ID collisions
    -- when multiple items are created within the same second
    return os.time() * 1000 + math.random(0, 999)
end

function Data:addQuest(quest_type, quest)
    local quests = self:loadAllQuests()
    quest.id = self:generateUniqueId()
    quest.created = os.date("%Y-%m-%d")
    quest.completed = false
    quest.completed_date = nil
    quest.streak = 0
    table.insert(quests[quest_type], quest)
    self:saveAllQuests(quests)
    return quest
end

function Data:updateQuest(quest_type, quest_id, updates)
    local quests = self:loadAllQuests()
    for _, quest in ipairs(quests[quest_type]) do
        if quest.id == quest_id then
            for k, v in pairs(updates) do
                quest[k] = v
            end
            self:saveAllQuests(quests)
            return quest
        end
    end
    return nil
end

function Data:deleteQuest(quest_type, quest_id)
    local quests = self:loadAllQuests()
    for i, quest in ipairs(quests[quest_type]) do
        if quest.id == quest_id then
            table.remove(quests[quest_type], i)
            self:saveAllQuests(quests)
            return true
        end
    end
    return false
end

function Data:completeQuest(quest_type, quest_id)
    local today = os.date("%Y-%m-%d")
    return self:updateQuest(quest_type, quest_id, {
        completed = true,
        completed_date = today,
    })
end

function Data:uncompleteQuest(quest_type, quest_id)
    return self:updateQuest(quest_type, quest_id, {
        completed = false,
        completed_date = nil,
    })
end

-- ============================================
-- Daily Log Operations (for heatmap & journal)
-- ============================================

function Data:loadDailyLogs()
    local l = self:getLogs()
    return l:readSetting("daily_logs") or {}
end

function Data:saveDailyLogs(logs)
    local l = self:getLogs()
    l:saveSetting("daily_logs", logs)
    l:flush()
end

function Data:logDay(date, entry)
    local logs = self:loadDailyLogs()
    logs[date] = entry
    self:saveDailyLogs(logs)
end

function Data:getDayLog(date)
    local logs = self:loadDailyLogs()
    return logs[date]
end

function Data:getLogsForRange(start_date, end_date)
    local logs = self:loadDailyLogs()
    local result = {}
    for date, entry in pairs(logs) do
        if date >= start_date and date <= end_date then
            result[date] = entry
        end
    end
    return result
end

--[[--
Add a mood/energy entry for a specific date and hour.
Allows multiple mood entries per day for intra-day tracking.
@param date string Date in YYYY-MM-DD format
@param hour number Hour of day (0-23)
@param energy string Energy level name
--]]
function Data:addMoodEntry(date, hour, energy)
    local logs = self:loadDailyLogs()
    local entry = logs[date] or {}

    -- Initialize energy_entries array if needed
    if not entry.energy_entries then
        entry.energy_entries = {}
    end

    -- Add new entry with hour and energy
    table.insert(entry.energy_entries, {
        hour = hour,
        energy = energy,
    })

    logs[date] = entry
    self:saveDailyLogs(logs)
end

--[[--
Get all mood entries for a specific date.
@param date string Date in YYYY-MM-DD format
@return table Array of {hour, energy} entries or empty table
--]]
function Data:getMoodEntries(date)
    local logs = self:loadDailyLogs()
    local entry = logs[date]
    if entry and entry.energy_entries then
        return entry.energy_entries
    end
    return {}
end

-- ============================================
-- Reminder Operations
-- ============================================

function Data:loadReminders()
    local r = self:getReminders()
    return r:readSetting("reminders") or {}
end

function Data:saveReminders(reminders)
    local r = self:getReminders()
    r:saveSetting("reminders", reminders)
    r:flush()
end

function Data:addReminder(reminder)
    local reminders = self:loadReminders()
    reminder.id = self:generateUniqueId()
    reminder.active = true
    reminder.last_triggered = nil
    table.insert(reminders, reminder)
    self:saveReminders(reminders)
    return reminder
end

function Data:updateReminder(reminder_id, updates)
    local reminders = self:loadReminders()
    for _, reminder in ipairs(reminders) do
        if reminder.id == reminder_id then
            for k, v in pairs(updates) do
                reminder[k] = v
            end
            self:saveReminders(reminders)
            return reminder
        end
    end
    return nil
end

function Data:deleteReminder(reminder_id)
    local reminders = self:loadReminders()
    for i, reminder in ipairs(reminders) do
        if reminder.id == reminder_id then
            table.remove(reminders, i)
            self:saveReminders(reminders)
            return true
        end
    end
    return false
end

-- ============================================
-- Utility Functions
-- ============================================

function Data:getCurrentDate()
    return os.date("%Y-%m-%d")
end

function Data:getCurrentTime()
    return os.date("%H:%M")
end

function Data:getDayOfWeek()
    return os.date("%a")  -- Mon, Tue, Wed, etc.
end

function Data:flushAll()
    if settings_cache then settings_cache:flush() end
    if quests_cache then quests_cache:flush() end
    if logs_cache then logs_cache:flush() end
    if reminders_cache then reminders_cache:flush() end
end

return Data
