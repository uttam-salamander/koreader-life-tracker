--[[--
AnimatedImageWidget for Life Tracker.
Displays animated GIFs by cycling through frames using UIManager scheduling.

Uses KOReader's RenderImage module with want_frames=true to extract GIF frames,
then cycles through them at a configurable frame rate.

@module lifetracker.animated_image
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local RenderImage = require("ui/renderimage")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local AnimatedImageWidget = Widget:extend{
    -- File path to the GIF
    file = nil,
    -- Maximum dimensions (will fit within while preserving aspect ratio)
    width = nil,
    height = nil,
    -- Frame delay in seconds (default: 100ms for ~10fps)
    frame_delay = 0.1,
    -- Whether to loop the animation
    loop = true,
    -- Number of loops (0 = infinite, only used if loop=true)
    max_loops = 0,
    -- Callback when animation completes (only if loop=false or max_loops reached)
    on_complete = nil,

    -- Internal state
    _frames = nil,
    _frame_count = 0,
    _current_frame = 1,
    _current_bb = nil,
    _loop_count = 0,
    _is_playing = false,
    _scheduled_action = nil,
    _actual_width = nil,
    _actual_height = nil,
}

function AnimatedImageWidget:init()
    -- Set default max dimensions if not specified
    self.width = self.width or Screen:scaleBySize(200)
    self.height = self.height or Screen:scaleBySize(200)

    -- Load frames (will calculate actual dimensions preserving aspect ratio)
    self:_loadFrames()

    -- Set dimensions based on actual rendered size
    self.dimen = Geom:new{
        w = self._actual_width or self.width,
        h = self._actual_height or self.height,
    }
end

--[[--
Calculate dimensions that fit within max bounds while preserving aspect ratio.
@tparam number orig_w Original width
@tparam number orig_h Original height
@tparam number max_w Maximum width
@tparam number max_h Maximum height
@treturn number, number Scaled width and height
--]]
function AnimatedImageWidget:_calculateFitDimensions(orig_w, orig_h, max_w, max_h)
    if orig_w <= 0 or orig_h <= 0 then
        return max_w, max_h
    end

    local scale_w = max_w / orig_w
    local scale_h = max_h / orig_h
    local scale = math.min(scale_w, scale_h)

    return math.floor(orig_w * scale), math.floor(orig_h * scale)
end

--[[--
Load GIF frames using RenderImage, preserving aspect ratio.
--]]
function AnimatedImageWidget:_loadFrames()
    if not self.file then
        return
    end

    -- First, load at original size to get dimensions
    local orig_bb = RenderImage:renderImageFile(self.file, false)
    if not orig_bb then
        return
    end

    local orig_w = orig_bb:getWidth()
    local orig_h = orig_bb:getHeight()
    orig_bb:free()

    -- Calculate dimensions that preserve aspect ratio
    local scaled_w, scaled_h = self:_calculateFitDimensions(orig_w, orig_h, self.width, self.height)
    self._actual_width = scaled_w
    self._actual_height = scaled_h

    -- Now load frames at the correct aspect-ratio-preserving size
    local frames = RenderImage:renderImageFile(self.file, true, scaled_w, scaled_h)

    if frames and type(frames) == "table" and #frames > 0 then
        self._frames = frames
        self._frame_count = #frames
        -- Render the first frame
        self:_renderFrame(1)
    else
        -- Fallback: load as single static image at correct size
        local bb = RenderImage:renderImageFile(self.file, false, scaled_w, scaled_h)
        if bb then
            self._current_bb = bb
            self._frame_count = 1
        end
    end
end

--[[--
Render a specific frame to the current BlitBuffer.
@tparam number frame_num Frame number (1-indexed)
--]]
function AnimatedImageWidget:_renderFrame(frame_num)
    if not self._frames or frame_num < 1 or frame_num > self._frame_count then
        return
    end

    local frame_func = self._frames[frame_num]
    if type(frame_func) == "function" then
        -- Frame is a function that returns a BlitBuffer
        local new_bb = frame_func()
        if new_bb then
            -- Free previous buffer if we own it
            if self._current_bb and self._frames.image_disposable then
                self._current_bb:free()
            end
            self._current_bb = new_bb
        end
    elseif frame_func then
        -- Frame might already be a BlitBuffer
        self._current_bb = frame_func
    end

    self._current_frame = frame_num
end

--[[--
Start playing the animation.
--]]
function AnimatedImageWidget:play()
    if self._is_playing or self._frame_count <= 1 then
        return
    end

    self._is_playing = true
    self._loop_count = 0
    self:_scheduleNextFrame()
end

--[[--
Stop playing the animation.
--]]
function AnimatedImageWidget:stop()
    self._is_playing = false
    if self._scheduled_action then
        UIManager:unschedule(self._scheduled_action)
        self._scheduled_action = nil
    end
end

--[[--
Schedule the next frame update.
--]]
function AnimatedImageWidget:_scheduleNextFrame()
    if not self._is_playing then
        return
    end

    local widget = self
    self._scheduled_action = function()
        widget:_advanceFrame()
    end

    UIManager:scheduleIn(self.frame_delay, self._scheduled_action)
end

--[[--
Advance to the next frame and trigger a repaint.
--]]
function AnimatedImageWidget:_advanceFrame()
    if not self._is_playing then
        return
    end

    local next_frame = self._current_frame + 1

    if next_frame > self._frame_count then
        -- Reached end of animation
        if self.loop then
            self._loop_count = self._loop_count + 1
            if self.max_loops > 0 and self._loop_count >= self.max_loops then
                -- Max loops reached
                self:stop()
                if self.on_complete then
                    self.on_complete()
                end
                return
            end
            next_frame = 1
        else
            -- No loop, animation complete
            self:stop()
            if self.on_complete then
                self.on_complete()
            end
            return
        end
    end

    -- Render the next frame
    self:_renderFrame(next_frame)

    -- Request a fast refresh of this widget's area
    -- Use "fast" mode for e-ink to minimize ghosting while keeping animation smooth
    if self.show_parent then
        UIManager:setDirty(self.show_parent, "fast", self.dimen)
    else
        UIManager:setDirty("all", "fast", self.dimen)
    end

    -- Schedule the next frame
    self:_scheduleNextFrame()
end

--[[--
Paint the current frame to the screen.
@tparam BlitBuffer bb Target BlitBuffer to paint to
@tparam number x X offset
@tparam number y Y offset
--]]
function AnimatedImageWidget:paintTo(bb, x, y)
    if not self._current_bb then
        return
    end

    -- Store position for dirty region calculation
    self.dimen.x = x
    self.dimen.y = y

    -- Blit the current frame to the target buffer
    bb:blitFrom(self._current_bb, x, y, 0, 0, self._current_bb:getWidth(), self._current_bb:getHeight())
end

--[[--
Get the widget dimensions.
@treturn Geom Widget dimensions
--]]
function AnimatedImageWidget:getSize()
    return self.dimen
end

--[[--
Clean up resources when the widget is closed.
--]]
function AnimatedImageWidget:onCloseWidget()
    -- Stop animation
    self:stop()

    -- Free frame resources
    if self._frames then
        if self._frames.free then
            -- Use the frames' cleanup method if available
            self._frames:free()
        end
        self._frames = nil
    end

    -- Free current buffer if we own it
    if self._current_bb then
        self._current_bb:free()
        self._current_bb = nil
    end
end

--[[--
Alias for cleanup (some widgets call free instead of onCloseWidget).
--]]
function AnimatedImageWidget:free()
    self:onCloseWidget()
end

return AnimatedImageWidget
