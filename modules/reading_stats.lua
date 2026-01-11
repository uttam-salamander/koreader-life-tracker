--[[--
Reading Stats module for Life Tracker.
Integrates with KOReader's built-in statistics plugin.
@module lifetracker.reading_stats
--]]

local Data = require("modules/data")
local Utils = require("modules/utils")

local ReadingStats = {}

-- Cache for database connection
local stats_db = nil

-- Maximum allowed values for SQL query parameters (prevent abuse)
local MAX_LIMIT = 1000
local MAX_TIMESTAMP = 4102444800  -- Year 2100

--[[--
Validate and sanitize a numeric parameter for SQL queries.
@param value any Value to validate
@param default number Default value if invalid
@param max_val number Maximum allowed value
@return number Sanitized integer
--]]
local function sanitizeSqlInt(value, default, max_val)
    local num = tonumber(value)
    if not num then return default end
    -- Ensure integer, positive, within bounds
    num = math.floor(num)
    if num < 0 then return default end
    if max_val and num > max_val then return max_val end
    return num
end

--[[--
Get the statistics database connection.
@return SQ3 database connection or nil
--]]
function ReadingStats:getStatsDB()
    if stats_db then
        return stats_db
    end

    -- Try to open the statistics database
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok then
        return nil
    end

    local ok2, DataStorage = pcall(require, "datastorage")
    if not ok2 then
        return nil
    end

    local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

    local open_ok, db = pcall(function()
        local conn = SQ3.open(db_path)
        -- Set busy timeout to prevent blocking on locked database
        if conn and conn.exec then
            pcall(function() conn:exec("PRAGMA busy_timeout = 5000") end)
        end
        return conn
    end)

    if open_ok and db then
        stats_db = db
        return stats_db
    end

    return nil
end

--[[--
Close the statistics database connection.
Call this when the plugin is disabled or KOReader exits.
--]]
function ReadingStats:close()
    if stats_db then
        pcall(function()
            if stats_db.close then
                stats_db:close()
            end
        end)
        stats_db = nil
    end
end

--[[--
Get total reading statistics from KOReader's database.
@return table with total_books, total_pages, total_time
--]]
function ReadingStats:getTotalReadingStats()
    local stats = {
        total_books = 0,
        total_pages = 0,
        total_time = 0,
    }

    local db = self:getStatsDB()
    if not db then
        return stats
    end

    local ok, result = pcall(function()
        local sql = [[
            SELECT
                COUNT(*) as total_books,
                COALESCE(SUM(total_read_pages), 0) as total_pages,
                COALESCE(SUM(total_read_time), 0) as total_time
            FROM book
            WHERE total_read_time > 0
        ]]
        return db:exec(sql)
    end)

    if ok and result then
        -- lua-ljsqlite3 returns column-based arrays
        stats.total_books = tonumber(result.total_books and result.total_books[1]) or 0
        stats.total_pages = tonumber(result.total_pages and result.total_pages[1]) or 0
        stats.total_time = tonumber(result.total_time and result.total_time[1]) or 0
    end

    return stats
end

--[[--
Get recently read books from KOReader's statistics database.
@param limit Maximum number of books to return
@return table Array of book info
--]]
function ReadingStats:getRecentBooksFromDB(limit)
    -- Sanitize limit parameter to prevent SQL injection
    limit = sanitizeSqlInt(limit, 12, MAX_LIMIT)
    local books = {}

    local db = self:getStatsDB()
    if not db then
        return books
    end

    local ok, result = pcall(function()
        -- Using sanitized integer is safe for string.format with %d
        local sql = string.format([[
            SELECT
                id,
                title,
                authors,
                pages,
                total_read_pages,
                total_read_time,
                last_open,
                md5
            FROM book
            WHERE last_open > 0
            ORDER BY last_open DESC
            LIMIT %d
        ]], limit)
        return db:exec(sql)
    end)

    if ok and result then
        -- lua-ljsqlite3 returns column-based arrays, need to iterate by index
        local num_rows = result.title and #result.title or 0
        for i = 1, num_rows do
            local title = result.title and result.title[i]
            -- Skip books with empty or nil titles
            if title and title ~= "" then
                local total_pages = tonumber(result.pages and result.pages[i]) or 0
                local read_pages = tonumber(result.total_read_pages and result.total_read_pages[i]) or 0
                local progress = 0
                if total_pages > 0 then
                    progress = read_pages / total_pages
                end

                table.insert(books, {
                    id = result.id and result.id[i],
                    title = title,
                    authors = result.authors and result.authors[i],
                    pages = total_pages,
                    pages_read = read_pages,
                    total_time = tonumber(result.total_read_time and result.total_read_time[i]) or 0,
                    last_open = tonumber(result.last_open and result.last_open[i]) or 0,
                    progress = progress,
                    md5 = result.md5 and result.md5[i],
                })
            end
        end
    end

    return books
end

--[[--
Get reading stats for today from the database.
@return table with pages and time for today
--]]
function ReadingStats:getTodayStatsFromDB()
    local stats = {
        pages = 0,
        time = 0,
    }

    local db = self:getStatsDB()
    if not db then
        return stats
    end

    -- Get start of today using DST-safe method
    local today_start = Data:getTodayStartTime()
    -- Sanitize timestamp
    today_start = sanitizeSqlInt(today_start, 0, MAX_TIMESTAMP)

    local ok, result = pcall(function()
        local sql = string.format([[
            SELECT
                COUNT(DISTINCT page) as pages,
                COALESCE(SUM(duration), 0) as time
            FROM page_stat_data
            WHERE start_time >= %d
        ]], today_start)
        return db:exec(sql)
    end)

    if ok and result then
        -- lua-ljsqlite3 returns column-based arrays
        stats.pages = tonumber(result.pages and result.pages[1]) or 0
        stats.time = tonumber(result.time and result.time[1]) or 0
    end

    return stats
end

--[[--
Get reading stats for this week from the database.
@return table with pages and time for this week
--]]
function ReadingStats:getWeekStatsFromDB()
    local stats = {
        pages = 0,
        time = 0,
    }

    local db = self:getStatsDB()
    if not db then
        return stats
    end

    -- Get start of 7 days ago using DST-safe method
    local week_start = Data:getDaysAgoStartTime(7)
    -- Sanitize timestamp
    week_start = sanitizeSqlInt(week_start, 0, MAX_TIMESTAMP)

    local ok, result = pcall(function()
        local sql = string.format([[
            SELECT
                COUNT(DISTINCT page) as pages,
                COALESCE(SUM(duration), 0) as time
            FROM page_stat_data
            WHERE start_time >= %d
        ]], week_start)
        return db:exec(sql)
    end)

    if ok and result then
        -- lua-ljsqlite3 returns column-based arrays
        stats.pages = tonumber(result.pages and result.pages[1]) or 0
        stats.time = tonumber(result.time and result.time[1]) or 0
    end

    return stats
end

--[[--
Get today's reading statistics from KOReader.
@param ui The KOReader UI instance
@return table with pages, time, current_book, sessions
--]]
function ReadingStats:getTodayStats(ui)
    local stats = {
        pages_read = 0,
        time_spent = 0,
        current_book = nil,
        sessions = 0,
    }

    -- Try to access KOReader's statistics plugin
    if not ui then
        return stats
    end

    -- Method 1: Direct statistics plugin access
    if ui.statistics then
        local reader_stats = ui.statistics

        -- Get today's pages
        if reader_stats.getTodayPages then
            stats.pages_read = reader_stats:getTodayPages() or 0
        end

        -- Get today's reading time
        if reader_stats.getTodayReadingTime then
            stats.time_spent = reader_stats:getTodayReadingTime() or 0
        end

        -- Get session count
        if reader_stats.getTodaySessions then
            stats.sessions = reader_stats:getTodaySessions() or 0
        end
    end

    -- Get current book info
    if ui.document then
        local props = ui.document:getProps()
        if props then
            stats.current_book = props.title
        end
    end

    return stats
end

--[[--
Get reading statistics for a specific date.
@param date_str Date in YYYY-MM-DD format
@return table with reading stats for that day
--]]
function ReadingStats:getStatsForDate(date_str)
    local logs = Data:loadDailyLogs()
    local day_log = logs[date_str]

    if day_log and day_log.reading then
        return day_log.reading
    end

    return {
        pages_read = 0,
        time_spent = 0,
        current_book = nil,
        sessions = 0,
    }
end

--[[--
Get weekly reading statistics.
@return table with weekly totals and daily breakdown
--]]
function ReadingStats:getWeeklyStats()
    local logs = Data:loadDailyLogs()
    local today = os.time()

    local weekly = {
        total_pages = 0,
        total_time = 0,
        days_read = 0,
        daily = {},
    }

    local day_names = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

    for i = 0, 6 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_info = os.date("*t", day_time)
        local day_name = day_names[day_info.wday]

        local day_log = logs[date_str]
        local pages = 0
        local time = 0

        if day_log and day_log.reading then
            pages = day_log.reading.pages_read or 0
            time = day_log.reading.time_spent or 0
        end

        weekly.total_pages = weekly.total_pages + pages
        weekly.total_time = weekly.total_time + time
        if pages > 0 then
            weekly.days_read = weekly.days_read + 1
        end

        table.insert(weekly.daily, 1, {
            date = date_str,
            day = day_name,
            pages = pages,
            time = time,
        })
    end

    return weekly
end

--[[--
Get monthly reading statistics.
@return table with monthly totals
--]]
function ReadingStats:getMonthlyStats()
    local logs = Data:loadDailyLogs()
    local today = os.date("*t")

    local monthly = {
        total_pages = 0,
        total_time = 0,
        days_read = 0,
        books = {},
    }

    for date_str, day_log in pairs(logs) do
        local year, month = date_str:match("(%d+)-(%d+)")
        if tonumber(year) == today.year and tonumber(month) == today.month then
            if day_log.reading then
                local pages = day_log.reading.pages_read or 0
                local time = day_log.reading.time_spent or 0

                monthly.total_pages = monthly.total_pages + pages
                monthly.total_time = monthly.total_time + time
                if pages > 0 then
                    monthly.days_read = monthly.days_read + 1
                end

                -- Track books
                if day_log.reading.current_book then
                    monthly.books[day_log.reading.current_book] = true
                end
            end
        end
    end

    -- Convert books set to count
    local book_count = 0
    for _ in pairs(monthly.books) do
        book_count = book_count + 1
    end
    monthly.book_count = book_count

    return monthly
end

--[[--
Log current reading stats to daily log.
Called periodically or on document close.
@param ui The KOReader UI instance
--]]
function ReadingStats:logCurrentStats(ui)
    local stats = self:getTodayStats(ui)
    local today = os.date("%Y-%m-%d")
    local logs = Data:loadDailyLogs()

    if not logs[today] then
        logs[today] = {}
    end

    logs[today].reading = {
        pages_read = stats.pages_read,
        time_spent = stats.time_spent,
        current_book = stats.current_book,
        sessions = stats.sessions,
        last_updated = os.time(),
    }

    Data:saveDailyLogs(logs)
end

--[[--
Format reading time for display.
Delegates to Utils.formatReadingTime for consistency.
@param seconds Time in seconds
@return string Formatted time (e.g., "1h 23m")
--]]
function ReadingStats:formatTime(seconds)
    return Utils.formatReadingTime(seconds)
end

--[[--
Calculate average pages per day.
@param days Number of days to average over (default 7)
@return number Average pages per day
--]]
function ReadingStats:getAveragePagesPerDay(days)
    days = days or 7
    local logs = Data:loadDailyLogs()
    local today = os.time()

    local total_pages = 0
    local days_with_data = 0

    for i = 0, days - 1 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_log = logs[date_str]

        if day_log and day_log.reading and day_log.reading.pages_read then
            total_pages = total_pages + day_log.reading.pages_read
            if day_log.reading.pages_read > 0 then
                days_with_data = days_with_data + 1
            end
        end
    end

    if days_with_data > 0 then
        return math.floor(total_pages / days_with_data)
    end

    return 0
end

return ReadingStats
