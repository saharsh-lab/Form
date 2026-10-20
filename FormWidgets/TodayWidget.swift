import SwiftUI
import WidgetKit
import FormCore

/// Large Home Screen widget: nutrition, training and body weight together.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FormToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "form://today"))
                .formWidgetBackground()
        }
        .configurationDisplayName("Today")
        .description("Nutrition, training and body weight at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let nutrition = snapshot.nutrition(on: entry.date)
            let headline = WidgetText.caloriesHeadline(nutrition)
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.formTextSecondary)

                HStack(spacing: Spacing.m) {
                    ZStack {
                        WidgetRing(progress: nutrition.progress(for: .calories), lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(headline.value).font(.title2.weight(.bold)).monospacedDigit()
                                .foregroundStyle(Color.formTextPrimary).minimumScaleFactor(0.6).lineLimit(1)
                            Text(headline.caption).font(.caption2).foregroundStyle(Color.formTextSecondary)
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(width: 112, height: 112)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Calories")
                    .accessibilityValue("\(headline.value) \(headline.caption)")

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        WidgetMacroBar(title: "Protein", nutrient: .protein, nutrition: nutrition, tint: .formProtein)
                        WidgetMacroBar(title: "Carbs", nutrient: .carbohydrates, nutrition: nutrition, tint: .formCarbs)
                        WidgetMacroBar(title: "Fat", nutrient: .fat, nutrition: nutrition, tint: .formFat)
                    }
                }

                Divider().overlay(Color.formSeparator)

                if let active = snapshot.training.active {
                    Link(destination: URL(string: "form://workout")!) {
                        ActiveWorkoutWidgetContent(active: active, compact: false)
                    }
                } else {
                    HStack(alignment: .top) {
                        tile(title: "This week", value: "\(snapshot.workoutsThisWeek(on: entry.date))", caption: "workouts")
                        tile(title: "Streak", value: "\(snapshot.training.weeklyStreak)", caption: "weeks")
                        if let weight = snapshot.latestBodyWeight {
                            tile(title: "Weight", value: NumberText.weight(kilograms: weight.kilograms, unit: snapshot.weightUnit),
                                 caption: weight.date.formatted(.dateTime.day().month(.abbreviated)))
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: Spacing.s) {
                    action("Workout", symbol: "figure.strengthtraining.traditional", url: "form://start-workout")
                    action("Food", symbol: "fork.knife", url: "form://nutrition")
                    action("Weight", symbol: "scalemass", url: "form://log-weight")
                }
            }
        } else {
            WidgetEmptyView(symbol: "sun.max", message: "Open Form to show today's nutrition, training and body weight here.")
        }
    }

    private func tile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Color.formTextSecondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Color.formTextPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(Color.formTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func action(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(Color.formAccentSoft))
                .foregroundStyle(Color.formAccent)
        }
    }
}
