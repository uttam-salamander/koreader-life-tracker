# KOReader Life Tracker - ADHD Bullet Journal Planner

## Research-Backed Analysis & Design

### Your Original Concept (Summary)

| Feature | Description |
|---------|-------------|
| **Navigation** | Thin right-side column with rotated text (like journal month tabs) |
| **Tasks/Quests** | Daily, Weekly, Monthly types with time-of-day slots (Morning, Afternoon, Evening, Night) |
| **Reminders** | Dedicated reminder section |
| **Dashboard** | Morning check-in (energy level), filtered tasks, streak meter, mood graph |
| **Task Metadata** | "What type of days" - energy level required for each task |

---

## Critique & Research-Backed Improvements

### What You Got Right (Validated by Research)

1. **Energy-based task filtering** - Aligns perfectly with [Spoon Theory for ADHD](https://www.goblinxadhd.com/blog/understanding-spoon-theory-adhd-a-comprehensive-g/). Research shows ADHD brains need more energy for tasks neurotypical people find simple.

2. **Bullet journal style** - The BuJo system was [created by Ryder Carroll to manage his own ADHD](https://bulletjournal.com/blogs/bulletjournalist/bullet-journal-for-adhd). Native fit.

3. **Streaks & progress tracking** - [Gamification research](https://www.tiimoapp.com/resource-hub/gamification-adhd) confirms ADHD brains need continuous micro-wins due to dopamine processing differences.

4. **Mood tracking over time** - Helps identify patterns and builds self-awareness.

---

### Critical Improvements Needed

#### 1. **Rename "Tasks" to "Quests" Fully + Add XP System**

**Why:** [Research shows](https://imaginovation.net/blog/gamification-adhd-apps-user-retention/) gamification improves focus duration by up to 47%. Tasks feel like obligations; quests feel like adventures.

**Suggestion:**
- Each quest completion = XP points
- XP varies by difficulty (Daily=10, Weekly=30, Monthly=100)
- Streak multipliers (3-day streak = 1.5x XP)
- Simple level-up system with milestones

---

#### 2. **Add Visual Timeline View (Critical for Time Blindness)**

**Why:** [Time blindness](https://www.timetimer.com/blogs/news/time-blindness) is a core ADHD challenge. [Tiimo won iPhone App of the Year 2025](https://www.tiimoapp.com/) specifically for visual timelines.

**Suggestion:**
- Add a "Today" visual timeline showing time blocks
- Color-coded blocks for Morning/Afternoon/Evening/Night
- Shows remaining time visually (shrinking blocks)
- Optional 24-hour circular clock view (like [Weel](https://www.weelplanner.app/adhd-friendly))

---

#### 3. **Expand Energy Model (Spoon Types)**

**Why:** [The Neurodivergent Spoon Drawer concept](https://neurodivergentinsights.com/the-neurodivergent-spoon-drawer-spoon-theory-for-adhders-and-autists/) shows ADHD energy isn't monolithic—it's distributed across different areas.

**Suggestion:** Instead of just Energetic/Average/Down, track multiple spoon types:
- **Focus spoons** (deep work capacity)
- **Social spoons** (calls, meetings, interactions)
- **Physical spoons** (exercise, errands, movement)
- **Creative spoons** (brainstorming, writing)

Tasks get tagged with which spoon type they drain. Morning check-in asks about each type.

---

#### 4. **Add "Brain Dump" Capture Zone**

**Why:** [ADHD planners need brain dump pages](https://fhynix.com/best-adhd-planners/) for capturing random thoughts without structure. Reduces cognitive load.

**Suggestion:**
- Quick-capture inbox (no categorization required)
- Process later into proper quests
- Voice note option (for when typing feels like too much)

---

#### 5. **Simplify the Dashboard (Reduce Decision Fatigue)**

**Why:** [Research shows](https://productivewithchris.com/guides/best-planning-apps-adhd-2025/) ADHD apps fail when they require too many decisions. "Less friction, fewer decisions, simple structure."

**Current Problem:** Your dashboard has many elements (check-in, filtered tasks, streak meter, mood graph). Could overwhelm.

**Suggestion:** Progressive disclosure:
1. **First thing seen:** Just the check-in question (big, centered)
2. **After check-in:** Reveal filtered quests for today (max 3-5 visible)
3. **Stats panel:** Collapsed by default, expandable
4. **Mood graph:** Separate page, not on main dashboard

---

#### 6. **Add Task Estimation & Actual Time Tracking**

**Why:** ADHD causes chronic underestimation of task duration. [Structured app](https://fluidwave.com/blog/adhd-task-management-apps) uses this to combat time blindness.

**Suggestion:**
- When creating quest: "How long do you think this will take?"
- After completion: Record actual time
- Over time: Show user their estimation accuracy
- Builds meta-awareness of time perception

---

#### 7. **Navigation Improvement: Keep Right-Side Tabs, Add Quick Actions**

**Why:** Your rotated tab idea is visually appealing and journal-like. But [ADHD needs minimal friction](https://www.additudemag.com/bullet-journaling-adhd-quarantine/).

**Suggestion:**
- Keep rotated tabs for main sections (Dashboard, Quests, Reminders, Journal)
- Add floating quick-action button (bottom-right)
  - Quick add quest
  - Quick brain dump
  - Quick reminder
- Reduces navigation friction for capture

---

#### 8. **Add "Parking Lot" for Migrated Tasks**

**Why:** Bullet journal's [migration concept](https://workbrighter.co/bullet-journaling-for-adhd/) is key. Tasks that keep getting pushed forward need examination.

**Suggestion:**
- Tasks migrated 3+ times automatically go to "Parking Lot"
- Prompt: "This quest keeps moving. Should we break it down, delegate it, or drop it?"
- Prevents guilt spiral from perpetually postponed tasks

---

#### 9. **Gentle Notifications, Not Aggressive Reminders**

**Why:** [ADHD apps should feel supportive, not punitive](https://www.tiimoapp.com/resource-hub/digital-planner-apps-for-adhd). Harsh reminders trigger shame/avoidance.

**Suggestion:**
- Notification tone: Encouraging, not alarming
- Copy: "Ready for your Morning Focus quest?" not "You haven't done X!"
- Allow snooze without guilt messaging
- Celebrate small wins in notifications

---

#### 10. **Add Reflection/Review Ritual**

**Why:** Bullet journaling's power comes from [regular reflection](https://medium.com/@mindyjones/how-to-manage-adhd-with-the-bullet-journal-455384fdd503). Without it, patterns go unnoticed.

**Suggestion:**
- Weekly review prompt (5 min max)
- "What worked? What didn't? Any quests to drop?"
- Auto-generated insights: "You complete 80% more quests in the morning"
- Monthly "Level Up" summary

---

## Revised Feature Architecture

### Pages/Sections

1. **Dashboard** (Home)
   - Morning check-in (spoon levels)
   - Today's filtered quests (3-5 max)
   - Current streak badge
   - Quick stats (collapsed)

2. **Quests**
   - Daily / Weekly / Monthly tabs
   - Each quest shows: name, spoon type, time-of-day, estimated duration
   - Visual progress (XP bar)

3. **Timeline** (NEW)
   - Visual day view with time blocks
   - Color-coded by time-of-day
   - Drag quests into slots

4. **Brain Dump** (NEW)
   - Unstructured capture
   - Process later into quests

5. **Reminders**
   - Time-based or location-based
   - Gentle notification settings

6. **Journal/Reflect** (NEW)
   - Weekly review prompts
   - Mood history graph
   - Streak history
   - Insights & patterns

7. **Parking Lot** (NEW)
   - Migrated 3+ times tasks
   - Decision prompt: break down / delegate / drop

### Navigation (Right-Side Tabs)

```
┌─────────────────────────────────┬──┐
│                                 │D │ ← Dashboard
│                                 │a │
│        MAIN CONTENT             │s │
│                                 │h │
│                                 ├──┤
│                                 │Q │ ← Quests
│                                 │u │
│                                 │e │
│                                 │s │
│                                 │t │
│                                 ├──┤
│                                 │T │ ← Timeline
│                                 │i │
│                                 │m │
│                                 │e │
│                                 ├──┤
│                                 │. │ ← More (Brain Dump,
│                                 │. │    Reminders, Journal,
│                                 │. │    Parking Lot)
└─────────────────────────────────┴──┘
         [+] Quick Add (floating)
```

---

## Technical Considerations for KOReader

### E-Ink Constraints
- Limited refresh rate (no smooth animations)
- Grayscale display (color-coding → pattern/icon differentiation)
- Button-based navigation (no touch on some devices)

### Adapted Design
- Use bullet journal symbols (•, ○, >, <, ×) for status
- High contrast UI
- Large tap targets
- Minimize page refreshes

---

## Final Decisions (User Confirmed)

| Decision | Choice |
|----------|--------|
| **Platform** | KOReader (e-ink) - grayscale, no animations |
| **Energy Model** | User-configurable categories |
| **Gamification** | Streaks only (no XP/levels) |
| **V1 Scope** | Dashboard + Quests + Timeline + Journal/Reflect + Reminders |
| **Completion UX** | Swipe/drag left-to-right to cross off tasks |
| **Long-term tracker** | GitHub-style contribution heatmap on dashboard |
| **KOReader Integration** | Pull daily reading stats (pages, time, books) into dashboard |
| **Timeline Style** | Time-of-day slots (Morning/Afternoon/Evening/Night) - NOT strict time blocks |

---

## V1 Implementation Plan

### Data Model (Lua Tables)

```lua
-- Settings
settings = {
    energy_categories = {"Energetic", "Average", "Down"},  -- User configurable
    time_slots = {"Morning", "Afternoon", "Evening", "Night"},  -- User configurable
    streak_data = {
        current = 0,
        longest = 0,
        last_completed_date = nil,
    },
}

-- Quest Structure
quest = {
    id = timestamp,
    title = "string",
    type = "daily" | "weekly" | "monthly",
    time_slot = "Morning" | "Afternoon" | "Evening" | "Night",
    energy_required = "Energetic" | "Average" | "Down",  -- Which days to show
    created = date,
    completed = false,
    completed_date = nil,
    streak = 0,  -- Individual quest streak
}

-- Mood/Energy Log
mood_entry = {
    date = date,
    energy_level = "string",  -- User's chosen category
    quests_assigned = count,
    quests_completed = count,
    notes = "optional string",
}

-- Reminder Structure
reminder = {
    id = timestamp,
    title = "string",
    time = "HH:MM",           -- When to show reminder
    repeat_days = {"Mon", "Tue", ...},  -- Which days (empty = one-time)
    active = true,
    last_triggered = date,
}

-- Daily Activity Log (includes KOReader stats)
daily_log = {
    date = date,
    energy_level = "string",
    quests_completed = count,
    quests_total = count,
    -- KOReader reading stats (pulled from ReaderStatistics)
    reading = {
        pages_read = number,
        time_spent = seconds,
        books_opened = count,
        current_book = "string",
    },
}
```

### File Structure

```
lifetracker.koplugin/
├── _meta.lua              # Plugin metadata
├── main.lua               # Main plugin entry, menu registration
├── modules/
│   ├── dashboard.lua      # Dashboard view & morning check-in
│   ├── quests.lua         # Quest management (CRUD)
│   ├── timeline.lua       # Timeline view by time-of-day
│   ├── reminders.lua      # Reminder management & notifications
│   ├── journal.lua        # Journal/reflect & mood graph
│   ├── reading_stats.lua  # KOReader statistics integration
│   ├── heatmap.lua        # GitHub-style activity heatmap
│   ├── settings.lua       # User configuration
│   └── data.lua           # Data persistence helpers
└── assets/
    └── icons/             # Bullet journal style icons (optional)
```

### UI Screens (E-Ink Optimized)

#### 1. Dashboard (Home)
```
┌─────────────────────────────────────────┬──┐
│  ☀ Good Morning!                        │ D│
│                                         │ a│
│  How are you feeling today?             │ s│
│  ┌─────────┐ ┌─────────┐ ┌─────────┐   │ h│
│  │Energetic│ │ Average │ │  Down   │   ├──┤
│  └─────────┘ └─────────┘ └─────────┘   │ Q│
│                                         │ u│
│  ─────────────────────────────────────  │ e│
│  Today's Quests (3 matched)             │ s│
│                                         │ t│
│  ○──────> [M] Morning meditation        ├──┤
│  ○──────> [A] Review inbox              │ T│
│  ○──────> [E] Read 20 pages             │ i│
│                                         │ m│
│  (Swipe right to cross off ──────> ✓)   │ e│
│                                         ├──┤
│  ─────────────────────────────────────  │ R│
│  🔥 Streak: 7 days                      │ e│
│                                         │ m│
│  ─────────────────────────────────────  ├──┤
│  Quest Activity (Last 12 Weeks)         │ J│
│  ┌─────────────────────────────────┐   │ r│
│  │ ░░▓▓██░░▓▓██▓▓░░██▓▓░░▓▓██░░▓▓ │   │ n│
│  │ ▓▓██░░▓▓██░░▓▓██░░▓▓██▓▓░░██▓▓ │   │  │
│  │ ██▓▓░░██▓▓██░░▓▓██▓▓░░██▓▓██░░ │   │  │
│  │ ░░▓▓██░░▓▓░░██▓▓░░██▓▓░░▓▓██▓▓ │   │  │
│  │ ▓▓░░▓▓██░░▓▓██░░▓▓░░██▓▓██░░▓▓ │   │  │
│  │ ██▓▓██░░▓▓██▓▓░░▓▓██░░▓▓░░██▓▓ │   │  │
│  │ ░░██▓▓██░░▓▓██▓▓██░░▓▓██▓▓░░██ │   │  │
│  └─────────────────────────────────┘   │  │
│  ░=0  ▓=1-2  █=3+  completions/day     │  │
│                                         │  │
│  ─────────────────────────────────────  │  │
│  📖 Today's Reading                     │  │
│  Pages: 47  |  Time: 1h 23m             │  │
│  Currently: "Atomic Habits"             │  │
└─────────────────────────────────────────┴──┘
```

**Cross-off Interaction:**
- User selects a quest, then swipes/drags right (or presses right arrow key)
- Quest gets struck through: `○──────> ✓ ~~Morning meditation~~`
- On e-ink: Can use button press (right arrow) since swipe may not be available

#### 2. Quests (List + Add)
```
┌─────────────────────────────────────────┬──┐
│  QUESTS                                 │  │
│  [Daily] [Weekly] [Monthly]             │  │
│                                         │  │
│  Daily Quests                           │  │
│  ─────────────────────────────────────  │  │
│  • Morning meditation      [M] [Avg]    │  │
│    🔥 12 day streak                     │  │
│  • Review inbox            [A] [Any]    │  │
│    🔥 5 day streak                      │  │
│  • Evening journal         [E] [Down]   │  │
│    🔥 3 day streak                      │  │
│                                         │  │
│  ─────────────────────────────────────  │  │
│  [+] Add New Quest                      │  │
│                                         │  │
│  Legend:                                │  │
│  [M]=Morning [A]=Afternoon              │  │
│  [E]=Evening [N]=Night                  │  │
└─────────────────────────────────────────┴──┘
```

#### 3. Timeline (Day View)
```
┌─────────────────────────────────────────┬──┐
│  TODAY - Tuesday, Jan 7                 │  │
│                                         │  │
│  ═══ MORNING ═══════════════════════   │  │
│  • Morning meditation            ✓      │  │
│  • Review emails                 ○      │  │
│                                         │  │
│  ═══ AFTERNOON ═════════════════════   │  │
│  • Deep work session             ○      │  │
│                                         │  │
│  ═══ EVENING ═══════════════════════   │  │
│  • Read 20 pages                 ○      │  │
│  • Evening journal               ○      │  │
│                                         │  │
│  ═══ NIGHT ═════════════════════════   │  │
│  • Prepare tomorrow's list       ○      │  │
│                                         │  │
│  Progress: 1/6 (17%)                    │  │
└─────────────────────────────────────────┴──┘
```

#### 4. Journal/Reflect
```
┌─────────────────────────────────────────┬──┐
│  JOURNAL & INSIGHTS                     │  │
│                                         │  │
│  Weekly Review                          │  │
│  ─────────────────────────────────────  │  │
│  Completion Rate: 73%                   │  │
│  Best Day: Tuesday (5/5)                │  │
│  Missed: 2 quests                       │  │
│                                         │  │
│  Mood This Week                         │  │
│  ─────────────────────────────────────  │  │
│  Mon: ████████░░ Energetic              │  │
│  Tue: ██████░░░░ Average                │  │
│  Wed: ████░░░░░░ Down                   │  │
│  Thu: ██████░░░░ Average                │  │
│  Fri: ████████░░ Energetic              │  │
│                                         │  │
│  Pattern: You complete 40% more on      │  │
│  Energetic days. Consider lighter       │  │
│  loads on Down days.                    │  │
│                                         │  │
│  [Add Reflection Note]                  │  │
└─────────────────────────────────────────┴──┘
```

#### 5. Reminders
```
┌─────────────────────────────────────────┬──┐
│  REMINDERS                              │  │
│                                         │  │
│  Active Reminders                       │  │
│  ─────────────────────────────────────  │  │
│  ⏰ 08:00  Morning vitamins     [Daily] │  │
│  ⏰ 12:00  Lunch break          [Daily] │  │
│  ⏰ 18:00  Exercise             [M/W/F] │  │
│  ⏰ 21:00  Wind down routine    [Daily] │  │
│                                         │  │
│  Upcoming Today                         │  │
│  ─────────────────────────────────────  │  │
│  → 18:00  Exercise (in 2 hours)         │  │
│  → 21:00  Wind down routine             │  │
│                                         │  │
│  ─────────────────────────────────────  │  │
│  [+] Add New Reminder                   │  │
│                                         │  │
│  Tip: Reminders show as notifications   │  │
│  when KOReader is open at the set time  │  │
└─────────────────────────────────────────┴──┘
```

### KOReader Statistics Integration

**How it works:**
- KOReader has a built-in `ReaderStatistics` plugin that tracks reading activity
- We can access this data via `self.ui.statistics` or reading the statistics database
- Available data:
  - Pages read today/this week/this month
  - Time spent reading
  - Books opened
  - Reading sessions
  - Current book info

**Integration approach:**
```lua
-- Access KOReader's statistics plugin
local ReaderStatistics = require("readerstats")

-- Get today's reading data
function LifeTracker:getReadingStats()
    local stats = self.ui.statistics
    if stats then
        return {
            pages_today = stats:getTodayPages(),
            time_today = stats:getTodayReadingTime(),
            current_book = self.ui.document:getProps().title,
        }
    end
    return nil
end
```

### Implementation Order

1. **Phase 1: Foundation**
   - [ ] Data persistence layer (`data.lua`)
   - [ ] Settings management (`settings.lua`)
   - [ ] Main menu integration (`main.lua`)

2. **Phase 2: Core Quests**
   - [ ] Quest CRUD operations (`quests.lua`)
   - [ ] Quest list view with filtering
   - [ ] Add quest dialog (InputDialog)
   - [ ] Swipe-right cross-off completion

3. **Phase 3: Dashboard**
   - [ ] Morning check-in flow (`dashboard.lua`)
   - [ ] Energy-filtered quest display
   - [ ] Streak calculation and display
   - [ ] GitHub-style activity heatmap (`heatmap.lua`)
   - [ ] KOReader reading stats integration (`reading_stats.lua`)

4. **Phase 4: Timeline**
   - [ ] Day view grouped by time slot (`timeline.lua`)
   - [ ] Progress indicator

5. **Phase 5: Reminders**
   - [ ] Reminder CRUD operations (`reminders.lua`)
   - [ ] Time-based notification system
   - [ ] Repeat scheduling (daily, specific days)

6. **Phase 6: Journal**
   - [ ] Mood logging (`journal.lua`)
   - [ ] Weekly review generation
   - [ ] Simple bar chart for mood history
   - [ ] Pattern insights (including reading correlation)

7. **Phase 7: Polish**
   - [ ] Right-side tab navigation
   - [ ] Bullet journal symbols (•, ○, ✓, >, <)
   - [ ] User-configurable categories
   - [ ] E-ink optimized refresh

### Key Files to Create/Modify

| File | Purpose |
|------|---------|
| `main.lua` | Entry point, menu registration (exists, needs expansion) |
| `modules/data.lua` | LuaSettings wrapper, CRUD helpers |
| `modules/settings.lua` | User preferences, energy categories, time slots |
| `modules/quests.lua` | Quest management, streak tracking, cross-off |
| `modules/dashboard.lua` | Check-in, filtered view, reading stats display |
| `modules/timeline.lua` | Day view by time slots |
| `modules/reminders.lua` | Reminder management, time-based notifications |
| `modules/journal.lua` | Mood tracking, weekly review, insights |
| `modules/reading_stats.lua` | KOReader statistics integration |
| `modules/heatmap.lua` | GitHub-style activity heatmap rendering |

### Verification Plan

1. **Install plugin** on KOReader (Kindle/Kobo/Android)
2. **Test quest CRUD:** Add, edit, complete, delete quests
3. **Test cross-off gesture:** Swipe/press right to complete quest
4. **Test morning check-in:** Select energy level, verify filtering
5. **Test streaks:** Complete quests across multiple days, check per-quest streaks
6. **Test timeline:** Verify time slot grouping (Morning/Afternoon/Evening/Night)
7. **Test reminders:** Add reminder, verify notification at set time
8. **Test heatmap:** Complete quests over several days, verify heatmap updates
9. **Test reading stats:** Read a book, verify pages/time shows on dashboard
10. **Test journal:** Add mood entries, check weekly view, verify patterns
11. **Test settings:** Modify energy categories and time slots, verify persistence

---

## Sources

- [Tiimo - Visual Planner for ADHD](https://www.tiimoapp.com/)
- [Bullet Journal for ADHD](https://bulletjournal.com/blogs/bulletjournalist/bullet-journal-for-adhd)
- [Spoon Theory for ADHD](https://www.goblinxadhd.com/blog/understanding-spoon-theory-adhd-a-comprehensive-g/)
- [Neurodivergent Spoon Drawer](https://neurodivergentinsights.com/the-neurodivergent-spoon-drawer-spoon-theory-for-adhders-and-autists/)
- [Gamification for ADHD](https://www.tiimoapp.com/resource-hub/gamification-adhd)
- [Time Blindness Solutions](https://www.timetimer.com/blogs/news/time-blindness)
- [Best ADHD Planning Apps 2025](https://productivewithchris.com/guides/best-planning-apps-adhd-2025/)
- [Weel Planner](https://www.weelplanner.app/adhd-friendly)
