# KOReader Life Tracker Plugin

Track your reading habits, personal goals, and life metrics alongside your books.

## Installation

1. Copy the `lifetracker.koplugin` folder to your KOReader plugins directory:
   - Kindle: `koreader/plugins/`
   - Kobo: `.adds/koreader/plugins/`
   - Android: Depends on installation location

2. Restart KOReader

## Usage

Access Life Tracker from the main menu under **Tools > Life Tracker**

## Features (Planned)

- [ ] Reading session tracking
- [ ] Daily/weekly/monthly goals
- [ ] Custom metrics tracking
- [ ] Progress visualization
- [ ] Export data

## Development

This plugin is built for KOReader's plugin architecture using Lua.

### Structure

```
lifetracker.koplugin/
├── _meta.lua    # Plugin metadata
├── main.lua     # Main plugin code
└── README.md    # This file
```

## License

AGPL-3.0 (same as KOReader)
