# Testing the KOReader Life Tracker Plugin

## Testing Options

### Option 1: Test on Actual E-Reader (Recommended)

The most reliable way to test is on an actual KOReader device.

**Setup:**
1. Copy the entire `koreader-life-tracker` folder to your device's plugins directory:
   - **Kindle**: `koreader/plugins/lifetracker.koplugin/`
   - **Kobo**: `.adds/koreader/plugins/lifetracker.koplugin/`
   - **Android**: `/sdcard/koreader/plugins/lifetracker.koplugin/`

2. Rename the folder to `lifetracker.koplugin` (required for KOReader to recognize it)

3. Restart KOReader

4. Access from menu: **Tools > Life Tracker**

**What to Test:**
- [ ] Plugin appears in Tools menu
- [ ] Morning check-in dialog shows on first open
- [ ] Energy level selection works
- [ ] Dashboard displays correctly
- [ ] Tab navigation works (tap right-side tabs)
- [ ] Add a quest (Daily/Weekly/Monthly)
- [ ] Complete a quest (tap → Complete)
- [ ] Streak increments correctly
- [ ] Heatmap updates after completion
- [ ] Settings menu works
- [ ] Reminders can be added
- [ ] Journal view shows data

---

### Option 2: Test with KOReader Emulator

KOReader has an emulator for desktop testing.

**Setup:**
```bash
# Clone KOReader
git clone --recurse-submodules https://github.com/koreader/koreader.git
cd koreader

# Build for emulator (requires dependencies)
./kodev build

# Copy plugin to emulator plugins
cp -r /path/to/koreader-life-tracker ./plugins/lifetracker.koplugin

# Run emulator
./kodev run
```

**Dependencies:**
- Linux/macOS recommended
- SDL2
- Lua 5.1 (LuaJIT)
- Various build tools (see KOReader wiki)

**KOReader Emulator Docs:** https://github.com/koreader/koreader/wiki/Building-KOReader

---

### Option 3: Lua Syntax Checking Only

Quick check without running KOReader:

```bash
# Install luacheck
brew install luacheck  # macOS
# or
luarocks install luacheck

# Run linter
cd koreader-life-tracker
luacheck . --std lua51+lua52+lua53 --ignore 211 --ignore 212
```

This validates syntax but doesn't test functionality.

---

### Option 4: Unit Tests (Future)

The plugin doesn't have unit tests yet. To add them:

1. Create `tests/` directory
2. Use [busted](https://lunarmodules.github.io/busted/) framework
3. Mock KOReader's UI components

Example test structure:
```lua
-- tests/data_spec.lua
describe("Data module", function()
    local Data

    setup(function()
        -- Mock LuaSettings
        package.loaded["luasettings"] = {
            open = function() return {
                readSetting = function() return {} end,
                saveSetting = function() end,
                flush = function() end,
            } end
        }
        Data = require("modules/data")
    end)

    it("should generate unique IDs", function()
        local id1 = Data:generateUniqueId()
        local id2 = Data:generateUniqueId()
        assert.are_not.equal(id1, id2)
    end)
end)
```

---

## Test Scenarios

### First-Time User
1. Open plugin with no existing data
2. Should see morning check-in
3. Select energy level
4. Should see empty dashboard (no quests)
5. Add first quest → should appear in list

### Quest Completion Flow
1. Add a daily quest
2. Go to Dashboard
3. Quest should appear in "Today's Quests"
4. Tap quest → "Complete" button
5. Streak should show 1
6. Heatmap should show 1 completion for today

### Streak Calculation
1. Complete a quest on Day 1
2. (Simulate) Complete same quest on Day 2
3. Streak should be 2
4. Miss Day 3
5. Complete on Day 4
6. Streak should reset to 1

### Navigation
1. Open Dashboard
2. Tap "Quest" tab on right
3. Should navigate to Quests view
4. Tap "Jrnl" tab
5. Should navigate to Journal view
6. Swipe right → should close

### Settings
1. Open Settings
2. Change energy categories (add "Super")
3. Save
4. Check morning check-in shows new category
5. Reset all data
6. Confirm data is cleared

### Reminders
1. Add a reminder for current time + 1 minute
2. Wait for notification
3. Should see gentle notification message
4. Disable reminder
5. Should not fire again

---

## Known Limitations

1. **No offline sync** - Data is stored locally only
2. **E-ink refresh** - Some visual artifacts on partial refresh
3. **Touch targets** - May need adjustment for very small screens
4. **Unicode** - Vertical tab text uses ASCII only (no CJK support yet)

---

## Debugging

Enable KOReader debug logging:
1. Open KOReader settings
2. Enable "Debug" mode
3. Logs written to `crash.log` in KOReader directory

Add custom logging in plugin:
```lua
local logger = require("logger")
logger.dbg("LifeTracker:", "your debug message")
```

---

## Reporting Issues

When reporting bugs, include:
1. Device model and KOReader version
2. Steps to reproduce
3. Expected vs actual behavior
4. Contents of `crash.log` if available
