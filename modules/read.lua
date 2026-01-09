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
local Event = require("ui/event")
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

local Read = {}

-- Grid configuration
local GRID_COLS = 3
local CARD_SPACING = Size.padding.default or 10
local PROGRESS_BAR_HEIGHT = 4

-- Scan Books folder for ebooks
-- Set to nil to use only ReadHistory/database
Read.TEST_BOOKS_PATH = "Books"

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
    self:showReadView()
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
                    doc_settings:close()
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
                        doc_settings:close()
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
    local db_books = ReadingStats:getRecentBooksFromDB(12)
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
        if doc.getCoverPageImage then
            local cok, cover = pcall(function()
                return doc:getCoverPageImage()
            end)
            if cok and cover then
                cover_bb = cover
            end
        end
        doc:close()
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
Create a book card widget.
--]]
function Read:createBookCard(book, card_width, card_height)
    local title_height = 28
    local progress_height = PROGRESS_BAR_HEIGHT + 2
    local cover_height = card_height - title_height - progress_height

    local cover = self:getCoverImage(book.file, card_width, cover_height)

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
        height = PROGRESS_BAR_HEIGHT,
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
    table.insert(card_content, cover)
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

    local third_width = math.floor((content_width - 20) / 3)

    local books_stat = VerticalGroup:new{align = "center"}
    table.insert(books_stat, TextWidget:new{
        text = tostring(total_books),
        face = Font:getFace("tfont", 18),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(books_stat, TextWidget:new{
        text = "Books",
        face = Font:getFace("tfont", 10),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    local pages_stat = VerticalGroup:new{align = "center"}
    table.insert(pages_stat, TextWidget:new{
        text = tostring(total_pages),
        face = Font:getFace("tfont", 18),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(pages_stat, TextWidget:new{
        text = "Pages",
        face = Font:getFace("tfont", 10),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    local time_stat = VerticalGroup:new{align = "center"}
    table.insert(time_stat, TextWidget:new{
        text = total_time,
        face = Font:getFace("tfont", 18),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(time_stat, TextWidget:new{
        text = "Total Time",
        face = Font:getFace("tfont", 10),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    local stats_row = HorizontalGroup:new{align = "top"}
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = 50},
        books_stat,
    })
    table.insert(stats_row, HorizontalSpan:new{width = 10})
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = 50},
        pages_stat,
    })
    table.insert(stats_row, HorizontalSpan:new{width = 10})
    table.insert(stats_row, CenterContainer:new{
        dimen = Geom:new{w = third_width, h = 50},
        time_stat,
    })

    return FrameContainer:new{
        width = content_width,
        padding = Size.padding.small,
        bordersize = 1,
        background = Blitbuffer.COLOR_WHITE,
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

    local half_width = math.floor((content_width - 10) / 2)

    local left_stats = VerticalGroup:new{align = "left"}
    table.insert(left_stats, TextWidget:new{
        text = "Today",
        face = Font:getFace("tfont", 11),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })
    table.insert(left_stats, TextWidget:new{
        text = string.format("%d pages", today_pages),
        face = Font:getFace("tfont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(left_stats, TextWidget:new{
        text = today_time,
        face = Font:getFace("tfont", 11),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    local right_stats = VerticalGroup:new{align = "left"}
    table.insert(right_stats, TextWidget:new{
        text = "This Week",
        face = Font:getFace("tfont", 11),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })
    table.insert(right_stats, TextWidget:new{
        text = string.format("%d pages", week_pages),
        face = Font:getFace("tfont", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(right_stats, TextWidget:new{
        text = week_time,
        face = Font:getFace("tfont", 11),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

    local stats_row = HorizontalGroup:new{align = "top"}
    table.insert(stats_row, FrameContainer:new{
        width = half_width,
        padding = Size.padding.small,
        bordersize = 1,
        background = Blitbuffer.COLOR_WHITE,
        left_stats,
    })
    table.insert(stats_row, HorizontalSpan:new{width = 10})
    table.insert(stats_row, FrameContainer:new{
        width = half_width,
        padding = Size.padding.small,
        bordersize = 1,
        background = Blitbuffer.COLOR_WHITE,
        right_stats,
    })

    return stats_row
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

    local total_spacing = CARD_SPACING * (GRID_COLS - 1)
    local card_width = math.floor((content_width - total_spacing) / GRID_COLS)
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
        if (i - 1) % GRID_COLS == 0 and i > 1 then
            table.insert(grid, row)
            table.insert(grid, VerticalSpan:new{width = CARD_SPACING})
            row = HorizontalGroup:new{align = "top"}
            row_count = row_count + 1
        elseif i > 1 then
            table.insert(row, HorizontalSpan:new{width = CARD_SPACING})
        end

        local card = self:createBookCard(book, card_width, card_height)
        table.insert(row, card)

        local col = (i - 1) % GRID_COLS
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
    local scroll_width = screen_width - Navigation.TAB_WIDTH
    local scroll_height = screen_height
    local content_width = scroll_width - Size.padding.large * 3

    -- Get recent books
    self.books = self:getRecentBooks()

    -- Build content
    local content = VerticalGroup:new{align = "left"}

    -- Title
    table.insert(content, TextWidget:new{
        text = "Reading",
        face = Font:getFace("tfont", 20),
    })
    table.insert(content, VerticalSpan:new{width = Size.padding.default})

    -- All-time book stats (from KOReader statistics database)
    local book_stats = self:createBookStatsRow(content_width)
    table.insert(content, book_stats)
    table.insert(content, VerticalSpan:new{width = Size.padding.small})

    -- Today/Week reading stats row
    local stats_widget = self:createStatsOverview(content_width)
    table.insert(content, stats_widget)

    -- Divider
    table.insert(content, VerticalSpan:new{width = Size.padding.default})
    table.insert(content, LineWidget:new{
        dimen = Geom:new{w = content_width, h = 1},
        background = Blitbuffer.COLOR_LIGHT_GRAY,
    })
    table.insert(content, VerticalSpan:new{width = Size.padding.default})

    -- Book grid
    local grid_widget, card_positions = self:createBookGrid(self.books, content_width)
    self.card_positions = card_positions
    table.insert(content, grid_widget)

    -- Bottom padding
    table.insert(content, VerticalSpan:new{width = Size.padding.large * 2})

    -- Wrap content in frame with minimum height to fill viewport
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local inner_frame = FrameContainer:new{
        width = scroll_width - scrollbar_width,
        height = math.max(scroll_height, content:getSize().h + Size.padding.large * 2),
        padding = Size.padding.large,
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
        UIManager:close(read_module.read_widget)
        Navigation:navigateTo(tab_id, ui)
    end

    -- Build navigation tabs
    local tabs = Navigation:buildTabColumn("read", screen_height)
    Navigation.on_tab_change = on_tab_change

    -- Create main layout
    local main_layout = OverlapGroup:new{
        dimen = Geom:new{w = screen_width, h = screen_height},
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

    -- Top zone gesture for KOReader menu
    local top_safe_zone = math.floor(screen_height / 8)
    local corner_size = math.floor(screen_width / 8)

    self.read_widget.ges_events.TopCenterTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = corner_size,
                y = 0,
                w = screen_width - corner_size * 2,
                h = top_safe_zone,
            },
        },
    }
    local read_ui = self.ui
    self.read_widget.onTopCenterTap = function()
        if read_ui and read_ui.menu then
            read_ui.menu:onShowMenu()
        elseif read_ui then
            read_ui:handleEvent(Event:new("ShowReaderMenu"))
        end
        return true
    end

    -- Swipe to close
    self.read_widget.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = Geom:new{
                x = 0,
                y = 0,
                w = screen_width - Navigation.TAB_WIDTH,
                h = screen_height,
            },
        },
    }
    self.read_widget.onSwipe = function(_, _, ges)
        if ges.direction == "east" then
            UIManager:close(self.read_widget)
            return true
        end
        return false
    end

    UIManager:show(self.read_widget)
end

--[[--
Setup tap handlers for book cards.
--]]
function Read:setupBookTapHandlers()
    if not self.books or #self.books == 0 then return end
    if not self.card_positions then return end

    local card_width = self.card_width or 100
    local card_height = self.card_height or 150

    -- Header heights (approximate)
    local header_height = 150

    for i, pos in pairs(self.card_positions) do
        local x = Size.padding.large + pos.col * (card_width + CARD_SPACING)
        local y = header_height + pos.row * (card_height + CARD_SPACING)

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
