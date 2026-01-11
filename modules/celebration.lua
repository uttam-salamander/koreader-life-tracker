--[[--
Celebration module for Life Tracker.
Displays celebratory animations when quests are completed.

@module lifetracker.celebration
--]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")

local UIConfig = require("modules/ui_config")

local Celebration = {}

-- Animation files directory (relative to plugin root)
Celebration.ANIMATIONS_DIR = "Animations"

-- Cache for animation file list
Celebration._animation_files = nil

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
Load an image from a GIF file.
Uses ImageWidget's built-in file loading (extracts first frame for GIFs).
@tparam string filepath Path to the GIF file
@tparam number width Desired width
@tparam number height Desired height
@treturn ImageWidget|nil Image widget or nil if loading failed
--]]
function Celebration:loadAnimationImage(filepath, width, height)
    if not filepath then
        return nil
    end

    -- Use ImageWidget's file parameter - it handles GIFs natively
    local ok, widget = pcall(function()
        return ImageWidget:new{
            file = filepath,
            width = width,
            height = height,
            scale_factor = 0,
            autostretch = true,
        }
    end)

    if ok and widget then
        return widget
    end

    return nil
end

--[[--
Show a celebration dialog for quest completion.
Displays a random animation with congratulation text.
@tparam string message Optional custom message (default: "Quest completed!")
@tparam number timeout Auto-dismiss timeout in seconds (default: 1.5)
--]]
function Celebration:showCompletion(message, timeout)
    message = message or _("Quest completed!")
    timeout = timeout or 1.5

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local colors = UIConfig:getColors()

    -- Dialog dimensions
    local dialog_width = math.floor(screen_width * 0.7)
    local dialog_height = math.floor(screen_height * 0.5)
    local image_height = math.floor(dialog_height * 0.65)
    local image_width = math.floor(dialog_width * 0.8)

    -- Try to load a random animation
    local animation_path = self:getRandomAnimation()
    local image_widget = self:loadAnimationImage(animation_path, image_width, image_height)

    -- Build dialog content
    local content = VerticalGroup:new{ align = "center" }

    -- Add animation image if loaded
    if image_widget then
        table.insert(content, CenterContainer:new{
            dimen = Geom:new{ w = dialog_width - Size.padding.large * 2, h = image_height },
            image_widget,
        })
        table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    else
        -- No image available, just show a larger text area
        table.insert(content, VerticalSpan:new{ width = Size.padding.large * 2 })
    end

    -- Celebration text
    table.insert(content, CenterContainer:new{
        dimen = Geom:new{ w = dialog_width - Size.padding.large * 2, h = 40 },
        TextWidget:new{
            text = message,
            face = UIConfig:getFont("tfont", 18),
            fgcolor = colors.foreground,
            bold = true,
        },
    })

    -- Wrap in frame container for dialog appearance
    local dialog_frame = FrameContainer:new{
        width = dialog_width,
        height = dialog_height,
        padding = Size.padding.large,
        bordersize = Size.border.thick,
        background = colors.background,
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
        UIManager:close(celebration.celebration_widget)
        return true
    end

    -- Show dialog
    UIManager:show(self.celebration_widget)

    -- Auto-dismiss after timeout
    UIManager:scheduleIn(timeout, function()
        if celebration.celebration_widget then
            UIManager:close(celebration.celebration_widget)
            celebration.celebration_widget = nil
        end
    end)
end

return Celebration
