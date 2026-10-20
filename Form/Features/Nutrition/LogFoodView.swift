import SwiftUI
import SwiftData
import FormCore

/// Chooses quantity, unit and meal for a food, with a live nutrition preview.
/// Used both to log a new entry and to edit an existing one.
struct LogFoodView: View {
    enum Mode {
        case new(Food, day: Date)
        case edit(FoodLogEntry)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    /// Called after a successful save or delete.
    var onFinished: () -> Void

    @State private var quantityText: String
    @State private var unit: QuantityUnit
    @State private var meal: MealType
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmDelete = false
    @FocusState private var quantityFocused: Bool

    init(mode: Mode, meal: MealType, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.onFinished = onFinished
        switch mode {
        case .new(let food, _):
            let defaults = Self.defaultQuantity(for: food.serving)
            _quantityText = State(initialValue: NumberText.editable(defaults.quantity))
            _unit = State(initialValue: defaults.unit)
            _meal = State(initialValue: meal)
        case .edit(let entry):
            _quantityText = State(initialValue: NumberText.editable(entry.quantity))
            _unit = State(initialValue: entry.quantityUnit)
            _meal = State(initialValue: entry.meal)
        }
    }

    // MARK: Derived values

    private var name: String {
        switch mode {
        case .new(let food, _): return food.name
        case .edit(let entry): return entry.foodName
        }
    }

    private var servingDescription: String {
        switch mode {
        case .new(let food, _): return food.servingDescription
        case .edit(let entry): return entry.servingDescription
        }
    }

    /// The serving definition used for scaling. Edits use the entry's snapshot, not the food's current values.
    private var serving: ServingDefinition {
        switch mode {
        case .new(let food, _): return food.serving
        case .edit(let entry): return entry.snapshotServing
        }
    }

    private var baseNutrition: NutritionValues {
        switch mode {
        case .new(let food, _): return food.nutrition
        case .edit(let entry): return entry.snapshotNutrition
        }
    }

    private var units: [QuantityUnit] {
        NutritionScaler.compatibleUnits(for: serving)
    }

    private var parsedQuantity: Double? {
        InputValidator.parseDecimal(quantityText)
    }

    private var preview: Result<NutritionValues, ScalingError> {
        guard let quantity = parsedQuantity else { return .failure(.invalidQuantity) }
        return NutritionScaler.values(base: baseNutrition, serving: serving, quantity: quantity, unit: unit)
    }

    private var canSave: Bool {
        if case .success = preview, !isSaving { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.formTextPrimary)
                    Text(servingSummary)
                        .formCaption()
                }
                .padding(.vertical, Spacing.xxs)
            }

            Section {
                HStack(spacing: Spacing.s) {
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .focused($quantityFocused)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel("Quantity")
                    Picker("Unit", selection: $unit) {
                        ForEach(units) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Unit")
                }
                if unit == .serving {
                    HStack(spacing: Spacing.xs) {
                        ForEach([0.5, 1, 1.5, 2], id: \.self) { amount in
                            Button(NumberText.amount(amount)) {
                                quantityText = NumberText.editable(amount)
                                HapticsManager.shared.selectionChanged()
                            }
                            .buttonStyle(FormSecondaryButtonStyle())
                            .accessibilityLabel("\(NumberText.amount(amount)) servings")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.xxs, leading: 0, bottom: Spacing.xxs, trailing: 0))
                }
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.displayName, systemImage: meal.symbol).tag(meal)
                    }
                }
            } footer: {
                if let message = quantityMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            Section("Nutrition for this amount") {
                switch preview {
                case .success(let values):
                    ForEach(Nutrient.allCases) { nutrient in
                        LabeledContent(nutrient.displayName) {
                            Text(values[nutrient].map { "\(NumberText.amount($0)) \(nutrient.unitSymbol)" } ?? "Not specified")
                                .monospacedDigit()
                                .foregroundStyle(values[nutrient] == nil ? Color.formTextSecondary : Color.formTextPrimary)
                        }
                    }
                case .failure:
                    Text("Enter a valid quantity to see nutrition.")
                        .foregroundStyle(Color.formTextSecondary)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            if case .edit = mode {
                Section {
                    Button("Delete entry", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditing ? "Edit entry" : "Log food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(isEditing ? "Save changes" : "Add to \(meal.displayName)", action: save)
                .buttonStyle(FormPrimaryButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(Color.formBackground.opacity(0.96))
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { quantityFocused = false }
            }
        }
        .onChange(of: unit) { _, _ in errorMessage = nil }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteEntry)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var servingSummary: String {
        let size = "\(NumberText.amount(serving.servingQuantity)) \(serving.servingUnit.symbol)"
        let description = servingDescription.isEmpty ? "1 serving = \(size)" : "\(servingDescription) · 1 serving = \(size)"
        switch serving.basis {
        case .perServing: return "\(description) · values per serving"
        case .per100Grams: return "\(description) · values per 100 g"
        case .per100Milliliters: return "\(description) · values per 100 ml"
        }
    }

    private var quantityMessage: String? {
        guard !quantityText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let quantity = parsedQuantity else { return "Enter a number." }
        if quantity <= 0 { return "Enter a quantity greater than zero." }
        if quantity > 100_000 { return "That quantity is too large." }
        return nil
    }

    // MARK: Actions

    private func save() {
        guard canSave, let quantity = parsedQuantity, quantity <= 100_000 else { return }
        isSaving = true
        defer { isSaving = false }
        let repository = NutritionRepository(context: modelContext)
        do {
            switch mode {
            case .new(let food, let day):
                try repository.log(food, quantity: quantity, unit: unit, meal: meal, day: day)
            case .edit(let entry):
                try repository.update(entry, quantity: quantity, unit: unit, meal: meal)
            }
            HapticsManager.shared.saveSucceeded()
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    private func deleteEntry() {
        guard case .edit(let entry) = mode else { return }
        do {
            try NutritionRepository(context: modelContext).delete(entry)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    /// One serving for per-serving foods; one serving's weight or volume for per-100 foods.
    static func defaultQuantity(for serving: ServingDefinition) -> (quantity: Double, unit: QuantityUnit) {
        switch serving.basis {
        case .perServing:
            return (1, .serving)
        case .per100Grams, .per100Milliliters:
            return (serving.servingQuantity, serving.servingUnit)
        }
    }
}
