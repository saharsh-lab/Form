import SwiftUI
import SwiftData

@main
struct FormApplication: App {
    @State private var router = AppRouter()
    private let storeResult: Result<ModelContainer, Error>

    init() {
        if ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") {
            storeResult = Result { try PersistenceController.makeContainer(location: .inMemory) }
        } else {
            storeResult = Result { try PersistenceController.makeContainer() }
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storeResult {
            case .success(let container):
                RootView()
                    .environment(router)
                    .onOpenURL { router.handle(url: $0) }
                    .modelContainer(container)
            case .failure(let error):
                DataStoreErrorView(error: error)
            }
        }
    }
}

/// Shown if the local database cannot be opened. Nothing is deleted automatically.
struct DataStoreErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.formWarning)
                .accessibilityHidden(true)
            Text("Form couldn't open your data")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your data has not been changed or deleted. Try restarting the app. If this keeps happening, make sure your iPhone has free storage and that Form is up to date.")
                .font(.body)
                .foregroundStyle(Color.formTextSecondary)
                .multilineTextAlignment(.center)
            Text(error.localizedDescription)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.formTextSecondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .formPageBackground()
    }
}
