--[[--
Journal module for Life Tracker.
Mood tracking, weekly review, and insights with reading correlation.
@module lifetracker.journal
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local _ = require("gettext")

local Data = require("modules/data")
local Navigation = require("modules/navigation")
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")

local Journal = {}

--[[--
Custom widget for drawing mood line graph using Blitbuffer.
Displays dots for data points with connecting lines.
--]]
local MoodGraphWidget = Widget:extend{
    width = nil,
    height = nil,
    data_points = nil,  -- Array of {value = 0-1, is_day_start = bool}
    num_levels = 3,
    day_labels = nil,   -- Array of day abbreviations
    num_slots_per_day = 3,
}

function MoodGraphWidget:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
end

function MoodGraphWidget:paintTo(bb, x, y)
    local num_points = #self.data_points
    if num_points == 0 then return end

    local graph_height = self.height - 20  -- Reserve space for labels
    local graph_y = y

    -- Calculate point spacing
    local point_spacing = self.width / num_points
    local dot_radius = 4
    local line_thickness = 2

    -- Draw horizontal grid lines for each level
    for level = 1, self.num_levels do
        local line_y = graph_y + Math.round((level - 1) * graph_height / (self.num_levels - 1))
        bb:paintRect(x, line_y, self.width, 1, Blitbuffer.COLOR_LIGHT_GRAY)
    end

    -- Draw vertical day separators and collect points
    -- Fill missing values with previous known value
    local points = {}
    local last_value = nil
    for i, point in ipairs(self.data_points) do
        local px = x + Math.round((i - 0.5) * point_spacing)

        -- Draw day separator at start of each day
        if point.is_day_start then
            bb:paintRect(px - point_spacing/2, graph_y, 1, graph_height, Blitbuffer.COLOR_LIGHT_GRAY)
        end

        -- Use current value or fall back to last known value
        local value = point.value or last_value
        if value then
            last_value = value
            local py = graph_y + graph_height - Math.round(value * graph_height)
            table.insert(points, {x = px, y = py, has_data = true, is_interpolated = (point.value == nil)})
        else
            table.insert(points, {x = px, y = nil, has_data = false})
        end
    end

    -- Draw connecting lines between points (thicker for visibility)
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        if p1.has_data and p2.has_data then
            local dx = p2.x - p1.x
            local dy = p2.y - p1.y
            local steps = math.max(math.abs(dx), math.abs(dy))
            if steps > 0 then
                for step = 0, steps do
                    local lx = Math.round(p1.x + dx * step / steps)
                    local ly = Math.round(p1.y + dy * step / steps)
                    -- Draw thicker line
                    bb:paintRect(lx, ly - line_thickness/2, 1, line_thickness, Blitbuffer.COLOR_BLACK)
                end
            end
        end
    end

    -- Draw dots on top of lines (larger dots for real data, smaller for interpolated)
    for _, p in ipairs(points) do
        if p.has_data then
            local radius = p.is_interpolated and 2 or dot_radius
            -- Draw filled circle
            for dy = -radius, radius do
                local dx = Math.round(math.sqrt(radius * radius - dy * dy))
                bb:paintRect(p.x - dx, p.y + dy, dx * 2 + 1, 1, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

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
    local screen_height = Screen:getHeight()
    local content_width = screen_width - Navigation.TAB_WIDTH - Size.padding.large * 2

    -- KOReader reserves top ~10% for menu gesture
    local top_safe_zone = UIConfig:getTopSafeZone()

    local content = VerticalGroup:new{ align = "left" }

    -- Header (in top zone - non-interactive, standardized page title)
    table.insert(content, TextWidget:new{
        text = "Journal & Insights",
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    })

    -- Add spacer to push interactive content below top_safe_zone
    local header_height = 28
    local spacer_needed = top_safe_zone - Size.padding.large - header_height
    if spacer_needed > 0 then
        table.insert(content, VerticalSpan:new{ width = spacer_needed })
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    -- Weekly Review Section
    table.insert(content, TextWidget:new{
        text = "Weekly Review",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

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
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Mood This Week Section
    table.insert(content, TextWidget:new{
        text = "Mood This Week",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    local mood_data, energy_categories, time_slots = self:getWeeklyMood()

    -- Build data points for pixel-based graph
    local data_points = {}
    local day_labels = {}

    for _, day in ipairs(mood_data) do
        table.insert(day_labels, day.abbr)
        for slot_idx, slot in ipairs(time_slots) do
            local score = day.slot_scores[slot]
            local value = nil
            if score then
                -- Convert score (0-10) to ratio (0-1)
                value = score / 10
            end
            table.insert(data_points, {
                value = value,
                is_day_start = (slot_idx == 1),
            })
        end
    end

    -- Create pixel-based graph widget
    local graph_height = Screen:scaleBySize(80)
    local mood_graph = MoodGraphWidget:new{
        width = content_width,
        height = graph_height,
        data_points = data_points,
        num_levels = #energy_categories,
        day_labels = day_labels,
        num_slots_per_day = #time_slots,
    }
    table.insert(content, mood_graph)

    -- Add day labels using TextWidgets for proper rendering
    local label_row = HorizontalGroup:new{align = "center"}
    local day_width = math.floor(content_width / #mood_data)
    for _, day in ipairs(mood_data) do
        table.insert(label_row, CenterContainer:new{
            dimen = Geom:new{w = day_width, h = 16},
            TextWidget:new{
                text = day.abbr,
                face = Font:getFace("cfont", 11),
            },
        })
    end
    table.insert(content, label_row)
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Persistent Notes Section (stays across days)
    local persistent_notes = Data:loadPersistentNotes()
    local Button = require("ui/widget/button")

    table.insert(content, TextWidget:new{
        text = "Notes",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    if persistent_notes and persistent_notes ~= "" then
        table.insert(content, TextWidget:new{
            text = persistent_notes,
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.gray(0.3),
            max_width = content_width,
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    else
        table.insert(content, TextWidget:new{
            text = "(No notes yet)",
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.gray(0.5),
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    end

    -- Edit/Add Notes Button
    local journal_self = self
    local has_notes = persistent_notes and persistent_notes ~= ""
    local notes_button = Button:new{
        text = has_notes and "Edit Notes" or "Add Notes",
        callback = function()
            journal_self:showEditPersistentNotes()
        end,
        width = 120,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
    }
    table.insert(content, notes_button)
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Today's Reflection Section (daily)
    local reflection = self:getTodayReflection()

    table.insert(content, TextWidget:new{
        text = "Today's Reflection",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    if reflection and reflection ~= "" then
        table.insert(content, TextWidget:new{
            text = reflection,
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.gray(0.3),
            max_width = content_width,
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    else
        table.insert(content, TextWidget:new{
            text = "(No reflection yet)",
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.gray(0.5),
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    end

    -- Edit Reflection Button
    local reflection_button = Button:new{
        text = reflection and "Edit Reflection" or "Add Reflection",
        callback = function()
            journal_self:showAddReflection()
        end,
        width = 140,
        bordersize = 1,
        margin = 0,
        padding = Size.padding.small,
    }
    table.insert(content, reflection_button)
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Category Performance Chart
    table.insert(content, TextWidget:new{
        text = "Category Performance",
        face = Font:getFace("tfont", 16),
        bold = true,
    })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = content_width, h = 1 },
        background = Blitbuffer.gray(0.5),
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    local spider_widgets = self:buildCategorySpiderChart(content_width)
    for _, widget in ipairs(spider_widgets) do
        table.insert(content, widget)
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })

    -- Pattern Insight
    local insight = self:generateInsight(weekly_stats, mood_data)
    if insight then
        table.insert(content, TextWidget:new{
            text = "Pattern: " .. insight,
            face = Font:getFace("cfont", 14),
            fgcolor = Blitbuffer.gray(0.3),
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    end

    -- Reading Correlation
    local reading_insight = self:getReadingCorrelation()
    if reading_insight then
        table.insert(content, TextWidget:new{
            text = "Reading: " .. reading_insight,
            face = Font:getFace("cfont", 14),
            fgcolor = Blitbuffer.gray(0.3),
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    end

    -- Add Reflection Button (tap anywhere to show menu)
    table.insert(content, VerticalSpan:new{ width = Size.padding.large })
    table.insert(content, TextWidget:new{
        text = "[Tap for menu]",
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.gray(0.5),
    })

    -- Wrap content in scrollable container
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local scroll_height = screen_height

    local inner_frame = FrameContainer:new{
        width = scroll_width - scrollbar_width,
        height = math.max(scroll_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    local padded_content = ScrollableContainer:new{
        dimen = Geom:new{ w = scroll_width, h = scroll_height },
        inner_frame,
    }
    self.scrollable_container = padded_content

    -- Setup navigation
    local journal = self
    local ui = self.ui

    local function on_tab_change(tab_id)
        UIManager:close(journal.journal_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("journal", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create the main layout with content and navigation
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        padded_content,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Standard InputContainer
    self.journal_widget = InputContainer:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        ges_events = {},
        main_layout,
    }

    -- Set show_parent for ScrollableContainer refresh
    self.scrollable_container.show_parent = self.journal_widget

    -- Setup corner gesture handlers using shared helpers
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = top_safe_zone,
    }
    UIHelpers.setupCornerGestures(self.journal_widget, self, gesture_dims)
    UIHelpers.setupSwipeToClose(self.journal_widget, function()
        UIManager:close(self.journal_widget)
    end, gesture_dims)

    -- Tap anywhere in content area (below top zone) to show actions menu
    self.journal_widget.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = top_safe_zone,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height - top_safe_zone,
            },
        },
    }
    self.journal_widget.onTap = function()
        self:showActions()
        return true
    end

    UIManager:show(self.journal_widget)
end

--[[--
Show journal actions.
--]]
function Journal:showActions()
    local buttons = {
        {{
            text = _("Add Reflection"),
            callback = function()
                UIManager:close(self.action_dialog)
                self:showAddReflection()
            end,
        }},
        {{
            text = _("View Past Reflections"),
            callback = function()
                UIManager:close(self.action_dialog)
                self:showPastReflections()
            end,
        }},
        {{
            text = _("Monthly Summary"),
            callback = function()
                UIManager:close(self.action_dialog)
                self:showMonthlySummary()
            end,
        }},
        {{
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.action_dialog)
            end,
        }},
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
Get weekly mood data with time slot breakdown.
Returns mood by time slot for each day (Morning, Afternoon, Evening, Night).
--]]
function Journal:getWeeklyMood()
    local logs = Data:loadDailyLogs()
    local settings = Data:loadUserSettings()
    local energy_categories = settings.energy_categories or {"Energetic", "Average", "Down"}
    local time_slots = settings.time_slots or {"Morning", "Afternoon", "Evening", "Night"}
    local today = os.time()
    local day_abbrs = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}

    -- Map energy levels to scores (first = highest)
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

        -- Initialize slots for this day
        local slot_scores = {}
        for _, slot in ipairs(time_slots) do
            slot_scores[slot] = nil  -- No data yet
        end

        -- Get mood entries and map to time slots
        local entries = day_data and day_data.energy_entries or {}
        for _, entry in ipairs(entries) do
            local slot = entry.time_slot or Data:hourToTimeSlot(entry.hour, time_slots)
            local entry_score = energy_scores[entry.energy] or 0
            -- Keep the latest entry for each slot
            slot_scores[slot] = entry_score
        end

        -- Fallback to daily energy if no entries
        if #entries == 0 and day_data and day_data.energy_level then
            local score = energy_scores[day_data.energy_level] or 0
            -- Apply to all slots as fallback
            for _, slot in ipairs(time_slots) do
                slot_scores[slot] = score
            end
        end

        table.insert(mood_data, {
            abbr = day_abbr,
            date = date_str,
            slot_scores = slot_scores,
        })
    end

    return mood_data, energy_categories, time_slots
end

--[[--
Render a connected line graph for weekly mood using Unicode characters.
Shows individual time slot data points expanded across the full width.
@param mood_data table Weekly mood data from getWeeklyMood
@param energy_categories table Energy level names
@param max_width number Maximum width in characters
@param time_slots table Array of time slot names from user config
@return table Array of TextWidgets for the graph
--]]
function Journal:renderMoodLineGraph(mood_data, energy_categories, max_width, time_slots)
    local widgets = {}
    local num_levels = #energy_categories
    local num_days = #mood_data
    local num_slots = time_slots and #time_slots or 3
    local total_points = num_days * num_slots
    local score_step = 10 / num_levels

    -- Build flat array of all data points (day1_slot1, day1_slot2, ..., day7_slotN)
    local all_scores = {}
    for day_idx, day in ipairs(mood_data) do
        for slot_idx, slot in ipairs(time_slots) do
            local score = day.slot_scores[slot]
            if score then
                -- Convert score (0-10) to row (1-num_levels)
                local row = num_levels - math.floor(score / score_step)
                row = math.max(1, math.min(num_levels, row))
                table.insert(all_scores, {row = row, day_idx = day_idx, slot_idx = slot_idx})
            else
                table.insert(all_scores, {row = nil, day_idx = day_idx, slot_idx = slot_idx})
            end
        end
    end

    -- Calculate column width to fill available space
    -- Reserve 3 chars for y-axis label, use rest for data
    local available_width = max_width - 4
    local col_width = math.max(2, math.floor(available_width / total_points))

    -- Build each row of the graph
    for row = 1, num_levels do
        local label = string.sub(energy_categories[row], 1, 1)
        local line = label .. " │"

        for point_idx, point in ipairs(all_scores) do
            local point_row = point.row
            local next_point = all_scores[point_idx + 1]
            local next_row = next_point and next_point.row

            local cell = ""

            if point_row == row then
                -- Data point on this row
                cell = "●"
                -- Add connector if next point exists
                if next_row then
                    if next_row < row then
                        cell = cell .. "╱"
                    elseif next_row > row then
                        cell = cell .. "╲"
                    else
                        cell = cell .. "─"
                    end
                end
            elseif point_row and next_row then
                -- Check if connector passes through
                local min_row = math.min(point_row, next_row)
                local max_row = math.max(point_row, next_row)
                if row > min_row and row < max_row then
                    if point_row < next_row then
                        cell = " ╲"
                    else
                        cell = " ╱"
                    end
                end
            end

            -- Pad to col_width
            while #cell < col_width do
                cell = cell .. " "
            end
            line = line .. cell
        end

        table.insert(widgets, TextWidget:new{
            text = line,
            face = Font:getFace("cfont", 11),
        })
    end

    -- Baseline with tick marks for each slot
    local baseline = "  +"
    for _, point in ipairs(all_scores) do
        -- Add day separator tick at start of each day
        if point.slot_idx == 1 then
            baseline = baseline .. "┬"
        else
            baseline = baseline .. "─"
        end
        -- Fill rest of column
        for _ = 2, col_width do
            baseline = baseline .. "─"
        end
    end
    table.insert(widgets, TextWidget:new{
        text = baseline,
        face = Font:getFace("cfont", 11),
    })

    -- Day labels - centered under each day's slots
    local day_col_width = col_width * num_slots
    local day_labels = "   "
    for _, day in ipairs(mood_data) do
        local abbr = day.abbr
        local left_pad = math.floor((day_col_width - #abbr) / 2)
        local right_pad = day_col_width - #abbr - left_pad
        day_labels = day_labels .. string.rep(" ", left_pad) .. abbr .. string.rep(" ", right_pad)
    end
    table.insert(widgets, TextWidget:new{
        text = day_labels,
        face = Font:getFace("cfont", 11),
    })

    return widgets
end

--[[--
Generate an insight based on patterns.
--]]
function Journal:generateInsight(weekly_stats, _mood_data)
    -- Check for energy-productivity correlation
    local logs = Data:loadDailyLogs()
    local settings = Data:loadUserSettings()
    local energy_categories = settings.energy_categories or {"Energetic", "Average", "Down"}
    local high_energy = energy_categories[1]
    local low_energy = energy_categories[#energy_categories]

    local high_energy_completion = 0
    local high_energy_days = 0
    local low_energy_completion = 0
    local low_energy_days = 0

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
        return string.format("You complete %d%% more on %s days.", diff, high_energy)
    end

    if weekly_stats.completion_rate >= 80 then
        return "Great week! You're hitting your goals consistently."
    end

    if weekly_stats.missed > 5 then
        return "Consider reducing quest count or breaking tasks smaller."
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
            return string.format("Days with reading show %d%% higher completion.", diff)
        end
    end

    return nil
end

--[[--
Show dialog to add or edit persistent notes.
--]]
function Journal:showEditPersistentNotes()
    local existing_text = Data:loadPersistentNotes() or ""
    local title = existing_text ~= "" and _("Edit Notes") or _("Add Notes")

    self.notes_dialog = InputDialog:new{
        title = title,
        input = existing_text,
        input_hint = _("Persistent notes that stay across days..."),
        allow_newline = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.notes_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local text = self.notes_dialog:getInputText()
                        UIManager:close(self.notes_dialog)
                        Data:savePersistentNotes(text)
                        -- Refresh journal view
                        UIManager:close(self.journal_widget)
                        self:showJournalView()
                        UIManager:setDirty("all", "ui")
                    end,
                },
            },
        },
    }
    UIManager:show(self.notes_dialog)
    self.notes_dialog:onShowKeyboard()
end

--[[--
Show dialog to add or edit today's reflection.
--]]
function Journal:showAddReflection()
    local existing_text = self:getTodayReflection() or ""
    local title = existing_text ~= "" and _("Edit Today's Reflection") or _("Add Today's Reflection")

    self.reflection_dialog = InputDialog:new{
        title = title,
        input = existing_text,
        input_hint = _("What worked? What didn't? How do you feel?"),
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
                            -- Refresh journal view
                            UIManager:close(self.journal_widget)
                            self:showJournalView()
                            UIManager:setDirty("all", "ui")
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
    UIManager:setDirty("all", "ui")

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
            content = content .. string.format("-- %s --\n%s\n\n", r.date, r.text)
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

Days Tracked: %d
Quests Completed: %d/%d (%d%%)

Reading
Pages: %d
Time: %d hours

Keep going!
]], month_name, days_logged, total_completed, total_assigned, completion_rate, total_reading_pages, reading_hours)

    UIManager:show(InfoMessage:new{
        text = summary,
        width = Screen:getWidth() - 40,
    })
end

--[[--
Build ASCII spider/radar chart for category performance.
Shows completion rate per quest category as a diamond pattern.
@param content_width number Available width for the chart
@return table Array of TextWidget objects
--]]
function Journal:buildCategorySpiderChart(_content_width)
    local widgets = {}
    local quests = Data:loadAllQuests()
    local settings = Data:loadUserSettings()
    local categories = settings.quest_categories or {"Health", "Work", "Personal", "Learning"}
    local today = os.date("%Y-%m-%d")

    -- Calculate completion rate per category
    local category_stats = {}
    for _, cat in ipairs(categories) do
        category_stats[cat] = { completed = 0, total = 0 }
    end
    category_stats["None"] = { completed = 0, total = 0 }

    -- Count quests per category
    for _, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for _, quest in ipairs(quests[quest_type] or {}) do
            local cat = quest.category or "None"
            if not category_stats[cat] then
                category_stats[cat] = { completed = 0, total = 0 }
            end
            category_stats[cat].total = category_stats[cat].total + 1
            if quest.completed and quest.completed_date == today then
                category_stats[cat].completed = category_stats[cat].completed + 1
            end
        end
    end

    -- Build data for spider chart (only categories with quests)
    local active_categories = {}
    for _, cat in ipairs(categories) do
        if category_stats[cat] and category_stats[cat].total > 0 then
            local rate = category_stats[cat].completed / category_stats[cat].total
            table.insert(active_categories, { name = cat, rate = rate })
        end
    end

    -- If no categorized quests, show a message
    if #active_categories == 0 then
        table.insert(widgets, TextWidget:new{
            text = "No categorized quests yet",
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.gray(0.5),
        })
        return widgets
    end

    -- Build ASCII spider chart
    -- Uses a diamond pattern with labels at compass points

    local num_cats = #active_categories
    local max_radius = 4  -- Max characters from center

    if num_cats == 4 then
        -- 4-category diamond: Top, Right, Bottom, Left
        local top = active_categories[1]
        local right = active_categories[2]
        local bottom = active_categories[3]
        local left = active_categories[4]

        -- Calculate radius for each (0-max_radius based on rate)
        local r_top = math.ceil(top.rate * max_radius)
        local r_right = math.ceil(right.rate * max_radius)
        local r_bottom = math.ceil(bottom.rate * max_radius)
        local r_left = math.ceil(left.rate * max_radius)

        -- Build the chart line by line
        local center = max_radius + 8  -- Center position accounting for label

        -- Top label
        local top_label = string.format("%s %d%%", top.name:sub(1,6), math.floor(top.rate * 100))
        local top_line = string.rep(" ", center - math.floor(#top_label/2)) .. top_label
        table.insert(widgets, TextWidget:new{ text = top_line, face = Font:getFace("cfont", 10) })

        -- Build diamond rows
        for row = max_radius, 1, -1 do
            local line = ""
            -- Left label on middle row
            if row == math.ceil(max_radius / 2) then
                line = left.name:sub(1,4) .. " "
            else
                line = string.rep(" ", 5)
            end

            -- Build this row of the diamond
            for col = 1, max_radius * 2 + 1 do
                local dist_from_center = math.abs(col - max_radius - 1)
                if row == r_top and col == max_radius + 1 then
                    line = line .. "█"
                elseif dist_from_center == 0 and row <= r_top then
                    line = line .. "│"
                elseif row == math.ceil(max_radius / 2) and col <= max_radius + 1 - r_left then
                    line = line .. " "
                elseif row == math.ceil(max_radius / 2) and col == max_radius + 1 - r_left then
                    line = line .. "█"
                elseif row == math.ceil(max_radius / 2) and col > max_radius + 1 and col <= max_radius + 1 + r_right then
                    if col == max_radius + 1 + r_right then
                        line = line .. "█"
                    else
                        line = line .. "─"
                    end
                elseif row == math.ceil(max_radius / 2) then
                    if col < max_radius + 1 then
                        line = line .. "─"
                    else
                        line = line .. " "
                    end
                else
                    line = line .. " "
                end
            end

            -- Right label on middle row
            if row == math.ceil(max_radius / 2) then
                line = line .. " " .. right.name:sub(1,4)
            end

            table.insert(widgets, TextWidget:new{ text = line, face = Font:getFace("cfont", 10) })
        end

        -- Center row
        local center_line = string.rep(" ", 5)
        for col = 1, max_radius * 2 + 1 do
            if col == max_radius + 1 then
                center_line = center_line .. "+"
            elseif col >= max_radius + 1 - r_left and col <= max_radius + 1 + r_right then
                center_line = center_line .. "─"
            else
                center_line = center_line .. " "
            end
        end
        table.insert(widgets, TextWidget:new{ text = center_line, face = Font:getFace("cfont", 10) })

        -- Bottom half (mirror of top)
        for row = 1, max_radius do
            local line = string.rep(" ", 5)
            for col = 1, max_radius * 2 + 1 do
                if row == r_bottom and col == max_radius + 1 then
                    line = line .. "█"
                elseif col == max_radius + 1 and row <= r_bottom then
                    line = line .. "│"
                else
                    line = line .. " "
                end
            end
            table.insert(widgets, TextWidget:new{ text = line, face = Font:getFace("cfont", 10) })
        end

        -- Bottom label
        local bottom_label = string.format("%s %d%%", bottom.name:sub(1,6), math.floor(bottom.rate * 100))
        local bottom_line = string.rep(" ", center - math.floor(#bottom_label/2)) .. bottom_label
        table.insert(widgets, TextWidget:new{ text = bottom_line, face = Font:getFace("cfont", 10) })

    else
        -- Fallback: simple horizontal bar chart for any number of categories
        for _, cat_data in ipairs(active_categories) do
            local bar_width = 20
            local filled = math.floor(cat_data.rate * bar_width)
            local bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)
            local line = string.format("%-8s %s %3d%%", cat_data.name:sub(1,8), bar, math.floor(cat_data.rate * 100))
            table.insert(widgets, TextWidget:new{
                text = line,
                face = Font:getFace("cfont", 11),
            })
        end
    end

    return widgets
end

--[[--
Get today's reflection text.
@return string|nil Reflection text or nil if none
--]]
function Journal:getTodayReflection()
    local today = os.date("%Y-%m-%d")
    local log = Data:getDayLog(today)
    if log and log.reflection then
        return log.reflection
    end
    return nil
end

return Journal
