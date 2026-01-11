--[[--
Settings module for Life Tracker.
Manages user preferences for energy categories, time slots, and display options.
Displays as a full-page view (not a popup) to avoid stacking issues.

@module lifetracker.settings
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
-- HorizontalGroup available if needed for future layouts
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
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

local Celebration = require("modules/celebration")
local Data = require("modules/data")
local Navigation = require("modules/navigation")
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")

local Settings = {}

-- Row height for settings items
local function getRowHeight()
    return UIConfig:dim("touch_target_height")
end

--[[--
Create a settings row with label and optional value/status.
@tparam string label The setting label
@tparam string|nil value Optional value to display on the right
@tparam boolean|nil is_checked Optional checked state for toggles
@tparam function callback Function to call when tapped
@tparam number width Available width
@treturn Widget The settings row widget
--]]
function Settings:createSettingsRow(label, _value, _is_checked, callback, width)
    -- Create a button that spans the full width
    return Button:new{
        text = label,
        width = width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = 0,
        padding = Size.padding.default,
        bordersize = 0,
        callback = callback,
    }
end

--[[--
Create a section header.
@tparam string title Section title
@tparam number width Available width
@treturn Widget Section header widget
--]]
function Settings:createSectionHeader(title, width)
    local content = VerticalGroup:new{align = "left"}

    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})
    table.insert(content, TextWidget:new{
        text = title,
        face = UIConfig:getFont("tfont", UIConfig:fontSize("section_header")),
        fgcolor = UIConfig:color("foreground"),
        bold = true,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w = width, h = 1},
        background = UIConfig:color("muted"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("sm")})

    return content
end

--[[--
Show the settings page as a full-screen view.
@tparam table ui The UI manager reference
--]]
function Settings:show(ui)
    self.ui = ui
    self:showSettingsView()
end

--[[--
Build and display the settings view.
--]]
function Settings:showSettingsView()
    local user_settings = Data:loadUserSettings()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local content_width = scroll_width - Size.padding.large * 3
    local button_width = content_width

    local content = VerticalGroup:new{align = "left"}

    -- Page title
    table.insert(content, TextWidget:new{
        text = _("Settings"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("lg")})

    -- ===== Customization Section =====
    table.insert(content, self:createSectionHeader(_("Customization"), content_width))

    table.insert(content, Button:new{
        text = _("Energy Categories"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:showEnergyCategoriesMenu(self.ui, user_settings)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    table.insert(content, Button:new{
        text = _("Time Slots"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:showTimeSlotsMenu(self.ui, user_settings)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    table.insert(content, Button:new{
        text = _("Daily Quotes"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:showQuotesMenu(self.ui, user_settings)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    table.insert(content, Button:new{
        text = _("Celebration Animations"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:showCelebrationMenu(self.ui)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    -- ===== Display Section =====
    table.insert(content, self:createSectionHeader(_("Display"), content_width))

    -- Sleep Screen Dashboard toggle
    local sleep_enabled = user_settings.sleep_screen_enabled == true
    table.insert(content, Button:new{
        text = sleep_enabled and _("Sleep Screen Dashboard [ON]") or _("Sleep Screen Dashboard [OFF]"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        preselect = sleep_enabled,
        callback = function()
            local currently_enabled = user_settings.sleep_screen_enabled == true
            local action_text = currently_enabled
                and _("Disable Sleep Screen Dashboard?")
                or _("Enable Sleep Screen Dashboard?")
            local description = currently_enabled
                and _("The default KOReader screensaver will be used when device sleeps.")
                or _("Life Tracker dashboard will be shown when device sleeps.")

            UIManager:show(ConfirmBox:new{
                text = action_text .. "\n\n" .. description,
                ok_text = currently_enabled and _("Disable") or _("Enable"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    user_settings.sleep_screen_enabled = not currently_enabled
                    Data:saveUserSettings(user_settings)
                    UIManager:close(self.settings_widget)
                    self:showSettingsView()
                end,
            })
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    -- Large Touch Targets toggle
    local large_targets = user_settings.large_touch_targets == true
    table.insert(content, Button:new{
        text = large_targets and _("Large Touch Targets [ON]") or _("Large Touch Targets [OFF]"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        preselect = large_targets,
        callback = function()
            user_settings.large_touch_targets = not user_settings.large_touch_targets
            Data:saveUserSettings(user_settings)
            UIConfig:invalidateDimensions()
            UIManager:close(self.settings_widget)
            self:showSettingsView()
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    -- High Contrast Mode toggle
    local high_contrast = user_settings.high_contrast == true
    table.insert(content, Button:new{
        text = high_contrast and _("High Contrast Mode [ON]") or _("High Contrast Mode [OFF]"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        preselect = high_contrast,
        callback = function()
            user_settings.high_contrast = not user_settings.high_contrast
            Data:saveUserSettings(user_settings)
            UIConfig:updateColorScheme()
            UIManager:close(self.settings_widget)
            self:showSettingsView()
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    -- ===== Data Section =====
    table.insert(content, self:createSectionHeader(_("Data"), content_width))

    table.insert(content, Button:new{
        text = _("Backup Data"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:createBackup(self.ui)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    table.insert(content, Button:new{
        text = _("Restore Data"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:showRestoreMenu(self.ui)
        end,
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("xs")})

    table.insert(content, Button:new{
        text = _("Reset All Data"),
        width = button_width,
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        margin = Size.margin.small,
        padding = Size.padding.default,
        callback = function()
            self:confirmResetData(self.ui)
        end,
    })

    -- Bottom padding
    table.insert(content, VerticalSpan:new{width = Size.padding.large * 2})

    -- Wrap content in scrollable frame
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local inner_frame = FrameContainer:new{
        width = scroll_width - scrollbar_width,
        height = math.max(screen_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = scroll_width, h = screen_height},
        inner_frame,
    }
    self.scrollable_container = scrollable

    -- Tab change callback
    local ui = self.ui
    local settings = self
    local function on_tab_change(tab_id)
        UIManager:close(settings.settings_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs (settings not in nav, but we still show tabs)
    local tabs = Navigation:buildTabColumn(nil, screen_height)  -- nil = no active tab
    Navigation.on_tab_change = on_tab_change

    -- Main layout
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        scrollable,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Create widget with gestures
    self.settings_widget = InputContainer:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        },
        ges_events = {},
        main_layout,
    }

    -- Set show_parent for ScrollableContainer
    self.scrollable_container.show_parent = self.settings_widget

    -- Setup corner gestures
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = UIConfig:getTopSafeZone(),
    }
    UIHelpers.setupCornerGestures(self.settings_widget, self, gesture_dims)

    -- Setup swipe-to-close
    UIHelpers.setupSwipeToClose(self.settings_widget, function()
        UIManager:close(self.settings_widget)
    end, gesture_dims)

    UIManager:show(self.settings_widget)
end

--[[--
Dispatch corner gesture to UI.
Required by UIHelpers.setupCornerGestures.
--]]
function Settings:dispatchCornerGesture(gesture_name)
    UIHelpers.dispatchCornerGesture(self.ui, gesture_name)
end

--[[--
Show energy categories configuration.
--]]
function Settings:showEnergyCategoriesMenu(ui, user_settings)
    local items = {}

    -- Current categories
    for i, category in ipairs(user_settings.energy_categories) do
        table.insert(items, {
            text = category,
            callback = function()
                self:editEnergyCategory(ui, user_settings, i)
            end,
        })
    end

    -- Add new category
    table.insert(items, {
        text = _("[+] Add Category"),
        callback = function()
            self:addEnergyCategory(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Energy Categories"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Edit an existing energy category.
--]]
function Settings:editEnergyCategory(ui, user_settings, index)
    local current = user_settings.energy_categories[index]

    local dialog
    dialog = ButtonDialog:new{
        title = current,
        buttons = {
            {{
                text = _("Rename"),
                callback = function()
                    UIManager:close(dialog)
                    self:renameEnergyCategory(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    if #user_settings.energy_categories > 1 then
                        table.remove(user_settings.energy_categories, index)
                        Data:saveUserSettings(user_settings)
                        UIManager:show(InfoMessage:new{
                            text = _("Category deleted"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Cannot delete last category"),
                            timeout = 2,
                        })
                    end
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Rename an energy category.
--]]
function Settings:renameEnergyCategory(ui, user_settings, index)
    local current = user_settings.energy_categories[index]

    local dialog
    dialog = InputDialog:new{
        title = _("Rename Category"),
        input = current,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
                    if new_name and new_name ~= "" then
                        user_settings.energy_categories[index] = new_name
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Add a new energy category.
--]]
function Settings:addEnergyCategory(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("New Energy Category"),
        input = "",
        input_hint = _("e.g., Focused, Tired, Anxious"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
                    if new_name and new_name ~= "" then
                        table.insert(user_settings.energy_categories, new_name)
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showEnergyCategoriesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Show time slots configuration.
--]]
function Settings:showTimeSlotsMenu(ui, user_settings)
    local items = {}

    -- Current time slots
    for i, slot in ipairs(user_settings.time_slots) do
        table.insert(items, {
            text = slot,
            callback = function()
                self:editTimeSlot(ui, user_settings, i)
            end,
        })
    end

    -- Add new slot
    table.insert(items, {
        text = _("[+] Add Time Slot"),
        callback = function()
            self:addTimeSlot(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Time Slots"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Edit an existing time slot.
--]]
function Settings:editTimeSlot(ui, user_settings, index)
    local current = user_settings.time_slots[index]

    local dialog
    dialog = ButtonDialog:new{
        title = current,
        buttons = {
            {{
                text = _("Rename"),
                callback = function()
                    UIManager:close(dialog)
                    self:renameTimeSlot(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    if #user_settings.time_slots > 1 then
                        table.remove(user_settings.time_slots, index)
                        Data:saveUserSettings(user_settings)
                        UIManager:show(InfoMessage:new{
                            text = _("Time slot deleted"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Cannot delete last time slot"),
                            timeout = 2,
                        })
                    end
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Rename a time slot.
--]]
function Settings:renameTimeSlot(ui, user_settings, index)
    local current = user_settings.time_slots[index]

    local dialog
    dialog = InputDialog:new{
        title = _("Rename Time Slot"),
        input = current,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
                    if new_name and new_name ~= "" then
                        user_settings.time_slots[index] = new_name
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Add a new time slot.
--]]
function Settings:addTimeSlot(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("New Time Slot"),
        input = "",
        input_hint = _("e.g., Early Morning, Late Night"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    -- Sanitize input
                    local new_name = Data:sanitizeTextInput(dialog:getInputText(), 50)
                    if new_name and new_name ~= "" then
                        table.insert(user_settings.time_slots, new_name)
                        Data:saveUserSettings(user_settings)
                    end
                    UIManager:close(dialog)
                    self:showTimeSlotsMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- Daily Quotes Functions
-- ============================================

-- Maximum quote length
local MAX_QUOTE_LENGTH = 200

--[[--
Show quotes management menu.
--]]
function Settings:showQuotesMenu(ui, user_settings)
    local items = {}

    -- Current quotes
    local quotes = user_settings.quotes or {}
    for i, quote in ipairs(quotes) do
        -- Truncate long quotes for menu display
        local display_text = quote
        if #quote > 50 then
            display_text = quote:sub(1, 47) .. "..."
        end
        table.insert(items, {
            text = display_text,
            callback = function()
                self:showQuoteOptions(ui, user_settings, i)
            end,
        })
    end

    -- Add new quote option
    table.insert(items, {
        text = _("[+] Add New Quote"),
        callback = function()
            self:addNewQuote(ui, user_settings)
        end,
    })

    local menu
    menu = Menu:new{
        title = _("Daily Quotes"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show options for a specific quote (edit/delete).
--]]
function Settings:showQuoteOptions(ui, user_settings, index)
    local quote = user_settings.quotes[index]
    local dialog
    dialog = ButtonDialog:new{
        title = quote,
        buttons = {
            {{
                text = _("Edit"),
                callback = function()
                    UIManager:close(dialog)
                    self:editQuote(ui, user_settings, index)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    table.remove(user_settings.quotes, index)
                    Data:saveUserSettings(user_settings)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote deleted"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Add a new quote.
--]]
function Settings:addNewQuote(ui, user_settings)
    local dialog
    dialog = InputDialog:new{
        title = _("Add Quote"),
        input = "",
        input_hint = _("Enter your quote (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    local quote = Data:sanitizeTextInput(dialog:getInputText(), MAX_QUOTE_LENGTH)
                    if not quote or quote == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a quote"),
                            timeout = 2,
                        })
                        return
                    end
                    if not user_settings.quotes then
                        user_settings.quotes = {}
                    end
                    table.insert(user_settings.quotes, quote)
                    Data:saveUserSettings(user_settings)
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote added!"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--[[--
Edit an existing quote.
--]]
function Settings:editQuote(ui, user_settings, index)
    local dialog
    dialog = InputDialog:new{
        title = _("Edit Quote"),
        input = user_settings.quotes[index],
        input_hint = _("Enter your quote (max 200 chars)"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local quote = Data:sanitizeTextInput(dialog:getInputText(), MAX_QUOTE_LENGTH)
                    if not quote or quote == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a quote"),
                            timeout = 2,
                        })
                        return
                    end
                    user_settings.quotes[index] = quote
                    Data:saveUserSettings(user_settings)
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Quote updated!"),
                        timeout = 2,
                    })
                    self:showQuotesMenu(ui, user_settings)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- Celebration Settings Functions
-- ============================================

--[[--
Show celebration settings menu.
--]]
function Settings:showCelebrationMenu(ui)
    local settings = Celebration:getSettings()
    local animations = Celebration:getAnimationList()

    local menu  -- Declare early for closure access
    local items = {}

    -- Enable/disable toggle
    table.insert(items, {
        text = settings.enabled and _("Celebrations: ON") or _("Celebrations: OFF"),
        callback = function()
            settings.enabled = not settings.enabled
            Celebration:saveSettings(settings)
            UIManager:show(InfoMessage:new{
                text = settings.enabled and _("Celebrations enabled") or _("Celebrations disabled"),
                timeout = 2,
            })
            UIManager:close(menu)
            self:showCelebrationMenu(ui)
        end,
    })

    -- Animation selection
    local current_anim = settings.selected_animation or _("Random")
    table.insert(items, {
        text = _("Animation: ") .. current_anim,
        callback = function()
            UIManager:close(menu)
            self:showAnimationSelector(ui, settings, animations)
        end,
    })

    -- Animation speed
    local speed_labels = {
        [0.05] = _("Fast (20 fps)"),
        [0.1] = _("Normal (10 fps)"),
        [0.15] = _("Slow (7 fps)"),
        [0.2] = _("Very Slow (5 fps)"),
    }
    local current_speed = speed_labels[settings.frame_delay] or string.format("%.0f ms", settings.frame_delay * 1000)
    table.insert(items, {
        text = _("Speed: ") .. current_speed,
        callback = function()
            UIManager:close(menu)
            self:showSpeedSelector(ui, settings)
        end,
    })

    -- Display duration
    table.insert(items, {
        text = string.format(_("Duration: %.1f seconds"), settings.timeout),
        callback = function()
            UIManager:close(menu)
            self:showDurationSelector(ui, settings)
        end,
    })

    -- Preview animation
    if #animations > 0 then
        table.insert(items, {
            text = _("Preview Animation"),
            callback = function()
                Celebration:showCompletion(_("Preview!"))
            end,
        })
    end

    menu = Menu:new{
        title = _("Celebration Animations"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show animation selector.
--]]
function Settings:showAnimationSelector(ui, settings, animations)
    local items = {}

    -- Random option
    table.insert(items, {
        text = settings.selected_animation == nil and _("Random (selected)") or _("Random"),
        callback = function()
            settings.selected_animation = nil
            Celebration:saveSettings(settings)
            UIManager:show(InfoMessage:new{
                text = _("Animation set to random"),
                timeout = 2,
            })
            self:showCelebrationMenu(ui)
        end,
    })

    -- List each animation
    for _, anim in ipairs(animations) do
        local is_selected = settings.selected_animation == anim.filename
        table.insert(items, {
            text = is_selected and (anim.display_name .. _(" (selected)")) or anim.display_name,
            callback = function()
                settings.selected_animation = anim.filename
                Celebration:saveSettings(settings)
                UIManager:show(InfoMessage:new{
                    text = _("Animation selected: ") .. anim.display_name,
                    timeout = 2,
                })
                self:showCelebrationMenu(ui)
            end,
        })
    end

    local menu
    menu = Menu:new{
        title = _("Select Animation"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:showCelebrationMenu(ui)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show animation speed selector.
--]]
function Settings:showSpeedSelector(ui, settings)
    local speeds = {
        { delay = 0.05, label = _("Fast (20 fps)") },
        { delay = 0.1, label = _("Normal (10 fps)") },
        { delay = 0.15, label = _("Slow (7 fps)") },
        { delay = 0.2, label = _("Very Slow (5 fps)") },
    }

    local items = {}
    for _, speed in ipairs(speeds) do
        local is_selected = math.abs(settings.frame_delay - speed.delay) < 0.01
        table.insert(items, {
            text = is_selected and (speed.label .. _(" (selected)")) or speed.label,
            callback = function()
                settings.frame_delay = speed.delay
                Celebration:saveSettings(settings)
                UIManager:show(InfoMessage:new{
                    text = _("Speed set to: ") .. speed.label,
                    timeout = 2,
                })
                self:showCelebrationMenu(ui)
            end,
        })
    end

    local menu
    menu = Menu:new{
        title = _("Animation Speed"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:showCelebrationMenu(ui)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show display duration selector.
--]]
function Settings:showDurationSelector(ui, settings)
    local durations = {
        { time = 1.5, label = _("1.5 seconds") },
        { time = 2.0, label = _("2 seconds") },
        { time = 3.0, label = _("3 seconds") },
        { time = 5.0, label = _("5 seconds") },
        { time = 10.0, label = _("10 seconds") },
    }

    local items = {}
    for _, dur in ipairs(durations) do
        local is_selected = math.abs(settings.timeout - dur.time) < 0.1
        table.insert(items, {
            text = is_selected and (dur.label .. _(" (selected)")) or dur.label,
            callback = function()
                settings.timeout = dur.time
                Celebration:saveSettings(settings)
                UIManager:show(InfoMessage:new{
                    text = _("Duration set to: ") .. dur.label,
                    timeout = 2,
                })
                self:showCelebrationMenu(ui)
            end,
        })
    end

    local menu
    menu = Menu:new{
        title = _("Display Duration"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
            self:showCelebrationMenu(ui)
        end,
    }
    UIManager:show(menu)
end

-- ============================================
-- Backup & Restore Functions
-- ============================================

--[[--
Create a backup of all plugin data.
--]]
function Settings:createBackup(_ui)
    local ok, result = Data:exportBackupToFile()

    if ok then
        -- Extract filename and show backup location
        local filename = result:match("([^/]+)$")
        local backup_dir = Data:getBackupDir()
        UIManager:show(InfoMessage:new{
            text = _("Backup created successfully!\n\nFile: ") .. filename .. _("\n\nLocation: ") .. backup_dir,
            timeout = 6,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Backup failed: ") .. (result or "Unknown error"),
            timeout = 5,
        })
    end
end

--[[--
Show menu to restore from available backups.
--]]
function Settings:showRestoreMenu(ui)
    local backups = Data:listBackups()

    if #backups == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No backups found.\n\nCreate a backup first using 'Backup Data'."),
            timeout = 4,
        })
        return
    end

    local items = {}
    local menu
    local navigating_away = false  -- Flag to prevent close_callback from showing settings

    for _, backup in ipairs(backups) do
        -- Format size in KB
        local size_kb = string.format("%.1f KB", (backup.size or 0) / 1024)
        table.insert(items, {
            text = backup.created_at .. " (" .. size_kb .. ")",
            callback = function()
                navigating_away = true
                UIManager:close(menu)
                self:confirmRestore(ui, backup)
            end,
            hold_callback = function()
                navigating_away = true
                UIManager:close(menu)
                self:showBackupOptions(ui, backup)
            end,
        })
    end

    menu = Menu:new{
        title = _("Select Backup to Restore"),
        item_table = items,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--[[--
Show options for a backup (restore or delete).
--]]
function Settings:showBackupOptions(ui, backup)
    local dialog
    dialog = ButtonDialog:new{
        title = backup.created_at,
        buttons = {
            {{
                text = _("Restore"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmRestore(ui, backup)
                end,
            }},
            {{
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    self:confirmDeleteBackup(ui, backup)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                    self:showRestoreMenu(ui)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

--[[--
Confirm restoration from a backup.
--]]
function Settings:confirmRestore(ui, backup)
    UIManager:show(ConfirmBox:new{
        text = _("Restore from backup?\n\nThis will replace all current data with:\n") .. backup.created_at,
        ok_text = _("Restore"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local ok, result = Data:importBackupFromFile(backup.filepath)
            if ok then
                UIManager:show(InfoMessage:new{
                    text = _("Data restored successfully!"),
                    timeout = 3,
                })
                -- Refresh settings view
                if self.settings_widget then
                    UIManager:close(self.settings_widget)
                    self:showSettingsView()
                end
            else
                UIManager:show(InfoMessage:new{
                    text = _("Restore failed: ") .. (result or "Unknown error"),
                    timeout = 5,
                })
            end
        end,
        cancel_callback = function()
            self:showRestoreMenu(ui)
        end,
    })
end

--[[--
Confirm deletion of a backup file.
--]]
function Settings:confirmDeleteBackup(ui, backup)
    UIManager:show(ConfirmBox:new{
        text = _("Delete backup?\n\n") .. backup.created_at,
        ok_text = _("Delete"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local ok = Data:deleteBackup(backup.filepath)
            if ok then
                UIManager:show(InfoMessage:new{
                    text = _("Backup deleted"),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Failed to delete backup"),
                    timeout = 3,
                })
            end
            self:showRestoreMenu(ui)
        end,
        cancel_callback = function()
            self:showRestoreMenu(ui)
        end,
    })
end

--[[--
Confirm and reset all plugin data.
--]]
function Settings:confirmResetData(_ui)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Reset All Data?"),
        buttons = {
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
            {{
                text = _("Reset Everything"),
                callback = function()
                    UIManager:close(dialog)
                    -- Reset to defaults
                    Data:saveUserSettings({
                        energy_categories = {"Energetic", "Average", "Down"},
                        time_slots = {"Morning", "Afternoon", "Evening", "Night"},
                        streak_data = {current = 0, longest = 0, last_completed_date = nil},
                        today_energy = nil,
                        today_date = nil,
                        lock_screen_dashboard = false,
                    })
                    Data:saveAllQuests({daily = {}, weekly = {}, monthly = {}})
                    Data:saveDailyLogs({})
                    Data:saveReminders({})
                    UIManager:show(InfoMessage:new{
                        text = _("All data has been reset"),
                        timeout = 3,
                    })
                    -- Refresh settings view
                    if self.settings_widget then
                        UIManager:close(self.settings_widget)
                        self:showSettingsView()
                    end
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

return Settings
