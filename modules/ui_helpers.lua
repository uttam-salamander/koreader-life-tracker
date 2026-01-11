--[[--
UI Helpers module for Life Tracker.
Centralizes common UI patterns: gesture handlers, layout builders, page headers.
Eliminates code duplication across dashboard, quests, timeline, reminders, journal modules.

@module lifetracker.ui_helpers
--]]

local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")

local Navigation = require("modules/navigation")
local UIConfig = require("modules/ui_config")

local UIHelpers = {}

-- ============================================================================
-- Gesture Helpers
-- ============================================================================

--[[--
Dispatch a corner gesture to the user's configured action.
KOReader stores gesture settings in the gestures module.
This is called by corner tap handlers to execute user-configured actions.

@param ui The KOReader UI reference (module.ui)
@param gesture_name string The gesture name (e.g., "tap_top_left_corner")
@return bool True if gesture was handled
--]]
function UIHelpers.dispatchCornerGesture(ui, gesture_name)
    -- Try to access KOReader's gesture module for user settings
    if ui and ui.gestures then
        local gesture_manager = ui.gestures
        -- Check if user has a gesture configured
        local settings = gesture_manager.gestures or {}
        local action = settings[gesture_name]
        if action then
            -- Dispatch the action
            local Dispatcher = require("dispatcher")
            Dispatcher:execute(action)
            return true
        end
    end

    -- Fallback: try common corner actions directly via event
    if gesture_name == "tap_top_right_corner" then
        ui:handleEvent(Event:new("ToggleFrontlight"))
        return true
    elseif gesture_name == "tap_top_left_corner" then
        ui:handleEvent(Event:new("ToggleBookmark"))
        return true
    end

    -- No action configured, let gesture pass through
    return false
end

--[[--
Setup corner gesture handlers on a widget.
Sets up 5 zones: TopCenter (menu), TopLeft, TopRight, BottomLeft, BottomRight.
Uses the module's ui reference for dispatching.

@param widget InputContainer The widget to add handlers to
@param module_self table The module instance (must have .ui property)
@param dims table {screen_width, screen_height, top_safe_zone}
--]]
function UIHelpers.setupCornerGestures(widget, module_self, dims)
    local screen_width = dims.screen_width
    local screen_height = dims.screen_height
    local top_safe_zone = dims.top_safe_zone

    -- KOReader gesture zone dimensions (from defaults.lua)
    local corner_size = UIConfig:getCornerSize()
    local corner_height = UIConfig:getTopSafeZone()

    -- Top CENTER zone tap handler - Opens KOReader menu (excludes corners)
    widget.ges_events.TopCenterTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = corner_size,  -- Start after top-left corner
                y = 0,
                w = screen_width - corner_size * 2,  -- Exclude both corners
                h = top_safe_zone,
            },
        },
    }
    widget.onTopCenterTap = function()
        -- Show KOReader's reader menu by sending event
        if module_self.ui and module_self.ui.menu then
            module_self.ui.menu:onShowMenu()
        else
            -- Fallback: send event through UI manager
            module_self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Top-left corner tap handler - Dispatch to user's corner action
    widget.ges_events.TopLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = 0,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    widget.onTopLeftCornerTap = function()
        return UIHelpers.dispatchCornerGesture(module_self.ui, "tap_top_left_corner")
    end

    -- Top-right corner tap handler - Dispatch to user's corner action
    widget.ges_events.TopRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = screen_width - corner_size,
                y = 0,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    widget.onTopRightCornerTap = function()
        return UIHelpers.dispatchCornerGesture(module_self.ui, "tap_top_right_corner")
    end

    -- Bottom-left corner tap handler
    widget.ges_events.BottomLeftCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = screen_height - corner_height,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    widget.onBottomLeftCornerTap = function()
        return UIHelpers.dispatchCornerGesture(module_self.ui, "tap_bottom_left_corner")
    end

    -- Bottom-right corner tap handler
    widget.ges_events.BottomRightCornerTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = screen_width - corner_size,
                y = screen_height - corner_height,
                w = corner_size,
                h = corner_height,
            },
        },
    }
    widget.onBottomRightCornerTap = function()
        return UIHelpers.dispatchCornerGesture(module_self.ui, "tap_bottom_right_corner")
    end
end

--[[--
Setup swipe-to-close gesture handler on a widget.
Swipe east (right) to close the current view.

@param widget InputContainer The widget to add handler to
@param close_callback function Function to call when closing
@param dims table {screen_width, screen_height, top_safe_zone}
--]]
function UIHelpers.setupSwipeToClose(widget, close_callback, dims)
    local screen_width = dims.screen_width
    local screen_height = dims.screen_height
    local top_safe_zone = dims.top_safe_zone

    widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            -- Only capture swipes below top 1/8 zone (leave for KOReader)
            range = Geom:new{
                x = 0,
                y = top_safe_zone,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height - top_safe_zone,
            },
        },
    }
    widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            close_callback()
            return true
        end
        return false
    end
end

-- ============================================================================
-- Layout Builders (available for future consolidation, not currently used)
-- ============================================================================

--[[--
Build the main layout for a page with content and navigation tabs.
Returns the InputContainer widget and a reference to the ScrollableContainer.

@param content VerticalGroup The page content
@param tab_id string Current tab ID ("dashboard", "quests", etc.)
@param screen_dims table {screen_width, screen_height}
@param ui table KOReader UI reference
@param on_close function Function to close the current widget
@return InputContainer, ScrollableContainer The main widget and scrollable container reference
--]]
function UIHelpers.buildMainLayout(content, tab_id, screen_dims, ui, on_close)
    local screen_width = screen_dims.screen_width
    local screen_height = screen_dims.screen_height

    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local scroll_height = screen_height

    -- Inner frame with padding
    local inner_frame = FrameContainer:new{
        width = scroll_width,
        height = math.max(scroll_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    -- Scrollable container as the outer wrapper
    local scrollable_container = ScrollableContainer:new{
        dimen = Geom:new{ w = scroll_width, h = scroll_height },
        inner_frame,
    }

    -- Tab change callback
    local function on_tab_change(tab_id_new)
        on_close()
        Navigation:navigateTo(tab_id_new, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn(tab_id, screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create main layout
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        scrollable_container,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Standard InputContainer
    local main_widget = InputContainer:new{
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
    scrollable_container.show_parent = main_widget

    return main_widget, scrollable_container
end

--[[--
Build a standard page header with title and optional subtitle.
Handles safe zone spacing automatically.

@param title string The page title
@param options table Optional: {subtitle, greeting, top_safe_zone, content_width}
@return VerticalGroup, number The header widgets and visual_y position after header
--]]
function UIHelpers.buildPageHeader(title, options)
    options = options or {}
    local top_safe_zone = options.top_safe_zone or UIConfig:getTopSafeZone()

    local header = VerticalGroup:new{ align = "left" }
    local visual_y = Size.padding.large

    -- Main title
    local title_widget = TextWidget:new{
        text = title,
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    }
    table.insert(header, title_widget)
    visual_y = visual_y + title_widget:getSize().h

    -- Optional subtitle (used for greeting + quote on dashboard)
    if options.subtitle then
        table.insert(header, VerticalSpan:new{ width = UIConfig:spacing("xs") })
        visual_y = visual_y + UIConfig:spacing("xs")

        local subtitle_widget = TextWidget:new{
            text = options.subtitle,
            face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
            fgcolor = UIConfig:color("muted"),
            max_width = options.content_width,
        }
        table.insert(header, subtitle_widget)
        visual_y = visual_y + subtitle_widget:getSize().h
    end

    -- Add spacer to push interactive content below top_safe_zone
    local spacer_needed = top_safe_zone - visual_y
    if spacer_needed > 0 then
        table.insert(header, VerticalSpan:new{ width = spacer_needed })
        visual_y = visual_y + spacer_needed
    end

    -- Standard spacing after header
    table.insert(header, VerticalSpan:new{ width = UIConfig:spacing("md") })
    visual_y = visual_y + UIConfig:spacing("md")

    return header, visual_y
end

return UIHelpers
