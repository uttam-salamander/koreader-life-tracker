--[[--
Utilities module for Life Tracker.
Pure utility functions for formatting, validation, and common operations.
Keeps Data module focused on persistence.

@module lifetracker.utils
--]]

local _ = require("gettext")

local Utils = {}

-- ============================================================================
-- Time Formatting
-- ============================================================================

--[[--
Format seconds into a human-readable time string.
@param seconds number Time in seconds
@return string Formatted time (e.g., "2h 30m" or "45m")
--]]
function Utils.formatReadingTime(seconds)
    if not seconds or seconds == 0 then
        return "0m"
    end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    else
        return string.format("%dm", mins)
    end
end

--[[--
Format a date string for display.
@param date_string string Date in YYYY-MM-DD format
@param format string Optional format: "short" (Jan 15), "long" (January 15, 2025), "weekday" (Mon)
@return string Formatted date
--]]
function Utils.formatDate(date_string, format)
    if not date_string then return "" end

    local year, month, day = date_string:match("(%d+)-(%d+)-(%d+)")
    if not year then return date_string end

    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
    })

    format = format or "short"

    if format == "weekday" then
        return os.date("%a", time)  -- Mon, Tue, etc.
    elseif format == "long" then
        return os.date("%B %d, %Y", time)  -- January 15, 2025
    else  -- short
        return os.date("%b %d", time)  -- Jan 15
    end
end

-- ============================================================================
-- Day Names
-- ============================================================================

--[[--
Get day abbreviations for display.
@return table Array of day abbreviations {"Mon", "Tue", ...}
--]]
function Utils.getDayAbbreviations()
    return {
        _("Mon"),
        _("Tue"),
        _("Wed"),
        _("Thu"),
        _("Fri"),
        _("Sat"),
        _("Sun"),
    }
end

--[[--
Get full day names for display.
@return table Array of full day names {"Monday", "Tuesday", ...}
--]]
function Utils.getDayNames()
    return {
        _("Monday"),
        _("Tuesday"),
        _("Wednesday"),
        _("Thursday"),
        _("Friday"),
        _("Saturday"),
        _("Sunday"),
    }
end

--[[--
Get day abbreviation for a specific day index (1 = Monday, 7 = Sunday).
@param day_index number Day index (1-7)
@return string Day abbreviation
--]]
function Utils.getDayAbbr(day_index)
    local abbrs = Utils.getDayAbbreviations()
    return abbrs[day_index] or ""
end

-- ============================================================================
-- Text Validation
-- ============================================================================

--[[--
Sanitize text input by trimming whitespace and limiting length.
@param text string Input text
@param max_length number Optional maximum length (default 500)
@return string Sanitized text
--]]
function Utils.sanitizeTextInput(text, max_length)
    if not text then return "" end
    max_length = max_length or 500

    -- Trim leading/trailing whitespace
    text = text:match("^%s*(.-)%s*$") or ""

    -- Limit length
    if #text > max_length then
        text = text:sub(1, max_length)
    end

    return text
end

--[[--
Check if a string is empty or only whitespace.
@param text string Input text
@return bool True if empty or whitespace only
--]]
function Utils.isEmpty(text)
    if not text then return true end
    return text:match("^%s*$") ~= nil
end

-- ============================================================================
-- Number Utilities
-- ============================================================================

--[[--
Clamp a number between min and max values.
@param value number The value to clamp
@param min_val number Minimum value
@param max_val number Maximum value
@return number Clamped value
--]]
function Utils.clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value))
end

--[[--
Round a number to the nearest integer.
@param value number The value to round
@return number Rounded value
--]]
function Utils.round(value)
    return math.floor(value + 0.5)
end

-- ============================================================================
-- Date Utilities
-- ============================================================================

--[[--
Get the current date in YYYY-MM-DD format.
@return string Current date
--]]
function Utils.getCurrentDate()
    return os.date("%Y-%m-%d")
end

--[[--
Get the current time in HH:MM format.
@return string Current time
--]]
function Utils.getCurrentTime()
    return os.date("%H:%M")
end

--[[--
Check if a date string is today.
@param date_string string Date in YYYY-MM-DD format
@return bool True if date is today
--]]
function Utils.isToday(date_string)
    return date_string == Utils.getCurrentDate()
end

--[[--
Add days to a date string.
@param date_string string Date in YYYY-MM-DD format
@param days number Number of days to add (can be negative)
@return string New date in YYYY-MM-DD format
--]]
function Utils.addDays(date_string, days)
    local year, month, day = date_string:match("(%d+)-(%d+)-(%d+)")
    if not year then return date_string end

    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
    })

    local new_time = time + (days * 86400)
    return os.date("%Y-%m-%d", new_time)
end

return Utils
