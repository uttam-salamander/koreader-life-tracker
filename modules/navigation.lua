--[[--
Navigation module for Life Tracker.
Provides a bullet journal-style right-side tab navigation.
@module lifetracker.navigation
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local Navigation = {}

-- Tab definitions with vertical labels (diary-style rotated text)
-- Labels are displayed vertically, one character per line
Navigation.TABS = {
    {id = "dashboard", label = "HOME", full = _("Dashboard")},
    {id = "quests",    label = "QUEST", full = _("Quests")},
    {id = "timeline",  label = "DAY", full = _("Timeline")},
    {id = "reminders", label = "ALARM", full = _("Reminders")},
    {id = "journal",   label = "LOG", full = _("Journal")},
    {id = "read",      label = "READ", full = _("Reading")},
}

-- Tab width for the right sidebar (wider for better touch targets)
Navigation.TAB_WIDTH = 60

--[[--
Create a wrapped content view with right-side tab navigation.
@param content Widget The main content to display
@param current_tab string The ID of the currently active tab
@param on_tab_change function Callback when tab is selected
@return Widget The wrapped content with navigation
--]]
function Navigation:wrap(content, current_tab, on_tab_change)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Store callback
    self.on_tab_change = on_tab_change

    -- Build tab column
    local tabs = self:buildTabColumn(current_tab, screen_height)

    -- Use OverlapGroup to overlay tabs on top of content
    -- This ensures tabs are always visible on the right edge
    local layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        -- Layer 1: Main content (full screen)
        content,
        -- Layer 2: Tabs positioned on the right
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    return layout
end

--[[--
Build the vertical tab column.
@param current_tab string Active tab ID
@param height number Screen height
@return Widget Tab column widget
--]]
function Navigation:buildTabColumn(current_tab, height)
    local tab_height = math.floor(height / #self.TABS)
    local screen_width = Screen:getWidth()
    local tab_x = screen_width - self.TAB_WIDTH  -- X position of tabs

    -- Create container that holds all tabs with gestures
    local tabs_container = InputContainer:new{
        dimen = Geom:new{w = self.TAB_WIDTH, h = height},
        ges_events = {},  -- Will be populated with tab tap events
    }

    local tabs_group = VerticalGroup:new{ align = "center" }

    for idx, tab in ipairs(self.TABS) do
        local is_active = (tab.id == current_tab)

        -- Tab background styling (high contrast for e-ink)
        local bg_color = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg_color = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local border_size = is_active and 2 or 1

        -- Create vertical text label
        local vertical_label = VerticalGroup:new{ align = "center" }
        for i = 1, #tab.label do
            local char = tab.label:sub(i, i)
            table.insert(vertical_label, TextWidget:new{
                text = char,
                face = Font:getFace("tfont", 14),
                fgcolor = fg_color,
                bold = is_active,
            })
        end

        -- Wrap in container
        local inner_width = self.TAB_WIDTH - Size.padding.small * 2
        local inner_height = tab_height - Size.padding.small * 2
        local tab_frame = FrameContainer:new{
            width = self.TAB_WIDTH,
            height = tab_height,
            padding = Size.padding.small,
            bordersize = border_size,
            background = bg_color,
            CenterContainer:new{
                dimen = Geom:new{w = inner_width, h = inner_height},
                vertical_label,
            },
        }

        table.insert(tabs_group, tab_frame)

        -- Add tap gesture for this tab region (using screen coordinates)
        local tab_y = (idx - 1) * tab_height
        local gesture_name = "Tap_" .. tab.id
        tabs_container.ges_events[gesture_name] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = tab_x,
                    y = tab_y,
                    w = self.TAB_WIDTH,
                    h = tab_height,
                },
            },
        }

        -- Create handler for this tab
        local nav = self
        local tab_id = tab.id
        tabs_container["on" .. gesture_name] = function()
            if nav.on_tab_change and tab_id ~= current_tab then
                nav.on_tab_change(tab_id)
            end
            return true
        end
    end

    -- Add the visual tabs group
    tabs_container[1] = FrameContainer:new{
        width = self.TAB_WIDTH,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        tabs_group,
    }

    return tabs_container
end

--[[--
Create a full-screen view with navigation.
Shows content with right-side tabs.
@param content Widget The content to display
@param current_tab string Current tab ID
@param on_tab_change function Tab change callback
@param on_close function Close callback
@return Widget Full screen container with navigation
--]]
function Navigation:createView(content, current_tab, on_tab_change, on_close)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    -- Leave top 10% free for KOReader system gestures (menu, etc.)
    local top_safe_zone = math.floor(screen_height * 0.1)

    -- Wrap content with tabs
    local wrapped = self:wrap(content, current_tab, on_tab_change)

    -- Create container with gesture handling
    -- Exclude top 10% for KOReader accessibility (menu, etc.)
    -- Use VerticalGroup with spacer to push content below safe zone
    local content_with_spacer = VerticalGroup:new{
        align = "left",
        -- Top spacer for KOReader menu access
        VerticalSpan:new{ width = top_safe_zone },
        -- Main content
        FrameContainer:new{
            width = screen_width,
            height = screen_height - top_safe_zone,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            wrapped,
        },
    }

    local container = InputContainer:new{
        -- Dimen excludes top safe zone so taps there go to KOReader
        dimen = Geom:new{
            x = 0,
            y = top_safe_zone,
            w = screen_width,
            h = screen_height - top_safe_zone,
        },
        ges_events = {
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{
                        x = 0,
                        y = top_safe_zone,
                        w = screen_width,
                        h = screen_height - top_safe_zone,
                    },
                },
            },
            -- Capture taps only below safe zone
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0,
                        y = top_safe_zone,
                        w = screen_width,
                        h = screen_height - top_safe_zone,
                    },
                },
            },
        },
        content_with_spacer,
    }

    -- Tap handler - only handle taps below safe zone (let top area pass through)
    function container:onTap(_, ges)
        -- If tap is in safe zone, don't handle it (return false to propagate)
        if ges.pos.y < top_safe_zone then
            return false
        end
        -- Otherwise, let child widgets handle it
        return false
    end

    -- Swipe navigation
    function container:onSwipe(_, ges)
        if ges.direction == "east" then
            -- Swipe right to close or go back
            if on_close then
                on_close()
            end
            return true
        elseif ges.direction == "north" or ges.direction == "south" then
            -- Swipe up/down to navigate tabs
            local current_index = 1
            for i, tab in ipairs(Navigation.TABS) do
                if tab.id == current_tab then
                    current_index = i
                    break
                end
            end

            local new_index
            if ges.direction == "north" then
                new_index = current_index + 1
            else
                new_index = current_index - 1
            end

            -- Wrap around
            if new_index > #Navigation.TABS then
                new_index = 1
            elseif new_index < 1 then
                new_index = #Navigation.TABS
            end

            if on_tab_change then
                on_tab_change(Navigation.TABS[new_index].id)
            end
            return true
        end
        return false
    end

    return container
end

--[[--
Get the content width available after tab navigation.
@return number Width in pixels
--]]
function Navigation:getContentWidth()
    return Screen:getWidth() - self.TAB_WIDTH
end

--[[--
Navigate to a tab by ID.
@param tab_id string Tab to navigate to
@param ui table KOReader UI instance
--]]
function Navigation:navigateTo(tab_id, ui)
    -- Close any current view
    if self.current_view then
        UIManager:close(self.current_view)
        self.current_view = nil
    end

    -- Load and show the appropriate module
    local module_map = {
        dashboard = "modules/dashboard",
        quests = "modules/quests",
        timeline = "modules/timeline",
        reminders = "modules/reminders",
        journal = "modules/journal",
        read = "modules/read",
    }

    local module_path = module_map[tab_id]
    if module_path then
        local module = require(module_path)
        module:show(ui)
    end
end

return Navigation
