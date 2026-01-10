--[[--
Heatmap module for Life Tracker.
GitHub-style contribution heatmap for quest completion visualization.
@module lifetracker.heatmap
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Data = require("modules/data")
local UIConfig = require("modules/ui_config")

local Heatmap = {}

--[[--
Get the color for a given heat level.
Uses UIConfig colors which support color screens and night mode.
@param level Heat level 0-4
@return Blitbuffer color
--]]
function Heatmap:getHeatColor(level)
    local colors = UIConfig:getColors()
    local heat_colors = {
        colors.heat_0,
        colors.heat_1,
        colors.heat_2,
        colors.heat_3,
        colors.heat_4,
    }
    return heat_colors[math.min((level or 0) + 1, 5)]
end

-- Heatmap characters for e-ink display (grayscale compatible)
-- Using block characters with different fill levels
local HEAT_CHARS = {
    "░",  -- 0 completions (light)
    "▒",  -- 1-2 completions (medium)
    "▓",  -- 3-4 completions (dark)
    "█",  -- 5+ completions (solid)
}

-- Alternative ASCII for devices without Unicode support
local HEAT_ASCII = {
    ".",  -- 0 completions
    "o",  -- 1-2 completions
    "O",  -- 3-4 completions
    "#",  -- 5+ completions
}

--[[--
Get the heat level (0-3) based on completion count.
@param count Number of quests completed
@return number Heat level 0-3
--]]
function Heatmap:getHeatLevel(count)
    if not count or count == 0 then
        return 0
    elseif count <= 2 then
        return 1
    elseif count <= 4 then
        return 2
    else
        return 3
    end
end

--[[--
Get the character for a given heat level.
@param level Heat level 0-3
@param use_ascii Use ASCII characters instead of Unicode
@return string Character to display
--]]
function Heatmap:getHeatChar(level, use_ascii)
    local chars = use_ascii and HEAT_ASCII or HEAT_CHARS
    return chars[(level or 0) + 1]
end

--[[--
Build heatmap data for the last N weeks.
@param weeks Number of weeks to display (default 12)
@return table 2D array [week][day] of completion counts
--]]
function Heatmap:buildHeatmapData(weeks)
    weeks = weeks or 12
    local logs = Data:loadDailyLogs()
    local today = os.time()

    -- Build 2D array: rows = weeks, cols = days (Sun-Sat)
    local heatmap = {}
    local total_days = weeks * 7

    -- Start from (weeks * 7 - 1) days ago
    local start_offset = total_days - 1

    -- Determine starting day of week for alignment
    local today_info = os.date("*t", today)
    local days_into_week = today_info.wday - 1  -- 0 = Sunday

    -- Adjust start to align weeks
    start_offset = start_offset + (6 - days_into_week)

    for week = 1, weeks do
        heatmap[week] = {}
        for day = 1, 7 do
            local day_offset = start_offset - ((week - 1) * 7 + (day - 1))
            local day_time = today - (day_offset * 86400)
            local date_str = os.date("%Y-%m-%d", day_time)

            local day_log = logs[date_str]
            local count = 0
            if day_log and day_log.quests_completed then
                count = day_log.quests_completed
            end

            heatmap[week][day] = count
        end
    end

    return heatmap
end

--[[--
Build a text-based heatmap widget for KOReader.
@param weeks Number of weeks to display
@param use_ascii Use ASCII characters
@return VerticalGroup widget
--]]
function Heatmap:buildWidget(weeks, use_ascii)
    weeks = weeks or 12
    local heatmap_data = self:buildHeatmapData(weeks)

    local content = VerticalGroup:new{ align = "left" }

    -- Header
    table.insert(content, TextWidget:new{
        text = _("Quest Activity (Last 12 Weeks)"),
        face = Font:getFace("tfont", 14),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    -- Build heatmap rows (7 rows for days of week)
    local day_labels = {"S", "M", "T", "W", "T", "F", "S"}

    for day = 1, 7 do
        local row = day_labels[day] .. " "
        for week = 1, weeks do
            local count = heatmap_data[week][day]
            local level = self:getHeatLevel(count)
            row = row .. self:getHeatChar(level, use_ascii)
        end

        table.insert(content, TextWidget:new{
            text = row,
            face = Font:getFace("cfont", 12),
        })
    end

    -- Legend
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })
    local legend = "  "
    for i = 0, 3 do
        legend = legend .. self:getHeatChar(i, use_ascii)
    end
    legend = legend .. " Less → More"

    local colors = UIConfig:getColors()
    table.insert(content, TextWidget:new{
        text = legend,
        face = UIConfig:getFont("cfont", 10),
        fgcolor = colors.muted,
    })

    return content
end

--[[--
Build a compact single-line heatmap summary.
@param days Number of days to show
@return string Single line heatmap
--]]
function Heatmap:buildCompactLine(days)
    days = days or 30
    local logs = Data:loadDailyLogs()
    local today = os.time()

    local line = ""
    for i = days - 1, 0, -1 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)

        local day_log = logs[date_str]
        local count = 0
        if day_log and day_log.quests_completed then
            count = day_log.quests_completed
        end

        local level = self:getHeatLevel(count)
        line = line .. self:getHeatChar(level)
    end

    return line
end

--[[--
Get statistics from heatmap data.
@param weeks Number of weeks
@return table Stats including total, streak, average
--]]
function Heatmap:getStats(weeks)
    weeks = weeks or 12
    local heatmap_data = self:buildHeatmapData(weeks)

    local total_completions = 0
    local days_with_activity = 0
    local current_streak = 0
    local longest_streak = 0
    local temp_streak = 0

    -- Process in reverse order (oldest to newest) for streak calculation
    for week = weeks, 1, -1 do
        for day = 7, 1, -1 do
            local count = heatmap_data[week][day]
            total_completions = total_completions + count

            if count > 0 then
                days_with_activity = days_with_activity + 1
                temp_streak = temp_streak + 1
                if temp_streak > longest_streak then
                    longest_streak = temp_streak
                end
            else
                temp_streak = 0
            end
        end
    end

    -- Calculate current streak (from today going back)
    local logs = Data:loadDailyLogs()
    local today = os.time()
    current_streak = 0

    for i = 0, (weeks * 7 - 1) do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)

        local day_log = logs[date_str]
        if day_log and day_log.quests_completed and day_log.quests_completed > 0 then
            current_streak = current_streak + 1
        else
            break
        end
    end

    local total_days = weeks * 7
    local average = days_with_activity > 0 and math.floor(total_completions / days_with_activity) or 0

    return {
        total_completions = total_completions,
        days_with_activity = days_with_activity,
        total_days = total_days,
        current_streak = current_streak,
        longest_streak = longest_streak,
        average_per_active_day = average,
    }
end

return Heatmap
