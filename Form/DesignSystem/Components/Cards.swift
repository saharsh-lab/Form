import SwiftUI

/// The standard content container: a surface with a hairline border and a soft shadow.
struct FormCard<Content: View>: View {
    var padding: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.formSurface)
                .shadow(color: .formShadow, radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Color.formSeparator, lineWidth: 0.5)
        )
    }
}

/// A section title with an optional trailing control.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.formTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.xs)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// A compact labelled value, for example "Workouts this week · 3".
struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .formCaption()
            Text(value)
                .formNumeric(.title3)
                .foregroundStyle(Color.formTextPrimary)
            if let caption {
                Text(caption).formCaption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A friendly placeholder for screens and sections with no data yet.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.formAccent)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.formTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.formTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FormSecondaryButtonStyle(fullWidth: false))
                    .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .padding(.horizontal, Spacing.m)
    }
}

/// An inline notice explaining incomplete or noteworthy data. Uses an icon and text, not colour alone.
struct InlineNotice: View {
    let symbol: String
    let text: String
    var tint: Color = .formTextSecondary

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.formTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
