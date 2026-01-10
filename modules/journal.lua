--[[--
Journal module for Life Tracker.
Mood tracking, weekly review, and insights with reading correlation.
@module lifetracker.journal
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local Data = require("modules/data")
local Navigation = require("modules/navigation")
local UIConfig = require("modules/ui_config")

local Journal = {}

--[[--
Dispatch a corner gesture to the user's configured action.
@tparam string gesture_name The gesture name (e.g., "tap_top_left_corner")
@treturn bool True if gesture was handled
--]]
function Journal:dispatchCornerGesture(gesture_name)
    if self.ui and self.ui.gestures then
        local gesture_manager = self.ui.gestures
        local settings = gesture_manager.gestures or {}
        local action = settings[gesture_name]
        if action then
            local Dispatcher = require("dispatcher")
            Dispatcher:execute(action)
            return true
        end
    end

    if gesture_name == "tap_top_right_corner" then
        self.ui:handleEvent(Event:new("ToggleFrontlight"))
        return true
    elseif gesture_name == "tap_top_left_corner" then
        self.ui:handleEvent(Event:new("ToggleBookmark"))
        return true
    end

    return false
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

    -- KOReader reserves top 1/8 (12.5%) for menu gesture
    local top_safe_zone = math.floor(screen_height / 8)

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

    local mood_data, energy_categories = self:getWeeklyMood()
    -- Use line graph visualization - calculate character width from pixel width
    -- Monospace font at size 11 is approximately 7 pixels per character
    local char_width = math.floor(content_width / 7)
    local graph_widgets = self:renderMoodLineGraph(mood_data, energy_categories, char_width)
    for __, widget in ipairs(graph_widgets) do
        table.insert(content, widget)
    end
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

    -- Edit Notes Button
    local journal_self = self
    local notes_button = Button:new{
        text = persistent_notes and "Edit Notes" or "Add Notes",
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
    for __, widget in ipairs(spider_widgets) do
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

    -- KOReader gesture zone dimensions
    local corner_size = math.floor(screen_width / 8)
    local corner_height = math.floor(screen_height / 8)

    -- Top CENTER zone - Opens KOReader menu
    self.journal_widget.ges_events.TopCenterTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = corner_size,
                y = 0,
                w = screen_width - corner_size * 2,
                h = top_safe_zone,
            },
        },
    }
    self.journal_widget.onTopCenterTap = function()
        if self.ui and self.ui.menu then
            self.ui.menu:onShowMenu()
        else
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Corner tap handlers
    self.journal_widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.journal_widget.onTopLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_top_left_corner")
    end

    self.journal_widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = 0, w = corner_size, h = corner_height },
        },
    }
    self.journal_widget.onTopRightCornerTap = function()
        return self:dispatchCornerGesture("tap_top_right_corner")
    end

    self.journal_widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.journal_widget.onBottomLeftCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_left_corner")
    end

    self.journal_widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = screen_width - corner_size, y = screen_height - corner_height, w = corner_size, h = corner_height },
        },
    }
    self.journal_widget.onBottomRightCornerTap = function()
        return self:dispatchCornerGesture("tap_bottom_right_corner")
    end

    -- Tap anywhere in content area (below top zone) to show menu
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

    -- Swipe gestures (leave top 1/8 for KOReader menu)
    self.journal_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = Geom:new{
                x = 0,
                y = top_safe_zone,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height - top_safe_zone,
            },
        },
    }
    self.journal_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            UIManager:close(self.journal_widget)
            return true
        end
        return false
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
        for __, slot in ipairs(time_slots) do
            slot_scores[slot] = nil  -- No data yet
        end

        -- Get mood entries and map to time slots
        local entries = day_data and day_data.energy_entries or {}
        for __, entry in ipairs(entries) do
            local slot = entry.time_slot or Data:hourToTimeSlot(entry.hour, time_slots)
            local entry_score = energy_scores[entry.energy] or 0
            -- Keep the latest entry for each slot
            slot_scores[slot] = entry_score
        end

        -- Fallback to daily energy if no entries
        if #entries == 0 and day_data and day_data.energy_level then
            local score = energy_scores[day_data.energy_level] or 0
            -- Apply to all slots as fallback
            for __, slot in ipairs(time_slots) do
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
Render a text-based line graph for weekly mood with time slot breakdown.
Each day is divided into time slots (Morning, Afternoon, Evening, Night).
@param mood_data table Weekly mood data from getWeeklyMood
@param energy_categories table Energy level names
@param _max_width number Maximum width in characters (unused, we use fixed widths)
@return table Array of TextWidgets for the graph
--]]
function Journal:renderMoodLineGraph(mood_data, energy_categories, _max_width)
    local widgets = {}
    local settings = Data:loadUserSettings()
    local time_slots = settings.time_slots or {"Morning", "Afternoon", "Evening", "Night"}
    local num_slots = #time_slots

    -- Fixed layout: each slot gets 2 chars, prefix is 4 chars "X | "
    local slot_width = 2
    local day_width = slot_width * num_slots  -- 8 chars per day

    -- Build the graph rows (top to bottom = highest to lowest score)
    local score_step = 10 / #energy_categories
    for row = 1, #energy_categories do
        local row_score = math.floor((#energy_categories - row + 1) * score_step)
        local label = string.sub(energy_categories[row], 1, 1)
        local line = label .. " | "  -- 4 chars: "E | "

        for __, day in ipairs(mood_data) do
            for __, slot in ipairs(time_slots) do
                local slot_score = day.slot_scores[slot]
                local marker = "."
                if slot_score then
                    if math.abs(slot_score - row_score) < score_step / 2 then
                        marker = "*"
                    end
                end
                line = line .. marker .. " "  -- 2 chars per slot
            end
        end

        table.insert(widgets, TextWidget:new{
            text = line,
            face = Font:getFace("cfont", 10),
        })
    end

    -- Baseline: same prefix width, then dashes matching day widths
    local baseline = "  + "  -- 4 chars to match "X | "
    for _ = 1, 7 do
        baseline = baseline .. string.rep("-", day_width)
    end
    table.insert(widgets, TextWidget:new{
        text = baseline,
        face = Font:getFace("cfont", 10),
    })

    -- Day labels: same prefix width, then centered labels
    local day_labels = "    "  -- 4 spaces to match "X | "
    for __, day in ipairs(mood_data) do
        local abbr = day.abbr
        local total_pad = day_width - #abbr
        local left = math.floor(total_pad / 2)
        local right = total_pad - left
        day_labels = day_labels .. string.rep(" ", left) .. abbr .. string.rep(" ", right)
    end
    table.insert(widgets, TextWidget:new{
        text = day_labels,
        face = Font:getFace("cfont", 10),
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
    for __, cat in ipairs(categories) do
        category_stats[cat] = { completed = 0, total = 0 }
    end
    category_stats["None"] = { completed = 0, total = 0 }

    -- Count quests per category
    for __, quest_type in ipairs({"daily", "weekly", "monthly"}) do
        for __, quest in ipairs(quests[quest_type] or {}) do
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
    for __, cat in ipairs(categories) do
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
        for __, cat_data in ipairs(active_categories) do
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
