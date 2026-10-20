import SwiftUI
import SwiftData
import Observation
import FormCore

/// Form state and validation for creating, editing or duplicating a food.
@MainActor
@Observable
final class FoodEditorModel {
    enum Field: Hashable {
        case name, servingDescription, servingQuantity, notes
        case nutrient(Nutrient)
    }

    enum Mode {
        case create(prefillName: String)
        case edit(Food)
        case duplicate(Food)
    }

    let mode: Mode
    var name: String
    var servingDescription: String
    var basis: ServingBasis
    var servingQuantityText: String
    var servingUnit: QuantityUnit
    var nutrientText: [Nutrient: String]
    var notes: String
    var isFavourite: Bool
    var errors: [Field: String] = [:]
    var saveError: String?
    private(set) var isSaving = false

    static let servingQuantityRange: ClosedRange<Double> = 0.01...10_000
    static func range(for nutrient: Nutrient) -> ClosedRange<Double> {
        nutrient == .calories ? 0...10_000 : 0...1_000
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let prefillName):
            name = prefillName
            servingDescription = ""
            basis = .per100Grams
            servingQuantityText = "100"
            servingUnit = .gram
            nutrientText = [:]
            notes = ""
            isFavourite = false
        case .edit(let food), .duplicate(let food):
            if case .duplicate = mode {
                name = NutritionRepository.copyName(for: food.name)
                isFavourite = false
            } else {
                name = food.name
                isFavourite = food.isFavourite
            }
            servingDescription = food.servingDescription
            basis = food.serving.basis
            servingQuantityText = NumberText.editable(food.servingQuantity)
            servingUnit = food.serving.servingUnit
            var text: [Nutrient: String] = [:]
            for nutrient in Nutrient.allCases {
                text[nutrient] = NumberText.editable(food.nutrition[nutrient])
            }
            nutrientText = text
            notes = food.notes
        }
    }

    var title: String {
        switch mode {
        case .create: return "New food"
        case .edit: return "Edit food"
        case .duplicate: return "Duplicate food"
        }
    }

    /// Serving-size units that make sense for the chosen basis.
    var allowedServingUnits: [QuantityUnit] {
        switch basis {
        case .perServing: return QuantityUnit.servingSizeUnits
        case .per100Grams: return QuantityUnit.servingSizeUnits.filter { $0.dimension == .mass }
        case .per100Milliliters: return QuantityUnit.servingSizeUnits.filter { $0.dimension == .volume }
        }
    }

    var basisExplanation: String {
        switch basis {
        case .perServing:
            return "Enter the nutrition for one serving as defined below, for example one egg or one 150 g pot."
        case .per100Grams:
            return "Enter the nutrition for 100 g, as printed on most labels. The serving size lets you log in servings too."
        case .per100Milliliters:
            return "Enter the nutrition for 100 ml. The serving size lets you log in servings too."
        }
    }

    /// Keeps the serving unit compatible with the basis, for example grams for "per 100 g".
    func normalizeServingUnit() {
        guard !allowedServingUnits.contains(servingUnit) else { return }
        switch basis {
        case .per100Grams:
            servingUnit = .gram
            servingQuantityText = "100"
        case .per100Milliliters:
            servingUnit = .milliliter
            servingQuantityText = "100"
        case .perServing:
            servingUnit = .piece
            servingQuantityText = "1"
        }
    }

    func clearError(_ field: Field) {
        errors[field] = nil
        saveError = nil
    }

    struct Validated {
        let name: String
        let servingDescription: String
        let serving: ServingDefinition
        let nutrition: NutritionValues
        let notes: String
    }

    /// Validates every field, filling `errors`. Returns nil if anything is invalid.
    func validate(locale: Locale = .current) -> Validated? {
        var newErrors: [Field: String] = [:]

        let validName: String?
        switch InputValidator.name(name) {
        case .success(let value): validName = value
        case .failure(let error): validName = nil; newErrors[.name] = error.localizedDescription
        }

        let description = servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.count > 60 { newErrors[.servingDescription] = ValidationError.tooLong(maximum: 60).localizedDescription }

        let quantity: Double?
        switch InputValidator.requiredDecimal(servingQuantityText, in: Self.servingQuantityRange, locale: locale) {
        case .success(let value): quantity = value
        case .failure(let error): quantity = nil; newErrors[.servingQuantity] = error.localizedDescription
        }

        var nutrition = NutritionValues()
        for nutrient in Nutrient.allCases {
            switch InputValidator.optionalDecimal(nutrientText[nutrient] ?? "", in: Self.range(for: nutrient), locale: locale) {
            case .success(let value): nutrition[nutrient] = value
            case .failure(let error): newErrors[.nutrient(nutrient)] = error.localizedDescription
            }
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes.count > 500 { newErrors[.notes] = ValidationError.tooLong(maximum: 500).localizedDescription }

        errors = newErrors
        guard newErrors.isEmpty, let validName, let quantity else { return nil }
        return Validated(name: validName,
                         servingDescription: description,
                         serving: ServingDefinition(basis: basis, servingQuantity: quantity, servingUnit: servingUnit),
                         nutrition: nutrition,
                         notes: trimmedNotes)
    }

    /// Validates and saves. Returns the saved food, or nil if validation or saving failed.
    func save(in context: ModelContext) -> Food? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }

        guard let values = validate() else { return nil }

        let food: Food
        switch mode {
        case .edit(let existing):
            food = existing
            food.name = values.name
            food.servingDescription = values.servingDescription
            food.serving = values.serving
            food.nutrition = values.nutrition
            food.notes = values.notes
            food.isFavourite = isFavourite
            food.updatedAt = .now
        case .create, .duplicate:
            food = Food(name: values.name,
                        servingDescription: values.servingDescription,
                        serving: values.serving,
                        nutrition: values.nutrition,
                        notes: values.notes,
                        isFavourite: isFavourite)
            context.insert(food)
        }

        do {
            try context.save()
            return food
        } catch {
            context.rollback()
            saveError = "Couldn't save the food: \(error.localizedDescription)"
            return nil
        }
    }
}

/// Create, edit or duplicate a food. Every value is typed by the user; empty
/// nutrient fields are saved as "not specified", never as zero.
struct FoodEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: FoodEditorModel
    @FocusState private var focus: FoodEditorModel.Field?
    /// Called after a successful save. If nil, the view dismisses itself.
    var onSaved: ((Food) -> Void)?

    init(mode: FoodEditorModel.Mode, onSaved: ((Food) -> Void)? = nil) {
        _model = State(initialValue: FoodEditorModel(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                field(.name) {
                    TextField("Name", text: $model.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focus = .servingDescription }
                }
                field(.servingDescription) {
                    TextField("Serving description (optional)", text: $model.servingDescription, prompt: Text("e.g. 1 medium egg"))
                        .submitLabel(.next)
                        .onSubmit { focus = .servingQuantity }
                }
            } header: {
                Text("Food")
            }

            Section {
                Picker("Values are", selection: $model.basis) {
                    ForEach(ServingBasis.allCases) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                .onChange(of: model.basis) { _, _ in
                    model.normalizeServingUnit()
                    HapticsManager.shared.selectionChanged()
                }

                field(.servingQuantity) {
                    HStack {
                        Text("Serving size")
                        Spacer()
                        TextField("Amount", text: $model.servingQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 90)
                            .accessibilityLabel("Serving size amount")
                        Picker("Unit", selection: $model.servingUnit) {
                            ForEach(model.allowedServingUnits) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel("Serving size unit")
                    }
                }
            } header: {
                Text("Serving basis")
            } footer: {
                Text(model.basisExplanation)
            }

            Section {
                ForEach(Nutrient.allCases) { nutrient in
                    field(.nutrient(nutrient)) {
                        HStack {
                            Circle().fill(nutrient.tint).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(nutrient.displayName)
                            Spacer()
                            TextField("Not set", text: nutrientBinding(nutrient))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 110)
                                .accessibilityLabel("\(nutrient.displayName) in \(nutrient.unitSymbol)")
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(Color.formTextSecondary)
                                .frame(width: 36, alignment: .leading)
                        }
                    }
                }
            } header: {
                Text("Nutrition \(model.basis.displayName.lowercased())")
            } footer: {
                Text("Leave a value empty if you don't know it. Form keeps it as \"not specified\" instead of counting it as zero.")
            }

            Section {
                Toggle("Favourite", isOn: $model.isFavourite)
                field(.notes) {
                    TextField("Notes (optional)", text: $model.notes, axis: .vertical)
                        .lineLimit(1...5)
                }
            }

            if let saveError = model.saveError {
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
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(model.isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear {
            if case .create(let prefill) = model.mode, prefill.isEmpty { focus = .name }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ field: FoodEditorModel.Field, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            content()
                .focused($focus, equals: field)
            if let message = model.errors[field] {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.formDestructive)
            }
        }
        .onChange(of: focus) { old, _ in
            // Clear an error once the user has moved on from fixing it.
            if old == field { model.clearError(field) }
        }
    }

    private func nutrientBinding(_ nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { model.nutrientText[nutrient] ?? "" },
            set: { model.nutrientText[nutrient] = $0 }
        )
    }

    private func save() {
        focus = nil
        if let food = model.save(in: modelContext) {
            HapticsManager.shared.saveSucceeded()
            if let onSaved {
                onSaved(food)
            } else {
                dismiss()
            }
        } else if !model.errors.isEmpty || model.saveError != nil {
            HapticsManager.shared.error()
        }
    }
}
