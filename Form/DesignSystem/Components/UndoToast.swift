import SwiftUI

/// A short-lived banner offering to undo a destructive action.
/// It disappears by itself after `duration` seconds; VoiceOver announces it.
struct UndoToast: View {
    let message: String
    var duration: TimeInterval = 5
    let undo: () -> Void
    let onExpire: () -> Void

    init(message: String, duration: TimeInterval = 5, undo: @escaping () -> Void, onExpire: @escaping () -> Void) {
        self.message = message
        self.duration = duration
        self.undo = undo
        self.onExpire = onExpire
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.formTextPrimary)
                .lineLimit(2)
            Spacer(minLength: Spacing.xs)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.formAccent)
                .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.formSurface)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Color.formSeparator, lineWidth: 0.5)
        )
        .task {
            UIAccessibility.post(notification: .announcement, argument: "\(message). Undo available.")
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { onExpire() }
        }
    }
}
