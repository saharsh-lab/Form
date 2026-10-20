# Device QA checklist

Run this on a real iPhone (ideally one with a Dynamic Island) before each release. Start from a fresh install unless a step says otherwise. Note the iOS version and device model at the top of your results.

## First launch and navigation
- [ ] The first launch shows Today with empty states; Train lists 4 starter routines; the exercise library has 54 exercises.
- [ ] Each tab keeps its own navigation stack, and tapping the current tab again pops to its root.
- [ ] Each deep link opens the right place: `form://today`, `train`, `nutrition`, `progress`, `workout`, `start-workout`, `log-weight`. Test them from the Notes app or Safari.

## Workouts
- [ ] Start an empty workout, add an exercise, enter weight and reps, and complete a set. You feel a light haptic and the rest timer starts.
- [ ] Lock the phone during rest. The Live Activity counts down; when rest ends it shows "Rest over". With alerts on, a notification arrives.
- [ ] Pause the workout: the elapsed time freezes in the app and in the Live Activity, and the rest timer pauses.
- [ ] Force-quit mid-workout and relaunch: the workout, completed sets and rest timer are restored.
- [ ] Finish the workout: the summary shows duration, sets and volume. Beat a previous best in a second session and the record appears with a success haptic.
- [ ] Discarding asks for confirmation, removes the workout, and ends the Live Activity.
- [ ] Edit a past workout in History and confirm records recalculate.

## Nutrition
- [ ] Create a food with calories left blank. The diary shows it as "not specified" and the totals flag the missing value.
- [ ] Log foods in grams, servings and cups. The preview matches the saved entry.
- [ ] Edit the food's values. Entries already logged keep their original numbers.
- [ ] Delete an entry, then tap Undo within 5 seconds.
- [ ] Save a meal, delete one of its foods, and log the saved meal. It still works.
- [ ] Change the daily targets. Past days keep being judged against the targets in effect on those days.

## Progress
- [ ] Each section shows empty states with no data and charts with data. Tapping a point shows its exact value and date.
- [ ] Change the range picker: the counts and averages change, and nutrition averages say "over N logged days".

## Widgets, Live Activity and Siri
- [ ] Add every widget size before opening the app: each says "Open Form…". Open the app and log something: the widgets update.
- [ ] Leave the phone past midnight: the nutrition widgets reset to "0 kcal logged" or show the full target.
- [ ] Ask Siri "How many calories today in Form", then "Start a workout in Form".
- [ ] Turn off Live Activities in iOS Settings › Form. Starting a workout still works, with no Live Activity.

## Settings and data
- [ ] Switch weight units: existing values convert for display, and new entries are saved correctly.
- [ ] Turn the daily reminder on (permission prompt appears), set it 2 minutes ahead with nothing logged, and wait for it. Log a food and confirm today's reminder no longer arrives.
- [ ] Export CSV and open the files in Numbers. Blank cells appear where values were never entered.
- [ ] Export JSON and check it opens in a text editor.
- [ ] Delete all data: the button stays disabled until you type DELETE exactly. Afterwards the app looks like a fresh install and the widgets are empty.

## Appearance and accessibility
- [ ] Check light, dark, and both with Increase Contrast.
- [ ] Set Dynamic Type to the largest accessibility size. Nothing important is cut off on Today, the active workout, the diary or Settings.
- [ ] With VoiceOver, log a set, start and skip the rest timer, log a food, and read a chart (the Audio Graph is available from the rotor).
- [ ] Turn on Reduce Motion: rings, the undo banner and button presses don't animate.
- [ ] Test in a language with comma decimals (for example German): "72,5" is accepted as a weight.

## Robustness
- [ ] Use Airplane mode throughout: everything works.
- [ ] Change the time zone and confirm today's diary still shows the right entries.
- [ ] Fill the device storage nearly full and save something. An error message appears and nothing crashes.
