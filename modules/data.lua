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
        quest_categories = s:readSetting("quest_categories") or {"Health", "Work", "Personal", "Learning"},
        streak_data = s:readSetting("streak_data") or {
            current = 0,
            longest = 0,
            last_completed_date = nil,
        },
        today_energy = s:readSetting("today_energy") or nil,
        today_date = s:readSetting("today_date") or nil,
        lock_screen_dashboard = s:readSetting("lock_screen_dashboard") or false,
    }
end

function Data:saveUserSettings(user_settings)
    local s = self:getSettings()
    s:saveSetting("energy_categories", user_settings.energy_categories)
    s:saveSetting("time_slots", user_settings.time_slots)
    s:saveSetting("quest_categories", user_settings.quest_categories)
    s:saveSetting("streak_data", user_settings.streak_data)
    s:saveSetting("today_energy", user_settings.today_energy)
    s:saveSetting("today_date", user_settings.today_date)
    s:saveSetting("lock_screen_dashboard", user_settings.lock_screen_dashboard)
    s:flush()
end

-- ============================================
-- Persistent Notes Operations
-- ============================================

--[[--
Load persistent notes (not date-specific).
@return string|nil Notes text or nil if none
--]]
function Data:loadPersistentNotes()
    local s = self:getSettings()
    return s:readSetting("persistent_notes")
end

--[[--
Save persistent notes (not date-specific).
@param text string Notes text
--]]
function Data:savePersistentNotes(text)
    local s = self:getSettings()
    s:saveSetting("persistent_notes", text)
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

--[[--
Generate a unique sequential ID.
Uses persistent counter to prevent collisions.
@return number Unique ID
--]]
function Data:generateUniqueId()
    local s = self:getSettings()
    local last_id = s:readSetting("last_generated_id") or (os.time() * 1000)
    last_id = last_id + 1
    s:saveSetting("last_generated_id", last_id)
    s:flush()
    return last_id
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

--[[--
Increment progress for a progressive quest.
Auto-completes when target is reached.
@param quest_type string "daily", "weekly", or "monthly"
@param quest_id number Quest ID
@return table|nil Updated quest or nil if not found
--]]
function Data:incrementQuestProgress(quest_type, quest_id)
    local quests = self:loadAllQuests()
    for _, quest in ipairs(quests[quest_type]) do
        if quest.id == quest_id and quest.is_progressive then
            local today = os.date("%Y-%m-%d")

            -- Reset progress if it's a new day
            if quest.progress_last_date ~= today then
                quest.progress_current = 0
                quest.progress_last_date = today
            end

            -- Increment progress
            quest.progress_current = (quest.progress_current or 0) + 1

            -- Auto-complete if target reached
            if quest.progress_current >= (quest.progress_target or 1) then
                quest.completed = true
                quest.completed_date = today
            end

            self:saveAllQuests(quests)
            return quest
        end
    end
    return nil
end

--[[--
Decrement progress for a progressive quest.
@param quest_type string "daily", "weekly", or "monthly"
@param quest_id number Quest ID
@return table|nil Updated quest or nil if not found
--]]
function Data:decrementQuestProgress(quest_type, quest_id)
    local quests = self:loadAllQuests()
    for _, quest in ipairs(quests[quest_type]) do
        if quest.id == quest_id and quest.is_progressive then
            local today = os.date("%Y-%m-%d")

            -- Reset progress if it's a new day
            if quest.progress_last_date ~= today then
                quest.progress_current = 0
                quest.progress_last_date = today
            end

            -- Decrement progress (min 0)
            quest.progress_current = math.max(0, (quest.progress_current or 0) - 1)

            -- Un-complete if below target
            if quest.progress_current < (quest.progress_target or 1) then
                quest.completed = false
            end

            self:saveAllQuests(quests)
            return quest
        end
    end
    return nil
end

--[[--
Set progress for a progressive quest to a specific value.
@param quest_type string "daily", "weekly", or "monthly"
@param quest_id number Quest ID
@param value number Progress value to set
@return table|nil Updated quest or nil if not found
--]]
function Data:setQuestProgress(quest_type, quest_id, value)
    local quests = self:loadAllQuests()
    for _, quest in ipairs(quests[quest_type]) do
        if quest.id == quest_id and quest.is_progressive then
            local today = os.date("%Y-%m-%d")
            local target = quest.progress_target or 1

            -- Clamp value between 0 and target (can't exceed target)
            quest.progress_current = math.max(0, math.min(value, target))
            quest.progress_last_date = today

            -- Auto-complete if target reached
            if quest.progress_current >= target then
                quest.completed = true
                quest.completed_date = today
            else
                quest.completed = false
            end

            self:saveAllQuests(quests)
            return quest
        end
    end
    return nil
end

--[[--
Reset daily progress for all progressive quests.
Called when a new day starts.
--]]
function Data:resetDailyProgress()
    local today = os.date("%Y-%m-%d")
    local quests = self:loadAllQuests()
    local changed = false

    for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for _, quest in ipairs(quests[quest_type]) do
            if quest.is_progressive and quest.progress_last_date ~= today then
                quest.progress_current = 0
                quest.progress_last_date = today
                quest.completed = false
                changed = true
            end
        end
    end

    if changed then
        self:saveAllQuests(quests)
    end
end

--[[--
Map an hour of day to a time slot name.
@param hour number Hour of day (0-23)
@param time_slots table Array of time slot names (default: Morning, Afternoon, Evening, Night)
@return string Time slot name
--]]
function Data:hourToTimeSlot(hour, time_slots)
    time_slots = time_slots or {"Morning", "Afternoon", "Evening", "Night"}
    local num_slots = #time_slots

    if num_slots == 4 then
        -- Standard 4-slot breakdown
        if hour >= 5 and hour < 12 then
            return time_slots[1]  -- Morning: 5am-12pm
        elseif hour >= 12 and hour < 17 then
            return time_slots[2]  -- Afternoon: 12pm-5pm
        elseif hour >= 17 and hour < 21 then
            return time_slots[3]  -- Evening: 5pm-9pm
        else
            return time_slots[4]  -- Night: 9pm-5am
        end
    elseif num_slots == 3 then
        -- 3-slot breakdown
        if hour >= 5 and hour < 12 then
            return time_slots[1]  -- Morning
        elseif hour >= 12 and hour < 18 then
            return time_slots[2]  -- Afternoon
        else
            return time_slots[3]  -- Evening/Night
        end
    else
        -- Generic breakdown: divide 24 hours by number of slots
        local hours_per_slot = 24 / num_slots
        local slot_index = math.floor(hour / hours_per_slot) + 1
        return time_slots[math.min(slot_index, num_slots)]
    end
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
@param time_slots table Optional array of time slot names for mapping
--]]
function Data:addMoodEntry(date, hour, energy, time_slots)
    local logs = self:loadDailyLogs()
    local entry = logs[date] or {}

    -- Initialize energy_entries array if needed
    if not entry.energy_entries then
        entry.energy_entries = {}
    end

    -- Map hour to time slot
    local time_slot = self:hourToTimeSlot(hour, time_slots)

    -- Add new entry with hour, time_slot, and energy
    table.insert(entry.energy_entries, {
        hour = hour,
        time_slot = time_slot,
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

-- ============================================
-- Backup & Restore Operations
-- ============================================

local BACKUP_VERSION = 1  -- Increment when backup format changes

--[[--
Get the backup directory path.
@return string Path to backup directory
--]]
function Data:getBackupDir()
    return DATA_DIR .. "/lifetracker_backups"
end

--[[--
Ensure the backup directory exists.
@return boolean Success status
--]]
function Data:ensureBackupDir()
    local lfs = require("libs/libkoreader-lfs")
    local backup_dir = self:getBackupDir()
    if lfs.attributes(backup_dir, "mode") ~= "directory" then
        local ok = lfs.mkdir(backup_dir)
        return ok ~= nil
    end
    return true
end

--[[--
Sanitize a filename to prevent path traversal attacks.
Removes directory separators and dangerous characters.
@param filename string The filename to sanitize
@return string Sanitized filename
--]]
function Data:sanitizeFilename(filename)
    if not filename or filename == "" then
        return nil
    end
    -- Remove path separators and parent directory references
    local sanitized = filename:gsub("[/\\]", "_")
    sanitized = sanitized:gsub("%.%.", "_")
    -- Ensure it ends with .json
    if not sanitized:match("%.json$") then
        sanitized = sanitized .. ".json"
    end
    -- Ensure filename is not empty after sanitization
    if sanitized == ".json" or sanitized == "" then
        return nil
    end
    return sanitized
end

--[[--
Validate that a filepath is within the backup directory.
Prevents path traversal attacks on import.
@param filepath string The filepath to validate
@return boolean Whether the path is safe
--]]
function Data:isValidBackupPath(filepath)
    if not filepath then
        return false
    end
    local backup_dir = self:getBackupDir()
    -- Normalize: ensure backup_dir ends without slash for consistent comparison
    backup_dir = backup_dir:gsub("/$", "")
    -- Check that filepath starts with backup_dir
    if not filepath:sub(1, #backup_dir) == backup_dir then
        return false
    end
    -- Check for path traversal attempts in the remaining path
    local remaining = filepath:sub(#backup_dir + 1)
    if remaining:match("%.%.") then
        return false
    end
    return true
end

--[[--
Create a backup of all plugin data.
@return table Backup data structure with all settings, quests, logs, and reminders
--]]
function Data:createBackup()
    -- Flush all caches first to ensure consistent snapshot
    self:flushAll()

    return {
        version = BACKUP_VERSION,
        created_at = os.date("%Y-%m-%d %H:%M:%S"),
        timestamp = os.time(),
        data = {
            settings = self:loadUserSettings(),
            persistent_notes = self:loadPersistentNotes(),
            quests = self:loadAllQuests(),
            logs = self:loadDailyLogs(),
            reminders = self:loadReminders(),
        }
    }
end

--[[--
Validate backup data structure before restore.
@param backup table Backup data to validate
@return boolean, string Success status and error message if any
--]]
function Data:validateBackupStructure(backup)
    if not backup then
        return false, "Invalid backup data"
    end

    if type(backup.version) ~= "number" then
        return false, "Backup version not found or invalid"
    end

    if backup.version > BACKUP_VERSION then
        return false, "Backup is from a newer version"
    end

    local data = backup.data
    if type(data) ~= "table" then
        return false, "No data found in backup"
    end

    -- Validate settings structure
    if data.settings then
        if type(data.settings) ~= "table" then
            return false, "Invalid settings format"
        end
        if data.settings.energy_categories and type(data.settings.energy_categories) ~= "table" then
            return false, "Invalid energy_categories format"
        end
        if data.settings.time_slots and type(data.settings.time_slots) ~= "table" then
            return false, "Invalid time_slots format"
        end
    end

    -- Validate quests structure
    if data.quests then
        if type(data.quests) ~= "table" then
            return false, "Invalid quests format"
        end
        for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
            if data.quests[quest_type] and type(data.quests[quest_type]) ~= "table" then
                return false, "Invalid " .. quest_type .. " quests format"
            end
        end
    end

    -- Validate logs structure
    if data.logs and type(data.logs) ~= "table" then
        return false, "Invalid logs format"
    end

    -- Validate reminders structure
    if data.reminders and type(data.reminders) ~= "table" then
        return false, "Invalid reminders format"
    end

    return true, nil
end

--[[--
Restore plugin data from a backup.
@param backup table Backup data structure
@return boolean, string Success status and message
--]]
function Data:restoreFromBackup(backup)
    -- Validate backup structure first
    local valid, err = self:validateBackupStructure(backup)
    if not valid then
        return false, err
    end

    -- Clear caches BEFORE restore to prevent stale data issues
    settings_cache = nil
    quests_cache = nil
    logs_cache = nil
    reminders_cache = nil

    local data = backup.data

    -- Restore each data section
    if data.settings then
        self:saveUserSettings(data.settings)
    end

    if data.persistent_notes then
        self:savePersistentNotes(data.persistent_notes)
    end

    if data.quests then
        self:saveAllQuests(data.quests)
    end

    if data.logs then
        self:saveDailyLogs(data.logs)
    end

    if data.reminders then
        self:saveReminders(data.reminders)
    end

    return true, "Data restored successfully"
end

--[[--
Export backup to a JSON file with atomic write.
@param filename string Optional filename (without path), defaults to timestamped name
@return boolean, string Success status and filepath or error message
--]]
function Data:exportBackupToFile(filename)
    local rapidjson = require("rapidjson")
    local lfs = require("libs/libkoreader-lfs")

    if not self:ensureBackupDir() then
        return false, "Failed to create backup directory"
    end

    -- Generate filename if not provided
    if not filename or filename == "" then
        filename = "lifetracker_backup_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    end

    -- Sanitize filename to prevent path traversal
    filename = self:sanitizeFilename(filename)
    if not filename then
        return false, "Invalid filename"
    end

    local filepath = self:getBackupDir() .. "/" .. filename
    local temp_filepath = filepath .. ".tmp"
    local backup = self:createBackup()

    -- Write to temp file first (atomic write pattern)
    local ok, err = pcall(function()
        return rapidjson.dump(backup, temp_filepath, { pretty = true, sort_keys = true })
    end)

    if not ok then
        pcall(os.remove, temp_filepath)
        return false, "Failed to write backup: " .. tostring(err)
    end

    -- Verify temp file was created
    if lfs.attributes(temp_filepath, "mode") ~= "file" then
        return false, "Failed to create backup file"
    end

    -- Remove old file if exists, then rename temp to final
    pcall(os.remove, filepath)
    local rename_ok, rename_err = os.rename(temp_filepath, filepath)

    if not rename_ok then
        pcall(os.remove, temp_filepath)
        return false, "Failed to finalize backup: " .. tostring(rename_err)
    end

    return true, filepath
end

--[[--
Import backup from a JSON file.
@param filepath string Full path to the backup file
@return boolean, string Success status and message
--]]
function Data:importBackupFromFile(filepath)
    local rapidjson = require("rapidjson")
    local lfs = require("libs/libkoreader-lfs")

    -- Validate path is within backup directory (prevent path traversal)
    if not self:isValidBackupPath(filepath) then
        return false, "Invalid backup file path"
    end

    -- Check if file exists
    if lfs.attributes(filepath, "mode") ~= "file" then
        return false, "Backup file not found"
    end

    -- Load and parse the backup file with error handling
    local ok, backup = pcall(rapidjson.load, filepath)

    if not ok then
        return false, "Failed to parse backup file: " .. tostring(backup)
    end

    if not backup then
        return false, "Backup file is empty or invalid"
    end

    return self:restoreFromBackup(backup)
end

--[[--
List available backup files.
@return table Array of {filename, filepath, created_at, size} entries
--]]
function Data:listBackups()
    local lfs = require("libs/libkoreader-lfs")
    local rapidjson = require("rapidjson")

    self:ensureBackupDir()
    local backup_dir = self:getBackupDir()
    local backups = {}

    for filename in lfs.dir(backup_dir) do
        -- Only list lifetracker backup files (not arbitrary json files)
        if filename:match("^lifetracker_.*%.json$") then
            local filepath = backup_dir .. "/" .. filename
            local attr = lfs.attributes(filepath)

            if attr then
                -- Try to read backup metadata with pcall to handle corrupted files
                local created_at = nil
                local ok, backup_data = pcall(rapidjson.load, filepath)
                if ok and backup_data and backup_data.created_at then
                    created_at = backup_data.created_at
                end

                table.insert(backups, {
                    filename = filename,
                    filepath = filepath,
                    created_at = created_at or os.date("%Y-%m-%d %H:%M:%S", attr.modification),
                    size = attr.size,
                })
            end
        end
    end

    -- Sort by creation time (newest first)
    table.sort(backups, function(a, b)
        return a.created_at > b.created_at
    end)

    return backups
end

--[[--
Delete a backup file.
@param filepath string Full path to the backup file
@return boolean, string Success status and error message
--]]
function Data:deleteBackup(filepath)
    -- Validate path is within backup directory
    if not self:isValidBackupPath(filepath) then
        return false, "Invalid backup file path"
    end

    local ok, err = os.remove(filepath)
    return ok ~= nil, err
end

--[[--
Perform auto-backup if one hasn't been created today.
Creates daily auto-backups with a rolling retention policy.
@param max_auto_backups number Maximum auto-backups to keep (default: 7)
@return boolean, string Whether backup was created and message
--]]
function Data:autoBackup(max_auto_backups)
    max_auto_backups = max_auto_backups or 7
    local today = os.date("%Y%m%d")
    local auto_filename = "lifetracker_auto_" .. today .. ".json"
    local auto_filepath = self:getBackupDir() .. "/" .. auto_filename

    -- Check if today's auto-backup already exists
    local lfs = require("libs/libkoreader-lfs")
    self:ensureBackupDir()

    if lfs.attributes(auto_filepath, "mode") == "file" then
        return false, "Auto-backup already exists for today"
    end

    -- Create today's auto-backup
    local ok, result = self:exportBackupToFile(auto_filename)

    if ok then
        -- Clean up old auto-backups beyond retention limit
        self:cleanupAutoBackups(max_auto_backups)
        return true, "Auto-backup created: " .. auto_filename
    else
        return false, result
    end
end

--[[--
Remove old auto-backups beyond the retention limit.
@param max_keep number Maximum number of auto-backups to keep
--]]
function Data:cleanupAutoBackups(max_keep)
    local lfs = require("libs/libkoreader-lfs")
    local backup_dir = self:getBackupDir()
    local auto_backups = {}

    -- Find all auto-backups
    for filename in lfs.dir(backup_dir) do
        if filename:match("^lifetracker_auto_%d+%.json$") then
            local filepath = backup_dir .. "/" .. filename
            local attr = lfs.attributes(filepath)
            table.insert(auto_backups, {
                filename = filename,
                filepath = filepath,
                mtime = attr.modification,
            })
        end
    end

    -- Sort by modification time (oldest first)
    table.sort(auto_backups, function(a, b)
        return a.mtime < b.mtime
    end)

    -- Remove oldest backups beyond limit
    while #auto_backups > max_keep do
        local oldest = table.remove(auto_backups, 1)
        os.remove(oldest.filepath)
    end
end

return Data
