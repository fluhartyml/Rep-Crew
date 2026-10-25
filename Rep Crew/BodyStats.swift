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

    /// Newest first, up to a year of daily readings. Empty when Health has none or access wasn't given.
    static func history(_ stat: BodyStat) async -> [BodyReading] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: stat.type)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                                                 limit: 366)
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
                        NavigationLink { BodyStatHistoryView(stat: stat, readings: readings[stat] ?? []) } label: {
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

/// Type a weight, pick when, Save. It goes to Health; nothing goes to iCloud or the crew.
private struct LogWeightView: View {
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
