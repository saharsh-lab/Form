import SwiftUI
import SwiftData
import FormCore

/// Reviews a saved meal and logs each of its foods as a separate, editable diary entry.
struct SavedMealLogView: View {
    @Environment(\.modelContext) private var modelContext
    let savedMeal: SavedMeal
    let day: Date
    var onFinished: () -> Void

    @State private var meal: MealType
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(savedMeal: SavedMeal, meal: MealType, day: Date, onFinished: @escaping () -> Void) {
        self.savedMeal = savedMeal
        self.day = day
        self.onFinished = onFinished
        _meal = State(initialValue: meal)
    }

    var body: some View {
        let items = savedMeal.orderedItems
        let totals = NutritionTotals(items.map(\.nutrition))
        List {
            Section {
                ForEach(items) { item in
                    SavedMealItemRow(item: item)
                }
            } header: {
                Text("Foods")
            } footer: {
                if items.contains(where: { $0.food == nil }) {
                    Text("Foods that were deleted from your list use the values saved with this meal.")
                }
            }

            Section("Total") {
                ForEach(Nutrient.allCases) { nutrient in
                    LabeledContent(nutrient.displayName,
                                   value: "\(NumberText.amount(totals.total(for: nutrient))) \(nutrient.unitSymbol)")
                }
                if totals.isIncomplete {
                    InlineNotice(symbol: "exclamationmark.triangle", text: "Some foods are missing values, so totals may be low.", tint: .formWarning)
                }
            }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.displayName, systemImage: meal.symbol).tag(meal)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(savedMeal.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Add \(items.count) \(items.count == 1 ? "food" : "foods") to \(meal.displayName)", action: log)
                .buttonStyle(FormPrimaryButtonStyle())
                .disabled(isSaving || items.isEmpty)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(Color.formBackground.opacity(0.96))
        }
    }

    private func log() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try NutritionRepository(context: modelContext).log(savedMeal, to: meal, day: day)
            HapticsManager.shared.saveSucceeded()
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}

struct SavedMealItemRow: View {
    let item: SavedMealItem

    var body: some View {
        let nutrition = item.nutrition
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.food?.name ?? item.foodName)
                    .foregroundStyle(Color.formTextPrimary)
                Text(quantityText)
                    .formCaption()
            }
            Spacer()
            Text(nutrition.calories.map { "\(NumberText.amount($0)) kcal" } ?? "– kcal")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(nutrition.calories == nil ? Color.formTextSecondary : Color.formTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var quantityText: String {
        let amount = NumberText.amount(item.quantity)
        if item.quantityUnit == .serving {
            return "\(amount) \(item.quantity == 1 ? "serving" : "servings")"
        }
        return "\(amount) \(item.quantityUnit.symbol)"
    }
}

/// Lists saved meals for management.
struct SavedMealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMeal.name) private var savedMeals: [SavedMeal]
    @State private var pendingDeletion: SavedMeal?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if savedMeals.isEmpty {
                EmptyStateView(symbol: "takeoutbag.and.cup.and.straw",
                               title: "No saved meals",
                               message: "In the diary, open a meal's menu and choose Save as Meal to reuse a combination of foods.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(savedMeals) { savedMeal in
                        NavigationLink {
                            SavedMealDetailView(savedMeal: savedMeal)
                        } label: {
                            SavedMealRow(savedMeal: savedMeal)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDeletion = savedMeal
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Color.formDestructive)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Saved meals")
        .confirmationDialog("Delete this saved meal?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { savedMeal in
            Button("Delete \(savedMeal.name)", role: .destructive) {
                do {
                    try NutritionRepository(context: modelContext).delete(savedMeal)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                    HapticsManager.shared.error()
                }
            }
        } message: { _ in
            Text("Diary entries you already logged from it are not affected.")
        }
    }
}

/// Rename a saved meal, remove foods from it, or delete it.
struct SavedMealDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let savedMeal: SavedMeal

    @State private var name = ""
    @State private var nameError: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .submitLabel(.done)
                    .onSubmit(rename)
                if let nameError {
                    Label(nameError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.formDestructive)
                }
            } header: {
                Text("Name")
            }

            Section {
                ForEach(savedMeal.orderedItems) { item in
                    SavedMealItemRow(item: item)
                        .swipeActions {
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                }
            } header: {
                Text("Foods")
            } footer: {
                Text("Swipe to remove a food. Logged diary entries are not affected.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            Section {
                Button("Delete saved meal", role: .destructive) { confirmDelete = true }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(savedMeal.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = savedMeal.name }
        .onDisappear(perform: rename)
        .confirmationDialog("Delete \(savedMeal.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try NutritionRepository(context: modelContext).delete(savedMeal)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func rename() {
        guard !savedMeal.isDeleted, name != savedMeal.name else { return }
        switch InputValidator.name(name, maximumLength: 60) {
        case .success(let valid):
            nameError = nil
            do {
                try NutritionRepository(context: modelContext).rename(savedMeal, to: valid)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            nameError = error.localizedDescription
        }
    }

    private func remove(_ item: SavedMealItem) {
        do {
            try NutritionRepository(context: modelContext).delete(item)
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}
