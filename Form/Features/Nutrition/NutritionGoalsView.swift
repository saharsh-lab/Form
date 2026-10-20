import SwiftUI
import SwiftData
import FormCore

/// Edits the daily nutrition targets that apply from today onwards.
/// Earlier days keep the targets that applied at the time.
struct NutritionGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyNutritionGoal.effectiveFrom, order: .reverse) private var goals: [DailyNutritionGoal]

    @State private var text: [Nutrient: String] = [:]
    @State private var errors: [Nutrient: String] = [:]
    @State private var saveError: String?
    @State private var didLoad = false
    @State private var isSaving = false
    @FocusState private var focused: Nutrient?

    /// Accepted range for each target.
    static func range(for nutrient: Nutrient) -> ClosedRange<Double> {
        nutrient == .calories ? 0...10_000 : 0...1_000
    }

    private var currentGoal: DailyNutritionGoal? {
        let snapshots = goals.map(\.snapshot)
        guard let resolved = GoalResolver.goal(on: .now, from: snapshots) else { return nil }
        return goals.first { $0.effectiveFrom == resolved.effectiveFrom }
    }

    var body: some View {
        List {
            Section {
                ForEach(Nutrient.allCases) { nutrient in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack {
                            Text(nutrient.displayName)
                            Spacer()
                            TextField("Not set", text: binding(for: nutrient))
                                .keyboardType(nutrient == .calories ? .numberPad : .decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focused, equals: nutrient)
                                .frame(maxWidth: 120)
                                .accessibilityLabel("\(nutrient.displayName) target in \(nutrient.unitSymbol)")
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(Color.formTextSecondary)
                                .frame(width: 36, alignment: .leading)
                        }
                        if let error = errors[nutrient] {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Color.formDestructive)
                        }
                    }
                }
            } header: {
                Text("Daily targets")
            } footer: {
                Text("Leave a field empty to track it without a target. These are personal settings you choose; Form doesn't give medical or dietary advice.")
            }

            if let macroCalories {
                Section {
                    LabeledContent("Calories from macros", value: "\(NumberText.amount(macroCalories)) kcal")
                } footer: {
                    Text("Calculated as 4 kcal per gram of protein and carbohydrate and 9 kcal per gram of fat, for reference only.")
                }
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Daily targets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    /// Reference value only; nil unless protein, carbs and fat are all entered.
    private var macroCalories: Double? {
        let locale = Locale.current
        guard let protein = InputValidator.parseDecimal(text[.protein] ?? "", locale: locale),
              let carbs = InputValidator.parseDecimal(text[.carbohydrates] ?? "", locale: locale),
              let fat = InputValidator.parseDecimal(text[.fat] ?? "", locale: locale) else { return nil }
        return protein * 4 + carbs * 4 + fat * 9
    }

    private func binding(for nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { text[nutrient] ?? "" },
            set: {
                text[nutrient] = $0
                errors[nutrient] = nil
            }
        )
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let goal = currentGoal else { return }
        for nutrient in Nutrient.allCases {
            text[nutrient] = NumberText.editable(goal.targets[nutrient], maxFractionDigits: 1)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        var targets = NutritionValues()
        var newErrors: [Nutrient: String] = [:]
        for nutrient in Nutrient.allCases {
            switch InputValidator.optionalDecimal(text[nutrient] ?? "", in: Self.range(for: nutrient)) {
            case .success(let value):
                // A zero target is treated as "no target" rather than a target of zero.
                targets[nutrient] = (value ?? 0) > 0 ? value : nil
            case .failure(let error):
                newErrors[nutrient] = error.localizedDescription
            }
        }
        errors = newErrors
        guard newErrors.isEmpty else {
            HapticsManager.shared.error()
            return
        }

        let today = Calendar.current.startOfDay(for: .now)
        if let goal = goals.first(where: { $0.effectiveFrom == today }) {
            goal.targets = targets
        } else {
            modelContext.insert(DailyNutritionGoal(effectiveFrom: today, targets: targets))
        }

        if let error = modelContext.saveReportingErrors() {
            modelContext.rollback()
            saveError = "Couldn't save targets: \(error.localizedDescription)"
            HapticsManager.shared.error()
            return
        }
        saveError = nil
        HapticsManager.shared.saveSucceeded()
        dismiss()
    }
}
