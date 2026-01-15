--[[--
Read module for Life Tracker.
Displays recently read books in a grid with covers and progress bars.

@module lifetracker.read
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
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

-- Cover cache configuration
local DataStorage = require("datastorage")
local COVER_CACHE_DIR = DataStorage:getDataDir() .. "/plugins/lifetracker.koplugin/.covers"

-- Grid configuration (scaled via UIConfig)
local function getGridCols()
    return UIConfig:dim("grid_columns")
end

local function getCardSpacing()
    return UIConfig:dim("padding_default")
end

local function getProgressBarHeight()
    return UIConfig:dim("progress_bar_height")
end

-- Scan Books folder for ebooks (development only)
-- Set to nil to use only ReadHistory/database (production)
Read.TEST_BOOKS_PATH = nil

-- Supported ebook extensions
local EBOOK_EXTENSIONS = {
    epub = true,
    pdf = true,
    mobi = true,
    azw = true,
    azw3 = true,
    fb2 = true,
    djvu = true,
    cbz = true,
    cbr = true,
    txt = true,
}

--[[--
Show the read view.
@param ui KOReader UI instance
--]]
function Read:show(ui)
    self.ui = ui
    self.books = {}
    self.cover_widgets = {}  -- Store references for lazy loading
    self:showReadView()
end

--[[--
Ensure cover cache directory exists.
@treturn string Cache directory path
--]]
function Read:ensureCacheDir()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        ok, lfs = pcall(require, "lfs")
    end
    if ok and lfs then
        local attr = lfs.attributes(COVER_CACHE_DIR)
        if not attr then
            -- Create parent directories if needed
            local parent = COVER_CACHE_DIR:match("(.+)/[^/]+$")
            if parent then
                lfs.mkdir(parent)
            end
            lfs.mkdir(COVER_CACHE_DIR)
        end
    end
    return COVER_CACHE_DIR
end

--[[--
Generate a cache key from filepath.
Uses a simple hash to create a filename-safe key.
@param filepath string Full path to the book file
@treturn string Cache key (filename safe)
--]]
function Read:getCacheKey(filepath)
    if not filepath then return nil end
    -- Simple hash: use last part of path + length
    local filename = filepath:match("([^/]+)$") or filepath
    -- Remove extension and sanitize
    local base = filename:gsub("%.[^%.]+$", ""):gsub("[^%w]", "_"):sub(1, 40)
    -- Add a simple checksum based on full path length and first/last chars
    local checksum = #filepath
    if #filepath > 1 then
        checksum = checksum + filepath:byte(1) + filepath:byte(-1)
    end
    return string.format("%s_%d.png", base, checksum)
end

--[[--
Get the full path for a cached cover.
@param filepath string Full path to the book file
@treturn string Full path to cached cover file
--]]
function Read:getCachedCoverPath(filepath)
    local key = self:getCacheKey(filepath)
    if not key then return nil end
    return COVER_CACHE_DIR .. "/" .. key
end

--[[--
Check if a cached cover exists.
@param filepath string Full path to the book file
@treturn boolean True if cached cover exists
--]]
function Read:hasCachedCover(filepath)
    local cache_path = self:getCachedCoverPath(filepath)
    if not cache_path then return false end

    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        ok, lfs = pcall(require, "lfs")
    end
    if ok and lfs then
        local attr = lfs.attributes(cache_path)
        return attr ~= nil and attr.mode == "file"
    end
    return false
end

--[[--
Save a blitbuffer cover image to cache.
@param filepath string Full path to the book file
@param bb BlitBuffer The cover image blitbuffer
--]]
function Read:saveCoverToCache(filepath, bb)
    if not filepath or not bb then return end

    self:ensureCacheDir()
    local cache_path = self:getCachedCoverPath(filepath)
    if not cache_path then return end

    -- Use KOReader's Blitbuffer write function if available
    local ok = pcall(function()
        local png = require("ffi/png")
        if png and png.encodeToFile then
            png.encodeToFile(cache_path, bb)
        end
    end)

    if not ok then
        -- Fallback: try using bb's built-in save if available
        pcall(function()
            if bb.writePNG then
                bb:writePNG(cache_path)
            end
        end)
    end
end

--[[--
Load a cover from cache.
@param filepath string Full path to the book file
@param width number Desired width
@param height number Desired height
@treturn Widget|nil ImageWidget if cached, nil otherwise
--]]
function Read:loadCoverFromCache(filepath, width, height)
    if not self:hasCachedCover(filepath) then return nil end

    local cache_path = self:getCachedCoverPath(filepath)
    local ok, result = pcall(function()
        return ImageWidget:new{
            file = cache_path,
            width = width,
            height = height,
            scale_factor = 0,
            autostretch = true,
        }
    end)

    if ok and result then
        return result
    end
    return nil
end

--[[--
Load covers asynchronously after initial render.
Loads covers in batches with batched UI refreshes for better e-ink performance.
--]]
function Read:loadCoversAsync()
    if not self.books or #self.books == 0 then return end
    if not self.cover_widgets then return end

    local book_index = 1
    local covers_loaded_since_refresh = 0
    local BATCH_SIZE = 3  -- Refresh UI after loading this many covers
    local MAX_BOOKS = 12  -- Limit to avoid loading too many

    local function loadNextCover()
        if book_index > #self.books or book_index > MAX_BOOKS then
            -- All done, trigger final refresh if any covers were loaded
            if covers_loaded_since_refresh > 0 and self.read_widget then
                UIManager:setDirty(self.read_widget, "ui")
            end
            return
        end

        local book = self.books[book_index]
        local widget_ref = self.cover_widgets[book_index]

        if book and book.file and widget_ref and widget_ref.cover_container then
            -- Try cache first (fast path)
            local cover = self:loadCoverFromCache(book.file, widget_ref.width, widget_ref.height)

            if not cover then
                -- Extract cover from document (slow operation)
                local cover_bb = nil
                local ok, doc = pcall(function()
                    return DocumentRegistry:openDocument(book.file)
                end)

                if ok and doc then
                    pcall(function()
                        if doc.getCoverPageImage then
                            local cok, cover_result = pcall(doc.getCoverPageImage, doc)
                            if cok and cover_result then
                                cover_bb = cover_result
                                -- Save to cache for next time
                                self:saveCoverToCache(book.file, cover_bb)
                            end
                        end
                    end)
                    doc:close()
                end

                if cover_bb then
                    cover = ImageWidget:new{
                        image = cover_bb,
                        width = widget_ref.width,
                        height = widget_ref.height,
                        scale_factor = 0,
                        autostretch = true,
                    }
                end
            end

            -- Update the widget if we got a cover
            if cover and widget_ref.cover_container then
                -- Replace the placeholder with the real cover
                widget_ref.cover_container[1] = cover
                covers_loaded_since_refresh = covers_loaded_since_refresh + 1

                -- Batch UI refreshes for better e-ink performance
                if covers_loaded_since_refresh >= BATCH_SIZE then
                    if self.read_widget then
                        UIManager:setDirty(self.read_widget, "ui")
                    end
                    covers_loaded_since_refresh = 0
                end
            end
        end

        book_index = book_index + 1
        -- Schedule next cover load with a small delay to keep UI responsive
        -- Longer delay if we just did a refresh (let e-ink settle)
        local delay = covers_loaded_since_refresh == 0 and 0.15 or 0.03
        UIManager:scheduleIn(delay, loadNextCover)
    end

    -- Start loading after a short delay to let initial render complete
    UIManager:scheduleIn(0.2, loadNextCover)
end

--[[--
Scan a directory for ebook files.
--]]
function Read:scanDirectoryForBooks(dir_path)
    local files = {}

    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        ok, lfs = pcall(require, "lfs")
    end

    if not ok or not lfs then
        return files
    end

    pcall(function()
        for entry in lfs.dir(dir_path) do
            if entry ~= "." and entry ~= ".." then
                local filepath = dir_path .. "/" .. entry
                local attr = lfs.attributes(filepath)

                if attr and attr.mode == "file" then
                    local ext = entry:match("%.([^%.]+)$")
                    if ext and EBOOK_EXTENSIONS[ext:lower()] then
                        table.insert(files, {
                            file = filepath,
                            time = attr.modification or os.time(),
                        })
                    end
                end
            end
        end
    end)

    table.sort(files, function(a, b)
        return (a.time or 0) > (b.time or 0)
    end)

    return files
end

--[[--
Get recently read books.
--]]
function Read:getRecentBooks()
    local books = {}

    -- First: scan Books folder if configured
    if self.TEST_BOOKS_PATH then
        local files = self:scanDirectoryForBooks(self.TEST_BOOKS_PATH)

        for i, item in ipairs(files) do
            if i > 12 then break end

            local progress = 0
            -- Try to get real progress from DocSettings
            local dok, DocSettings = pcall(require, "docsettings")
            if dok and DocSettings then
                local doc_settings = DocSettings:open(item.file)
                if doc_settings then
                    local pct = doc_settings:readSetting("percent_finished")
                    if pct then
                        progress = pct
                    end
                    -- DocSettings doesn't need explicit close
                end
            end

            local book = {
                file = item.file,
                title = self:extractTitle(item.file),
                time = item.time,
                progress = progress,
            }
            table.insert(books, book)
        end

        if #books > 0 then
            return books
        end
    end

    -- Fallback: use KOReader's ReadHistory
    local ok, ReadHistory = pcall(require, "readhistory")
    if ok and ReadHistory then
        local history = ReadHistory.hist or {}

        for i, item in ipairs(history) do
            if i > 12 then break end

            if item.file and not item.dim then
                local book = {
                    file = item.file,
                    title = self:extractTitle(item.file),
                    time = item.time,
                    progress = 0,
                }

                -- Try to get progress
                local dok, DocSettings = pcall(require, "docsettings")
                if dok and DocSettings then
                    local doc_settings = DocSettings:open(item.file)
                    if doc_settings then
                        local pct = doc_settings:readSetting("percent_finished")
                        if pct then
                            book.progress = pct
                        end
                        -- DocSettings doesn't need explicit close
                    end
                end

                table.insert(books, book)
            end
        end

        if #books > 0 then
            return books
        end
    end

    -- Last fallback: Get books from KOReader statistics database
    local db_books = ReadingStats:getRecentBooksFromDB(12) or {}
    for _, db_book in ipairs(db_books) do
        table.insert(books, {
            file = nil,  -- DB doesn't store file path
            title = db_book.title,
            time = db_book.last_open,
            progress = db_book.progress,
            pages = db_book.pages,
            pages_read = db_book.pages_read,
            total_time = db_book.total_time,
        })
    end

    return books
end

--[[--
Extract title from file path.
--]]
function Read:extractTitle(filepath)
    if not filepath then return "Unknown" end

    local filename = filepath:match("([^/]+)$") or filepath
    filename = filename:gsub("%.[^.]+$", "")
    filename = filename:gsub("[_-]", " ")
    return filename
end

--[[--
Open a book file.
--]]
function Read:openBook(filepath)
    if not filepath then return end

    if self.read_widget then
        UIManager:close(self.read_widget)
        self.read_widget = nil
    end

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(filepath)
end

--[[--
Create a placeholder cover.
--]]
function Read:createPlaceholderCover(width, height)
    return FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        margin = 0,
        bordersize = 1,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{w = width, h = height},
            TextWidget:new{
                text = "?",
                face = Font:getFace("tfont", 28),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        },
    }
end

--[[--
Get cover image for a book.
--]]
function Read:getCoverImage(filepath, width, height)
    if not filepath then
        return self:createPlaceholderCover(width, height)
    end

    local cover_bb = nil

    local ok, doc = pcall(function()
        return DocumentRegistry:openDocument(filepath)
    end)

    if ok and doc then
        -- Wrap cover extraction in pcall to ensure doc:close() always runs
        pcall(function()
            if doc.getCoverPageImage then
                local cok, cover = pcall(doc.getCoverPageImage, doc)
                if cok and cover then
                    cover_bb = cover
                end
            end
        end)
        doc:close()  -- Always close document to prevent resource leak
    end

    if cover_bb then
        return ImageWidget:new{
            image = cover_bb,
            width = width,
            height = height,
            scale_factor = 0,
            autostretch = true,
        }
    end

    return self:createPlaceholderCover(width, height)
end

--[[--
Create a book card widget with placeholder cover for lazy loading.
@param book table Book info with file, title, progress
@param card_width number Card width in pixels
@param card_height number Card height in pixels
@param book_index number Index of book for lazy loading reference
@treturn Widget The book card widget
--]]
function Read:createBookCard(book, card_width, card_height, book_index)
    local title_height = 28
    local progress_height = getProgressBarHeight() + 2
    local cover_height = card_height - title_height - progress_height

    -- Create placeholder cover initially (will be replaced asynchronously)
    local placeholder = self:createPlaceholderCover(card_width, cover_height)

    -- Create a container that can hold the cover (for lazy update)
    local cover_container = VerticalGroup:new{
        align = "center",
        placeholder,  -- This will be replaced with real cover
    }

    -- Store reference for lazy loading
    if book_index and book.file then
        self.cover_widgets[book_index] = {
            cover_container = cover_container,
            width = card_width,
            height = cover_height,
        }
    end

    local title_text = book.title or "Unknown"
    if #title_text > 14 then
        title_text = title_text:sub(1, 12) .. ".."
    end

    local title_widget = CenterContainer:new{
        dimen = Geom:new{w = card_width, h = title_height},
        TextWidget:new{
            text = title_text,
            face = Font:getFace("tfont", 10),
            fgcolor = Blitbuffer.COLOR_BLACK,
        },
    }

    local progress_widget = ProgressWidget:new{
        width = card_width,
        height = getProgressBarHeight(),
        percentage = book.progress or 0,
        margin_h = 0,
        margin_v = 0,
        radius = 0,
        bordersize = 0,
        bgcolor = Blitbuffer.COLOR_LIGHT_GRAY,
        fillcolor = Blitbuffer.COLOR_BLACK,
    }

    local card_content = VerticalGroup:new{
        align = "center",
    }
    table.insert(card_content, cover_container)
    table.insert(card_content, title_widget)
    table.insert(card_content, progress_widget)

    return FrameContainer:new{
        width = card_width,
        height = card_height,
        padding = 0,
        margin = 0,
        bordersize = 1,
        background = Blitbuffer.COLOR_WHITE,
        card_content,
    }
end

--[[--
Create the all-time book stats widget from KOReader statistics.
--]]
function Read:createBookStatsRow(content_width)
    -- Get total stats from KOReader's statistics database
    local total_stats = ReadingStats:getTotalReadingStats()

    local total_books = total_stats.total_books or 0
    local total_pages = total_stats.total_pages or 0
    local total_time = ReadingStats:formatTime(total_stats.total_time or 0)

    -- Use UIConfig for consistent spacing and sizing
    local card_spacing = UIConfig:dim("stat_card_spacing")
    local card_height = UIConfig:dim("stat_card_height")
    local value_font = UIConfig:fontSize("stat_value")
    local label_font = UIConfig:fontSize("stat_label")

    -- Get colors (night mode aware)
    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local bg_color = UIConfig:color("background")

    -- Calculate card widths: account for spacing between 3 cards
    local total_spacing = card_spacing * 2  -- Two gaps between three cards
    local third_width = math.floor((content_width - total_spacing) / 3)

    -- Helper to create a stat card
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

    local books_stat = createStatCard(total_books, "Books")
    local pages_stat = createStatCard(total_pages, "Pages")
    local time_stat = createStatCard(total_time, "Total Time")

    -- Build stats row with proper spacing
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
--]]
function Read:createStatsOverview(content_width)
    -- Try to get stats from KOReader database first
    local today_db = ReadingStats:getTodayStatsFromDB()
    local week_db = ReadingStats:getWeekStatsFromDB()

    -- Fallback to stored logs if database not available
    local weekly = ReadingStats:getWeeklyStats()
    local today_stats = ReadingStats:getTodayStats(self.ui)

    local today_pages = today_db.pages > 0 and today_db.pages or (today_stats.pages_read or 0)
    local today_time_sec = today_db.time > 0 and today_db.time or (today_stats.time_spent or 0)
    local today_time = ReadingStats:formatTime(today_time_sec)

    local week_pages = week_db.pages > 0 and week_db.pages or (weekly.total_pages or 0)
    local week_time_sec = week_db.time > 0 and week_db.time or (weekly.total_time or 0)
    local week_time = ReadingStats:formatTime(week_time_sec)

    -- Use UIConfig for consistent spacing and colors (match book stats row)
    local card_spacing = UIConfig:dim("stat_card_spacing")
    local card_height = UIConfig:dim("stat_card_height")
    local caption_font = UIConfig:fontSize("caption")
    local body_font = UIConfig:fontSize("body")

    -- Get colors (night mode aware)
    local fg_color = UIConfig:color("foreground")
    local muted_color = UIConfig:color("muted")
    local bg_color = UIConfig:color("background")

    -- Helper to create period stats (centered in container)
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

    local left_stats = createPeriodStats("Today", today_pages, today_time)
    local right_stats = createPeriodStats("This Week", week_pages, week_time)

    -- Calculate card widths to match book stats row styling
    local outer_padding = UIConfig:spacing("sm")
    local outer_border = UIConfig:dim("border_thin")
    local inner_content_width = content_width - (outer_padding * 2) - (outer_border * 2)
    local card_width = math.floor((inner_content_width - card_spacing) / 2)

    -- Use same height as upper stats row
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

    -- Wrap in FrameContainer with same styling as book stats row
    return FrameContainer:new{
        width = content_width,
        padding = UIConfig:spacing("sm"),
        bordersize = UIConfig:dim("border_thin"),
        background = bg_color,
        stats_row,
    }
end

--[[--
Create the book grid widget.
--]]
function Read:createBookGrid(books, content_width)
    local card_positions = {}

    if #books == 0 then
        return TextWidget:new{
            text = "No recently read books",
            face = Font:getFace("tfont", 14),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }, card_positions
    end

    local total_spacing = getCardSpacing() * (getGridCols() - 1)
    local card_width = math.floor((content_width - total_spacing) / getGridCols())
    local card_height = math.floor(card_width * 1.5)

    self.card_width = card_width
    self.card_height = card_height

    local grid = VerticalGroup:new{align = "left"}

    table.insert(grid, TextWidget:new{
        text = "Recently Read",
        face = Font:getFace("tfont", 16),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(grid, VerticalSpan:new{width = Size.padding.small})

    local row = HorizontalGroup:new{align = "top"}
    local row_count = 0

    for i, book in ipairs(books) do
        if (i - 1) % getGridCols() == 0 and i > 1 then
            table.insert(grid, row)
            table.insert(grid, VerticalSpan:new{width = getCardSpacing()})
            row = HorizontalGroup:new{align = "top"}
            row_count = row_count + 1
        elseif i > 1 then
            table.insert(row, HorizontalSpan:new{width = getCardSpacing()})
        end

        local card = self:createBookCard(book, card_width, card_height, i)
        table.insert(row, card)

        local col = (i - 1) % getGridCols()
        card_positions[i] = {
            col = col,
            row = row_count,
            book = book,
        }
    end

    -- Add last row if it has cards
    if #row > 0 then
        table.insert(grid, row)
    end

    return grid, card_positions
end

--[[--
Show the main read view.
--]]
function Read:showReadView()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- Calculate dimensions
    local scroll_width = UIConfig:getScrollWidth()
    local scroll_height = screen_height
    local page_padding = UIConfig:getPagePadding()
    local content_width = UIConfig:getPaddedContentWidth()

    -- Get recent books
    self.books = self:getRecentBooks()

    -- Build content
    local content = VerticalGroup:new{align = "left"}

    -- Title (standardized to page_title size)
    table.insert(content, TextWidget:new{
        text = "Reading",
        face = UIConfig:getFont("tfont", UIConfig:fontSize("page_title")),
        fgcolor = UIConfig:color("foreground"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})

    -- All-time book stats (from KOReader statistics database)
    local book_stats = self:createBookStatsRow(content_width)
    table.insert(content, book_stats)
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("sm")})

    -- Today/Week reading stats row
    local stats_widget = self:createStatsOverview(content_width)
    table.insert(content, stats_widget)

    -- Divider (uses muted color for subtle appearance)
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("lg")})
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w = content_width, h = 1},
        background = UIConfig:color("muted"),
    })
    table.insert(content, VerticalSpan:new{width = UIConfig:spacing("md")})

    -- Book grid
    local grid_widget, card_positions = self:createBookGrid(self.books, content_width)
    self.card_positions = card_positions
    table.insert(content, grid_widget)

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

    -- Create main layout with full-screen white background to prevent bleed-through
    local white_bg = FrameContainer:new{
        width = screen_width,
        height = screen_height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{},  -- Empty child required by FrameContainer
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

    -- Setup book tap handlers
    self:setupBookTapHandlers()

    -- Setup corner gesture handlers using shared helpers
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

    -- Start loading covers asynchronously after initial render
    self:loadCoversAsync()
end

--[[--
Setup tap handlers for book cards.
--]]
function Read:setupBookTapHandlers()
    if not self.books or #self.books == 0 then return end
    if not self.card_positions then return end

    local card_width = self.card_width or 100
    local card_height = self.card_height or 150

    -- NOTE: The content is laid out with visual_y tracking, but we need to track
    -- where the book grid actually starts. Use book_grid_y if set, otherwise approximate.
    -- The header includes: title, stats, section header, spacing - approximately scaled 140px
    local header_height = self.book_grid_y or UIConfig:scale(160)

    for i, pos in pairs(self.card_positions) do
        local x = Size.padding.large + pos.col * (card_width + getCardSpacing())
        local y = header_height + pos.row * (card_height + getCardSpacing())

        local gesture_name = "BookTap_" .. i
        self.read_widget.ges_events[gesture_name] = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = x,
                    y = y,
                    w = card_width,
                    h = card_height,
                },
            },
        }

        local book = pos.book
        local read_module = self
        self.read_widget["on" .. gesture_name] = function()
            read_module:openBook(book.file)
            return true
        end
    end
end

--[[--
Close the read view.
--]]
function Read:close()
    if self.read_widget then
        UIManager:close(self.read_widget)
        self.read_widget = nil
    end
end

return Read
