--[[--
Navigation module for Life Tracker.
Provides a bullet journal-style right-side tab navigation.
@module lifetracker.navigation
--]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = require("device").screen
local _ = require("gettext")

local Navigation = {}

-- Tab definitions with short labels and full names
Navigation.TABS = {
    {id = "dashboard", label = "Dash", full = _("Dashboard")},
    {id = "quests",    label = "Quest", full = _("Quests")},
    {id = "timeline",  label = "Time", full = _("Timeline")},
    {id = "reminders", label = "Rem", full = _("Reminders")},
    {id = "journal",   label = "Jrnl", full = _("Journal")},
}

-- Tab width for the right sidebar
Navigation.TAB_WIDTH = 50

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
    local tab_width = self.TAB_WIDTH
    local content_width = screen_width - tab_width

    -- Store callback
    self.on_tab_change = on_tab_change

    -- Build tab column
    local tabs = self:buildTabColumn(current_tab, screen_height)

    -- Build main layout: content on left, tabs on right
    local layout = HorizontalGroup:new{
        align = "top",
        -- Main content (shrunk to fit)
        FrameContainer:new{
            width = content_width,
            height = screen_height,
            padding = 0,
            bordersize = 0,
            content,
        },
        -- Tab column
        tabs,
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
    local tabs_group = VerticalGroup:new{ align = "center" }

    for _, tab in ipairs(self.TABS) do
        local is_active = (tab.id == current_tab)

        -- Tab background styling
        local bg_color = is_active and 0x000000 or 0xEEEEEE
        local fg_color = is_active and 0xFFFFFF or 0x000000
        local border_size = is_active and 0 or 1

        -- Create tab label (vertical text simulation using short labels)
        local label = TextWidget:new{
            text = tab.label,
            face = Font:getFace("tfont", 12),
            fgcolor = fg_color,
            bold = is_active,
        }

        -- Wrap in container
        local tab_frame = FrameContainer:new{
            width = self.TAB_WIDTH,
            height = tab_height,
            padding = Size.padding.small,
            bordersize = border_size,
            background = bg_color,
            CenterContainer:new{
                dimen = {w = self.TAB_WIDTH - Size.padding.small * 2, h = tab_height - Size.padding.small * 2},
                label,
            },
        }

        -- Make tappable
        local tab_button = InputContainer:new{
            dimen = {w = self.TAB_WIDTH, h = tab_height},
            ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = {x = 0, y = 0, w = self.TAB_WIDTH, h = tab_height},
                    },
                },
            },
            tab_frame,
        }

        -- Store tab ID for callback
        tab_button.tab_id = tab.id
        tab_button.onTap = function()
            if self.on_tab_change and tab.id ~= current_tab then
                self.on_tab_change(tab.id)
            end
            return true
        end

        table.insert(tabs_group, tab_button)
    end

    return tabs_group
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

    -- Wrap content with tabs
    local wrapped = self:wrap(content, current_tab, on_tab_change)

    -- Create full-screen container with gesture handling
    local container = InputContainer:new{
        dimen = Screen:getSize(),
        ges_events = {
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Screen:getSize(),
                },
            },
        },
        FrameContainer:new{
            width = screen_width,
            height = screen_height,
            padding = 0,
            bordersize = 0,
            background = 0xFFFFFF,
            wrapped,
        },
    }

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
    }

    local module_path = module_map[tab_id]
    if module_path then
        local module = require(module_path)
        module:show(ui)
    end
end

return Navigation
