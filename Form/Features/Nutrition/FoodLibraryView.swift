import SwiftUI
import SwiftData
import FormCore

/// Manage the food catalogue: search, create, edit, duplicate, favourite and delete.
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Food> { !$0.isArchived }, sort: \Food.name) private var foods: [Food]

    @State private var searchText = ""
    @State private var showFavouritesOnly = false
    @State private var editorMode: EditorSheet?
    @State private var pendingDeletion: Food?
    @State private var errorMessage: String?

    /// Wraps the editor mode so it can drive `.sheet(item:)`.
    struct EditorSheet: Identifiable {
        let id = UUID()
        let mode: FoodEditorModel.Mode
    }

    private var visibleFoods: [Food] {
        let base = showFavouritesOnly ? foods.filter(\.isFavourite) : foods
        return TextSearch.rank(base, query: searchText, name: { $0.name })
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SavedMealsView()
                } label: {
                    Label("Saved meals", systemImage: "takeoutbag.and.cup.and.straw")
                }
                Toggle("Favourites only", isOn: $showFavouritesOnly)
            }

            Section {
                if foods.isEmpty {
                    EmptyStateView(symbol: "fork.knife",
                                   title: "No foods yet",
                                   message: "Add foods with the values from their labels. Form never estimates nutrition.",
                                   actionTitle: "Add food") {
                        editorMode = EditorSheet(mode: .create(prefillName: ""))
                    }
                    .listRowBackground(Color.clear)
                } else if visibleFoods.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("No foods match.")
                            .foregroundStyle(Color.formTextSecondary)
                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add \u{201C}\(searchText.trimmingCharacters(in: .whitespaces))\u{201D}") {
                                editorMode = EditorSheet(mode: .create(prefillName: searchText.trimmingCharacters(in: .whitespaces)))
                            }
                        }
                    }
                } else {
                    ForEach(visibleFoods) { food in
                        Button {
                            editorMode = EditorSheet(mode: .edit(food))
                        } label: {
                            FoodRow(food: food)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = food
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editorMode = EditorSheet(mode: .duplicate(food))
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(Color.formFat)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleFavourite(food)
                            } label: {
                                Label(food.isFavourite ? "Unfavourite" : "Favourite",
                                      systemImage: food.isFavourite ? "star.slash" : "star")
                            }
                            .tint(Color.formCarbs)
                        }
                        .contextMenu {
                            Button { editorMode = EditorSheet(mode: .edit(food)) } label: { Label("Edit", systemImage: "pencil") }
                            Button { editorMode = EditorSheet(mode: .duplicate(food)) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { toggleFavourite(food) } label: {
                                Label(food.isFavourite ? "Remove from favourites" : "Add to favourites", systemImage: "star")
                            }
                            Button(role: .destructive) { pendingDeletion = food } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            } header: {
                Text("Foods")
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.formDestructive)
                } else if !foods.isEmpty {
                    Text("Swipe left to duplicate or delete, right to favourite.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Foods")
        .searchable(text: $searchText, prompt: "Search your foods")
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = EditorSheet(mode: .create(prefillName: ""))
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                }
                .accessibilityLabel("Add food")
            }
        }
        .sheet(item: $editorMode) { sheet in
            NavigationStack {
                FoodEditorView(mode: sheet.mode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editorMode = nil }
                        }
                    }
            }
        }
        .confirmationDialog("Delete this food?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { food in
            Button("Delete \(food.name)", role: .destructive) { delete(food) }
        } message: { _ in
            Text("Diary entries and saved meals that use it keep their recorded values.")
        }
    }

    private func toggleFavourite(_ food: Food) {
        do {
            try NutritionRepository(context: modelContext).toggleFavourite(food)
            HapticsManager.shared.selectionChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ food: Food) {
        do {
            try NutritionRepository(context: modelContext).delete(food)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
        pendingDeletion = nil
    }
}
