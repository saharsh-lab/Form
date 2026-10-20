import SwiftUI
import WidgetKit
import FormCore

/// Shown before the app has shared any data with widgets.
struct WidgetEmptyView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.formAccent)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.formTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A ring for one nutrient: filled to the target, or plain when no target is set.
struct WidgetRing: View {
    let progress: TargetProgress
    var tint: Color = .formAccent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.formSurfaceSecondary, lineWidth: lineWidth)
            if progress.hasTarget {
                Circle()
                    .trim(from: 0, to: progress.clampedFraction)
                    .stroke(progress.status == .exceeded ? Color.formWarning : tint,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct WidgetMacroBar: View {
    let title: String
    let nutrient: Nutrient
    let nutrition: WidgetSnapshot.Nutrition
    let tint: Color

    var body: some View {
        let progress = nutrition.progress(for: nutrient)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(title).font(.caption2.weight(.medium)).foregroundStyle(Color.formTextSecondary)
                Spacer(minLength: 2)
                Text(WidgetText.amount(nutrition.consumed[nutrient], target: nutrition.targets[nutrient], unit: "g"))
                    .font(.caption2).monospacedDigit().foregroundStyle(Color.formTextPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.formSurfaceSecondary)
                    if progress.hasTarget {
                        Capsule().fill(tint).frame(width: proxy.size.width * progress.clampedFraction)
                    }
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(WidgetText.spokenAmount(nutrition.consumed[nutrient], target: nutrition.targets[nutrient], unit: "grams"))
    }
}

enum WidgetText {
    /// "96 / 150 g", "96 g", or "— g" when nothing with this value was logged.
    static func amount(_ value: Double?, target: Double?, unit: String) -> String {
        let consumed = value.map { "\(Int($0.rounded()))" } ?? "—"
        if let target, target > 0 { return "\(consumed) / \(Int(target.rounded())) \(unit)" }
        return "\(consumed) \(unit)"
    }

    static func spokenAmount(_ value: Double?, target: Double?, unit: String) -> String {
        let consumed = value.map { "\(Int($0.rounded())) \(unit)" } ?? "not recorded"
        if let target, target > 0 { return "\(consumed) of \(Int(target.rounded())) \(unit)" }
        return consumed
    }

    static func caloriesHeadline(_ nutrition: WidgetSnapshot.Nutrition) -> (value: String, caption: String) {
        let progress = nutrition.progress(for: .calories)
        guard nutrition.entryCount > 0 else {
            if let target = progress.target { return ("\(Int(target.rounded()))", "kcal to go") }
            return ("0", "kcal logged")
        }
        if let remaining = progress.remaining {
            return remaining >= 0 ? ("\(Int(remaining.rounded()))", "kcal left") : ("\(Int((-remaining).rounded()))", "kcal over")
        }
        return ("\(Int((nutrition.consumed.calories ?? 0).rounded()))", "kcal logged")
    }
}

extension View {
    /// Widget background that follows the app's palette.
    func formWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color.formSurface }
    }
}
