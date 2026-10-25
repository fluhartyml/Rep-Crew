//
//  BodyStats.swift
//  Rep Crew
//
//  Your body stats, private. His word, 2026-10-25: "ask the crew member to track body statistics in
//  their profile privately by default and not shown to other crew members" — and on the plan (weight,
//  height, body fat, resting heart rate, read from Health, kept on the phone with a history): "yes
//  build the body stats".
//
//  REM: read from Health every time, never copied into SwiftData or iCloud, so nothing here can reach the
//  crew. Health stays the record. Asked for only when you tap the button here, in its own prompt, so
//  Start Set never asks for body stats.
//  REM: his word, 2026-10-25: "i want to be able to track my weight in the crew app" → "yes add log
//  weight". Log Weight saves to Health (the one body stat Rep Crew writes), so it stays private and
//  shows in the chart with readings from a scale or the Health app.
//

import Charts
import HealthKit
import SwiftUI

extension CrewSettings {
    /// True once you've tapped "Read Body Stats from Health" (Health never says whether read access was given).
    static let bodyStatsAsked = "bodyStatsAsked"
}

enum BodyStat: String, CaseIterable, Identifiable {
    case weight, height, bodyFat, restingHeartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Weight"
        case .height: "Height"
        case .bodyFat: "Body Fat"
        case .restingHeartRate: "Resting Heart Rate"
        }
    }

    var symbol: String {
        switch self {
        case .weight: "scalemass.fill"
        case .height: "ruler.fill"
        case .bodyFat: "percent"
        case .restingHeartRate: "heart.fill"
        }
    }

    var type: HKQuantityType {
        switch self {
        case .weight: HKQuantityType(.bodyMass)
        case .height: HKQuantityType(.height)
        case .bodyFat: HKQuantityType(.bodyFatPercentage)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        }
    }

    /// The unit values are read in; display converts to your region's units.
    var healthUnit: HKUnit {
        switch self {
        case .weight: .gramUnit(with: .kilo)
        case .height: .meter()
        case .bodyFat: .percent()
        case .restingHeartRate: .count().unitDivided(by: .minute())
        }
    }

    static var readTypes: Set<HKObjectType> { Set(allCases.map(\.type)) }

    private static var usesUSUnits: Bool { Locale.current.measurementSystem == .us }

    /// "182 lb", "5′ 10″", "18.5%", "58 bpm".
    func text(_ value: Double) -> String {
        switch self {
        case .weight:
            Measurement(value: value, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        case .height:
            Measurement(value: value, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .personHeight))
        case .bodyFat:
            value.formatted(.percent.precision(.fractionLength(0...1)))
        case .restingHeartRate:
            "\(Int(value.rounded())) bpm"
        }
    }

    /// The number the chart plots, in your region's unit, so the axis matches the text.
    func chartValue(_ value: Double) -> Double {
        switch self {
        case .weight: Self.usesUSUnits ? Measurement(value: value, unit: UnitMass.kilograms).converted(to: .pounds).value : value
        case .height: Self.usesUSUnits ? Measurement(value: value, unit: UnitLength.meters).converted(to: .inches).value : value * 100
        case .bodyFat: value * 100
        case .restingHeartRate: value
        }
    }

    var chartUnit: String {
        switch self {
        case .weight: Self.usesUSUnits ? "lb" : "kg"
        case .height: Self.usesUSUnits ? "in" : "cm"
        case .bodyFat: "%"
        case .restingHeartRate: "bpm"
        }
    }
}

struct BodyReading: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

enum BodyStatsReader {
    /// Shows Health's prompt for the four body stats. Health asks only about ones not answered before.
    static func ask() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await HealthSets.store.requestAuthorization(toShare: [], read: BodyStat.readTypes)
    }

    /// Saves a weight you typed, in your region's unit (lb or kg). Health asks first, the first time.
    static func logWeight(_ value: Double, at date: Date) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), value > 0 else { return false }
        let type = BodyStat.weight.type
        do {
            try await HealthSets.store.requestAuthorization(toShare: [type], read: BodyStat.readTypes)
            guard HealthSets.store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
            let unit: HKUnit = BodyStat.weight.chartUnit == "lb" ? .pound() : .gramUnit(with: .kilo)
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date)
            try await HealthSets.store.save(sample)
            return true
        } catch {
            return false
        }
    }

    /// Newest first, up to `limit` readings (nil = every reading). Empty when Health has none or access wasn't given.
    static func history(_ stat: BodyStat, limit: Int? = 366) async -> [BodyReading] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: stat.type)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                                                 limit: limit)
        guard let samples = try? await descriptor.result(for: HealthSets.store) else { return [] }
        return samples.map { BodyReading(id: $0.uuid, date: $0.endDate, value: $0.quantity.doubleValue(for: stat.healthUnit)) }
    }
}

/// The row in Settings, under your profile.
struct BodyStatsSection: View {
    var body: some View {
        Section {
            NavigationLink { BodyStatsView() } label: {
                Label("Body Stats", systemImage: "figure").font(AppFont.bodyBold)
            }
        } footer: {
            Text("Weight, height, body fat and resting heart rate from Health, with their history. Private: only you see them, on this iPhone.")
                .font(AppFont.body)
        }
    }
}

struct BodyStatsView: View {
    @AppStorage(CrewSettings.bodyStatsAsked) private var asked = false
    @State private var readings: [BodyStat: [BodyReading]] = [:]
    @State private var loaded = false
    @State private var loggingWeight = false

    var body: some View {
        List {
            Section {
                Button { loggingWeight = true } label: {
                    Label("Log Weight", systemImage: "scalemass.fill").font(AppFont.bodyBold)
                }
            } footer: {
                Text("Saved to Health, so only you see it.").font(AppFont.body)
            }
            if !asked {
                Section {
                    Button {
                        Task {
                            await BodyStatsReader.ask()
                            asked = true
                            await load()
                        }
                    } label: {
                        Label("Read Body Stats from Health", systemImage: "heart.text.square.fill").font(AppFont.bodyBold)
                    }
                } footer: {
                    Text("Health asks which stats Rep Crew may read. Nothing is saved to iCloud or shown to your crew.")
                        .font(AppFont.body)
                }
            } else {
                Section {
                    ForEach(BodyStat.allCases) { stat in
                        NavigationLink {
                            if stat == .weight {
                                WeightTrendView()
                            } else {
                                BodyStatHistoryView(stat: stat, readings: readings[stat] ?? [])
                            }
                        } label: {
                            BodyStatRow(stat: stat, latest: readings[stat]?.first, loaded: loaded)
                        }
                    }
                } footer: {
                    Text("Only you see these, on this iPhone. To add another reading or change what Rep Crew may read, use the Health app.")
                        .font(AppFont.body)
                }
            }
        }
        .navigationTitle("Body Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { if asked { await load() } }
        .refreshable { await load() }
        .sheet(isPresented: $loggingWeight, onDismiss: { Task { if asked { await load() } } }) { LogWeightView() }
    }

    private func load() async {
        for stat in BodyStat.allCases {
            readings[stat] = await BodyStatsReader.history(stat)
        }
        loaded = true
    }
}

private struct BodyStatRow: View {
    let stat: BodyStat
    let latest: BodyReading?
    let loaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(stat.title, systemImage: stat.symbol).font(AppFont.bodyBold)
                Spacer()
                if let latest { Text(stat.text(latest.value)).font(AppFont.bodyBold).monospacedDigit() }
            }
            Text(detail).font(AppFont.body).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        guard loaded else { return "Reading Health…" }
        guard let latest else { return "No readings in Health" }
        return "Latest " + latest.date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// One stat over time: a line chart, then every reading as a list.
struct BodyStatHistoryView: View {
    let stat: BodyStat
    let readings: [BodyReading]

    var body: some View {
        List {
            if readings.count > 1 {
                Section {
                    Chart(readings) { reading in
                        LineMark(x: .value("Date", reading.date), y: .value(stat.chartUnit, stat.chartValue(reading.value)))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Date", reading.date), y: .value(stat.chartUnit, stat.chartValue(reading.value)))
                            .symbolSize(64)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(AppFont.body)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel().font(AppFont.body)
                        }
                    }
                    .chartYAxisLabel(stat.chartUnit)
                    .frame(height: 240)
                    .padding(.vertical, 8)
                    .accessibilityLabel("\(stat.title) over time")
                }
            }
            Section {
                if readings.isEmpty {
                    Text("No readings in Health.").font(AppFont.body)
                }
                ForEach(readings) { reading in
                    HStack {
                        Text(reading.date.formatted(date: .abbreviated, time: .omitted)).font(AppFont.body)
                        Spacer()
                        Text(stat.text(reading.value)).font(AppFont.bodyBold).monospacedDigit()
                    }
                }
            } header: {
                Text("Readings").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle(stat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The D / W / M / Y / All picker above the weight chart.
enum WeightRange: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M", year = "Y", all = "All"

    var id: String { rawValue }

    /// Where the range starts, counting back from now. nil = from the first reading.
    func start(from now: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .day: return calendar.date(byAdding: .day, value: -1, to: now)
        case .week: return calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated)
        // Years only: "Jan 18" read as a day, and four of them ran together on his 11 (build 130).
        case .all: .dateTime.year()
        }
    }

    var spokenName: String {
        switch self {
        case .day: "the last day"
        case .week: "the last week"
        case .month: "the last month"
        case .year: "the last year"
        case .all: "all time"
        }
    }
}

/// Weight over time against where you started.
//  REM: his word, 2026-10-25: "can it show a D W M Y all time line graph to show weight trend with a line
//  denoting start weight maybe a pink shade for the weights that log above starting weight and blue shade
//  below starting weight?" → "yes build it and i want to enter current wight and have it track in the
//  health app".
//  REM: start weight = your FIRST reading in Health, and it stays put whichever range is picked (his yes to
//  that plan). So every reading is read here (no 366 cap), or a long history would move the start.
//  REM: the shade is drawn between the line and the start line. Where the line crosses the start between two
//  readings, a point is added at the exact crossing, so pink stops and blue begins right there instead of
//  one color bleeding past the line.
struct WeightTrendView: View {
    private let stat = BodyStat.weight
    /// In the Log Weight sheet: only the picker and chart, as one Form section (no page, no list of readings).
    /// REM: his word, 2026-10-25, on the Log Weight sheet: "it should show the stats at the bottom of the sheet".
    var inSheet = false

    @AppStorage("weightTrendRange") private var range: WeightRange = .month
    @State private var readings: [BodyReading] = []   // newest first
    @State private var loaded = false
    @State private var loggingWeight = false

    private struct ShadePoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    /// Oldest reading in Health, in your unit (lb or kg).
    private var startValue: Double? { readings.last.map { stat.chartValue($0.value) } }

    /// Readings in the picked range, oldest first, in your unit.
    private var visible: [(date: Date, value: Double)] {
        let from = range.start(from: .now)
        return readings.reversed()
            .filter { from == nil || $0.date >= from! }
            .map { ($0.date, stat.chartValue($0.value)) }
    }

    /// Where the line enters the range: your weight at the range's first moment, worked out between the last reading
    /// before it and the first inside it (or the last one before it, held flat). nil for All, or with nothing earlier.
    /// REM: his Y view, 2026-10-25: one reading this year showed as a lone dot with no line or shade (build 131).
    private var entry: (date: Date, value: Double)? {
        guard let from = range.start(from: .now),
              let before = readings.first(where: { $0.date < from }) else { return nil }   // newest first
        let earlier = (before.date, stat.chartValue(before.value))
        guard let first = visible.first else { return (from, earlier.1) }
        let span = first.date.timeIntervalSince(earlier.0)
        let fraction = span > 0 ? from.timeIntervalSince(earlier.0) / span : 0
        return (from, earlier.1 + (first.value - earlier.1) * fraction)
    }

    /// The line's points: the entry point, then the readings in the range.
    private var linePoints: [(date: Date, value: Double)] { (entry.map { [$0] } ?? []) + visible }

    /// The line's points plus a point wherever the line crosses the start line.
    private func shadePoints(start: Double) -> [ShadePoint] {
        var points: [ShadePoint] = []
        let readings = linePoints
        for (index, reading) in readings.enumerated() {
            if index > 0 {
                let previous = readings[index - 1]
                let before = previous.value - start, after = reading.value - start
                if before * after < 0 {
                    let fraction = before / (before - after)
                    let seconds = reading.date.timeIntervalSince(previous.date) * fraction
                    points.append(ShadePoint(date: previous.date.addingTimeInterval(seconds), value: start))
                }
            }
            points.append(ShadePoint(date: reading.date, value: reading.value))
        }
        return points
    }

    private func yDomain(start: Double) -> ClosedRange<Double> {
        let values = linePoints.map(\.value) + [start]
        let low = values.min() ?? start, high = values.max() ?? start
        let pad = max((high - low) * 0.1, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        if inSheet {
            chartSection.task { await load() }
        } else {
            page
        }
    }

    private var chartSection: some View {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(WeightRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Time range")

                if let start = startValue {
                    chart(start: start)
                } else {
                    Text(loaded ? "No weight readings in Health yet. Tap Log Weight to add one." : "Reading Health…")
                        .font(AppFont.body)
                }
            } footer: {
                if let first = readings.last {
                    Text("Dashed line: your starting weight, \(stat.text(first.value)) on \(first.date.formatted(date: .abbreviated, time: .omitted)). Pink is above it, blue is below it.")
                        .font(AppFont.body)
                }
            }
    }

    private var page: some View {
        List {
            chartSection

            Section {
                Button { loggingWeight = true } label: {
                    Label("Log Weight", systemImage: "scalemass.fill").font(AppFont.bodyBold)
                }
            } footer: {
                Text("Saved to Health, so only you see it.").font(AppFont.body)
            }

            Section {
                ForEach(readings) { reading in
                    HStack {
                        Text(reading.date.formatted(date: .abbreviated, time: .omitted)).font(AppFont.body)
                        Spacer()
                        Text(stat.text(reading.value)).font(AppFont.bodyBold).monospacedDigit()
                    }
                }
            } header: {
                Text("Readings").font(AppFont.bodyBold).textCase(nil)
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $loggingWeight, onDismiss: { Task { await load() } }) { LogWeightView() }
    }

    @ViewBuilder
    private func chart(start: Double) -> some View {
        let points = visible
        if points.isEmpty {
            Text("No weight readings in \(range.spokenName).").font(AppFont.body)
        } else {
            Chart {
                ForEach(shadePoints(start: start)) { point in
                    AreaMark(x: .value("Date", point.date),
                             yStart: .value(stat.chartUnit, start),
                             yEnd: .value(stat.chartUnit, max(point.value, start)))
                        .foregroundStyle(by: .value("Side", "Above"))
                    AreaMark(x: .value("Date", point.date),
                             yStart: .value(stat.chartUnit, start),
                             yEnd: .value(stat.chartUnit, min(point.value, start)))
                        .foregroundStyle(by: .value("Side", "Below"))
                }
                RuleMark(y: .value("Start", start))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.secondary)
                ForEach(Array(linePoints.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value(stat.chartUnit, point.value))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.primary)
                }
                // Dots only for real readings, not the entry point.
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    PointMark(x: .value("Date", point.date), y: .value(stat.chartUnit, point.value))
                        .symbolSize(64)
                        .foregroundStyle(Color.primary)
                }
            }
            .chartForegroundStyleScale(["Above": Color.pink.opacity(0.4), "Below": Color.blue.opacity(0.4)])
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain(start: start))
            .chartXScale(domain: (range.start(from: .now) ?? linePoints[0].date)...Date.now)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: range.axisFormat).font(AppFont.body)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().font(AppFont.body)
                }
            }
            .chartYAxisLabel(stat.chartUnit)
            .frame(height: 260)
            .padding(.vertical, 8)
            .accessibilityLabel("Weight over \(range.spokenName), against your starting weight")
        }
    }

    private func load() async {
        readings = await BodyStatsReader.history(stat, limit: nil)
        loaded = true
    }
}

/// Type a weight, pick when, Save. It goes to Health; nothing goes to iCloud or the crew.
struct LogWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double?
    @State private var date = Date.now
    @State private var saving = false
    @State private var failed = false
    @FocusState private var focused: Bool

    private var unit: String { BodyStat.weight.chartUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", value: $weight, format: .number.precision(.fractionLength(0...1)))
                            .font(AppFont.title)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                        Text(unit).font(AppFont.heading).foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date.now).font(AppFont.body)
                } footer: {
                    Text("Saved to Health, with your other weight readings. Only you see it.").font(AppFont.body)
                }
                if failed {
                    Text("It wasn't saved. Allow Rep Crew to save Weight in the Health app: Sharing → Apps → Rep Crew.")
                        .font(AppFont.body)
                }
                WeightTrendView(inSheet: true)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.font(AppFont.bodyBold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.bodyBold)
                        .disabled(saving || (weight ?? 0) <= 0)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() async {
        guard let weight else { return }
        saving = true
        failed = false
        if await BodyStatsReader.logWeight(weight, at: date) {
            UserDefaults.standard.set(true, forKey: CrewSettings.bodyStatsAsked)
            dismiss()
        } else {
            failed = true
        }
        saving = false
    }
}
