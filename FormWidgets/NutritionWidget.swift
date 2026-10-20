import SwiftUI
import WidgetKit
import FormCore

/// Calories left (or over) and macros for today, on the Home Screen and Lock Screen.
struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FormNutrition", provider: SnapshotProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .widgetURL(URL(string: "form://nutrition"))
                .formWidgetBackground()
        }
        .configurationDisplayName("Nutrition")
        .description("Calories and macros you've logged today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let nutrition = snapshot.nutrition(on: entry.date)
            switch family {
            case .accessoryCircular: circular(nutrition)
            case .accessoryRectangular: rectangular(nutrition)
            case .accessoryInline: inline(nutrition)
            case .systemMedium: medium(nutrition)
            default: small(nutrition)
            }
        } else {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Label("Open Form", systemImage: "fork.knife")
            default:
                WidgetEmptyView(symbol: "fork.knife", message: "Open Form to show today's nutrition here.")
            }
        }
    }

    private func small(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
        let headline = WidgetText.caloriesHeadline(nutrition)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Calories").font(.caption.weight(.semibold)).foregroundStyle(Color.formTextSecondary)
            ZStack {
                WidgetRing(progress: nutrition.progress(for: .calories), lineWidth: 9)
                VStack(spacing: 0) {
                    Text(headline.value).font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Color.formTextPrimary).minimumScaleFactor(0.6).lineLimit(1)
                    Text(headline.caption).font(.caption2).foregroundStyle(Color.formTextSecondary)
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(headline.value) \(headline.caption)")
    }

    private func medium(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
        HStack(spacing: Spacing.m) {
            small(nutrition)
            VStack(alignment: .leading, spacing: Spacing.s) {
                WidgetMacroBar(title: "Protein", nutrient: .protein, nutrition: nutrition, tint: .formProtein)
                WidgetMacroBar(title: "Carbs", nutrient: .carbohydrates, nutrition: nutrition, tint: .formCarbs)
                WidgetMacroBar(title: "Fat", nutrient: .fat, nutrition: nutrition, tint: .formFat)
                if nutrition.entriesMissingCalories > 0 {
                    Text("\(nutrition.entriesMissingCalories) without calories")
                        .font(.caption2).foregroundStyle(Color.formWarning)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func circular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
        let progress = nutrition.progress(for: .calories)
        let headline = WidgetText.caloriesHeadline(nutrition)
        return Gauge(value: progress.clampedFraction) {
            Image(systemName: "flame")
        } currentValueLabel: {
            Text(headline.value).monospacedDigit().minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Calories")
        .accessibilityValue("\(headline.value) \(headline.caption)")
    }

    private func rectangular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
        let headline = WidgetText.caloriesHeadline(nutrition)
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(headline.value) \(headline.caption)").font(.headline).widgetAccentable()
            Text("Protein \(WidgetText.amount(nutrition.consumed.protein, target: nutrition.targets.protein, unit: "g"))")
                .font(.caption)
            Gauge(value: nutrition.progress(for: .calories).clampedFraction) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }

    private func inline(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
        let headline = WidgetText.caloriesHeadline(nutrition)
        return Label("\(headline.value) \(headline.caption)", systemImage: "flame")
    }
}
