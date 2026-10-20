import SwiftUI
import SwiftData
import FormCore

/// Nutrition tab root: a food diary for one day with daily totals.
///
/// Phase 1 scope: the diary reads persisted entries, totals and goals.
/// Creating foods and logging entries arrive in Phase 2.
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

/// Totals and meal sections for one day.
struct DiaryDayView: View {
    @Query private var entries: [FoodLogEntry]
    @Query(sort: \DailyNutritionGoal.effectiveFrom, order: .reverse) private var goals: [DailyNutritionGoal]
    private let day: Date

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
                }
                .padding(.vertical, Spacing.xs)
            }

            ForEach(MealType.allCases) { meal in
                let mealEntries = entries.filter { $0.meal == meal }
                Section {
                    if mealEntries.isEmpty {
                        Text("Nothing logged")
                            .font(.subheadline)
                            .foregroundStyle(Color.formTextSecondary)
                    } else {
                        ForEach(mealEntries) { entry in
                            FoodLogRow(entry: entry)
                        }
                    }
                } header: {
                    MealHeader(meal: meal, totals: NutritionTotals(mealEntries.map(\.nutrition)), isEmpty: mealEntries.isEmpty)
                }
            }

            Section {
                InlineNotice(symbol: "hammer", text: "Adding foods and logging meals arrive in the next build (Phase 2). Form never estimates nutrition: you enter every value yourself.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

private struct MealHeader: View {
    let meal: MealType
    let totals: NutritionTotals
    let isEmpty: Bool

    var body: some View {
        HStack {
            Label(meal.displayName, systemImage: meal.symbol)
            Spacer()
            if !isEmpty {
                Text("\(NumberText.amount(totals.calories)) kcal")
                    .monospacedDigit()
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
