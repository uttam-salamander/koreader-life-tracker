# Life Tracker for KOReader

A bullet journal-style life planner plugin for KOReader. Track quests, habits, mood, and reading stats directly on your e-reader.

![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)

## Features

- **Dashboard** - Morning energy check-in, streak tracking, GitHub-style activity heatmap
- **Quests** - Daily, weekly, and monthly goals with time slots and energy tags
- **Reminders** - Time-based gentle notifications while reading
- **Journal** - Weekly mood tracking, pattern insights, reading correlations
- **Reading Stats** - Integration with KOReader's reading statistics
- **Sleep Screen** - Optional dashboard display on device wake

## Installation

### Method 1: Download Release

1. Download the latest release from [Releases](https://github.com/koreader/koreader-life-tracker/releases)
2. Extract `lifetracker.koplugin` folder
3. Copy to your KOReader plugins directory (see paths below)
4. Restart KOReader

### Method 2: Clone Repository

```bash
# Clone directly to your plugins folder
cd /path/to/koreader/plugins/
git clone https://github.com/koreader/koreader-life-tracker.git lifetracker.koplugin
```

### Plugin Paths by Device

| Device | Path |
|--------|------|
| **Kindle** | `koreader/plugins/lifetracker.koplugin/` |
| **Kobo** | `.adds/koreader/plugins/lifetracker.koplugin/` |
| **PocketBook** | `applications/koreader/plugins/lifetracker.koplugin/` |
| **Android** | Varies by installation (check your KOReader folder) |
| **Desktop/Emulator** | `koreader/plugins/lifetracker.koplugin/` |

### Verify Installation

After restarting KOReader:
1. Open the top menu (tap top of screen or swipe down)
2. Navigate to **Tools** (gear icon)
3. Look for **Life Tracker** in the menu

## Usage

### Getting Started

1. Open **Tools > Life Tracker**
2. Start with the **Dashboard** - do your morning energy check-in
3. Create your first quest in the **Quests** tab
4. Track your progress throughout the day

### Dashboard

The home screen shows:
- **Energy Level** - Tap to set your current energy (filters which quests to show)
- **Streak Counter** - Days in a row completing quests
- **Activity Heatmap** - 12-week visual of your completion history
- **Today's Reading** - Pages and time from KOReader stats

### Quests

Organize your goals:
- **Daily** - Reset each day (habits, routines)
- **Weekly** - Reset each week (bigger tasks)
- **Monthly** - Reset each month (major goals)

Each quest can have:
- **Time Slot** - Morning, Afternoon, Evening, Night
- **Energy Tag** - Show only when energy matches
- **Progress Tracking** - For countable goals (e.g., "Read 30 pages")

### Reminders

Set gentle notifications:
- Choose time (24-hour format)
- Select repeat days (Daily, Weekdays, Weekends, or custom)
- Reminders appear as non-intrusive popups while reading

### Journal

Review your patterns:
- **Weekly Stats** - Completion rate, best days
- **Mood Graph** - Energy levels over time
- **Category Performance** - Spider chart of quest categories
- **Insights** - "You complete 40% more on Energetic days"
- **Reflections** - Add notes about your week

### Settings

Customize the plugin:
- **Energy Categories** - Rename levels to match your vocabulary
- **Time Slots** - Adjust to your schedule
- **Sleep Screen** - Show dashboard when device wakes
- **Backup/Restore** - Export and import your data

## Keyboard Shortcuts (Emulator/Desktop)

| Key | Action |
|-----|--------|
| `H` | Go to Dashboard (Home) |
| `Q` | Go to Quests |
| `J` | Go to Journal |
| `R` | Go to Reminders |
| `S` | Go to Settings |

## Dispatcher Actions

Assign to gestures in KOReader settings:
- `lifetracker_dashboard` - Open Dashboard
- `lifetracker_quests` - Open Quests
- `lifetracker_timeline` - Open Timeline

## Data Storage

Your data is stored in KOReader's settings directory:
- `lifetracker_data.lua` - Quests, completions, mood logs
- `lifetracker_settings.lua` - User preferences

Use **Settings > Backup** to export your data as JSON.

## Designed for E-Ink

- High contrast black & white UI
- Large tap targets for touch accuracy
- Minimal screen refreshes
- Optimized for grayscale displays

## Requirements

- KOReader 2024.01 or newer
- Any device running KOReader (Kindle, Kobo, PocketBook, Android, etc.)

## Contributing

Issues and pull requests welcome!

Built with the help of [Claude Code](https://claude.ai/code).

## License

AGPL-3.0 (same as KOReader)
