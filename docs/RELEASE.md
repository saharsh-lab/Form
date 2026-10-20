# Releasing Form

This guide takes Form from this repository to TestFlight and the App Store. Read [QA.md](QA.md) first and work through it on a real iPhone before submitting.

## 1. Identity and signing

1. Choose your identifiers and set them at the top of `project.yml`:
   - `FORM_BUNDLE_ID`, for example `com.yourname.form`. The widget extension becomes `com.yourname.form.widgets`.
   - `FORM_APP_GROUP`, for example `group.com.yourname.form`.
   - `DEVELOPMENT_TEAM`: your 10-character Team ID.
2. Run `xcodegen generate`.
3. In Xcode, open **Signing & Capabilities** for the **Form** and **FormWidgets** targets. With automatic signing, Xcode registers both App IDs and the App Group. Check that both targets list the same App Group.
4. Set the version in `project.yml`. `MARKETING_VERSION` is the version people see (for example `1.0.0`). `CURRENT_PROJECT_VERSION` is the build number, which must go up with every upload.

## 2. Pre-flight checks

- [ ] CI is green: the FormCore tests, app build, unit tests and UI tests all pass.
- [ ] The QA checklist has been run on a device, in light and dark mode and at a large text size.
- [ ] The app icon is final. `Form/Resources/Assets.xcassets/AppIcon.appiconset` currently holds a placeholder 1024 × 1024 PNG.
- [ ] Deleting the app and reinstalling it starts cleanly (seeded catalogue only).
- [ ] Upgrading from the previous TestFlight build keeps all data. Any change to a SwiftData model must be a lightweight migration: add properties with defaults, never rename or retype them without a migration plan.

## 3. Archive and upload

1. Select **Any iOS Device (arm64)** as the destination.
2. Choose **Product › Archive**.
3. In the Organizer, choose **Distribute App › App Store Connect › Upload**.
4. When the build finishes processing, add it to a TestFlight group.

## 4. App Store Connect

| Field | Suggested value |
|---|---|
| Category | Health & Fitness |
| Age rating | 4+ (no objectionable content) |
| Price | Your choice. Form has no in-app purchases. |
| App Privacy | **Data Not Collected.** Form has no network code, analytics, advertising or account. The included `PrivacyInfo.xcprivacy` files declare no tracking, no collected data and no required-reason APIs. |
| Export compliance | `ITSAppUsesNonExemptEncryption` is already `NO` in Info.plist. |
| Sign-in for review | Not required. Form has no accounts. |

**Review notes**

> Form is fully offline and has no account. The exercise catalogue and four starter routines are created on first launch; everything else starts empty. To see the main features: Train › Start empty workout › Add exercise, then complete a set to start the rest timer. Lock the device to see the Live Activity. Nutrition › Foods › + creates a food, which you can then log from the diary. Widgets are available from the Home Screen widget gallery.

**Description draft**

> Form is a calm, focused tracker for training and nutrition. Log workouts set by set with an automatic rest timer, see your personal records and progress over time, and keep a food diary using foods you define yourself. Missing values stay missing, so your totals are never quietly wrong.
>
> • Workouts: routines, warm-up and drop sets, previous-session values, rest timer with Live Activity
> • Personal records: weight, estimated 1RM, set volume, reps, duration and distance
> • Food diary: your own foods, per serving or per 100 g/ml, saved meals, daily targets
> • Progress: workout consistency, exercise history, body measurements and nutrition trends
> • Widgets for the Home Screen and Lock Screen, plus Siri and Shortcuts
> • Private by design: no account, no ads, no tracking, no internet connection needed
> • Export everything as JSON or CSV whenever you like

**Keywords:** workout, gym, strength, lifting, log, rest timer, food diary, calories, protein, macros

**Screenshots (6.9" and 6.5")** in this suggested order: Today, active workout with the rest timer, an exercise progress chart, the food diary, the Lock Screen Live Activity, and widgets.

## 5. After release

- Tag the release: `git tag v1.0.0 && git push origin v1.0.0`.
- Add the release to [CHANGELOG.md](../CHANGELOG.md).
