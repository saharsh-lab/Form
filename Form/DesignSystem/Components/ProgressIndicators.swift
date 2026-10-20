import SwiftUI
import FormCore

/// A circular progress ring for a `TargetProgress`.
///
/// When the target is exceeded the ring is full and an overflow arc in the
/// warning colour shows how far over it is; the centre label also changes, so
/// the state never relies on colour alone.
struct RingProgressView<Center: View>: View {
    let progress: TargetProgress
    var tint: Color = .formAccent
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.formSurfaceSecondary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.clampedFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress.status == .exceeded {
                Circle()
                    .trim(from: 0, to: progress.overflowFraction)
                    .stroke(Color.formWarning, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center
        }
        .padding(lineWidth / 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress.clampedFraction)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress.overflowFraction)
    }
}

/// A horizontal bar for a `TargetProgress`, with an overflow marker when exceeded.
struct LinearProgressBar: View {
    let progress: TargetProgress
    var tint: Color = .formAccent
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.formSurfaceSecondary)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * progress.clampedFraction)
                if progress.status == .exceeded {
                    Capsule()
                        .fill(Color.formWarning)
                        .frame(width: max(height, proxy.size.width * progress.overflowFraction), height: height / 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress.clampedFraction)
        .accessibilityHidden(true)
    }
}

/// Text describing where a value stands against its target: "88 g left", "12 g over", "Target reached".
enum ProgressStatusText {
    static func describe(_ progress: TargetProgress, unit: String) -> String {
        switch progress.status {
        case .noTarget:
            return "No target set"
        case .underTarget:
            return "\(NumberText.amount(progress.remaining ?? 0)) \(unit) left"
        case .reached:
            return "Target reached"
        case .exceeded:
            return "\(NumberText.amount(-(progress.remaining ?? 0))) \(unit) over"
        }
    }

    static func symbol(for status: TargetProgress.Status) -> String? {
        switch status {
        case .noTarget, .underTarget: return nil
        case .reached: return "checkmark.circle.fill"
        case .exceeded: return "exclamationmark.circle.fill"
        }
    }
}
