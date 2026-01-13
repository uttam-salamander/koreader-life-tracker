--[[--
UI Configuration module for Life Tracker.
Centralizes device-aware UI settings including scaling, colors, and input handling.

Provides:
- Device capability detection (touch, color screen, e-ink, keyboard)
- Scaled dimensions using Screen:scaleBySize()
- Night mode-aware color schemes
- Font size scaling based on DPI
- E-ink refresh mode selection
- Keyboard/DPad navigation helpers

@module lifetracker.ui_config
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Size = require("ui/size")
local Screen = Device.screen

local UIConfig = {
    -- Cached device capabilities (set on first access)
    _capabilities = nil,
    -- Cached scaled dimensions
    _dimensions = nil,
    -- Cached color scheme
    _colors = nil,
}

-- ============================================================================
-- Device Capability Detection
-- ============================================================================

--[[--
Initialize and cache device capabilities.
Called automatically on first capability access.
@treturn table Device capabilities
--]]
function UIConfig:getCapabilities()
    if self._capabilities then
        return self._capabilities
    end

    self._capabilities = {
        -- Input methods
        is_touch = Device:isTouchDevice(),
        has_keys = Device:hasKeys(),
        has_dpad = Device:hasDPad(),
        has_keyboard = Device:hasKeyboard(),

        -- Display capabilities
        has_color = Device:hasColorScreen(),
        is_eink = Device:hasEinkScreen(),
        has_frontlight = Device:hasFrontlight(),
        has_natural_light = Device:hasNaturalLight(),

        -- Hardware features
        can_hw_invert = Device:canHWInvert(),
        can_hw_dither = Device:canHWDither(),

        -- Device type
        is_android = Device:isAndroid(),
        is_kindle = Device:isKindle(),
        is_kobo = Device:isKobo(),
        is_pocketbook = Device:isPocketBook(),
        is_remarkable = Device:isRemarkable(),
        is_emulator = Device:isEmulator(),

        -- Screen info
        screen_dpi = Screen:getDPI(),
        screen_width = Screen:getWidth(),
        screen_height = Screen:getHeight(),
    }

    return self._capabilities
end

--[[--
Check if device has touch input.
@treturn bool
--]]
function UIConfig:isTouchDevice()
    return self:getCapabilities().is_touch
end

--[[--
Check if device has physical keys (for navigation).
@treturn bool
--]]
function UIConfig:hasKeys()
    return self:getCapabilities().has_keys or self:getCapabilities().has_dpad
end

--[[--
Check if device has a color screen.
@treturn bool
--]]
function UIConfig:hasColorScreen()
    local caps = self:getCapabilities()
    return caps.has_color and Screen:isColorEnabled()
end

--[[--
Check if device has e-ink display.
@treturn bool
--]]
function UIConfig:isEinkDevice()
    return self:getCapabilities().is_eink
end

-- ============================================================================
-- Scaled Dimensions
-- ============================================================================

--[[--
Get scaled UI dimensions.
All values are scaled based on screen DPI/size.
@treturn table Scaled dimension values
--]]
function UIConfig:getDimensions()
    if self._dimensions then
        return self._dimensions
    end

    -- Check for high contrast setting
    local Data = require("modules/data")
    local user_settings = Data:loadUserSettings()
    local high_contrast = user_settings.high_contrast == true

    -- Border multiplier for high contrast (2x thicker)
    local border_scale = high_contrast and 2 or 1

    self._dimensions = {
        -- Navigation
        tab_width = Screen:scaleBySize(60),

        -- Touch targets (minimum 44px for accessibility, scaled)
        touch_target_height = Size.item.height_default or Screen:scaleBySize(48),
        button_width = Screen:scaleBySize(50),
        small_button_width = Screen:scaleBySize(35),

        -- Row heights
        row_height = Size.item.height_default or Screen:scaleBySize(50),
        small_row_height = Screen:scaleBySize(40),

        -- Tab dimensions
        type_tab_width = Screen:scaleBySize(80),
        type_tab_height = Screen:scaleBySize(40),
        energy_tab_width = Screen:scaleBySize(90),
        energy_tab_height = Screen:scaleBySize(44),

        -- Progress elements
        progress_width = Screen:scaleBySize(70),
        progress_bar_height = Screen:scaleBySize(4),
        button_gap = Screen:scaleBySize(2),  -- Gap between inline buttons

        -- Grid layout
        grid_columns = 3,  -- Responsive: could adjust based on screen width

        -- Content padding (uses Size module for consistency)
        padding_small = Size.padding.small,
        padding_default = Size.padding.default,
        padding_large = Size.padding.large,
        margin_default = Size.margin.default,

        -- Text heights
        header_height = Screen:scaleBySize(28),
        title_height = Screen:scaleBySize(24),
        greeting_height = Screen:scaleBySize(30),

        -- Borders (thicker in high contrast mode for better visibility)
        border_thin = Size.border.thin * border_scale,
        border_default = Size.border.default * border_scale,
        border_thick = Size.border.thick * border_scale,

        -- Page-level padding (left/right padding for all content pages)
        page_padding = Screen:scaleBySize(12),

        -- ============================================================
        -- Typography Scale (standardized font sizes across all screens)
        -- ============================================================
        font_page_title = 20,       -- Main page headers (Dashboard, Quests, etc.)
        font_section_header = 16,   -- Section titles (Today's Reminders, etc.)
        font_body = 14,             -- Primary content text
        font_body_small = 13,       -- Secondary content, quest titles
        font_caption = 11,          -- Captions, labels, small text
        font_button = 11,           -- Button text (standardized)
        font_stat_value = 20,       -- Large stat numbers
        font_stat_label = 10,       -- Stat labels below values

        -- Button-specific font sizes
        font_button_icon = 16,      -- +/- button icons
        font_button_primary = 12,   -- Done button text
        font_button_secondary = 10, -- Skip button text

        -- Specialized element fonts
        font_nav_button = 18,       -- Day navigation arrows
        font_progress = 11,         -- Progress bar text (3/10)
        font_heatmap_title = 18,    -- Heatmap section title
        font_heatmap_label = 14,    -- Heatmap legend labels
        font_graph = 11,            -- Line graph text (journal)
        font_quote = 14,            -- Daily quote text

        -- ============================================================
        -- Spacing Scale (consistent negative space across all screens)
        -- ============================================================
        spacing_xs = Screen:scaleBySize(4),   -- Between related items (tight)
        spacing_sm = Screen:scaleBySize(8),   -- Between elements in a group
        spacing_md = Screen:scaleBySize(12),  -- Between groups, after tabs
        spacing_lg = Screen:scaleBySize(16),  -- Between sections
        spacing_xl = Screen:scaleBySize(24),  -- Major section breaks

        -- ============================================================
        -- Stat Card Dimensions (for Read page and Dashboard)
        -- ============================================================
        stat_card_height = Screen:scaleBySize(60),
        stat_card_spacing = Screen:scaleBySize(10),

        -- ============================================================
        -- Dialog and Layout Constants
        -- ============================================================
        dialog_width_ratio = 0.8,   -- Standard dialog width (80% of screen)
        row_gap = Screen:scaleBySize(2),     -- Gap between adjacent rows/buttons
        section_gap = Screen:scaleBySize(4), -- Gap between sections
    }

    return self._dimensions
end

--[[--
Get a specific scaled dimension by name.
@tparam string name Dimension name
@treturn number Scaled pixel value
--]]
function UIConfig:dim(name)
    return self:getDimensions()[name]
end

--[[--
Get the available scroll width for content area next to navigation tabs.
This is the full width available for the scrollable container.
@treturn number Scroll width in pixels
--]]
function UIConfig:getScrollWidth()
    local screen_width = Screen:getWidth()
    local tab_width = self:dim("tab_width")
    return screen_width - tab_width
end

--[[--
Get the page padding (left/right padding inside content frames).
@treturn number Page padding in pixels
--]]
function UIConfig:getPagePadding()
    return self:dim("page_padding")
end

--[[--
Get the content width available after page padding.
Use this for sizing elements that should respect left/right padding.
@treturn number Content width in pixels (scroll_width - 2 * page_padding)
--]]
function UIConfig:getPaddedContentWidth()
    return self:getScrollWidth() - self:getPagePadding() * 2
end

--[[--
Scale a pixel value based on screen DPI.
Use this for custom values not in getDimensions().
@tparam number pixels Base pixel value (designed for ~160 DPI)
@treturn number Scaled pixel value
--]]
function UIConfig:scale(pixels)
    return Screen:scaleBySize(pixels)
end

--[[--
Get a standardized font size by semantic name.
@tparam string name Font size name: "page_title", "section_header", "body",
                    "body_small", "caption", "button", "stat_value", "stat_label"
@treturn number Font size value (unscaled, use with UIConfig:getFont())
--]]
function UIConfig:fontSize(name)
    local key = "font_" .. name
    return self:getDimensions()[key] or 14
end

--[[--
Get a standardized spacing value by semantic name.
@tparam string name Spacing name: "xs", "sm", "md", "lg", "xl"
@treturn number Scaled spacing value in pixels
--]]
function UIConfig:spacing(name)
    local key = "spacing_" .. name
    return self:getDimensions()[key] or Size.padding.default
end

--[[--
Invalidate cached dimensions (call on screen resize/rotation or settings change).
--]]
function UIConfig:invalidateDimensions()
    self._dimensions = nil
    self._capabilities = nil  -- Screen dimensions may have changed
    self._font_scale = nil    -- Font scale may depend on dimensions
end

--[[--
Invalidate all cached values (call on settings change for full refresh).
--]]
function UIConfig:invalidateAll()
    self._dimensions = nil
    self._capabilities = nil
    self._colors = nil
    self._font_scale = nil
end

-- ============================================================================
-- Color Scheme
-- ============================================================================

--[[--
Check if night mode is currently active.
@treturn bool
--]]
function UIConfig:isNightMode()
    -- Screen.night_mode is set by KOReader's night mode toggle
    return Screen.night_mode == true
end

--[[--
Get the current color scheme based on night mode, device capabilities, and high contrast setting.
@treturn table Color values for various UI elements
--]]
function UIConfig:getColors()
    -- Check for high contrast setting
    local Data = require("modules/data")
    local user_settings = Data:loadUserSettings()
    local high_contrast = user_settings.high_contrast == true

    -- Check if we need to regenerate colors
    local current_night_mode = self:isNightMode()
    local current_has_color = self:hasColorScreen()

    if self._colors
        and self._colors._night_mode == current_night_mode
        and self._colors._has_color == current_has_color
        and self._colors._high_contrast == high_contrast then
        return self._colors
    end

    local colors = {
        _night_mode = current_night_mode,
        _has_color = current_has_color,
        _high_contrast = high_contrast,
    }

    if current_night_mode then
        -- Night mode colors (inverted)
        colors.background = Blitbuffer.COLOR_BLACK
        colors.foreground = Blitbuffer.COLOR_WHITE
        -- High contrast: use pure white/black, no grays for text
        colors.secondary = high_contrast and Blitbuffer.COLOR_WHITE or Blitbuffer.gray(0.7)
        colors.muted = high_contrast and Blitbuffer.gray(0.8) or Blitbuffer.gray(0.5)
        colors.border = high_contrast and Blitbuffer.COLOR_WHITE or Blitbuffer.gray(0.3)
        colors.highlight_bg = Blitbuffer.COLOR_WHITE
        colors.highlight_fg = Blitbuffer.COLOR_BLACK
        colors.active_bg = Blitbuffer.COLOR_WHITE
        colors.active_fg = Blitbuffer.COLOR_BLACK
        colors.inactive_bg = Blitbuffer.COLOR_BLACK
        colors.inactive_fg = Blitbuffer.COLOR_WHITE
        -- Subtle background for completed items
        colors.completed_bg = high_contrast and Blitbuffer.gray(0.2) or Blitbuffer.gray(0.15)
    else
        -- Day mode colors (normal)
        colors.background = Blitbuffer.COLOR_WHITE
        colors.foreground = Blitbuffer.COLOR_BLACK
        -- High contrast: use pure black for text, stronger borders
        colors.secondary = high_contrast and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.3)
        colors.muted = high_contrast and Blitbuffer.gray(0.2) or Blitbuffer.gray(0.5)
        colors.border = high_contrast and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.8)
        colors.highlight_bg = Blitbuffer.COLOR_BLACK
        colors.highlight_fg = Blitbuffer.COLOR_WHITE
        colors.active_bg = Blitbuffer.COLOR_BLACK
        colors.active_fg = Blitbuffer.COLOR_WHITE
        colors.inactive_bg = Blitbuffer.COLOR_WHITE
        colors.inactive_fg = Blitbuffer.COLOR_BLACK
        -- Subtle background for completed items (more visible in high contrast)
        colors.completed_bg = high_contrast and Blitbuffer.gray(0.9) or Blitbuffer.gray(0.97)
    end

    -- Add color-specific values for color e-readers
    if current_has_color then
        -- Status colors (for quests, progress, etc.)
        colors.success = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#4CAF50") or Blitbuffer.gray(0.3)
        colors.warning = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#FF9800") or Blitbuffer.gray(0.5)
        colors.error = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#F44336") or Blitbuffer.gray(0.6)

        -- Energy level colors
        colors.energy_high = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#4CAF50") or Blitbuffer.gray(0.3)
        colors.energy_medium = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#FF9800") or Blitbuffer.gray(0.5)
        colors.energy_low = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#F44336") or Blitbuffer.gray(0.6)

        -- Heatmap gradient (green tones like GitHub)
        colors.heat_0 = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#EBEDF0") or Blitbuffer.gray(0.9)
        colors.heat_1 = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#9BE9A8") or Blitbuffer.gray(0.7)
        colors.heat_2 = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#40C463") or Blitbuffer.gray(0.5)
        colors.heat_3 = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#30A14E") or Blitbuffer.gray(0.3)
        colors.heat_4 = Blitbuffer.colorFromHex and Blitbuffer.colorFromHex("#216E39") or Blitbuffer.COLOR_BLACK
    else
        -- Grayscale fallbacks for e-ink
        colors.success = Blitbuffer.gray(0.3)
        colors.warning = Blitbuffer.gray(0.5)
        colors.error = Blitbuffer.gray(0.6)

        colors.energy_high = Blitbuffer.gray(0.3)
        colors.energy_medium = Blitbuffer.gray(0.5)
        colors.energy_low = Blitbuffer.gray(0.6)

        -- Heatmap gradient (grayscale)
        if current_night_mode then
            colors.heat_0 = Blitbuffer.gray(0.1)
            colors.heat_1 = Blitbuffer.gray(0.3)
            colors.heat_2 = Blitbuffer.gray(0.5)
            colors.heat_3 = Blitbuffer.gray(0.7)
            colors.heat_4 = Blitbuffer.COLOR_WHITE
        else
            colors.heat_0 = Blitbuffer.gray(0.9)
            colors.heat_1 = Blitbuffer.gray(0.7)
            colors.heat_2 = Blitbuffer.gray(0.5)
            colors.heat_3 = Blitbuffer.gray(0.3)
            colors.heat_4 = Blitbuffer.COLOR_BLACK
        end
    end

    self._colors = colors
    return colors
end

--[[--
Get a specific color by name.
@tparam string name Color name
@treturn Blitbuffer color
--]]
function UIConfig:color(name)
    return self:getColors()[name]
end

--[[--
Invalidate cached colors (call on night mode toggle).
--]]
function UIConfig:invalidateColors()
    self._colors = nil
end

--[[--
Update color scheme after night mode or color rendering change.
--]]
function UIConfig:updateColorScheme()
    self:invalidateColors()
end

-- ============================================================================
-- Font Scaling
-- ============================================================================

-- Cached font scale factor
UIConfig._font_scale = nil

--[[--
Get the font scale factor from KOReader settings.
Syncs with KOReader's "Menu Font Size" setting.
@treturn number Scale factor (default 1.0)
--]]
function UIConfig:getFontScale()
    -- Return cached value if available
    if self._font_scale then
        return self._font_scale
    end

    local scale = 1.0

    -- Try to get KOReader's font size multiplier from G_reader_settings
    local settings = _G.G_reader_settings
    if settings then
        -- KOReader stores font_size as a multiplier (0.8, 1.0, 1.2, etc.)
        -- This is used for menu and UI text sizing
        local font_size = settings:readSetting("font_size")
        if font_size and type(font_size) == "number" then
            -- KOReader font_size is typically in range 12-30, normalize to scale
            -- Default KOReader font size is around 20
            -- We want: 16 -> 0.8x, 20 -> 1.0x, 24 -> 1.2x
            scale = font_size / 20
            -- Clamp to reasonable range
            scale = math.max(0.7, math.min(1.5, scale))
        end

        -- Also check for font_gamma which some KOReader versions use
        local font_gamma = settings:readSetting("font_gamma")
        if font_gamma and type(font_gamma) == "number" and font_gamma > 0 then
            -- font_gamma is a multiplier, typically 1.0
            -- Only apply if it's not the default
            if math.abs(font_gamma - 1.0) > 0.01 then
                scale = scale * font_gamma
            end
        end
    end

    self._font_scale = scale
    return scale
end

--[[--
Invalidate cached font scale (call when KOReader font settings change).
--]]
function UIConfig:invalidateFontScale()
    self._font_scale = nil
end

--[[--
Get a scaled font size.
Respects KOReader's font size settings for consistency.
@tparam number base_size Base font size (designed for ~160 DPI)
@treturn number Scaled font size
--]]
function UIConfig:getFontSize(base_size)
    local scale = self:getFontScale()
    return math.floor(base_size * scale)
end

--[[--
Get a font face with scaled size.
@tparam string font_name Font name from Font.fontmap (e.g., "tfont", "cfont")
@tparam number base_size Base font size
@treturn table Font face object
--]]
function UIConfig:getFont(font_name, base_size)
    return Font:getFace(font_name, self:getFontSize(base_size))
end

-- ============================================================================
-- E-ink Refresh Optimization
-- ============================================================================

--[[--
Get the optimal refresh mode for a given UI context.
@tparam string context The type of UI update:
  - "toggle" - Button/checkbox toggle
  - "scroll" - Scrolling content
  - "button_press" - Button interaction
  - "view_change" - Changing to a different view
  - "tab_change" - Switching tabs
  - "dialog_open" - Opening a dialog
  - "dialog_close" - Closing a dialog
  - "full" - Force full refresh
@treturn string Refresh mode ("partial", "ui", "full")
--]]
function UIConfig:getRefreshMode(context)
    -- Non-e-ink devices don't need special refresh handling
    if not self:isEinkDevice() then
        return "ui"
    end

    local refresh_modes = {
        -- Fast partial refresh for frequent updates
        toggle = "partial",
        scroll = "partial",
        button_press = "partial",

        -- UI refresh for content changes
        view_change = "ui",
        tab_change = "ui",
        dialog_open = "ui",
        dialog_close = "partial",

        -- Full refresh for complete redraws
        full = "full",
    }

    return refresh_modes[context] or "ui"
end

-- ============================================================================
-- Keyboard/DPad Navigation Helpers
-- ============================================================================

--[[--
Create key event handlers for a focusable widget.
@tparam table widget The widget to add key handlers to
@tparam table options Configuration options:
  - items: Array of focusable items
  - on_select: Callback when item is selected (receives item)
  - on_focus_change: Callback when focus changes (receives index, item)
  - on_close: Callback for back/close action
  - initial_focus: Initial focus index (default 1)
@treturn table The modified widget with key handlers
--]]
function UIConfig:setupKeyNavigation(widget, options)
    -- Only set up key navigation for devices with keys
    if not self:hasKeys() then
        return widget
    end

    options = options or {}
    local items = options.items or {}
    local on_select = options.on_select
    local on_focus_change = options.on_focus_change
    local on_close = options.on_close

    -- Initialize focus state
    widget._focus_index = options.initial_focus or 1
    widget._focusable_items = items

    -- Define key events
    widget.key_events = widget.key_events or {}

    -- DPad/Arrow navigation
    widget.key_events.FocusPrev = {
        {"Up"},
        doc = "Focus previous item",
    }
    widget.key_events.FocusNext = {
        {"Down"},
        doc = "Focus next item",
    }
    widget.key_events.Select = {
        {"Press", "Enter", "Space"},
        doc = "Select focused item",
    }
    widget.key_events.Close = {
        {"Back"},
        doc = "Close view",
    }

    -- Optional: Left/Right for tab navigation
    widget.key_events.PrevTab = {
        {"Left"},
        doc = "Previous tab",
    }
    widget.key_events.NextTab = {
        {"Right"},
        doc = "Next tab",
    }

    -- Focus movement helper
    local function moveFocus(direction)
        local old_index = widget._focus_index
        local new_index = old_index + direction

        -- Wrap around
        if new_index < 1 then
            new_index = #items
        elseif new_index > #items then
            new_index = 1
        end

        if new_index ~= old_index and #items > 0 then
            widget._focus_index = new_index
            if on_focus_change then
                on_focus_change(new_index, items[new_index])
            end
            return true
        end
        return false
    end

    -- Event handlers
    function widget:onFocusPrev()
        return moveFocus(-1)
    end

    function widget:onFocusNext()
        return moveFocus(1)
    end

    function widget:onSelect()
        local index = self._focus_index
        if index > 0 and index <= #items and on_select then
            on_select(items[index])
            return true
        end
        return false
    end

    function widget:onClose()
        if on_close then
            on_close()
            return true
        end
        return false
    end

    return widget
end

--[[--
Get a visual focus indicator frame style.
@tparam bool is_focused Whether the item is currently focused
@treturn table Style options for FrameContainer
--]]
function UIConfig:getFocusStyle(is_focused)
    local colors = self:getColors()

    if is_focused then
        return {
            bordersize = Size.border.thick,
            color = colors.foreground,
            background = colors.background,
        }
    else
        return {
            bordersize = Size.border.thin,
            color = colors.border,
            background = colors.background,
        }
    end
end

-- ============================================================================
-- Safe Zone Calculations
-- ============================================================================

--[[--
Get the top safe zone height (reserved for KOReader system gestures).
@treturn number Pixel height of safe zone
--]]
function UIConfig:getTopSafeZone()
    local screen_height = Screen:getHeight()
    -- Reserve top 10-12.5% for KOReader menu access
    return math.floor(screen_height * 0.1)
end

--[[--
Get the corner gesture exclusion size.
@treturn number Pixel size for corner exclusion zones
--]]
function UIConfig:getCornerSize()
    local screen_width = Screen:getWidth()
    return math.floor(screen_width / 8)
end

--[[--
Get the content width available after navigation tabs.
@treturn number Available content width in pixels
--]]
function UIConfig:getContentWidth()
    return Screen:getWidth() - self:dim("tab_width") - self:dim("padding_large") * 2
end

--[[--
Get the content height available after safe zone.
@treturn number Available content height in pixels
--]]
function UIConfig:getContentHeight()
    return Screen:getHeight() - self:getTopSafeZone()
end

-- ============================================================================
-- Coordinate Transformation Helpers
-- ============================================================================

--[[--
Calculate the Y offset to convert content-relative coordinates to screen coordinates.
This accounts for frame padding and scroll position.

The issue: GestureRange expects screen-absolute coordinates, but content Y positions
are tracked relative to the VerticalGroup inside a FrameContainer with padding.

@tparam number frame_padding The padding applied to the content frame (default: Size.padding.large)
@treturn number Y offset to add to content-relative Y when creating GestureRange
--]]
function UIConfig:getFrameYOffset(frame_padding)
    return frame_padding or Size.padding.large
end

--[[--
Convert a screen tap Y coordinate to content-relative Y coordinate.
This is the inverse transformation for tap detection.

@tparam number screen_y The screen Y coordinate from ges.pos.y
@tparam number frame_padding The padding applied to the content frame
@tparam table scroll_container Optional ScrollableContainer instance
@treturn number Content-relative Y coordinate
--]]
function UIConfig:screenToContentY(screen_y, frame_padding, scroll_container)
    frame_padding = frame_padding or Size.padding.large

    -- Get scroll offset (how much content has scrolled up)
    local scroll_offset = 0
    if scroll_container then
        -- Try to get scroll position - use private field as fallback
        if scroll_container._scroll_offset_y then
            scroll_offset = scroll_container._scroll_offset_y
        end
    end

    -- Convert: subtract frame padding (widget starts after padding),
    -- then add scroll offset (scrolled content has higher content Y)
    return screen_y - frame_padding + scroll_offset
end

--[[--
Convert a content-relative Y coordinate to screen Y coordinate.
Use this when creating GestureRange from content positions.

@tparam number content_y The content-relative Y coordinate
@tparam number frame_padding The padding applied to the content frame
@tparam table scroll_container Optional ScrollableContainer instance
@treturn number Screen Y coordinate for GestureRange
--]]
function UIConfig:contentToScreenY(content_y, frame_padding, scroll_container)
    frame_padding = frame_padding or Size.padding.large

    -- Get scroll offset
    local scroll_offset = 0
    if scroll_container then
        if scroll_container._scroll_offset_y then
            scroll_offset = scroll_container._scroll_offset_y
        end
    end

    -- Convert: add frame padding, subtract scroll offset
    return content_y + frame_padding - scroll_offset
end

return UIConfig
