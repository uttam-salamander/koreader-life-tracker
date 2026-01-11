--[[--
Celebration module for Life Tracker.
Displays celebratory animations when quests are completed.

@module lifetracker.celebration
--]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local AnimatedImageWidget = require("modules/animated_image")
local Data = require("modules/data")
local UIConfig = require("modules/ui_config")

local Celebration = {}

-- Animation files directory (relative to plugin root)
Celebration.ANIMATIONS_DIR = "Animations"

-- Cache for animation file list
Celebration._animation_files = nil

-- Default settings
Celebration.DEFAULT_SETTINGS = {
    enabled = true,
    selected_animation = nil,  -- nil = random
    frame_delay = 0.1,         -- 100ms per frame (~10fps)
    timeout = 3.0,             -- Auto-dismiss after 3 seconds
}

--[[--
Get the plugin root directory.
@treturn string Path to plugin root
--]]
function Celebration:getPluginRoot()
    -- Get the path from the module location
    local info = debug.getinfo(1, "S")
    local source = info.source:gsub("^@", "")
    -- Go up from modules/celebration.lua to plugin root
    return source:gsub("/modules/celebration%.lua$", "")
end

--[[--
Scan the Animations directory for GIF files.
@treturn table List of animation file paths
--]]
function Celebration:getAnimationFiles()
    if self._animation_files then
        return self._animation_files
    end

    self._animation_files = {}

    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        ok, lfs = pcall(require, "lfs")
    end

    if not ok or not lfs then
        return self._animation_files
    end

    local plugin_root = self:getPluginRoot()
    local animations_path = plugin_root .. "/" .. self.ANIMATIONS_DIR

    pcall(function()
        for entry in lfs.dir(animations_path) do
            if entry ~= "." and entry ~= ".." then
                local ext = entry:match("%.([^%.]+)$")
                if ext and ext:lower() == "gif" then
                    table.insert(self._animation_files, animations_path .. "/" .. entry)
                end
            end
        end
    end)

    return self._animation_files
end

--[[--
Get a random animation file path.
@treturn string|nil Path to a random animation file, or nil if none available
--]]
function Celebration:getRandomAnimation()
    local files = self:getAnimationFiles()
    if #files == 0 then
        return nil
    end

    math.randomseed(os.time())
    local idx = math.random(1, #files)
    return files[idx]
end

--[[--
Get celebration settings from user data.
@treturn table Celebration settings
--]]
function Celebration:getSettings()
    local user_settings = Data:loadUserSettings()
    local celebration_settings = user_settings.celebration or {}

    -- Merge with defaults
    local settings = {}
    for key, default_val in pairs(self.DEFAULT_SETTINGS) do
        settings[key] = celebration_settings[key]
        if settings[key] == nil then
            settings[key] = default_val
        end
    end

    return settings
end

--[[--
Save celebration settings.
@tparam table settings Settings to save
--]]
function Celebration:saveSettings(settings)
    local user_settings = Data:loadUserSettings()
    user_settings.celebration = settings
    Data:saveUserSettings(user_settings)
end

--[[--
Get the animation file to use based on settings.
@treturn string|nil Path to animation file, or nil if none available
--]]
function Celebration:getAnimationToUse()
    local settings = self:getSettings()

    -- If a specific animation is selected, use it
    if settings.selected_animation then
        local files = self:getAnimationFiles()
        for _idx, filepath in ipairs(files) do
            if filepath:match("([^/]+)$") == settings.selected_animation then
                return filepath
            end
        end
    end

    -- Otherwise use random
    return self:getRandomAnimation()
end

--[[--
Create an animated image widget for a GIF file.
@tparam string filepath Path to the GIF file
@tparam number width Desired width
@tparam number height Desired height
@tparam number frame_delay Delay between frames in seconds
@treturn AnimatedImageWidget|nil Widget or nil if loading failed
--]]
function Celebration:createAnimatedWidget(filepath, width, height, frame_delay)
    if not filepath then
        return nil
    end

    local ok, widget = pcall(function()
        return AnimatedImageWidget:new{
            file = filepath,
            width = width,
            height = height,
            frame_delay = frame_delay or 0.1,
            loop = true,
            max_loops = 0,  -- Infinite until dismissed
        }
    end)

    if ok and widget then
        return widget
    end

    return nil
end

--[[--
Show a celebration dialog for quest completion.
Displays an animated GIF with congratulation text.
@tparam string message Optional custom message (default: "Quest completed!")
--]]
function Celebration:showCompletion(message)
    local settings = self:getSettings()

    -- Check if celebrations are enabled
    if not settings.enabled then
        return
    end

    message = message or _("Quest completed!")
    local timeout = settings.timeout or 3.0

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local colors = UIConfig:getColors()

    -- Dialog dimensions
    local dialog_width = math.floor(screen_width * 0.7)
    local dialog_height = math.floor(screen_height * 0.5)
    local image_height = math.floor(dialog_height * 0.65)
    local image_width = math.floor(dialog_width * 0.8)

    -- Get animation to use
    local animation_path = self:getAnimationToUse()
    local animated_widget = self:createAnimatedWidget(
        animation_path,
        image_width,
        image_height,
        settings.frame_delay
    )

    -- Build dialog content
    local content = VerticalGroup:new{ align = "center" }

    -- Store reference for cleanup
    self._animated_widget = animated_widget

    -- Add animation if loaded
    if animated_widget then
        table.insert(content, CenterContainer:new{
            dimen = Geom:new{ w = dialog_width - Size.padding.large * 2, h = image_height },
            animated_widget,
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    else
        -- No animation available, just show a larger text area
        table.insert(content, VerticalSpan:new{ width = Size.padding.large * 2 })
    end

    -- Celebration text
    table.insert(content, CenterContainer:new{
        dimen = Geom:new{ w = dialog_width - Size.padding.large * 2, h = 40 },
        TextWidget:new{
            text = message,
            face = UIConfig:getFont("tfont", 18),
            fgcolor = colors.foreground or require("ffi/blitbuffer").COLOR_BLACK,
            bold = true,
        },
    })

    -- Wrap in frame container for dialog appearance
    local dialog_frame = FrameContainer:new{
        width = dialog_width,
        height = dialog_height,
        padding = Size.padding.large,
        bordersize = Size.border.thick,
        background = colors.background or require("ffi/blitbuffer").COLOR_WHITE,
        radius = Size.radius.window,
        content,
    }

    -- Center on screen
    local centered_dialog = CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = screen_height },
        dialog_frame,
    }

    -- Create dismissable container
    self.celebration_widget = InputContainer:new{
        dimen = Geom:new{ w = screen_width, h = screen_height },
        ges_events = {
            Tap = {
                GestureRange = require("ui/gesturerange"):new{
                    ges = "tap",
                    range = Geom:new{ x = 0, y = 0, w = screen_width, h = screen_height },
                },
            },
        },
        centered_dialog,
    }

    -- Tap to dismiss
    local celebration = self
    self.celebration_widget.onTap = function()
        celebration:closeCelebration()
        return true
    end

    -- Show dialog and start animation
    UIManager:show(self.celebration_widget)

    -- Start animation playback
    if animated_widget then
        animated_widget.show_parent = self.celebration_widget
        animated_widget:play()
    end

    -- Auto-dismiss after timeout
    UIManager:scheduleIn(timeout, function()
        celebration:closeCelebration()
    end)
end

--[[--
Close the celebration dialog and clean up resources.
--]]
function Celebration:closeCelebration()
    -- Stop and free animated widget
    if self._animated_widget then
        self._animated_widget:stop()
        self._animated_widget:free()
        self._animated_widget = nil
    end

    -- Close the dialog
    if self.celebration_widget then
        UIManager:close(self.celebration_widget)
        self.celebration_widget = nil
    end
end

--[[--
Get list of available animations with display names.
@treturn table List of {filename, display_name} pairs
--]]
function Celebration:getAnimationList()
    local files = self:getAnimationFiles()
    local list = {}

    for _idx, filepath in ipairs(files) do
        local filename = filepath:match("([^/]+)$")
        -- Create a friendlier display name
        local display_name = filename:gsub("%.gif$", ""):sub(1, 16)
        if #display_name < #filename - 4 then
            display_name = display_name .. "..."
        end
        table.insert(list, {
            filename = filename,
            filepath = filepath,
            display_name = display_name,
        })
    end

    return list
end

return Celebration
