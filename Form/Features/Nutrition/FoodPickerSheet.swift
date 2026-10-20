import SwiftUI
import SwiftData
import FormCore

/// Navigation targets inside the add-food sheet.
enum FoodPickerDestination: Hashable {
    case log(Food)
    case create(prefillName: String)
    case savedMeal(SavedMeal)
}

/// Sheet for adding to a meal: search the local catalogue, pick a recent,
/// favourite or saved meal, or create a new food. Nothing is ever looked up online.
struct FoodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: MealType
    let day: Date

    @State private var path: [FoodPickerDestination] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack(path: $path) {
            FoodPickerList(searchText: searchText) { destination in
                path.append(destination)
            }
            .navigationTitle("Add to \(meal.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your foods")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: FoodPickerDestination.self) { destination in
                switch destination {
                case .log(let food):
                    LogFoodView(mode: .new(food, day: day), meal: meal) { dismiss() }
                case .create(let prefill):
                    FoodEditorView(mode: .create(prefillName: prefill)) { food in
                        // Replace the editor with the log screen for the new food.
                        path.removeLast()
                        path.append(.log(food))
                    }
                case .savedMeal(let savedMeal):
                    SavedMealLogView(savedMeal: savedMeal, meal: meal, day: day) { dismiss() }
                }
            }
        }
    }
}

private struct FoodPickerList: View {
    @Query(filter: #Predicate<Food> { !$0.isArchived }, sort: \Food.name) private var foods: [Food]
    @Query(sort: \SavedMeal.name) private var savedMeals: [SavedMeal]
    let searchText: String
    let select: (FoodPickerDestination) -> Void

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var recent: [Food] {
        Array(foods.filter { $0.lastLoggedAt != nil }
            .sorted { ($0.lastLoggedAt ?? .distantPast) > ($1.lastLoggedAt ?? .distantPast) }
            .prefix(8))
    }

    private var favourites: [Food] { foods.filter(\.isFavourite) }

    private var matchingFoods: [Food] { TextSearch.rank(foods, query: query, name: { $0.name }) }
    private var matchingMeals: [SavedMeal] { TextSearch.rank(savedMeals, query: query, name: { $0.name }) }

    var body: some View {
        List {
            Section {
                Button {
                    select(.create(prefillName: query))
                } label: {
                    Label(query.isEmpty ? "Create a new food" : "Add \u{201C}\(query)\u{201D} as a new food", systemImage: "plus.circle.fill")
                        .font(.body.weight(.medium))
                }
            }

            if query.isEmpty {
                if foods.isEmpty && savedMeals.isEmpty {
                    EmptyStateView(symbol: "fork.knife",
                                   title: "Your food list is empty",
                                   message: "Form doesn't use an online food database. Create a food with the values from its label and it will be here next time.")
                        .listRowBackground(Color.clear)
                }
                if !savedMeals.isEmpty {
                    Section("Saved meals") {
                        ForEach(savedMeals) { savedMeal in
                            savedMealRow(savedMeal)
                        }
                    }
                }
                if !favourites.isEmpty {
                    Section("Favourites") {
                        ForEach(favourites) { food in foodRow(food) }
                    }
                }
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { food in foodRow(food) }
                    }
                }
                if !foods.isEmpty {
                    Section("All foods") {
                        ForEach(foods) { food in foodRow(food) }
                    }
                }
            } else {
                if !matchingMeals.isEmpty {
                    Section("Saved meals") {
                        ForEach(matchingMeals) { savedMeal in savedMealRow(savedMeal) }
                    }
                }
                Section("Foods") {
                    if matchingFoods.isEmpty {
                        Text("No foods match \u{201C}\(query)\u{201D}.")
                            .foregroundStyle(Color.formTextSecondary)
                    } else {
                        ForEach(matchingFoods) { food in foodRow(food) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
    }

    private func foodRow(_ food: Food) -> some View {
        Button {
            select(.log(food))
        } label: {
            FoodRow(food: food)
        }
        .buttonStyle(.plain)
    }

    private func savedMealRow(_ savedMeal: SavedMeal) -> some View {
        Button {
            select(.savedMeal(savedMeal))
        } label: {
            SavedMealRow(savedMeal: savedMeal)
        }
        .buttonStyle(.plain)
    }
}

/// A catalogue food: name, serving basis and the stored values.
struct FoodRow: View {
    let food: Food

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Text(food.name)
                        .foregroundStyle(Color.formTextPrimary)
                    if food.isFavourite {
                        Image(systemName: "star.fill")
                            .imageScale(.small)
                            .foregroundStyle(Color.formCarbs)
                            .accessibilityLabel("Favourite")
                    }
                }
                Text(subtitle)
                    .formCaption()
                    .lineLimit(1)
            }
            Spacer()
            Text(food.calories.map { "\(NumberText.amount($0)) kcal" } ?? "– kcal")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(food.calories == nil ? Color.formTextSecondary : Color.formTextPrimary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let basis: String
        switch food.serving.basis {
        case .perServing:
            let size = "\(NumberText.amount(food.servingQuantity)) \(food.serving.servingUnit.symbol)"
            basis = food.servingDescription.isEmpty ? "per serving (\(size))" : "per \(food.servingDescription)"
        case .per100Grams: basis = "per 100 g"
        case .per100Milliliters: basis = "per 100 ml"
        }
        let values = food.nutrition
        func part(_ letter: String, _ value: Double?) -> String {
            letter + " " + (value.map { NumberText.amount($0) } ?? "–")
        }
        let macros = [part("P", values.protein), part("C", values.carbohydrates), part("F", values.fat)].joined(separator: " ")
        return "\(basis) · \(macros)"
    }
}

struct SavedMealRow: View {
    let savedMeal: SavedMeal

    var body: some View {
        let totals = NutritionTotals(savedMeal.orderedItems.map(\.nutrition))
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label(savedMeal.name, systemImage: "takeoutbag.and.cup.and.straw")
                    .foregroundStyle(Color.formTextPrimary)
                Text("\(savedMeal.items.count) \(savedMeal.items.count == 1 ? "food" : "foods")")
                    .formCaption()
            }
            Spacer()
            Text(totals.missingCount(for: .calories) == totals.entryCount && totals.entryCount > 0
                 ? "– kcal" : "\(NumberText.amount(totals.calories)) kcal")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.formTextPrimary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
