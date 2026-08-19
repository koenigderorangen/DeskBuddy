import Charts
import SwiftUI

private enum StatisticsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    var id: Self { self }
}

private enum StatisticsResetTarget: Identifiable {
    case selected(UUID, String)
    case all

    var id: String {
        switch self {
        case .selected(let id, _): "selected-\(id)"
        case .all: "all"
        }
    }
}

private struct StatisticsBucket: Identifiable {
    let start: Date
    let durations: [StatisticsPosture: TimeInterval]

    var id: Date { start }
    var total: TimeInterval { durations.values.reduce(0, +) }
}

private struct StatisticsSummary {
    let durations: [StatisticsPosture: TimeInterval]
    let transitions: Int
    let activeDays: Int

    var total: TimeInterval { durations.values.reduce(0, +) }
}

struct StatisticsView: View {
    @ObservedObject private var statistics = PostureStatisticsStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedRange = StatisticsRange.week
    @State private var periodOffset = 0
    @State private var selectedDeskID: UUID?
    @State private var resetTarget: StatisticsResetTarget?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                rangeControls
                summaryGrid
                chart
                dataControls
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(.background.opacity(0.55))
        .confirmationDialog(
            resetTitle,
            isPresented: Binding(
                get: { resetTarget != nil },
                set: { if !$0 { resetTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset Statistics", role: .destructive) {
                performReset()
            }
            Button("Cancel", role: .cancel) {
                resetTarget = nil
            }
        } message: {
            Text("This permanently deletes the selected local posture history.")
        }
        .onChange(of: selectedRange) { _, _ in periodOffset = 0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics")
                    .font(.title2.weight(.semibold))
                Text("Connected time at your Sit, Stand, and other desk heights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Desk", selection: $selectedDeskID) {
                Text("All Desks").tag(UUID?.none)
                ForEach(availableDesks, id: \.id) { desk in
                    Text(desk.name).tag(Optional(desk.id))
                }
            }
            .frame(width: 190)
        }
    }

    private var rangeControls: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: $selectedRange) {
                ForEach(StatisticsRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)

            Spacer()

            Button {
                periodOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous period")
            .disabled(selectedRange == .all)

            Text(periodTitle)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 170)
                .multilineTextAlignment(.center)

            Button {
                periodOffset = min(periodOffset + 1, 0)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next period")
            .disabled(selectedRange == .all || periodOffset == 0)
        }
    }

    private var summaryGrid: some View {
        let summary = currentSummary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            summaryTile("Sitting · \(percentageText(summary.durations[.sitting, default: 0], total: summary.total))", value: durationText(summary.durations[.sitting, default: 0]), symbol: "chair", color: .blue)
            summaryTile("Standing · \(percentageText(summary.durations[.standing, default: 0], total: summary.total))", value: durationText(summary.durations[.standing, default: 0]), symbol: "figure.stand", color: .green)
            summaryTile("Other · \(percentageText(summary.durations[.other, default: 0], total: summary.total))", value: durationText(summary.durations[.other, default: 0]), symbol: "ellipsis", color: .secondary)
            summaryTile("Connected", value: durationText(summary.total), symbol: "clock", color: .primary)
            summaryTile("Transitions", value: "\(summary.transitions)", symbol: "arrow.up.arrow.down", color: .primary)
            summaryTile("Active Days", value: "\(summary.activeDays)", symbol: "calendar", color: .primary)
        }
    }

    private func summaryTile(_ title: String, value: String, symbol: String, color: Color) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
    }

    private var chart: some View {
        let buckets = currentBuckets
        let maximumHours = max(buckets.map { $0.total / 3_600 }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Posture Distribution")
                    .font(.headline)
                Spacer()
                distributionLegend
            }

            Chart {
                ForEach(buckets) { bucket in
                    ForEach(StatisticsPosture.allCases) { posture in
                        BarMark(
                            x: .value("Period", bucket.start, unit: bucketCalendarUnit),
                            y: .value("Hours", bucket.durations[posture, default: 0] / 3_600)
                        )
                        .foregroundStyle(postureColor(posture))
                    }
                }
            }
            .chartYScale(domain: 0...maximumHours)
            .chartYAxisLabel("Hours")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: desiredAxisMarks))
            }
            .chartLegend(.hidden)
            .frame(height: 250)
        }
        .padding(18)
        .glassEffect(
            .regular.tint(DeskBuddyDesign.trayGlassTint),
            in: RoundedRectangle(cornerRadius: DeskBuddyDesign.cornerRadius)
        )
    }

    private var distributionLegend: some View {
        HStack(spacing: 12) {
            ForEach(StatisticsPosture.allCases) { posture in
                HStack(spacing: 5) {
                    Circle()
                        .fill(postureColor(posture))
                        .frame(width: 8, height: 8)
                    Text(posture.title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var dataControls: some View {
        HStack {
            Label("Stored locally on this Mac", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                if let selectedDeskID,
                   let desk = availableDesks.first(where: { $0.id == selectedDeskID }) {
                    Button("Reset \(desk.name)", systemImage: "trash", role: .destructive) {
                        resetTarget = .selected(desk.id, desk.name)
                    }
                }
                Button("Reset All Statistics", systemImage: "trash", role: .destructive) {
                    resetTarget = .all
                }
            } label: {
                Label("Reset", systemImage: "trash")
            }
        }
    }

    private var filteredSessions: [PostureStatisticsSession] {
        statistics.sessions.filter { session in
            selectedDeskID == nil || session.deskID == selectedDeskID
        }
    }

    private var sessionsInPeriod: [PostureStatisticsSession] {
        let interval = periodInterval
        return filteredSessions.filter {
            $0.endedAt > interval.start && $0.startedAt < interval.end
        }
    }

    private var currentSummary: StatisticsSummary {
        let interval = periodInterval
        var durations = Dictionary(uniqueKeysWithValues: StatisticsPosture.allCases.map { ($0, 0.0) })
        for session in sessionsInPeriod {
            durations[session.posture, default: 0] += overlap(of: session, with: interval)
        }

        let grouped = Dictionary(grouping: sessionsInPeriod, by: \.connectionID)
        let transitions = grouped.values.reduce(0) { result, sessions in
            let recognized = sessions
                .sorted(by: { $0.startedAt < $1.startedAt })
                .map(\.posture)
                .filter { $0 != .other }
            return result + zip(recognized, recognized.dropFirst()).filter { $0 != $1 }.count
        }
        let activeDays = Set(sessionsInPeriod.flatMap { sessionDays($0, within: interval) }).count
        return StatisticsSummary(durations: durations, transitions: transitions, activeDays: activeDays)
    }

    private var currentBuckets: [StatisticsBucket] {
        bucketStarts.map { start in
            let end = calendar.date(byAdding: bucketComponent, value: 1, to: start) ?? periodInterval.end
            let interval = DateInterval(start: start, end: min(end, periodInterval.end))
            var durations = Dictionary(uniqueKeysWithValues: StatisticsPosture.allCases.map { ($0, 0.0) })
            for session in sessionsInPeriod {
                durations[session.posture, default: 0] += overlap(of: session, with: interval)
            }
            return StatisticsBucket(start: start, durations: durations)
        }
    }

    private var bucketStarts: [Date] {
        let interval = periodInterval
        let component = bucketComponent
        var starts: [Date] = []
        var date = interval.start
        while date < interval.end {
            starts.append(date)
            guard let next = calendar.date(byAdding: component, value: 1, to: date), next > date else { break }
            date = next
        }
        return starts.isEmpty ? [interval.start] : starts
    }

    private var bucketComponent: Calendar.Component {
        switch selectedRange {
        case .today: .day
        case .week, .month: .day
        case .year: .month
        case .all: .year
        }
    }

    private var bucketCalendarUnit: Calendar.Component {
        bucketComponent
    }

    private var desiredAxisMarks: Int {
        switch selectedRange {
        case .today: 1
        case .week: 7
        case .month: 6
        case .year: 12
        case .all: 6
        }
    }

    private var periodInterval: DateInterval {
        let now = Date()
        switch selectedRange {
        case .today:
            let start = calendar.date(byAdding: .day, value: periodOffset, to: calendar.startOfDay(for: now))!
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let current = calendar.dateInterval(of: .weekOfYear, for: now)!
            let start = calendar.date(byAdding: .weekOfYear, value: periodOffset, to: current.start)!
            return DateInterval(start: start, end: calendar.date(byAdding: .weekOfYear, value: 1, to: start)!)
        case .month:
            let current = calendar.dateInterval(of: .month, for: now)!
            let start = calendar.date(byAdding: .month, value: periodOffset, to: current.start)!
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!)
        case .year:
            let current = calendar.dateInterval(of: .year, for: now)!
            let start = calendar.date(byAdding: .year, value: periodOffset, to: current.start)!
            return DateInterval(start: start, end: calendar.date(byAdding: .year, value: 1, to: start)!)
        case .all:
            let start = filteredSessions.map(\.startedAt).min().map(calendar.startOfDay(for:))
                ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return DateInterval(start: start, end: end)
        }
    }

    private var periodTitle: String {
        let interval = periodInterval
        return switch selectedRange {
        case .today:
            interval.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \((interval.end - 1).formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            interval.start.formatted(.dateTime.year())
        case .all:
            "All Time"
        }
    }

    private var availableDesks: [(id: UUID, name: String)] {
        var names = Dictionary(uniqueKeysWithValues: settings.savedDesks.map { ($0.id, $0.name) })
        for session in statistics.sessions where names[session.deskID] == nil {
            names[session.deskID] = session.deskName
        }
        return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var resetTitle: String {
        switch resetTarget {
        case .selected(_, let name): "Reset statistics for \(name)?"
        case .all: "Reset all statistics?"
        case nil: "Reset statistics?"
        }
    }

    private func performReset() {
        switch resetTarget {
        case .selected(let id, _): statistics.reset(deskID: id)
        case .all: statistics.reset(deskID: nil)
        case nil: break
        }
        resetTarget = nil
    }

    private func overlap(of session: PostureStatisticsSession, with interval: DateInterval) -> TimeInterval {
        max(0, min(session.endedAt, interval.end).timeIntervalSince(max(session.startedAt, interval.start)))
    }

    private func sessionDays(_ session: PostureStatisticsSession, within interval: DateInterval) -> [Date] {
        let start = calendar.startOfDay(for: max(session.startedAt, interval.start))
        let end = min(session.endedAt, interval.end)
        var days: [Date] = []
        var day = start
        while day < end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func percentageText(_ duration: TimeInterval, total: TimeInterval) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((duration / total * 100).rounded()))%"
    }

    private func postureColor(_ posture: StatisticsPosture) -> Color {
        switch posture {
        case .sitting: .blue
        case .standing: .green
        case .other: .secondary
        }
    }
}