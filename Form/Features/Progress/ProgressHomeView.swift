import SwiftUI
import SwiftData
import FormCore

/// Progress tab root.
///
/// Phase 1 scope: record, correct and delete body measurements. Charts for
/// workouts, volume, records and nutrition arrive in Phase 4.
struct ProgressHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    @State private var kindFilter: MeasurementKind = .bodyWeight
    @State private var newEntryKind: MeasurementKind?
    @State private var editing: BodyMeasurement?
    @State private var pendingDeletion: BodyMeasurement?
    @State private var errorMessage: String?

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }
    private var lengthUnit: LengthUnit { preferences.first?.lengthUnit ?? .centimeters }

    private var filtered: [BodyMeasurement] {
        measurements.filter { $0.kind == kindFilter }
    }

    var body: some View {
        List {
            Section {
                Picker("Measurement", selection: $kindFilter) {
                    ForEach(MeasurementKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: kindFilter) { _, _ in HapticsManager.shared.selectionChanged() }
            }

            Section {
                if filtered.isEmpty {
                    EmptyStateView(symbol: kindFilter.symbol,
                                   title: "No \(kindFilter.displayName.lowercased()) entries",
                                   message: "Record a measurement to start your history. Form only shows values you entered.",
                                   actionTitle: "Add entry") {
                        newEntryKind = kindFilter
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { measurement in
                        Button {
                            editing = measurement
                        } label: {
                            MeasurementRow(measurement: measurement,
                                           text: measurement.displayValue(weightUnit: weightUnit, lengthUnit: lengthUnit))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = measurement
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                editing = measurement
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingDeletion = measurement
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("History")
            } footer: {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            Section {
                InlineNotice(symbol: "chart.xyaxis.line", text: "Charts for workouts, volume, personal records and nutrition arrive in a later build (Phase 4).")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Progress")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newEntryKind = kindFilter
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                }
                .accessibilityLabel("Add \(kindFilter.displayName.lowercased()) entry")
            }
        }
        .sheet(item: $newEntryKind) { kind in
            MeasurementEntrySheet(kind: kind)
        }
        .sheet(item: $editing) { measurement in
            MeasurementEntrySheet(editing: measurement, displayText: editableText(for: measurement))
        }
        .confirmationDialog("Delete this entry?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { measurement in
            Button("Delete", role: .destructive) { delete(measurement) }
            Button("Cancel", role: .cancel) {}
        } message: { measurement in
            Text("\(measurement.displayValue(weightUnit: weightUnit, lengthUnit: lengthUnit)) on \(measurement.date.formatted(date: .abbreviated, time: .omitted)) will be removed. This can't be undone.")
        }
    }

    private func editableText(for measurement: BodyMeasurement) -> String {
        let value: Double
        switch measurement.kind.dimension {
        case .mass: value = weightUnit.fromKilograms(measurement.value)
        case .length: value = lengthUnit.fromCentimeters(measurement.value)
        case .percentage: value = measurement.value
        }
        return NumberText.editable(value, maxFractionDigits: 1)
    }

    private func delete(_ measurement: BodyMeasurement) {
        modelContext.delete(measurement)
        if let error = modelContext.saveReportingErrors() {
            modelContext.rollback()
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
            HapticsManager.shared.error()
        } else {
            errorMessage = nil
        }
        pendingDeletion = nil
    }
}

private struct MeasurementRow: View {
    let measurement: BodyMeasurement
    let text: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Color.formTextPrimary)
                if !measurement.notes.isEmpty {
                    Text(measurement.notes)
                        .formCaption()
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(text)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.formTextPrimary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the entry for editing")
    }
}
