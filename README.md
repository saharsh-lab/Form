# Form

A minimalist, offline-first iPhone app for tracking workouts, nutrition and body measurements. Native Swift, SwiftUI and SwiftData, with no account, no server, no analytics and no AI. Every nutrition value is entered by the user.

> **Status: Phases 1–2 of 7 (foundation, foods and diary).** See [Implementation status](#implementation-status) for exactly what works today and what is still to come.

## Requirements

| | |
|---|---|
| Mac | macOS 14.5 or later |
| Xcode | **16.0 or later** (uses the iOS 18 SDK, where SwiftUI views are main-actor isolated) |
| XcodeGen | 2.40 or later: `brew install xcodegen` |
| Deployment target | **iOS 17.0** |

**Why iOS 17:** SwiftData, the `@Observable` macro, Swift Charts point selection (`chartXSelection`), interactive widgets with App Intents, and current ActivityKit APIs all require iOS 17. Nothing in the plan needs iOS 18, so iOS 17 keeps the widest device support.

## Run it in Xcode

1. Copy the `Form` folder to your Mac.
2. In Terminal, from the `Form` folder, generate the Xcode project:
   ```sh
   brew install xcodegen   # once
   xcodegen generate
   ```
   This creates `Form.xcodeproj` from `project.yml`. The project file is not committed; re-run `xcodegen generate` whenever you add or remove source files.
3. Open `Form.xcodeproj`.
4. Select the **Form** target › **Signing & Capabilities** and choose your **Team**. If Xcode reports that the bundle identifier is taken, change both `FORM_BUNDLE_ID` and `FORM_APP_GROUP` at the top of `project.yml` (for example `com.yourname.form` and `group.com.yourname.form`), then run `xcodegen generate` again.
5. Pick an iPhone simulator (for example iPhone 16) or your device and press **⌘R**.

On first launch Form creates its local database and seeds an editable exercise catalogue (54 exercises) and four starter routines. Nothing else is pre-filled: Today, Nutrition and Progress start empty.

### App Group note

Form stores its database in the App Group container so the widget extension (Phase 5) can read it. Simulators always allow this. On a device, App Groups need a paid Apple Developer team; with a free personal team Form automatically falls back to its own app container and everything except widgets keeps working.

## Tests

There are two test suites.

**FormCore** (pure Swift, no UIKit or SwiftData): food search ranking, unit conversion, serving-size scaling, daily totals, target progress, goal history, workout volume, personal records, rest timer and workout clock maths, input validation.

```sh
cd Packages/FormCore
swift test
```

This also runs on Linux with a Swift 5.9+ toolchain. In Xcode you can open `Packages/FormCore/Package.swift` and press **⌘U**.

**FormTests** (hosted in the app, uses SwiftData): logging, editing, moving, duplicating, deleting and undoing diary entries; saved meals, including after a food is deleted; food editor validation; historical nutrition snapshots, missing values staying unspecified, deleting foods and exercises without losing history, cascade deletes, active-workout and rest-timer restoration, persistence across container launches, seeding idempotence, deep links and exercise search.

In Xcode: choose the **Form** scheme and press **⌘U**. From the command line:

```sh
xcodebuild test -project Form.xcodeproj -scheme Form \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project structure

```
Form/
├── project.yml                  XcodeGen spec: targets, entitlements, Info.plist, scheme
├── Packages/FormCore/           Pure calculation services + their unit tests
│   ├── Sources/FormCore/
│   │   ├── Units.swift          kg/lb, cm/in, km/mi conversion (canonical: kg, cm, m)
│   │   ├── Nutrition.swift      NutritionValues (optional values), NutritionTotals
│   │   ├── Serving.swift        QuantityUnit, ServingBasis, NutritionScaler
│   │   ├── TargetProgress.swift Safe progress maths, goal history, day bounds
│   │   ├── Workout.swift        Set kinds, tracking types, volume, PR detection
│   │   ├── Timers.swift         Date-based RestTimer and WorkoutClock
│   │   ├── Validation.swift     Locale-aware number parsing, name and date rules
│   │   ├── TextSearch.swift     Case/diacritic-insensitive ranked search
│   │   └── DurationFormatting.swift
│   └── Tests/FormCoreTests/
├── Form/                        The iOS app target (module name FormApp)
│   ├── App/                     Entry point, root view, tab router and deep links
│   ├── DesignSystem/            Colour tokens, spacing, radii, typography helpers
│   │   └── Components/          Cards, buttons, rings, bars, macro summaries, empty states
│   ├── Models/                  SwiftData models and their enums
│   ├── Persistence/             Container setup, preferences, first-launch seed data
│   ├── Platform/                HapticsManager
│   ├── Features/                Today, Train, Nutrition, Progress, Settings, Shared
│   └── Resources/               Asset catalogue
└── FormTests/                   App-hosted SwiftData tests
```

### Architecture

- **MVVM, feature-oriented.** Each feature folder owns its views. Simple screens read straight from SwiftData with `@Query`; screens with real editing state get an `@Observable` view model (`FoodEditorModel`, and the active workout in Phase 3).
- **Calculations live in FormCore**, never in views. Views call `NutritionScaler`, `TargetProgress`, `WorkoutCalculator`, `PersonalRecordCalculator`, `RestTimer` and `InputValidator`.
- **Canonical units in storage.** Weight in kilograms, lengths in centimetres, distance in metres. The weight and length unit preferences only change display and entry.
- **Repositories only where they help.** `NutritionRepository` groups multi-model operations (logging with snapshots, saved meals, delete with undo) and always saves before returning, so success feedback follows a real save. Simple edits use `ModelContext` directly.

### Data model

| Model | Purpose | Notes |
|---|---|---|
| `Exercise` | Editable catalogue entry | Archive instead of delete; history keeps a name snapshot |
| `WorkoutRoutine`, `RoutineExercise` | Templates | Cascade delete of entries; exercise link nullifies |
| `WorkoutSession` | Active, completed or discarded workout | Pause times and an encoded `RestTimer` persist for restoration |
| `WorkoutExercise`, `WorkoutSet` | What was performed | Name and tracking-type snapshot; sets cascade with the session |
| `Food` | User-entered food | Values per serving, per 100 g or per 100 ml; `nil` = unspecified |
| `FoodLogEntry` | Diary entry | Full nutrition and serving **snapshot**, so editing a food never rewrites history |
| `SavedMeal`, `SavedMealItem` | Meal templates | Items keep a snapshot in case the food is deleted |
| `DailyNutritionGoal` | Targets from a given day | A goal history: past days are judged against the goal in effect then |
| `BodyMeasurement` | Weight, body fat, circumferences | Canonical units |
| `UserPreferences` | Single settings record | Theme, units, rest duration, haptics, reminders |

Relationship arrays in SwiftData are unordered, so ordered collections use a `sortIndex` and an `ordered…` accessor. Model initialisers never link relationships: insert the object, then link it.

### Definitions used in calculations

- **Volume** = weight × reps, summed over completed working and drop sets with a positive load. Warm-ups and incomplete sets are excluded; reps-only, duration and distance exercises have no volume.
- **Personal records** are compared only within one exercise and its tracking type: heaviest weight, best Epley estimated 1RM (1–12 reps), best single-set volume, most reps, longest duration, longest distance. The first session of an exercise sets a baseline and is not celebrated as a record; a record must strictly beat the previous best.
- **Target progress** treats a missing, zero or negative target as "no target" (never divides by zero) and distinguishes *reached* (within tolerance) from *exceeded*.
- **Missing nutrition values** stay `nil` through scaling and totals. Totals report how many entries were missing each value, and the UI says so instead of showing a falsely complete number.
- **Timers** store dates, not ticks: `RestTimer` keeps an end date and `WorkoutClock` keeps start, pause and accumulated-pause times, so both stay correct while the app is suspended or relaunched.

## Implementation status

### Phase 1: done (this build)

- XcodeGen project with app target, unit-test target, App Group entitlement, URL scheme and local `FormCore` package.
- Design system: light and dark colour tokens (with Increase Contrast variants), 8-pt spacing, 12–20 pt radii, Dynamic Type-friendly typography helpers; reusable card, section header, stat tile, empty state, inline notice, primary and secondary buttons, quick action tile, progress ring, linear progress bar, macro rows, calorie summary, food log row, filter chip.
- Four persistent tabs (Today, Train, Nutrition, Progress), each with its own navigation stack; re-tapping a tab pops to its root. `form://today|train|nutrition|progress|log-weight` deep links.
- All 13 SwiftData models with stable UUIDs, relationships, delete rules and snapshots.
- FormCore calculation services with unit tests (see above).
- **Today:** date and greeting; calories consumed, target and remaining; protein, carb and fat progress; today's workout status (in progress with live elapsed time, completed, or empty); quick actions; weekly consistency; latest body weight. All values come from stored records.
- **Train:** routine list and detail (seeded starter routines); exercise library with case-insensitive partial search and muscle-group and equipment filters.
- **Nutrition:** day-by-day diary with previous / next day, meal sections, per-meal and daily totals against the goal in effect that day; daily targets editor.
- **Progress:** record, edit and delete body weight, body fat and circumference measurements, with confirmation before deletion.
- **Settings:** System / Light / Dark theme, weight and measurement units, default rest duration, haptics level (Full / Reduced / Off), daily targets, privacy screen, version.
- `HapticsManager` with set-completed, selection, save-success, personal-record, timer, error and milestone feedback, gated by the haptics setting. Success feedback fires only after a save succeeds.
- Error handling for an unreadable store (no automatic deletion), validation messages on every numeric field, save-failure rollback.

### Phase 2: done

- **Foods:** create, edit, duplicate, favourite and delete in a Foods library (Nutrition › Foods). Values are entered per serving, per 100 g or per 100 ml with a clear serving size; empty values are saved as "not specified". Deleting a food keeps diary entries and saved meals intact.
- **Search:** case- and diacritic-insensitive partial matching of every word ("greek yog" finds "Yoghurt, Greek style"), ranked exact › prefix › word prefix › contains. An **Add "…" as a new food** row is always at the top.
- **Logging:** each meal has an Add food button that opens a picker with saved meals, favourites, recent foods and all foods. Choose a quantity in any compatible unit (servings, g, kg, oz, lb, ml, l, fl oz, cup, tbsp, tsp, pieces) with a live nutrition preview; invalid or incompatible quantities can't be saved.
- **Diary:** tap an entry to edit quantity, unit or meal (scaled from its stored snapshot); swipe to duplicate or delete; long-press to move to another meal. Deletes show an Undo banner for 5 seconds.
- **Saved meals:** save any meal's foods from its header menu, log them later as separate editable entries, and rename, trim or delete saved meals. If a food is later deleted, the saved meal uses the values stored with it.
- Daily totals update as soon as a save succeeds; missing calorie values are flagged in the totals.
- Double-tap protection on every save button; success haptics only after a successful save.

### Not yet implemented

| Phase | Remaining work |
|---|---|
| 3 | Start, pause, resume, finish and discard workouts; set logging with previous-session values; warm-up, drop and extra sets; skipping exercises; rest timer UI with notifications; routine and exercise editing; PR detection on save; reviewing and editing past sessions |
| 4 | Swift Charts: workout counts, exercise history, volume, personal records, body weight and measurements, average calories and protein, consistency; date ranges and point selection |
| 5 | WidgetKit extension (small, medium, large, Lock Screen), App Intents, Live Activities for the active workout and rest timer |
| 6 | Optional reminders, JSON/CSV export, delete-all-data flow, further accessibility and error-handling passes, UI tests |
| 7 | Visual polish, performance, device testing, release documentation |

## Verification and limitations

- **This code has not yet been compiled.** It was written in a Linux environment with no Xcode and no Swift toolchain, so neither the app nor the tests have been built or run. Every Swift file was checked with a Swift syntax parser (tree-sitter-swift) and parses cleanly, but type errors can only be caught by Xcode. If a build reports errors, please share the messages so they can be fixed before later phases build on top.
- Not yet tested on simulators or devices, in either theme, or at large Dynamic Type sizes.
- The app icon is a simple placeholder.
- HealthKit is intentionally out of scope for the MVP.

## Privacy

Form makes no network requests, has no account, analytics or advertising, and stores everything in a local SwiftData database on the device (CloudKit sync is explicitly disabled). Targets are user-chosen settings, not medical advice.
