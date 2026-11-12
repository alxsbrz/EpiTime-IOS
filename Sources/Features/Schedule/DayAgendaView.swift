import SwiftUI

/// One day, laid out as a vertical agenda with an hour rail and gap markers.
struct DayAgendaView: View {
    let day: Date
    var onSelect: (CourseEvent) -> Void

    @Environment(ScheduleStore.self) private var schedule

    var body: some View {
        let events = schedule.visibleEvents(on: day)

        ScrollView {
            if events.isEmpty {
                if schedule.isLoading {
                    VStack(spacing: 12) {
                        ForEach(0 ..< 4, id: \.self) { _ in SkeletonBlock(height: 92) }
                    }
                    .padding(Metrics.gutter)
                } else {
                    EmptyStateView(
                        symbol: "sun.max.fill",
                        title: "Journée libre",
                        message: day.isToday ? "Rien au programme aujourd'hui. Profites-en." : "Aucun cours ce jour-là."
                    )
                    .padding(.top, 40)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    LazyVStack(spacing: 10) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            if index > 0, let gap = gap(from: events[index - 1], to: event) {
                                GapMarker(text: gap)
                            }
                            Button { onSelect(event) } label: {
                                GlassCard(
                                    padding: 14,
                                    tint: event.isLive(at: context.date) ? Theme.live : nil
                                ) {
                                    CourseRow(event: event, now: context.date)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Metrics.gutter)
                    .padding(.bottom, 24)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// A free slot worth mentioning: more than half an hour between two courses.
    private func gap(from previous: CourseEvent, to next: CourseEvent) -> String? {
        let interval = next.start.timeIntervalSince(previous.end)
        guard interval >= 30 * 60 else { return nil }
        return "\(DateText.duration(interval)) de libre"
    }
}

private struct GapMarker: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}
