# KOReader Life Tracker - Integration & Refactoring Plan (Maximized)

## Optimization Strategy: Composition Over Monolith

After deep analysis, the maximum optimization comes from extracting **small, composable pieces** rather than large unified functions. This preserves functionality while eliminating redundancy.

---

## KOReader Native Widget Integration

### Replace Custom Components with KOReader Widgets

| Current Custom | KOReader Widget | Location | Benefit |
|----------------|-----------------|----------|---------|
| FrameContainer ON/OFF toggle | **ToggleSwitch** | reminders.lua | Native look, accessibility |
| Button group for energy tabs | **RadioButtonTable** | dashboard.lua | Exclusive selection built-in |
| Button group for type tabs | **RadioButtonTable** | quests.lua | Focus management |
| Manual stats layout | **KeyValuePage** | dashboard.lua, journal.lua | Pagination, overflow handling |
| Manual FrameContainer buttons | **Button** widget | timeline.lua | Callbacks, proper tap handling |

### KOReader Widgets to Adopt

#### 1. ToggleSwitch (for Reminders)
```lua
-- Path: frontend/ui/widget/toggleswitch.lua
local ToggleSwitch = require("ui/widget/toggleswitch")

local toggle = ToggleSwitch:new{
    width = Screen:scaleBySize(100),
    default_value = reminder.enabled and 1 or 2,
    values = {true, false},
    toggle = {"ON", "OFF"},
    callback = function(pos)
        self:toggleReminder(reminder, pos == 1)
    end,
}
```

#### 2. RadioButtonTable (for Energy/Type Tabs)
```lua
-- Path: frontend/ui/widget/radiobuttontable.lua
local RadioButtonTable = require("ui/widget/radiobuttontable")

local energy_tabs = RadioButtonTable:new{
    width = content_width,
    radio_buttons = {
        {{"Energetic"}, {"Average"}, {"Tired"}, {"Down"}},
    },
    checked_button = current_energy_index,
    callback = function(energy)
        self:setTodayEnergy(energy)
    end,
}
```

#### 3. KeyValuePage (for Stats Display)
```lua
-- Path: frontend/ui/widget/keyvaluepage.lua
local KeyValuePage = require("ui/widget/keyvaluepage")

local stats_page = KeyValuePage:new{
    title = _("Today's Stats"),
    kv_pairs = {
        {_("Reading Time"), formatted_time},
        {_("Quests Completed"), string.format("%d/%d", completed, total)},
        {_("Current Streak"), tostring(streak)},
    },
}
UIManager:show(stats_page)
```

### Standard Size Constants to Use

```lua
-- Already available in KOReader:
Size.padding.default   -- 5px scaled
Size.padding.small     -- 2px scaled
Size.padding.large     -- 10px scaled
Size.padding.button    -- 2px scaled
Size.padding.buttontable -- 4px scaled

Size.margin.default    -- 5px scaled
Size.margin.small      -- 2px scaled
Size.margin.button     -- 0

Size.border.default    -- 1px scaled
Size.border.thin       -- 0.5px scaled
Size.border.thick      -- 2px scaled
Size.border.button     -- 1.5px scaled

Size.item.height_default -- 30px scaled (good for list items)
Size.item.height_big     -- 40px scaled (good for touch targets)

Size.span.horizontal_default -- 10px scaled
Size.span.vertical_default   -- 2px scaled
```

### Font System Integration

```lua
-- Use Font:getFace with standard face names:
Font:getFace("cfont", size)     -- Content font (NotoSans-Regular)
Font:getFace("tfont", size)     -- Title font (NotoSans-Bold)
Font:getFace("ffont", size)     -- Footer font
Font:getFace("infofont", size)  -- Info message font

-- ALWAYS use Screen:scaleBySize for custom sizes:
Font:getFace("cfont", Screen:scaleBySize(14))
```

### Color System (Night Mode Compatible)

```lua
-- Standard colors (auto-invert in night mode):
Blitbuffer.COLOR_WHITE
Blitbuffer.COLOR_BLACK
Blitbuffer.COLOR_GRAY
Blitbuffer.COLOR_LIGHT_GRAY
Blitbuffer.COLOR_DARK_GRAY

-- For custom colors, check night mode:
local G_reader_settings = require("luasettings"):open(DataStorage:getSettingsDir().."/settings.reader.lua")
local night_mode = G_reader_settings:isTrue("night_mode")
```

### Reference: Statistics Plugin Pattern

The Statistics Plugin (`/tmp/koreader/plugins/statistics.koplugin/main.lua`) demonstrates:
- Proper KeyValuePage usage for stats display
- ButtonDialog for action menus
- ConfirmBox for confirmations
- Standard sizing and color patterns

---

## Phase 1: Create `modules/ui_helpers.lua`

### 1.1 Gesture Helpers (100% identical across 6 modules)

```lua
-- Saves ~180 lines (30 lines × 6 modules → 30 lines × 1)
function UIHelpers.dispatchCornerGesture(ui, gesture_name)
    -- Exact code from dashboard.lua:77-106
end

-- Saves ~450 lines (90 lines × 5 modules → 50 lines × 1)
function UIHelpers.setupCornerGestures(widget, module_self, dims)
    -- dims = {screen_width, screen_height, top_safe_zone}
    -- Sets up: TopCenter, TopLeft, TopRight, BottomLeft, BottomRight
    -- Uses module_self.ui for dispatchCornerGesture calls
end

-- Saves ~60 lines (12 lines × 5 modules → 12 lines × 1)
function UIHelpers.setupSwipeToClose(widget, close_callback, dims)
    -- East swipe handler
end
```

### 1.2 Main Layout Builder (100% identical)

```lua
-- Saves ~100 lines (20 lines × 5 modules → 20 lines × 1)
function UIHelpers.buildMainLayout(content, tab_id, screen_dims, on_close)
    -- Returns: InputContainer with OverlapGroup containing:
    --   - ScrollableContainer (content)
    --   - RightContainer (navigation tabs)
    -- Also returns scrollable_container reference for show_parent
end
```

### 1.3 Page Header Builder

```lua
-- Saves ~75 lines (15 lines × 5 modules → 15 lines × 1)
function UIHelpers.buildPageHeader(title, subtitle)
    -- Returns: VerticalGroup with title widget + safe zone spacing
    -- subtitle is optional (used for Dashboard greeting + quote)
end
```

**Total Phase 1 Savings: ~865 lines → ~130 lines = 735 lines saved**

---

## Phase 2: Create `modules/quest_ui_helpers.lua`

### 2.1 Button Factory Functions (100% identical styling)

```lua
-- Each button is ~15 lines, repeated 2-3x per module
function QuestUI.createMinusButton(callback)
    return Button:new{
        text = "−",
        width = QuestUI.SMALL_BUTTON_WIDTH,
        max_width = QuestUI.SMALL_BUTTON_WIDTH,
        bordersize = 1, margin = 0, padding = Size.padding.small,
        text_font_face = "cfont", text_font_size = 16, text_font_bold = true,
        callback = callback,
    }
end

function QuestUI.createPlusButton(callback, enabled)
function QuestUI.createDoneButton(callback, is_completed)
function QuestUI.createSkipButton(callback, text)  -- text = "Skip" or "Undo"
```

### 2.2 Progress Display Builder (95% identical)

```lua
function QuestUI.buildProgressDisplay(current, target, completed, options)
    -- options.show_unit, options.unit
    -- Returns FrameContainer with progress text
end
```

### 2.3 Quest Title Builder (90% identical)

```lua
function QuestUI.buildQuestTitle(quest, options)
    -- options.show_streak, options.max_width, options.text_color
    -- Returns TextWidget with title (+ optional streak count)
end
```

### 2.4 Quest Row Assembler (Optional - if variations are minimal)

```lua
function QuestUI.assembleProgressiveRow(quest, options, callbacks)
    -- Uses: createMinusButton, buildProgressDisplay, createPlusButton, buildQuestTitle
    -- callbacks: {on_minus, on_plus}
end

function QuestUI.assembleBinaryRow(quest, options, callbacks)
    -- Uses: createDoneButton, createSkipButton, buildQuestTitle
    -- callbacks: {on_complete, on_skip}
end
```

**Total Phase 2 Savings: ~380 lines → ~120 lines = 260 lines saved**

---

## Phase 3: Create `modules/utils.lua`

Keep Data.lua focused on persistence (already 1,284 lines).

```lua
-- Time formatting
function Utils.formatReadingTime(seconds)
function Utils.formatDate(date_string, format)

-- Day names (currently hardcoded in 3+ places)
function Utils.getDayAbbreviations()  -- {"Mon", "Tue", ...}
function Utils.getDayNames()          -- {"Monday", "Tuesday", ...}

-- Input validation (move from Data.lua if present)
function Utils.sanitizeTextInput(text)
```

---

## Phase 4: Extend `modules/ui_config.lua`

### 4.1 Font Size Constants (Replace ~40 hardcoded values)

```lua
-- Add to getDimensions():
font_body_small = 13,      -- dashboard:820, quests:398
font_nav_button = 18,      -- timeline:200
font_heatmap_title = 18,   -- dashboard:1352
font_heatmap_label = 14,   -- dashboard heatmap
font_graph = 11,           -- journal:708
font_progress = 11,        -- dashboard:858, quests:439
font_button_primary = 12,  -- Done button
font_button_secondary = 10 -- Skip button
```

### 4.2 Button Width Constants

```lua
button_width = 60,         -- Done/Skip buttons
small_button_width = 40,   -- +/- buttons
progress_width = 70,       -- Progress display
```

---

## Phase 5: Module-by-Module Refactoring

### Refactoring Pattern per Module:

1. Import ui_helpers and quest_ui_helpers
2. Delete `dispatchCornerGesture` function
3. Replace gesture setup with `UIHelpers.setupCornerGestures()`
4. Replace quest buttons with `QuestUI.create*Button()`
5. Standardize Font:getFace → UIConfig:getFont
6. Add UIManager:setDirty where missing
7. Test thoroughly

### Module Order:

| Module | Priority | Special Changes |
|--------|----------|-----------------|
| dashboard.lua | 1 | Use helpers, **RadioButtonTable for energy tabs**, KeyValuePage for stats |
| quests.lua | 2 | Use helpers, **RadioButtonTable for type tabs** |
| timeline.lua | 3 | **Convert nav to Button widgets**, use helpers |
| reminders.lua | 4 | **ToggleSwitch for on/off**, add setDirty |
| journal.lua | 5 | **KeyValuePage for mood stats**, add setDirty |
| read.lua | 6 | Add corner gestures (currently missing!) |

### Detailed Module Changes:

#### dashboard.lua
- Replace energy Button group → **RadioButtonTable**
- Replace stats display → **KeyValuePage** (optional, inline works too)
- Use UIHelpers for gestures
- Use QuestUI for quest rows

#### quests.lua
- Replace type tabs Button group → **RadioButtonTable**
- Use UIHelpers for gestures
- Use QuestUI for quest rows

#### timeline.lua
- Replace FrameContainer day nav → **Button widgets**
- Use UIHelpers for gestures
- Keep quest row (has Unskip variant)

#### reminders.lua
- Replace FrameContainer toggle → **ToggleSwitch**
- Add UIManager:setDirty after toggle
- Use UIHelpers for gestures

#### journal.lua
- Consider **KeyValuePage** for category breakdown
- Add UIManager:setDirty after saves
- Use UIHelpers for gestures

#### read.lua
- Add corner gesture handlers (missing!)
- Standardize fonts

---

## Phase 6: Timeline & Reminders Button Conversion

### Timeline Day Navigation (lines 190-239)

**Before:** Manual FrameContainer + separate GestureRange
**After:**
```lua
local prev_button = Button:new{
    text = "◀",
    width = NAV_BUTTON_WIDTH,
    callback = function() self:navigateDay(-1) end,
    text_font_face = "tfont",
    text_font_size = UIConfig:fontSize("nav_button"),
}
```

### Reminders Toggle (lines 382-427)

**Before:** FrameContainer + manual coordinate tracking
**After:**
```lua
local toggle_button = Button:new{
    text = reminder.enabled and "ON" or "OFF",
    preselect = reminder.enabled,
    callback = function() self:toggleReminder(reminder) end,
}
```

---

## Phase 7: UIManager:setDirty Audit

| Module | Missing Location | Add |
|--------|-----------------|-----|
| reminders.lua | after toggleReminder() | `UIManager:setDirty("all", "ui")` |
| journal.lua | after save notes (~872) | `UIManager:setDirty("all", "ui")` |
| journal.lua | after save reflection | `UIManager:setDirty("all", "ui")` |

---

## Expected Impact Summary

### Code Reduction

| Optimization | Lines Before | Lines After | Saved |
|--------------|--------------|-------------|-------|
| dispatchCornerGesture | 180 (6×30) | 30 | 150 |
| Corner gesture setup | 450 (5×90) | 50 | 400 |
| Swipe handler | 60 (5×12) | 12 | 48 |
| Main layout builder | 100 (5×20) | 20 | 80 |
| Page header | 75 (5×15) | 15 | 60 |
| Quest buttons | ~240 | ~60 | 180 |
| Progress display | ~80 | ~20 | 60 |
| **TOTAL** | **~1185** | **~207** | **~978** |

### KOReader Integration Improvements

| Issue | Before | After |
|-------|--------|-------|
| Hardcoded font sizes | 40 | 0 |
| Missing setDirty | 3 modules | 0 |
| Manual gesture buttons | 4 | 0 |
| Custom toggle buttons | FrameContainer | ToggleSwitch |
| Tab selection | Button group | RadioButtonTable |
| Stats display | Manual layout | KeyValuePage option |
| Corner gestures in read.lua | Missing | Added |
| Night mode support | Partial | Full (via Blitbuffer colors) |
| DPI scaling | Partial | Full (via Screen:scaleBySize) |
| User font settings | Ignored | Respected |

---

## Files to Create

| File | Size (est) | Purpose |
|------|------------|---------|
| modules/ui_helpers.lua | ~150 lines | Gestures, layout, headers |
| modules/quest_ui_helpers.lua | ~120 lines | Button factories, progress, title |
| modules/utils.lua | ~50 lines | Time/date formatting, validation |

## Files to Modify

| File | Lines Changed (est) |
|------|---------------------|
| modules/ui_config.lua | +20 (font constants) |
| modules/dashboard.lua | -200 (use helpers) |
| modules/quests.lua | -180 (use helpers) |
| modules/timeline.lua | -150 (helpers + Button conversion) |
| modules/reminders.lua | -100 (helpers + Button + setDirty) |
| modules/journal.lua | -80 (helpers + setDirty) |
| modules/read.lua | +30 (add corner gestures) |

---

## Testing Checklist

### Per Module:
- [ ] All buttons respond correctly
- [ ] Corner taps work (top-left, top-right, etc.)
- [ ] Top-center tap opens KOReader menu
- [ ] Swipe east closes view
- [ ] Screen refreshes properly
- [ ] Night mode colors correct

### Integration:
- [ ] Change KOReader font → plugin fonts update
- [ ] All 6 pages work together
- [ ] Navigation tabs work
- [ ] Quest data persists correctly

---

## Rollback Strategy

1. Create feature branch per module
2. Commit atomic changes
3. Test each module independently
4. Merge only after full testing
5. If issues: `git revert <commit>` for that module only
