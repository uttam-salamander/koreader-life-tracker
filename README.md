# KOReader Life Tracker Plugin

An ADHD-friendly bullet journal style planner for KOReader. Track quests, reminders, mood, and reading habits - all from your e-reader.

## Features

### Dashboard
- **Morning Check-in**: Start your day by selecting your energy level
- **Smart Filtering**: See only quests appropriate for your current energy
- **Streak Meter**: Track your daily completion streak
- **GitHub-style Heatmap**: Visualize 12 weeks of quest completion
- **Reading Stats**: Today's pages, reading time, current book
- **Lock Screen Option**: Show dashboard when device wakes

### Quests
- **Three Types**: Daily, Weekly, Monthly quests
- **Time Slots**: Assign to Morning, Afternoon, Evening, Night
- **Energy Tags**: Mark quests for Energetic, Average, or Down days
- **Per-Quest Streaks**: Track individual quest completion streaks
- **Cross-off Gesture**: Swipe right to complete (bullet journal style)

### Timeline
- **Day View**: See quests grouped by time of day
- **Progress Tracking**: Visual completion percentage
- **Quick Complete**: Tap to mark quests done

### Reminders
- **Time-based**: Set specific times for reminders
- **Repeat Options**: Daily, Weekdays, Weekends, Custom days
- **Gentle Notifications**: Non-intrusive alerts while reading
- **Upcoming View**: See what's coming today

### Journal
- **Weekly Review**: Completion rate, best days, insights
- **Mood Chart**: Visual bar graph of energy levels
- **Pattern Detection**: "You complete 40% more on Energetic days"
- **Reading Correlation**: Track how reading affects productivity
- **Reflection Notes**: Save thoughts and observations
- **Monthly Summary**: Pages read, time spent, quest stats

### Settings
- **Custom Energy Categories**: Rename or add energy levels
- **Custom Time Slots**: Adjust to your schedule
- **Lock Screen Dashboard**: Wake to your planner
- **Reset Data**: Start fresh when needed

## Installation

1. Copy the `lifetracker.koplugin` folder to your KOReader plugins directory:
   - **Kindle**: `koreader/plugins/`
   - **Kobo**: `.adds/koreader/plugins/`
   - **Android**: Depends on installation location

2. Restart KOReader

3. Access from menu: **Tools > Life Tracker**

## Designed for ADHD

This plugin is specifically designed with ADHD challenges in mind:

- **Energy-based filtering** reduces decision fatigue
- **Visual streaks** provide dopamine hits for consistency
- **Simple bullet journal symbols** (circles, checkmarks)
- **Cross-off gesture** satisfies completion impulse
- **Gentle reminders** don't shame, just nudge
- **Pattern insights** help understand your rhythms
- **Reading integration** rewards the act of reading itself

## File Structure

```
lifetracker.koplugin/
├── _meta.lua              # Plugin metadata
├── main.lua               # Entry point, menu, events
├── PLAN.md                # Design documentation
└── modules/
    ├── data.lua           # Persistence layer
    ├── settings.lua       # User preferences
    ├── quests.lua         # Quest CRUD & display
    ├── dashboard.lua      # Main dashboard view
    ├── timeline.lua       # Day timeline view
    ├── reminders.lua      # Reminder management
    ├── journal.lua        # Mood tracking & review
    ├── reading_stats.lua  # KOReader stats integration
    └── heatmap.lua        # Activity visualization
```

## Dispatcher Actions

These can be assigned to gestures or shortcuts:
- `lifetracker_dashboard` - Open Dashboard
- `lifetracker_quests` - Open Quests
- `lifetracker_timeline` - Open Timeline

## E-Ink Optimized

- **High contrast UI** for grayscale displays
- **Large tap targets** for easy navigation
- **Minimal refreshes** to reduce flashing
- **ASCII-compatible** fallback characters
- **No animations** that don't work on e-ink

## License

AGPL-3.0 (same as KOReader)

## Contributing

Built with the help of Claude Code. Issues and PRs welcome!

https://github.com/uttam-salamander/koreader-life-tracker
