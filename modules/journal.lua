--[[--
Journal module for Life Tracker.
Mood tracking, weekly review, and insights with reading correlation.
@module lifetracker.journal
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local _ = require("gettext")

local Data = require("modules/data")

local Journal = {}

--[[--
Show the journal view.
--]]
function Journal:show(ui)
    self.ui = ui
    self:showJournalView()
end

--[[--
Build and display the journal view.
--]]
function Journal:showJournalView()
    local screen_width = Screen:getWidth()
    local content = VerticalGroup:new{ align = "left" }

    -- Header
    table.insert(content, TextWidget:new{
        text = "JOURNAL & INSIGHTS",
        face = Font:getFace("tfont", 20),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })

    -- Weekly Review Section
    table.insert(content, TextWidget:new{
        text = "Weekly Review",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - 40, h = 1 },
        background = 0x888888,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local weekly_stats = self:getWeeklyStats()
    table.insert(content, TextWidget:new{
        text = string.format("Completion Rate: %d%%", weekly_stats.completion_rate),
        face = Font:getFace("cfont", 14),
    })
    table.insert(content, TextWidget:new{
        text = string.format("Best Day: %s (%d/%d)", weekly_stats.best_day, weekly_stats.best_completed, weekly_stats.best_total),
        face = Font:getFace("cfont", 14),
    })
    table.insert(content, TextWidget:new{
        text = string.format("Missed: %d quests", weekly_stats.missed),
        face = Font:getFace("cfont", 14),
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })

    -- Mood This Week Section
    table.insert(content, TextWidget:new{
        text = "Mood This Week",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = { w = screen_width - 40, h = 1 },
        background = 0x888888,
    })
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })

    local mood_data = self:getWeeklyMood()
    for _, day in ipairs(mood_data) do
        local bar_width = math.floor((day.score / 10) * 20)  -- Max 20 chars
        local bar = string.rep("█", bar_width) .. string.rep("░", 20 - bar_width)
        table.insert(content, TextWidget:new{
            text = string.format("%s: %s %s", day.abbr, bar, day.energy or ""),
            face = Font:getFace("cfont", 12),
        })
    end
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })

    -- Pattern Insight
    local insight = self:generateInsight(weekly_stats, mood_data)
    if insight then
        table.insert(content, TextWidget:new{
            text = "💡 Pattern: " .. insight,
            face = Font:getFace("cfont", 14),
            fgcolor = 0x444444,
        })
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })
    end

    -- Reading Correlation
    local reading_insight = self:getReadingCorrelation()
    if reading_insight then
        table.insert(content, TextWidget:new{
            text = "📖 Reading: " .. reading_insight,
            face = Font:getFace("cfont", 14),
            fgcolor = 0x444444,
        })
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })
    end

    -- Add Reflection Button
    table.insert(content, VerticalSpan:new{ width = Size.span.vertical_large })
    table.insert(content, TextWidget:new{
        text = "[Add Reflection Note]",
        face = Font:getFace("cfont", 14),
        fgcolor = 0x0066CC,
    })

    -- Build frame
    local frame = FrameContainer:new{
        width = screen_width,
        height = Screen:getHeight(),
        padding = Size.padding.large,
        bordersize = 0,
        background = 0xFFFFFF,
        content,
    }

    -- Wrap for gestures
    local container = InputContainer:new{
        dimen = Screen:getSize(),
        ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = frame.dimen,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = frame.dimen,
                },
            },
        },
        frame,
    }

    function container:onTap()
        Journal:showActions()
        return true
    end

    function container:onSwipe(_, ges)
        if ges.direction == "east" then
            UIManager:close(self)
            return true
        end
        return false
    end

    self.journal_widget = container
    UIManager:show(container)
end

--[[--
Show journal actions.
--]]
function Journal:showActions()
    local buttons = {
        {
            {
                text = _("Add Reflection"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:showAddReflection()
                end,
            },
        },
        {
            {
                text = _("View Past Reflections"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:showPastReflections()
                end,
            },
        },
        {
            {
                text = _("Monthly Summary"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    self:showMonthlySummary()
                end,
            },
        },
        {
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(self.action_dialog)
                    UIManager:close(self.journal_widget)
                end,
            },
        },
    }

    self.action_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(self.action_dialog)
end

--[[--
Calculate weekly statistics.
--]]
function Journal:getWeeklyStats()
    local logs = Data:loadDailyLogs()
    local today = os.time()
    local day_names = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

    local total_completed = 0
    local total_assigned = 0
    local best_day = "None"
    local best_completed = 0
    local best_total = 0
    local best_rate = 0

    for i = 0, 6 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_data = logs[date_str]

        if day_data then
            local completed = day_data.quests_completed or 0
            local assigned = day_data.quests_total or 0

            total_completed = total_completed + completed
            total_assigned = total_assigned + assigned

            if assigned > 0 then
                local rate = completed / assigned
                if rate > best_rate or (rate == best_rate and completed > best_completed) then
                    best_rate = rate
                    best_completed = completed
                    best_total = assigned
                    local day_info = os.date("*t", day_time)
                    best_day = day_names[day_info.wday]
                end
            end
        end
    end

    local completion_rate = 0
    if total_assigned > 0 then
        completion_rate = math.floor((total_completed / total_assigned) * 100)
    end

    return {
        completion_rate = completion_rate,
        best_day = best_day,
        best_completed = best_completed,
        best_total = best_total,
        missed = total_assigned - total_completed,
    }
end

--[[--
Get weekly mood data for bar chart.
--]]
function Journal:getWeeklyMood()
    local logs = Data:loadDailyLogs()
    local settings = Data:loadUserSettings()
    local energy_categories = settings.energy_categories or {"Energetic", "Average", "Down"}
    local today = os.time()
    local day_abbrs = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

    -- Map energy levels to scores
    local energy_scores = {}
    local score_step = 10 / #energy_categories
    for i, cat in ipairs(energy_categories) do
        energy_scores[cat] = math.floor((#energy_categories - i + 1) * score_step)
    end

    local mood_data = {}

    for i = 6, 0, -1 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_info = os.date("*t", day_time)
        local day_abbr = day_abbrs[day_info.wday == 1 and 7 or day_info.wday - 1]

        local day_data = logs[date_str]
        local energy = day_data and day_data.energy_level
        local score = energy and energy_scores[energy] or 0

        table.insert(mood_data, {
            abbr = day_abbr,
            energy = energy,
            score = score,
        })
    end

    return mood_data
end

--[[--
Generate an insight based on patterns.
--]]
function Journal:generateInsight(weekly_stats, mood_data)
    -- Check for energy-productivity correlation
    local high_energy_completion = 0
    local high_energy_days = 0
    local low_energy_completion = 0
    local low_energy_days = 0

    local logs = Data:loadDailyLogs()
    local settings = Data:loadUserSettings()
    local energy_categories = settings.energy_categories or {"Energetic", "Average", "Down"}
    local high_energy = energy_categories[1]
    local low_energy = energy_categories[#energy_categories]

    local today = os.time()
    for i = 0, 6 do
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_data = logs[date_str]

        if day_data then
            local rate = 0
            if day_data.quests_total and day_data.quests_total > 0 then
                rate = day_data.quests_completed / day_data.quests_total
            end

            if day_data.energy_level == high_energy then
                high_energy_completion = high_energy_completion + rate
                high_energy_days = high_energy_days + 1
            elseif day_data.energy_level == low_energy then
                low_energy_completion = low_energy_completion + rate
                low_energy_days = low_energy_days + 1
            end
        end
    end

    local high_avg = high_energy_days > 0 and (high_energy_completion / high_energy_days) or 0
    local low_avg = low_energy_days > 0 and (low_energy_completion / low_energy_days) or 0

    if high_avg > low_avg + 0.3 then
        local diff = math.floor((high_avg - low_avg) * 100)
        return string.format("You complete %d%% more on %s days. Consider lighter loads on %s days.",
            diff, high_energy, low_energy)
    end

    if weekly_stats.completion_rate >= 80 then
        return "Great week! You're hitting your goals consistently."
    end

    if weekly_stats.missed > 5 then
        return "Consider reducing quest count or breaking large tasks into smaller ones."
    end

    return nil
end

--[[--
Get reading-productivity correlation insight.
--]]
function Journal:getReadingCorrelation()
    local logs = Data:loadDailyLogs()
    local today = os.time()

    local reading_days_completion = 0
    local reading_days_count = 0
    local non_reading_completion = 0
    local non_reading_count = 0

    for i = 0, 13 do  -- Look at 2 weeks
        local day_time = today - (i * 86400)
        local date_str = os.date("%Y-%m-%d", day_time)
        local day_data = logs[date_str]

        if day_data then
            local rate = 0
            if day_data.quests_total and day_data.quests_total > 0 then
                rate = day_data.quests_completed / day_data.quests_total
            end

            local reading = day_data.reading
            if reading and reading.pages_read and reading.pages_read > 0 then
                reading_days_completion = reading_days_completion + rate
                reading_days_count = reading_days_count + 1
            else
                non_reading_completion = non_reading_completion + rate
                non_reading_count = non_reading_count + 1
            end
        end
    end

    if reading_days_count >= 3 and non_reading_count >= 3 then
        local reading_avg = reading_days_completion / reading_days_count
        local non_reading_avg = non_reading_completion / non_reading_count

        if reading_avg > non_reading_avg + 0.2 then
            local diff = math.floor((reading_avg - non_reading_avg) * 100)
            return string.format("Days with reading show %d%% higher quest completion.", diff)
        end
    end

    return nil
end

--[[--
Show dialog to add a reflection note.
--]]
function Journal:showAddReflection()
    self.reflection_dialog = InputDialog:new{
        title = _("Today's Reflection"),
        input_hint = _("What worked? What didn't?"),
        allow_newline = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.reflection_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local text = self.reflection_dialog:getInputText()
                        UIManager:close(self.reflection_dialog)
                        if text and text ~= "" then
                            self:saveReflection(text)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.reflection_dialog)
    self.reflection_dialog:onShowKeyboard()
end

--[[--
Save a reflection note.
--]]
function Journal:saveReflection(text)
    local today = os.date("%Y-%m-%d")
    local logs = Data:loadDailyLogs()

    if not logs[today] then
        logs[today] = {}
    end

    logs[today].reflection = text
    logs[today].reflection_time = os.time()

    Data:saveDailyLogs(logs)

    UIManager:show(InfoMessage:new{
        text = _("Reflection saved!"),
    })
end

--[[--
Show past reflections.
--]]
function Journal:showPastReflections()
    local logs = Data:loadDailyLogs()
    local reflections = {}

    -- Gather all reflections
    for date, data in pairs(logs) do
        if data.reflection then
            table.insert(reflections, {
                date = date,
                text = data.reflection,
            })
        end
    end

    -- Sort by date (newest first)
    table.sort(reflections, function(a, b) return a.date > b.date end)

    if #reflections == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No reflections yet.\nAdd your first one!"),
        })
        return
    end

    -- Build text display
    local content = ""
    for i, r in ipairs(reflections) do
        if i <= 5 then  -- Show last 5
            content = content .. string.format("── %s ──\n%s\n\n", r.date, r.text)
        end
    end

    UIManager:show(InfoMessage:new{
        text = content,
        width = Screen:getWidth() - 40,
    })
end

--[[--
Show monthly summary.
--]]
function Journal:showMonthlySummary()
    local logs = Data:loadDailyLogs()
    local today = os.date("*t")
    local month_name = os.date("%B %Y")

    local total_completed = 0
    local total_assigned = 0
    local total_reading_pages = 0
    local total_reading_time = 0
    local days_logged = 0

    -- Get all days this month
    for date, data in pairs(logs) do
        local year, month = date:match("(%d+)-(%d+)")
        if tonumber(year) == today.year and tonumber(month) == today.month then
            days_logged = days_logged + 1
            total_completed = total_completed + (data.quests_completed or 0)
            total_assigned = total_assigned + (data.quests_total or 0)

            if data.reading then
                total_reading_pages = total_reading_pages + (data.reading.pages_read or 0)
                total_reading_time = total_reading_time + (data.reading.time_spent or 0)
            end
        end
    end

    local completion_rate = total_assigned > 0 and math.floor((total_completed / total_assigned) * 100) or 0
    local reading_hours = math.floor(total_reading_time / 3600)

    local summary = string.format([[
%s Summary
═══════════════════════

Days Tracked: %d
Quests Completed: %d/%d (%d%%)

📖 Reading
Pages: %d
Time: %d hours

Keep going! 🔥
]], month_name, days_logged, total_completed, total_assigned, completion_rate, total_reading_pages, reading_hours)

    UIManager:show(InfoMessage:new{
        text = summary,
        width = Screen:getWidth() - 40,
    })
end

return Journal
