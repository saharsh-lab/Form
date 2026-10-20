import SwiftUI
import SwiftData
import FormCore

/// Nutrition tab root: a food diary for one day with daily totals.
///
/// Every value is entered by the user; Form never estimates nutrition.
struct NutritionView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)

    var body: some View {
        DiaryDayView(day: day)
            .formPageBackground()
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                DayStepper(day: $day)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.formBackground)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FoodLibraryView()
                    } label: {
                        Text("Foods")
                            .frame(minHeight: Metrics.minimumTouchTarget)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NutritionGoalsView()
                    } label: {
                        Image(systemName: "target")
                            .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                    }
                    .accessibilityLabel("Daily targets")
                }
            }
    }
}

/// Previous / next day controls around the selected date.
struct DayStepper: View {
    @Binding var day: Date
    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(day) }

    var body: some View {
        HStack {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            Button {
                day = calendar.startOfDay(for: .now)
            } label: {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.formTextPrimary)
                    if !isToday {
                        Text("Tap for today").formCaption()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityHint(isToday ? "" : "Returns to today")

            Spacer()

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
    }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        // The diary never moves past today.
        day = min(calendar.startOfDay(for: next), calendar.startOfDay(for: .now))
    }
}

/// Totals and meal sections for one day, with logging, editing, moving,
/// duplicating and deleting (with undo) of entries.
struct DiaryDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var entries: [FoodLogEntry]
    @Query(sort: \DailyNutritionGoal.effectiveFrom, order: .reverse) private var goals: [DailyNutritionGoal]
    private let day: Date

    @State private var addingTo: MealType?
    @State private var editing: FoodLogEntry?
    @State private var undoBackup: DeletedLogEntry?
    @State private var savingMealFrom: MealType?
    @State private var newMealName = ""
    @State private var errorMessage: String?

    init(day: Date) {
        self.day = day
        let range = DayBounds.range(containing: day)
        let start = range.lowerBound
        let end = range.upperBound
        _entries = Query(filter: #Predicate<FoodLogEntry> { entry in
            entry.day >= start && entry.day < end
        }, sort: \FoodLogEntry.loggedAt)
    }

    private var targets: NutritionValues? {
        GoalResolver.goal(on: day, from: goals.map(\.snapshot))?.targets
    }

    private var repository: NutritionRepository { NutritionRepository(context: modelContext) }

    var body: some View {
        let totals = NutritionTotals(entries.map(\.nutrition))
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CalorieSummaryView(totals: totals, target: targets?.calories)
                    MacroSummaryView(totals: totals, targets: targets)
                    if targets == nil {
                        InlineNotice(symbol: "target", text: "No daily targets set. Use the target button to add your own.")
                    }
                    if totals.missingCount(for: .calories) > 0 {
                        InlineNotice(symbol: "exclamationmark.triangle",
                                     text: "\(totals.missingCount(for: .calories)) \(totals.missingCount(for: .calories) == 1 ? "entry has" : "entries have") no calorie value, so the total may be low.",
                                     tint: .formWarning)
                    }
                }
                .padding(.vertical, Spacing.xs)
            } footer: {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            ForEach(MealType.allCases) { meal in
                let mealEntries = entries.filter { $0.meal == meal }
                Section {
                    ForEach(mealEntries) { entry in
                        entryRow(entry)
                    }
                    Button {
                        addingTo = meal
                    } label: {
                        Label("Add food", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityLabel("Add food to \(meal.displayName)")
                } header: {
                    MealHeader(meal: meal,
                               totals: NutritionTotals(mealEntries.map(\.nutrition)),
                               isEmpty: mealEntries.isEmpty) {
                        newMealName = "\(meal.displayName) \(day.formatted(.dateTime.day().month(.abbreviated)))"
                        savingMealFrom = meal
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) {
            if let backup = undoBackup {
                UndoToast(message: "Deleted \(backup.foodName)") {
                    restore(backup)
                } onExpire: {
                    if undoBackup?.id == backup.id { undoBackup = nil }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.s)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(backup.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: undoBackup?.id)
        .sheet(item: $addingTo) { meal in
            FoodPickerSheet(meal: meal, day: day)
        }
        .sheet(item: $editing) { entry in
            NavigationStack {
                LogFoodView(mode: .edit(entry), meal: entry.meal) { editing = nil }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editing = nil }
                        }
                    }
            }
        }
        .alert("Save as meal",
               isPresented: Binding(get: { savingMealFrom != nil }, set: { if !$0 { savingMealFrom = nil } })) {
            TextField("Name", text: $newMealName)
            Button("Save") { saveMeal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this meal's foods and quantities so you can log them together later.")
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: FoodLogEntry) -> some View {
        Button {
            editing = entry
        } label: {
            FoodLogRow(entry: entry)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                duplicate(entry)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(Color.formAccent)
        }
        .contextMenu {
            Button { editing = entry } label: { Label("Edit", systemImage: "pencil") }
            Button { duplicate(entry) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu {
                ForEach(MealType.allCases.filter { $0 != entry.meal }) { meal in
                    Button(meal.displayName) { move(entry, to: meal) }
                }
            } label: {
                Label("Move to", systemImage: "arrow.right.square")
            }
            Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityHint("Opens the entry for editing")
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    private func delete(_ entry: FoodLogEntry) {
        perform { undoBackup = try repository.delete(entry) }
    }

    private func restore(_ backup: DeletedLogEntry) {
        perform {
            try repository.restore(backup)
            undoBackup = nil
        }
    }

    private func duplicate(_ entry: FoodLogEntry) {
        perform {
            try repository.duplicate(entry)
            HapticsManager.shared.saveSucceeded()
        }
    }

    private func move(_ entry: FoodLogEntry, to meal: MealType) {
        perform { try repository.move(entry, to: meal) }
    }

    private func saveMeal() {
        guard let meal = savingMealFrom else { return }
        let mealEntries = entries.filter { $0.meal == meal }
        switch InputValidator.name(newMealName, maximumLength: 60) {
        case .success(let name):
            perform {
                try repository.saveMeal(named: name, from: mealEntries)
                HapticsManager.shared.saveSucceeded()
            }
        case .failure(let error):
            errorMessage = "Meal not saved: \(error.localizedDescription)"
            HapticsManager.shared.error()
        }
        savingMealFrom = nil
    }
}

private struct MealHeader: View {
    let meal: MealType
    let totals: NutritionTotals
    let isEmpty: Bool
    let saveAsMeal: () -> Void

    var body: some View {
        HStack {
            Label(meal.displayName, systemImage: meal.symbol)
            Spacer()
            if !isEmpty {
                Text("\(NumberText.amount(totals.calories)) kcal")
                    .monospacedDigit()
                Menu {
                    Button(action: saveAsMeal) {
                        Label("Save as meal", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: 32)
                }
                .accessibilityLabel("\(meal.displayName) options")
            }
        }
    }
}

/// One diary entry: name, quantity and its scaled nutrition, with missing values marked.
struct FoodLogRow: View {
    let entry: FoodLogEntry

    var body: some View {
        let nutrition = entry.nutrition
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .foregroundStyle(Color.formTextPrimary)
                Text(quantityText)
                    .formCaption()
                Text(macroText(nutrition))
                    .font(.caption)
                    .foregroundStyle(Color.formTextSecondary)
            }
            Spacer()
            Text(nutrition.calories.map { "\(NumberText.amount($0)) kcal" } ?? "– kcal")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(nutrition.calories == nil ? Color.formTextSecondary : Color.formTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var quantityText: String {
        let amount = NumberText.amount(entry.quantity)
        switch entry.quantityUnit {
        case .serving:
            let description = entry.servingDescription.isEmpty ? "" : " (\(entry.servingDescription))"
            return "\(amount) \(entry.quantity == 1 ? "serving" : "servings")\(description)"
        default:
            return "\(amount) \(entry.quantityUnit.symbol)"
        }
    }

    private func macroText(_ values: NutritionValues) -> String {
        func part(_ letter: String, _ value: Double?) -> String {
            "\(letter) \(value.map { NumberText.amount($0) } ?? "–") g"
        }
        return [part("P", values.protein), part("C", values.carbohydrates), part("F", values.fat)].joined(separator: "  ")
    }
}
