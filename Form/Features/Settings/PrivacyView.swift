import SwiftUI

/// Plain-language explanation of how Form handles data.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                PrivacyPoint(symbol: "iphone",
                             title: "Your data stays on this iPhone",
                             text: "Workouts, foods, diary entries, goals and measurements are stored only in Form's local database (\(PersistenceController.storeDescription)).")
                PrivacyPoint(symbol: "person.crop.circle.badge.xmark",
                             title: "No account",
                             text: "Form never asks you to sign up or sign in.")
                PrivacyPoint(symbol: "antenna.radiowaves.left.and.right.slash",
                             title: "No servers, no tracking",
                             text: "Form makes no network requests, contains no analytics or advertising, and doesn't send your data anywhere.")
                PrivacyPoint(symbol: "square.and.pencil",
                             title: "You enter every value",
                             text: "Form never estimates calories or nutrients and uses no AI, image recognition or food databases.")
                PrivacyPoint(symbol: "icloud.slash",
                             title: "Backups",
                             text: "Form doesn't sync with iCloud. Your iPhone's own device backups include Form's data according to your system settings.")
            }
            Section {
                Text("Targets you set in Form are personal preferences, not medical advice. Talk to a qualified professional about nutrition or training decisions that affect your health.")
                    .font(.footnote)
                    .foregroundStyle(Color.formTextSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.formAccent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.formTextPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.formTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
