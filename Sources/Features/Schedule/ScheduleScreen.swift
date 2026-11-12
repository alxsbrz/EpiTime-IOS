import SwiftUI

struct ScheduleScreen: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(Preferences.self) private var preferences

    @State private var anchor: Date = .now
    @State private var selected: CourseEvent?
    @Namespace private var layoutNamespace

    private var isToday: Bool {
        preferences.scheduleLayout == .day ? anchor.isToday : anchor.startOfWeek == Date().startOfWeek
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider().opacity(0.15)

                Group {
                    if preferences.scheduleLayout == .day {
                        DayAgendaView(day: anchor, onSelect: { selected = $0 })
                    } else {
                        WeekGridView(weekStart: anchor.startOfWeek, onSelect: { selected = $0 })
                    }
                }
                .transition(.opacity)
            }
            .auroraBackdrop()
            .navigationTitle("Planning")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) {
                            preferences.scheduleLayout = preferences.scheduleLayout == .day ? .week : .day
                        }
                    } label: {
                        Image(systemName: preferences.scheduleLayout.symbol)
                    }
                    .accessibilityLabel(preferences.scheduleLayout == .day ? "Passer en vue semaine" : "Passer en vue jour")
                }
            }
            .sheet(item: $selected) { EventDetailSheet(event: $0) }
            .task(id: anchor) { await schedule.ensureLoaded(around: anchor) }
            .refreshable { await schedule.refresh(around: anchor) }
        }
    }

    // MARK: Header controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Précédent")

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Suivant")
            }

            if !isToday {
                Button("Aujourd'hui") {
                    withAnimation(Motion.snappy) { anchor = .now }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .transition(.scale.combined(with: .opacity))
            }

            if preferences.scheduleLayout == .day {
                DayStrip(anchor: $anchor, namespace: layoutNamespace)
            }

            if schedule.servedFromCache, schedule.error == nil {
                InlineBanner(kind: .offline, message: "Hors ligne — planning enregistré.")
            }
            if let error = schedule.error {
                InlineBanner(kind: .error, message: error) {
                    Task { await schedule.refresh(around: anchor) }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
        .animation(Motion.snappy, value: isToday)
        .animation(Motion.quick, value: schedule.error)
    }

    private var title: String {
        preferences.scheduleLayout == .day
            ? DateText.fullDay.string(from: anchor).capitalizedFirst
            : DateText.monthYear.string(from: anchor.startOfWeek).capitalizedFirst
    }

    private var subtitle: String {
        if preferences.scheduleLayout == .day {
            let count = schedule.visibleEvents(on: anchor).count
            return count == 0 ? "Aucun cours" : "\(count) cours"
        }
        let start = anchor.startOfWeek
        return "Semaine du \(DateText.compactDay.string(from: start)) au \(DateText.compactDay.string(from: start.adding(days: 6)))"
    }

    private func step(_ direction: Int) {
        Haptics.tap()
        withAnimation(Motion.snappy) {
            anchor = anchor.adding(days: direction * (preferences.scheduleLayout == .day ? 1 : 7))
        }
    }
}

/// Seven-day selector under the header in day mode.
private struct DayStrip: View {
    @Binding var anchor: Date
    var namespace: Namespace.ID
    @Environment(ScheduleStore.self) private var schedule

    private var weekStart: Date { anchor.startOfWeek }

    var body: some View {
        let busy = schedule.daysWithEvents(from: weekStart, days: 7)
        HStack(spacing: 6) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = weekStart.adding(days: offset)
                let isSelected = day.isSameDay(as: anchor)
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { anchor = day }
                } label: {
                    VStack(spacing: 3) {
                        Text(DateText.weekdayShort.string(from: day).prefix(3).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                        Text(DateText.dayNumber.string(from: day))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        Circle()
                            .fill(busy.contains(day.startOfDay) ? Theme.accent : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                                .fill(Theme.accent.opacity(0.18))
                                .matchedGeometryEffect(id: "daySelection", in: namespace)
                        } else if day.isToday {
                            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                                .strokeBorder(Theme.live.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
