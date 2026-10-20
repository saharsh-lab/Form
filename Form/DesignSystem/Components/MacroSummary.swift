import SwiftUI
import FormCore

extension Nutrient {
    var tint: Color {
        switch self {
        case .calories: return .formAccent
        case .protein: return .formProtein
        case .carbohydrates: return .formCarbs
        case .fat: return .formFat
        }
    }
}

/// One macro: label, consumed / target, a bar and a status line.
struct MacroProgressRow: View {
    let nutrient: Nutrient
    let consumed: Double
    let target: Double?
    var missingCount: Int = 0

    private var progress: TargetProgress {
        TargetProgress(consumed: consumed, target: target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(nutrient.tint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(nutrient.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.formTextPrimary)
                Spacer()
                Text(amountText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.formTextPrimary)
            }
            LinearProgressBar(progress: progress, tint: nutrient.tint)
            HStack(spacing: Spacing.xxs) {
                if let symbol = ProgressStatusText.symbol(for: progress.status) {
                    Image(systemName: symbol)
                        .foregroundStyle(progress.status == .exceeded ? Color.formWarning : Color.formSuccess)
                        .accessibilityHidden(true)
                }
                Text(ProgressStatusText.describe(progress, unit: nutrient.unitSymbol))
                if missingCount > 0 {
                    Text("· \(missingCount) without a value")
                }
            }
            .formCaption()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nutrient.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var amountText: String {
        let consumedText = NumberText.amount(consumed)
        if let target, target > 0 {
            return "\(consumedText) / \(NumberText.amount(target)) \(nutrient.unitSymbol)"
        }
        return "\(consumedText) \(nutrient.unitSymbol)"
    }

    private var accessibilityValue: String {
        var parts = ["\(NumberText.amount(consumed)) \(nutrient.unitSymbol) consumed"]
        if let target, target > 0 { parts.append("target \(NumberText.amount(target))") }
        parts.append(ProgressStatusText.describe(progress, unit: nutrient.unitSymbol))
        if missingCount > 0 { parts.append("\(missingCount) entries without a value") }
        return parts.joined(separator: ", ")
    }
}

/// Protein, carbohydrate and fat rows for a day.
struct MacroSummaryView: View {
    let totals: NutritionTotals
    let targets: NutritionValues?

    var body: some View {
        VStack(spacing: Spacing.m) {
            ForEach([Nutrient.protein, .carbohydrates, .fat]) { nutrient in
                MacroProgressRow(nutrient: nutrient,
                                 consumed: totals.total(for: nutrient),
                                 target: targets?[nutrient],
                                 missingCount: totals.missingCount(for: nutrient))
            }
        }
    }
}

/// Calorie ring with consumed, target and remaining.
struct CalorieSummaryView: View {
    let totals: NutritionTotals
    let target: Double?

    private var progress: TargetProgress {
        TargetProgress(consumed: totals.calories, target: target, tolerance: 5)
    }

    var body: some View {
        HStack(spacing: Spacing.l) {
            RingProgressView(progress: progress, lineWidth: 12) {
                VStack(spacing: 0) {
                    Text(NumberText.amount(totals.calories))
                        .formNumeric(.title3, weight: .bold)
                        .foregroundStyle(Color.formTextPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("kcal").formCaption()
                }
                .padding(Spacing.xs)
            }
            .frame(width: 112, height: 112)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s) {
                summaryLine(title: "Consumed", value: "\(NumberText.amount(totals.calories)) kcal")
                summaryLine(title: "Target", value: target.map { "\(NumberText.amount($0)) kcal" } ?? "Not set")
                summaryLine(title: progress.status == .exceeded ? "Over" : "Remaining",
                            value: remainingText,
                            symbol: ProgressStatusText.symbol(for: progress.status),
                            emphasis: progress.status == .exceeded)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(accessibilityValue)
    }

    private var remainingText: String {
        guard let remaining = progress.remaining else { return "—" }
        return "\(NumberText.amount(abs(remaining))) kcal"
    }

    private var accessibilityValue: String {
        var text = "\(NumberText.amount(totals.calories)) kilocalories consumed"
        if let target, target > 0 { text += " of \(NumberText.amount(target))" }
        text += ". " + ProgressStatusText.describe(progress, unit: "kilocalories")
        return text
    }

    @ViewBuilder
    private func summaryLine(title: String, value: String, symbol: String? = nil, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).formCaption()
            HStack(spacing: Spacing.xxs) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(emphasis ? Color.formWarning : Color.formSuccess)
                }
                Text(value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(emphasis ? Color.formWarning : Color.formTextPrimary)
            }
        }
    }
}
