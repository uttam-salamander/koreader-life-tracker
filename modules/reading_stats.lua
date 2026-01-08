--[[--
Reading Stats module for Life Tracker.
Integrates with KOReader's built-in statistics plugin.
@module lifetracker.reading_stats
--]]

local Data = require("modules/data")

local ReadingStats = {}

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
@param seconds Time in seconds
@return string Formatted time (e.g., "1h 23m")
--]]
function ReadingStats:formatTime(seconds)
    if not seconds or seconds == 0 then
        return "0m"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
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
