--[[--
Read module for Life Tracker.
Displays reading statistics and recent books using native KOReader patterns.

Uses KOReader's native Menu widget for the book list, following established patterns.

@module lifetracker.read
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
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

local Navigation = require("modules/navigation")
local ReadingStats = require("modules/reading_stats")
local UIConfig = require("modules/ui_config")
local UIHelpers = require("modules/ui_helpers")

local Read = {}

-- Configuration
local MAX_RECENT_BOOKS = 6  -- 2 rows x 3 columns for optimal performance

--[[--
Show the read view.
@param ui KOReader UI instance
--]]
function Read:show(ui)
    self.ui = ui
    self:showReadView()
end

--[[--
Extract title from file path.
@param filepath string Full path to the book file
@treturn string Extracted title
--]]
function Read:extractTitle(filepath)
    if not filepath then return _("Unknown") end

    local filename = filepath:match("([^/]+)$") or filepath
    filename = filename:gsub("%.[^.]+$", "")
    filename = filename:gsub("[_-]", " ")
    return filename
end

-- Cover cache directory
local COVER_CACHE_DIR = nil

--[[--
Get or create the cover cache directory.
@treturn string Path to cover cache directory
--]]
function Read:getCoverCacheDir()
    if COVER_CACHE_DIR then return COVER_CACHE_DIR end

    local DataStorage = require("datastorage")
    COVER_CACHE_DIR = DataStorage:getDataDir() .. "/cache/lifetracker-covers"

    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(COVER_CACHE_DIR, "mode") ~= "directory" then
        lfs.mkdir(COVER_CACHE_DIR)
    end

    return COVER_CACHE_DIR
end

--[[--
Generate a cache key for a book's cover.
@param filepath string Full path to the book file
@treturn string Cache filename
--]]
function Read:getCoverCacheKey(filepath)
    -- Use a simple hash of the filepath + file modification time
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(filepath)
    local mtime = attr and attr.modification or 0

    -- Simple string hash
    local hash = 0
    for i = 1, #filepath do
        hash = (hash * 31 + filepath:byte(i)) % 2147483647
    end

    return string.format("%d_%d.png", hash, mtime)
end

--[[--
Get book metadata from DocSettings (fast, no document open).
Also retrieves progress in the same call.

@param filepath string Full path to the book file
@treturn table Book info with title, authors, progress
--]]
function Read:getBookMetadata(filepath)
    if not filepath then return nil end

    local bookinfo = { progress = 0 }

    local dok, DocSettings = pcall(require, "docsettings")
    if dok and DocSettings then
        local doc_settings = DocSettings:open(filepath)
        if doc_settings then
            -- Get metadata
            local doc_props = doc_settings:readSetting("doc_props")
            if doc_props then
                bookinfo.title = doc_props.title
                bookinfo.authors = doc_props.authors
            end
            -- Get progress in same call (avoids duplicate file read)
            local pct = doc_settings:readSetting("percent_finished")
            if pct then
                bookinfo.progress = pct
            end
        end
    end

    -- Fallback: extract title from filename
    if not bookinfo.title or bookinfo.title == "" then
        bookinfo.title = self:extractTitle(filepath)
    end

    return bookinfo
end

--[[--
Get cover for a book, using cache when available.
This is the expensive operation - call sparingly.

@param filepath string Full path to the book file
@param cover_width number Desired cover width
@param cover_height number Desired cover height
@treturn BlitBuffer|nil Cover image or nil
--]]
function Read:getBookCover(filepath, cover_width, cover_height)
    if not filepath then return nil end

    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")

    -- Check cache first
    local cache_dir = self:getCoverCacheDir()
    local cache_key = self:getCoverCacheKey(filepath)
    local cache_path = cache_dir .. "/" .. cache_key

    if lfs.attributes(cache_path, "mode") == "file" then
        -- Load from cache (use : for method call)
        local RenderImage = require("ui/renderimage")
        local cover_bb = RenderImage:renderImageFile(cache_path, false, cover_width, cover_height)
        if cover_bb then
            logger.dbg("LifeTracker: Loaded cover from cache:", cache_path)
            return cover_bb
        end
    end

    -- Extract cover from document (expensive!)
    local DocumentRegistry = require("document/documentregistry")
    if not DocumentRegistry:hasProvider(filepath) then
        return nil
    end

    logger.dbg("LifeTracker: Extracting cover from:", filepath)
    local doc = DocumentRegistry:openDocument(filepath)
    if not doc then return nil end

    -- Load metadata only (not full document)
    if doc.loadDocument then
        doc:loadDocument(false)
    end

    local cover_bb = doc:getCoverPageImage()
    doc:close()

    if not cover_bb then return nil end

    -- Scale to target size
    local scale_w = cover_width / cover_bb:getWidth()
    local scale_h = cover_height / cover_bb:getHeight()
    local scale = math.min(scale_w, scale_h)

    local result_bb
    if scale < 1 then
        result_bb = cover_bb:scale(
            math.floor(cover_bb:getWidth() * scale),
            math.floor(cover_bb:getHeight() * scale)
        )
        cover_bb:free()
    else
        result_bb = cover_bb
    end

    -- Save to cache for next time
    if result_bb then
        local ok, err = pcall(function()
            result_bb:writePNG(cache_path)
        end)
        if ok then
            logger.dbg("LifeTracker: Saved cover to cache:", cache_path)
        else
            logger.dbg("LifeTracker: Failed to cache cover:", err)
        end
    end

    return result_bb
end

--[[--
Create a cover placeholder widget when no cover is available.
@param width number Width of the placeholder
@param height number Height of the placeholder
@treturn Widget Placeholder widget
--]]
function Read:createCoverPlaceholder(width, height)
    local placeholder_color = Blitbuffer.Color8(0xDD)  -- Light gray

    return FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = placeholder_color,
        CenterContainer:new{
            dimen = Geom:new{w = width, h = height},
            TextWidget:new{
                text = "📖",
                face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
                fgcolor = UIConfig:color("muted"),
            },
        },
    }
end

--[[--
Open a book file.
@param filepath string Full path to the book file
--]]
function Read:openBook(filepath)
    if not filepath then return end

    UIHelpers.closeWidget(self, "read_widget")

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(filepath)
end

--[[--
Get recent books from ReadHistory.
@treturn table Array of menu items for Menu widget
--]]
function Read:getRecentBooksMenuItems()
    local items = {}
    local read_module = self

    local ok, ReadHistory = pcall(require, "readhistory")
    if not ok or not ReadHistory or not ReadHistory.hist then
        return items
    end

    local count = 0
    for _, item in ipairs(ReadHistory.hist) do
        if count >= MAX_RECENT_BOOKS then break end
        if item.file and not item.dim then
            -- Get progress from DocSettings
            local progress = 0
            local dok, DocSettings = pcall(require, "docsettings")
            if dok and DocSettings then
                local doc_settings = DocSettings:open(item.file)
                if doc_settings then
                    local pct = doc_settings:readSetting("percent_finished")
                    if pct then
                        progress = pct
                    end
                end
            end

            local title = self:extractTitle(item.file)
            local progress_text = string.format("%d%%", math.floor(progress * 100))
            local book_file = item.file

            -- Standard Menu item format (same pattern used throughout KOReader)
            table.insert(items, {
                text = title,
                mandatory = progress_text,
                callback = function()
                    read_module:openBook(book_file)
                end,
            })
            count = count + 1
        end
    end

    return items
end

--[[--
Create the all-time book stats widget from KOReader statistics.
@param content_width number Width of the content area
@treturn Widget Stats row widget
--]]
function Read:createBookStatsRow(content_width)
    local total_stats = ReadingStats:getTotalReadingStats()

    local total_books = total_stats.total_books or 0
    local total_pages = total_stats.total_pages or 0
    local total_time = ReadingStats:formatTime(total_stats.total_time or 0)

    local card_spacing = UIConfig:dim("stat_card_spacing")
    local card_height = UIConfig:dim("stat_card_height")
    local value_font = UIConfig:fontSize("stat_value")
    local label_font = UIConfig:fontSize("stat_label")

    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local bg_color = UIConfig:color("background")

    local total_spacing = card_spacing * 2
    local third_width = math.floor((content_width - total_spacing) / 3)

    local function createStatCard(value, label)
        local stat_group = VerticalGroup:new{align = "center"}
        table.insert(stat_group, TextWidget:new{
            text = tostring(value),
            face = UIConfig:getFont("tfont", value_font),
            fgcolor = fg_color,
        })
        table.insert(stat_group, VerticalSpan:new{width = UIConfig:spacing("xs")})
        table.insert(stat_group, TextWidget:new{
            text = label,
            face = UIConfig:getFont("cfont", label_font),
            fgcolor = muted_color,
        })
        return stat_group
    end

    local books_stat = createStatCard(total_books, _("Books"))
    local pages_stat = createStatCard(total_pages, _("Pages"))
    local time_stat = createStatCard(total_time, _("Total Time"))

    local stats_row = HorizontalGroup:new{align = "center"}
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = card_height},
        books_stat,
    })
    table.insert(stats_row, HorizontalSpan:new{width = card_spacing})
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = card_height},
        pages_stat,
    })
    table.insert(stats_row, HorizontalSpan:new{width = card_spacing})
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = card_height},
        time_stat,
    })

    return FrameContainer:new{
        width = content_width,
        padding = UIConfig:spacing("sm"),
        bordersize = UIConfig:dim("border_thin"),
        background = bg_color,
        stats_row,
    }
end

--[[--
Create the reading stats widget (today/this week).
@param content_width number Width of the content area
@treturn Widget Stats overview widget
--]]
function Read:createStatsOverview(content_width)
    local today_db = ReadingStats:getTodayStatsFromDB()
    local week_db = ReadingStats:getWeekStatsFromDB()

    local weekly = ReadingStats:getWeeklyStats()
    local today_stats = ReadingStats:getTodayStats(self.ui)

    local today_pages = today_db.pages > 0 and today_db.pages or (today_stats.pages_read or 0)
    local today_time_sec = today_db.time > 0 and today_db.time or (today_stats.time_spent or 0)
    local today_time = ReadingStats:formatTime(today_time_sec)

    local week_pages = week_db.pages > 0 and week_db.pages or (weekly.total_pages or 0)
    local week_time_sec = week_db.time > 0 and week_db.time or (weekly.total_time or 0)
    local week_time = ReadingStats:formatTime(week_time_sec)

    local card_spacing = UIConfig:dim("stat_card_spacing")
    local card_height = UIConfig:dim("stat_card_height")
    local caption_font = UIConfig:fontSize("caption")
    local body_font = UIConfig:fontSize("body")

    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local bg_color = UIConfig:color("background")

    local function createPeriodStats(title, pages, time)
        local stats_group = VerticalGroup:new{align = "center"}
        table.insert(stats_group, TextWidget:new{
            text = title,
            face = UIConfig:getFont("tfont", caption_font),
            fgcolor = muted_color,
        })
        table.insert(stats_group, VerticalSpan:new{width = UIConfig:spacing("xs")})
        table.insert(stats_group, TextWidget:new{
            text = string.format("%d page%s", pages, pages == 1 and "" or "s"),
            face = UIConfig:getFont("tfont", body_font),
            fgcolor = fg_color,
        })
        table.insert(stats_group, TextWidget:new{
            text = time,
            face = UIConfig:getFont("cfont", caption_font),
            fgcolor = muted_color,
        })
        return stats_group
    end

    local left_stats = createPeriodStats(_("Today"), today_pages, today_time)
    local right_stats = createPeriodStats(_("This Week"), week_pages, week_time)

    local outer_padding = UIConfig:spacing("sm")
    local outer_border = UIConfig:dim("border_thin")
    local inner_content_width = content_width - (outer_padding * 2) - (outer_border * 2)
    local card_width = math.floor((inner_content_width - card_spacing) / 2)

    local stats_row = HorizontalGroup:new{align = "center"}
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = card_width, h = card_height},
        left_stats,
    })
    table.insert(stats_row, HorizontalSpan:new{width = card_spacing})
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = card_width, h = card_height},
        right_stats,
    })

    return FrameContainer:new{
        width = content_width,
        padding = UIConfig:spacing("sm"),
        bordersize = UIConfig:dim("border_thin"),
        background = bg_color,
        stats_row,
    }
end

--[[--
Create quick action buttons.
@treturn Widget Quick actions widget
--]]
function Read:createQuickActions()
    local button_spacing = UIConfig:spacing("sm")
    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local read_module = self

    -- Get last book from ReadHistory for "Continue Reading" button
    local last_book = nil
    local last_book_title = nil
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and ReadHistory and ReadHistory.hist and #ReadHistory.hist > 0 then
        for _, item in ipairs(ReadHistory.hist) do
            if item.file and not item.dim then
                last_book = item.file
                last_book_title = self:extractTitle(item.file)
                if #last_book_title > 20 then
                    last_book_title = last_book_title:sub(1, 18) .. ".."
                end
                break
            end
        end
    end

    local buttons = VerticalGroup:new{align = "left"}

    -- Section header
    table.insert(buttons, TextWidget:new{
        text = _("Quick Actions"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("section_title")),
        fgcolor = fg_color,
    })
    table.insert(buttons, VerticalSpan:new{width = UIConfig:spacing("sm")})

    local button_row = HorizontalGroup:new{align = "center"}

    -- Continue Reading button (if there's a last book)
    if last_book then
        local continue_btn = Button:new{
            text = _("▶ Continue"),
            text_font_face = "cfont",
            text_font_size = UIConfig:fontSize("body"),
            radius = Size.radius.button,
            padding = Size.padding.button,
            margin = 0,
            callback = function()
                read_module:openBook(last_book)
            end,
        }
        table.insert(button_row, continue_btn)
        table.insert(button_row, HorizontalSpan:new{width = button_spacing})
    end

    -- Open File Manager button
    local file_manager_btn = Button:new{
        text = _("📁 Browse Books"),
        text_font_face = "cfont",
        text_font_size = UIConfig:fontSize("body"),
        radius = Size.radius.button,
        padding = Size.padding.button,
        margin = 0,
        callback = function()
            UIHelpers.closeWidget(read_module, "read_widget")
            local FileManager = require("apps/filemanager/filemanager")
            if FileManager.instance then
                FileManager.instance:onRefresh()
            else
                FileManager:showFiles()
            end
        end,
    }
    table.insert(button_row, file_manager_btn)

    table.insert(buttons, button_row)

    -- Show what book "Continue" will open
    if last_book_title then
        table.insert(buttons, VerticalSpan:new{width = UIConfig:spacing("xs")})
        table.insert(buttons, TextWidget:new{
            text = _("Last: ") .. last_book_title,
            face = UIConfig:getFont("cfont", UIConfig:fontSize("caption")),
            fgcolor = muted_color,
        })
    end

    return buttons
end

--[[--
Create the recent books section as a grid with cover thumbnails.
Uses BookInfoManager for efficient cover loading from KOReader's cache.

@param content_width number Width of the content area
@treturn Widget Recent books grid with covers
--]]
function Read:createRecentBooksList(content_width)
    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local read_module = self

    local container = VerticalGroup:new{align = "left"}

    -- Section header
    table.insert(container, TextWidget:new{
        text = _("Recent Books"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("section_title")),
        fgcolor = fg_color,
    })
    table.insert(container, VerticalSpan:new{width = UIConfig:spacing("sm")})

    -- Get recent books from ReadHistory
    local ok, ReadHistory = pcall(require, "readhistory")
    local books_list = {}

    -- First try ReadHistory
    if ok and ReadHistory and ReadHistory.hist then
        for _, item in ipairs(ReadHistory.hist) do
            if item.file and not item.dim then
                table.insert(books_list, item.file)
            end
        end
    end

    -- Also scan home/books directory to fill up the grid
    local lfs = require("libs/libkoreader-lfs")
    local DataStorage = require("datastorage")
    local DocumentRegistry = require("document/documentregistry")
    local logger = require("logger")

    -- Track which files we already have to avoid duplicates
    local seen_files = {}
    for _, f in ipairs(books_list) do
        seen_files[f] = true
    end

    -- Try common book directories
    local home_dir = DataStorage:getFullDataDir()
    local books_dirs = {
        home_dir .. "/books",
        home_dir .. "/../home/books",
        "/tmp/koreader/home/books",
    }

    logger.dbg("LifeTracker: Scanning for books, home_dir:", home_dir)
    logger.dbg("LifeTracker: Books from history:", #books_list)

    for _, books_dir in ipairs(books_dirs) do
        if #books_list >= MAX_RECENT_BOOKS then break end

        logger.dbg("LifeTracker: Checking directory:", books_dir)
        if lfs.attributes(books_dir, "mode") == "directory" then
            logger.dbg("LifeTracker: Found directory:", books_dir)
            for file in lfs.dir(books_dir) do
                if #books_list >= MAX_RECENT_BOOKS then break end
                if file ~= "." and file ~= ".." then
                    local filepath = books_dir .. "/" .. file
                    if not seen_files[filepath] and DocumentRegistry:hasProvider(filepath) then
                        logger.dbg("LifeTracker: Found book:", filepath)
                        table.insert(books_list, filepath)
                        seen_files[filepath] = true
                    end
                end
            end
        end
    end

    logger.dbg("LifeTracker: Total books found:", #books_list)

    if #books_list == 0 then
        table.insert(container, TextWidget:new{
            text = _("No recently read books"),
            face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
            fgcolor = muted_color,
        })
        return container
    end

    -- Grid configuration
    local cols = 3
    local spacing = UIConfig:spacing("sm")
    local card_width = math.floor((content_width - spacing * (cols - 1)) / cols)
    local card_padding = 6
    local cover_width = card_width - (card_padding * 2)  -- Fill card width
    local cover_height = math.floor(cover_width * 1.4)   -- Book aspect ratio (~1:1.4)
    local text_height = 52  -- Space for title + author below cover (increased for larger fonts)
    local card_height = cover_height + text_height + card_padding * 2

    -- Build grid
    local grid = VerticalGroup:new{align = "left"}
    local current_row = HorizontalGroup:new{align = "top"}
    local items_in_row = 0
    local book_count = 0

    local pending_cover_bb = nil  -- Track cover for cleanup on early exit
    for _, filepath in ipairs(books_list) do
        if book_count >= MAX_RECENT_BOOKS then
            -- Clean up any pending cover buffer before breaking
            if pending_cover_bb then
                pending_cover_bb:free()
                pending_cover_bb = nil
            end
            break
        end
        if not filepath then goto continue end

        -- OPTIMIZED: Get metadata + progress in ONE DocSettings call (fast)
        local bookinfo = self:getBookMetadata(filepath)
        if not bookinfo then goto continue end

        -- Prepare display data
        local title = bookinfo.title or self:extractTitle(filepath)
        local author = bookinfo.authors or ""
        local progress = bookinfo.progress or 0

        -- Truncate title and author to fit card
        local max_chars = math.floor(card_width / 7)
        if #title > max_chars then
            title = title:sub(1, max_chars - 2) .. ".."
        end
        if #author > max_chars then
            author = author:sub(1, max_chars - 2) .. ".."
        end

        -- OPTIMIZED: Get cover with caching (expensive, but cached)
        -- Store in pending_cover_bb so we can free it if loop exits early
        pending_cover_bb = self:getBookCover(filepath, cover_width, cover_height)

        -- Create cover widget
        local cover_widget
        if pending_cover_bb then
            cover_widget = ImageWidget:new{
                image = pending_cover_bb,
                width = cover_width,
                height = cover_height,
                scale_factor = 0,
                image_disposable = true,  -- ImageWidget takes ownership
            }
            pending_cover_bb = nil  -- ImageWidget now owns it, clear tracking
        else
            cover_widget = self:createCoverPlaceholder(cover_width, cover_height)
        end

        -- Build card content: cover + title + author
        local card_content = VerticalGroup:new{align = "center"}

        -- Cover (centered in card)
        table.insert(card_content, CenterContainer:new{
            dimen = Geom:new{w = card_width - card_padding * 2, h = cover_height},
            cover_widget,
        })

        table.insert(card_content, VerticalSpan:new{width = 4})

        -- Title (centered, truncated) - use body_small for readability
        table.insert(card_content, CenterContainer:new{
            dimen = Geom:new{w = cover_width, h = 24},
            TextWidget:new{
                text = title,
                face = UIConfig:getFont("cfont", UIConfig:fontSize("body_small")),
                fgcolor = fg_color,
                max_width = cover_width - 4,
            },
        })

        -- Author or progress (centered) - use caption for subtitle
        local subtitle = author ~= "" and author or string.format("%d%%", math.floor(progress * 100))
        table.insert(card_content, CenterContainer:new{
            dimen = Geom:new{w = cover_width, h = 20},
            TextWidget:new{
                text = subtitle,
                face = UIConfig:getFont("cfont", UIConfig:fontSize("caption")),
                fgcolor = muted_color,
                max_width = cover_width - 4,
            },
        })

        -- Wrap in tappable button
        local book_file = filepath
        local card = Button:new{
            width = card_width,
            height = card_height,
            padding = card_padding,
            margin = 0,
            bordersize = Size.border.thin,
            radius = Size.radius.button,
            callback = function()
                read_module:openBook(book_file)
            end,
        }
        -- Replace button content with our card
        card[1] = FrameContainer:new{
            width = card_width,
            height = card_height,
            padding = card_padding,
            margin = 0,
            bordersize = Size.border.thin,
            radius = Size.radius.button,
            background = Blitbuffer.COLOR_WHITE,
            card_content,
        }

        -- Add spacing between cards (not before first in row)
        if items_in_row > 0 then
            table.insert(current_row, HorizontalSpan:new{width = spacing})
        end

        table.insert(current_row, card)
        items_in_row = items_in_row + 1
        book_count = book_count + 1

        -- Start new row when full
        if items_in_row >= cols then
            table.insert(grid, current_row)
            table.insert(grid, VerticalSpan:new{width = spacing})
            current_row = HorizontalGroup:new{align = "top"}
            items_in_row = 0
        end

        ::continue::
    end

    -- Add last partial row
    if items_in_row > 0 then
        table.insert(grid, current_row)
    end

    if book_count == 0 then
        table.insert(container, TextWidget:new{
            text = _("No recently read books"),
            face = UIConfig:getFont("cfont", UIConfig:fontSize("body")),
            fgcolor = muted_color,
        })
    else
        table.insert(container, grid)
    end

    return container
end

--[[--
Show the main read view.
--]]
function Read:showReadView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    local scroll_width = UIConfig:getScrollWidth()
    local scroll_height = screen_height
    local page_padding = UIConfig:getPagePadding()
    local content_width = UIConfig:getPaddedContentWidth()

    -- Build content
    local content = VerticalGroup:new{align = "left"}

    -- Title
    table.insert(content, TextWidget:new{
        text = _("Reading"),
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})

    -- All-time book stats
    local book_stats = self:createBookStatsRow(content_width)
    table.insert(content, book_stats)
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("sm")})

    -- Today/Week reading stats
    local stats_widget = self:createStatsOverview(content_width)
    table.insert(content, stats_widget)

    -- Divider
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("lg")})
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w = content_width, h = 1},
        background = UIConfig:color("muted"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})

    -- Quick actions
    local quick_actions = self:createQuickActions()
    table.insert(content, quick_actions)

    -- Divider
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("lg")})
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w = content_width, h = 1},
        background = UIConfig:color("muted"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})

    -- Recent books list (simple Button-based list)
    local recent_books = self:createRecentBooksList(content_width)
    table.insert(content, recent_books)

    -- Bottom padding
    table.insert(content, VerticalSpan:new{width = Size.padding.large * 2})

    -- Wrap content in frame with page padding
    local inner_frame = FrameContainer:new{
        width = scroll_width,
        height = math.max(scroll_height, content:getSize().h + page_padding * 2),
        padding = page_padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    -- Scrollable container
    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = scroll_width, h = scroll_height},
        inner_frame,
    }
    self.scrollable_container = scrollable

    -- Tab change callback
    local ui = self.ui
    local read_module = self
    local function on_tab_change(tab_id)
        UIHelpers.closeWidget(read_module, "read_widget")
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("read", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create main layout with full-screen white background
    local white_bg = FrameContainer:new{
        width = screen_width,
        height = screen_height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{},
    }
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
        white_bg,
        scrollable,
        RightContainer:new{
            dimen = Geom:new{w = screen_width, h = screen_height},
            tabs,
        },
    }

    -- Create widget with gestures
    self.read_widget = InputContainer:new{
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
    self.scrollable_container.show_parent = self.read_widget

    -- Setup corner gesture handlers
    local top_safe_zone = UIConfig:getTopSafeZone()
    local gesture_dims = {
        screen_width = screen_width,
        screen_height = screen_height,
        top_safe_zone = top_safe_zone,
    }
    UIHelpers.setupCornerGestures(self.read_widget, self, gesture_dims)
    UIHelpers.setupSwipeToClose(self.read_widget, function()
        UIHelpers.closeWidget(read_module, "read_widget")
    end, gesture_dims)

    UIManager:show(self.read_widget)
end

--[[--
Close the read view.
--]]
function Read:close()
    UIHelpers.closeWidget(self, "read_widget")
end

return Read
