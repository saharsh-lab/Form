import SwiftUI
import Charts
import Accessibility
import FormCore

/// Bubble showing the exact recorded value and date of a selected chart point.
struct ChartValueBubble: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Color.formTextSecondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Color.formTextPrimary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.formSurfaceSecondary))
    }
}

/// Recorded values over time. Points are drawn only where a value was recorded;
/// the optional line simply joins recorded points and is labelled as such.
/// Tapping or dragging reveals the nearest recorded value and its date.
struct PointSeriesChart: View {
    let points: [SeriesPoint]
    var tint: Color = .formAccent
    var connectPoints = true
    var height: CGFloat = 200
    let format: (Double) -> String

    @State private var selectedDate: Date?

    private var selected: SeriesPoint? {
        selectedDate.flatMap { ProgressAnalytics.nearest(to: $0, in: points) }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, abs(high) * 0.02, 1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                if connectPoints && points.count > 1 {
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(tint)
                    .symbolSize(selected?.date == point.date ? 120 : 45)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.formSeparator)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartValueBubble(title: selected.date.formatted(date: .abbreviated, time: .omitted), value: format(selected.value))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .frame(height: height)
        .onChange(of: selected?.date) { old, new in
            if new != nil && new != old { HapticsManager.shared.selectionChanged() }
        }
        .accessibilityChartDescriptor(SeriesDescriptor(points: points, format: format))
    }
}

/// Bars counting events per week or month, with selection.
struct PeriodBarChart: View {
    let counts: [PeriodCount]
    let component: Calendar.Component
    var tint: Color = .formAccent
    var height: CGFloat = 180
    let label: (Int) -> String

    @State private var selectedDate: Date?

    private var selected: PeriodCount? {
        selectedDate.flatMap { ProgressAnalytics.bucket(containing: $0, in: counts, per: component) }
    }

    private var unit: Calendar.Component { component == .month ? .month : .weekOfYear }

    var body: some View {
        Chart {
            ForEach(counts) { bucket in
                BarMark(x: .value("Period", bucket.start, unit: unit), y: .value("Count", bucket.count))
                    .foregroundStyle(selected?.start == bucket.start ? tint : tint.opacity(selected == nil ? 1 : 0.45))
                    .cornerRadius(4)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.start, unit: unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartValueBubble(title: periodTitle(selected.start), value: label(selected.count))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: height)
        .accessibilityChartDescriptor(PeriodDescriptor(counts: counts, title: periodTitle, label: label))
    }

    private func periodTitle(_ date: Date) -> String {
        component == .month
            ? date.formatted(.dateTime.month(.wide).year())
            : "Week of \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

// MARK: - Audio graphs / VoiceOver chart descriptions

private struct SeriesDescriptor: AXChartDescriptorRepresentable {
    let points: [SeriesPoint]
    let format: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let values = points.map(\.value)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: (dates.min()?.timeIntervalSince1970 ?? 0)...(dates.max()?.timeIntervalSince1970 ?? 1),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Value",
            range: (values.min() ?? 0)...(values.max() ?? 1),
            gridlinePositions: []
        ) { format($0) }
        let series = AXDataSeriesDescriptor(name: "Recorded values", isContinuous: false, dataPoints: points.map {
            AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value)
        })
        return AXChartDescriptor(title: "Recorded values", summary: "\(points.count) recorded values",
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

private struct PeriodDescriptor: AXChartDescriptorRepresentable {
    let counts: [PeriodCount]
    let title: (Date) -> String
    let label: (Int) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Period", categoryOrder: counts.map { title($0.start) })
        let maxCount = Double(counts.map(\.count).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(title: "Count", range: 0...max(1, maxCount), gridlinePositions: []) { label(Int($0)) }
        let series = AXDataSeriesDescriptor(name: "Count", isContinuous: false, dataPoints: counts.map {
            AXDataPoint(x: title($0.start), y: Double($0.count))
        })
        return AXChartDescriptor(title: "Counts by period", summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
