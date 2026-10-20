import SwiftUI
import SwiftData
import FormCore

/// Records a new body measurement, or edits an existing one.
/// Values are entered in the user's unit and stored canonically.
struct MeasurementEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    private let existing: BodyMeasurement?
    @State private var kind: MeasurementKind
    @State private var valueText: String
    @State private var date: Date
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var valueFocused: Bool

    /// New entry.
    init(kind: MeasurementKind) {
        existing = nil
        _kind = State(initialValue: kind)
        _valueText = State(initialValue: "")
        _date = State(initialValue: .now)
        _notes = State(initialValue: "")
    }

    /// Edit an existing entry. `displayText` is the value already converted to the user's unit.
    init(editing measurement: BodyMeasurement, displayText: String) {
        existing = measurement
        _kind = State(initialValue: measurement.kind)
        _valueText = State(initialValue: displayText)
        _date = State(initialValue: measurement.date)
        _notes = State(initialValue: measurement.notes)
    }

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }
    private var lengthUnit: LengthUnit { preferences.first?.lengthUnit ?? .centimeters }

    private var unitSymbol: String {
        switch kind.dimension {
        case .mass: return weightUnit.symbol
        case .length: return lengthUnit.symbol
        case .percentage: return "%"
        }
    }

    /// Valid range expressed in the user's unit, for parsing and error messages.
    private var displayRange: ClosedRange<Double> {
        let range = kind.validRange
        switch kind.dimension {
        case .mass:
            return weightUnit.fromKilograms(range.lowerBound).rounded(.down)...weightUnit.fromKilograms(range.upperBound).rounded(.up)
        case .length:
            return lengthUnit.fromCentimeters(range.lowerBound).rounded(.down)...lengthUnit.fromCentimeters(range.upperBound).rounded(.up)
        case .percentage:
            return range
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if existing == nil {
                    Section {
                        Picker("Measurement", selection: $kind) {
                            ForEach(MeasurementKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .focused($valueFocused)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .accessibilityLabel("\(kind.displayName) in \(unitSymbol)")
                        Text(unitSymbol)
                            .foregroundStyle(Color.formTextSecondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.formDestructive)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Log \(kind.displayName.lowercased())" : "Edit \(kind.displayName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaving || valueText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { valueFocused = false }
                }
            }
            .onAppear { valueFocused = existing == nil }
            .onChange(of: kind) { _, _ in errorMessage = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let parsed = InputValidator.requiredDecimal(valueText, in: displayRange)
        let entered: Double
        switch parsed {
        case .success(let value):
            entered = value
        case .failure(let error):
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
            return
        }
        if case .failure(let error) = InputValidator.pastOrPresent(date) {
            errorMessage = error.localizedDescription
            return
        }

        let canonical: Double
        switch kind.dimension {
        case .mass: canonical = weightUnit.toKilograms(entered)
        case .length: canonical = lengthUnit.toCentimeters(entered)
        case .percentage: canonical = entered
        }

        if let existing {
            existing.value = canonical
            existing.date = date
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let measurement = BodyMeasurement(kind: kind, value: canonical, date: date,
                                              notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
            modelContext.insert(measurement)
        }

        if let error = modelContext.saveReportingErrors() {
            modelContext.rollback()
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            HapticsManager.shared.error()
            return
        }
        HapticsManager.shared.saveSucceeded()
        dismiss()
    }
}
