import SwiftUI

/// A true week grid: days across, hours down, blocks sized by duration and
/// side-by-side when they overlap.
struct WeekGridView: View {
    let weekStart: Date
    var onSelect: (CourseEvent) -> Void

    @Environment(ScheduleStore.self) private var schedule

    private let hourHeight: CGFloat = 58
    private let railWidth: CGFloat = 42

    var body: some View {
        let events = schedule.events(from: weekStart, to: weekStart.adding(days: 7))
            .filter { !(schedule.visibleEvents(on: $0.start).isEmpty) }
        let days = visibleDays(for: events)
        let bounds = hourBounds(for: events)

        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                headerRow(days: days)
                    .padding(.leading, railWidth)

                HStack(alignment: .top, spacing: 0) {
                    hourRail(bounds: bounds)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        ZStack(alignment: .topLeading) {
                            gridLines(bounds: bounds, columns: days.count)
                            HStack(alignment: .top, spacing: 4) {
                                ForEach(days, id: \.self) { day in
                                    dayColumn(day: day, bounds: bounds, now: context.date)
                                }
                            }
                            if let offset = nowOffset(bounds: bounds, days: days, now: context.date) {
                                nowLine.offset(y: offset)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 100)
            .frame(minWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .overlay {
            if events.isEmpty, !schedule.isLoading {
                EmptyStateView(symbol: "calendar.badge.exclamationmark", title: "Semaine vide", message: "Aucun cours sur cette semaine.")
            }
        }
    }

    // MARK: Pieces

    private func headerRow(days: [Date]) -> some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(DateText.weekdayShort.string(from: day).prefix(3).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Text(DateText.dayNumber.string(from: day))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(day.isToday ? Theme.live : Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.live.opacity(0.12))
                    }
                }
            }
        }
    }

    private func hourRail(bounds: ClosedRange<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(bounds), id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -5)
            }
        }
        .frame(width: railWidth, alignment: .leading)
    }

    private func gridLines(bounds: ClosedRange<Int>, columns: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(bounds), id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private func dayColumn(day: Date, bounds: ClosedRange<Int>, now: Date) -> some View {
        let dayEvents = schedule.visibleEvents(on: day)
        let lanes = Self.assignLanes(dayEvents)
        let laneCount = max(1, (lanes.values.max() ?? 0) + 1)

        return GeometryReader { proxy in
            ForEach(dayEvents) { event in
                let lane = lanes[event.id] ?? 0
                let width = (proxy.size.width - CGFloat(laneCount - 1) * 3) / CGFloat(laneCount)
                Button { onSelect(event) } label: {
                    WeekBlock(event: event, now: now)
                }
                .buttonStyle(.plain)
                .frame(width: max(24, width), height: max(22, height(for: event)), alignment: .topLeading)
                .offset(x: CGFloat(lane) * (width + 3), y: offset(for: event.start, bounds: bounds))
            }
        }
        .frame(height: CGFloat(bounds.count) * hourHeight)
        .frame(maxWidth: .infinity)
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.live).frame(width: 7, height: 7)
            Rectangle().fill(Theme.live.opacity(0.75)).frame(height: 1.5)
        }
    }

    // MARK: Geometry

    private func offset(for date: Date, bounds: ClosedRange<Int>) -> CGFloat {
        CGFloat(date.minutesIntoDay / 60 - Double(bounds.lowerBound)) * hourHeight
    }

    private func height(for event: CourseEvent) -> CGFloat {
        CGFloat(event.duration / 3600) * hourHeight - 3
    }

    private func nowOffset(bounds: ClosedRange<Int>, days: [Date], now: Date) -> CGFloat? {
        guard days.contains(where: { $0.isSameDay(as: now) }) else { return nil }
        let value = offset(for: now, bounds: bounds)
        guard value >= 0, value <= CGFloat(bounds.count) * hourHeight else { return nil }
        return value
    }

    /// Weekdays always; weekend days only when something is scheduled.
    private func visibleDays(for events: [CourseEvent]) -> [Date] {
        (0 ..< 7).map { weekStart.adding(days: $0) }.filter { day in
            let weekday = Calendar.epitime.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            return !isWeekend || events.contains { $0.start.isSameDay(as: day) }
        }
    }

    /// Clamp the grid to the hours actually used, with a sensible default.
    private func hourBounds(for events: [CourseEvent]) -> ClosedRange<Int> {
        guard !events.isEmpty else { return 8 ... 19 }
        let first = events.map { Int($0.start.minutesIntoDay / 60) }.min() ?? 8
        let last = events.map { Int(ceil($0.end.minutesIntoDay / 60)) }.max() ?? 19
        return max(0, min(first, 8)) ... min(23, max(last, 18))
    }

    /// Greedy lane packing so overlapping courses sit side by side instead of stacking.
    static func assignLanes(_ events: [CourseEvent]) -> [String: Int] {
        var lanes: [String: Int] = [:]
        var laneEnds: [Date] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            if let index = laneEnds.firstIndex(where: { $0 <= event.start }) {
                laneEnds[index] = event.end
                lanes[event.id] = index
            } else {
                laneEnds.append(event.end)
                lanes[event.id] = laneEnds.count - 1
            }
        }
        return lanes
    }
}

private struct WeekBlock: View {
    let event: CourseEvent
    let now: Date

    var body: some View {
        let color = CourseColor.color(for: event)
        VStack(alignment: .leading, spacing: 2) {
            Text(DateText.time.string(from: event.start))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(event.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            if let room = event.rooms.first?.name {
                Text(room)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.17))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: 3).padding(.vertical, 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(event.isLive(at: now) ? Theme.live : color.opacity(0.35), lineWidth: event.isLive(at: now) ? 1.5 : 0.8)
                }
        }
        .opacity(event.isCancelled ? 0.4 : (event.end <= now ? 0.55 : 1))
    }
}
