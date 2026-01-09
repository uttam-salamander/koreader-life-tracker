# KOReader Life Tracker - Development Notes

## Running the Emulator

### Copy plugin to emulator and restart
```bash
# Copy plugin files
cp -r /Users/uttamkumar/Desktop/Code\ Projects/koreader-life-tracker/* /tmp/koreader/koreader-emulator-arm64-apple-darwin25.2.0-debug/koreader/plugins/lifetracker.koplugin/

# Stop existing emulator
pkill -f luajit

# Start emulator
cd /tmp/koreader/koreader-emulator-arm64-apple-darwin25.2.0-debug/koreader && ./reader.lua &
```

### Quick restart (copy + restart)
```bash
pkill -f luajit; sleep 1; cp -r /Users/uttamkumar/Desktop/Code\ Projects/koreader-life-tracker/* /tmp/koreader/koreader-emulator-arm64-apple-darwin25.2.0-debug/koreader/plugins/lifetracker.koplugin/ && cd /tmp/koreader/koreader-emulator-arm64-apple-darwin25.2.0-debug/koreader && ./reader.lua &
```

### Check if emulator is running
```bash
pgrep -f luajit
```

### View emulator logs
```bash
tail -f /tmp/koreader-emulator.log
```

## Test Books Path

For testing the Read module, books are loaded from:
```
/Users/uttamkumar/Downloads/Books
```

To disable test mode and use real ReadHistory, set in `modules/read.lua`:
```lua
Read.TEST_BOOKS_PATH = nil
```

## Plugin Location in Emulator
```
/tmp/koreader/koreader-emulator-arm64-apple-darwin25.2.0-debug/koreader/plugins/lifetracker.koplugin/
```
