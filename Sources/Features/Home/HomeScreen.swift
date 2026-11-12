import SwiftUI

struct HomeScreen: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(AuthStore.self) private var auth
    @Environment(Preferences.self) private var preferences

    @State private var selected: CourseEvent?
    @State private var showsPast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    greeting

                    if schedule.error != nil || schedule.servedFromCache {
                        banners
                    }

                    if schedule.events.isEmpty, schedule.isLoading {
                        SkeletonBlock(height: 168, radius: Metrics.cardRadius)
                        SkeletonBlock(height: 120, radius: Metrics.cardRadius)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HeroCard(now: context.date, onOpen: { selected = $0 })
                        }
                        todayTimeline
                        upcomingDays
                    }
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .auroraBackdrop()
            .refreshable { await schedule.refresh(around: .now) }
            .task {
                await schedule.ensureLoaded(around: .now)
                if Screenshots.opensLiveEvent { selected = schedule.current() }
            }
            .sheet(item: $selected) { EventDetailSheet(event: $0) }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    // MARK: Sections

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(salutation)
                .font(.display(32))
                .foregroundStyle(Theme.textPrimary)
            Text(DateText.fullDay.string(from: .now).capitalizedFirst)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(preferences.groupsSummary)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var salutation: String {
        let hour = Calendar.epitime.component(.hour, from: .now)
        let name = auth.profile?.shortName ?? ""
        let base = switch hour {
        case 0 ..< 6: "Bonne nuit"
        case 6 ..< 12: "Bonjour"
        case 12 ..< 18: "Bon après-midi"
        default: "Bonsoir"
        }
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private var banners: some View {
        VStack(spacing: 8) {
            if let error = schedule.error {
                InlineBanner(kind: .error, message: error) {
                    Task { await schedule.refresh(around: .now) }
                }
            } else if schedule.servedFromCache {
                InlineBanner(kind: .offline, message: "Hors ligne — planning enregistré.")
            }
        }
    }

    private var todayTimeline: some View {
        let events = schedule.visibleEvents(on: .now)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ta journée", subtitle: Self.daySummary(events), symbol: "list.bullet")
            if events.isEmpty {
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.success)
                        Text("Aucun cours aujourd'hui. Repose-toi.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let pastCount = events.count(where: { $0.end <= context.date })
                    VStack(spacing: 10) {
                        // Finished courses fold away so the afternoon opens on what is left.
                        if pastCount > 0 {
                            Button { withAnimation(Motion.snappy) { showsPast.toggle() } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.success)
                                    Text(pastCount == 1 ? "1 cours terminé" : "\(pastCount) cours terminés")
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(showsPast ? 180 : 0))
                                }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(showsPast ? "affichés" : "masqués")
                        }
                        ForEach(events.filter { showsPast || $0.end > context.date }) { event in
                            Button { selected = event } label: {
                                GlassCard(padding: 14, tint: event.isLive(at: context.date) ? Theme.live : nil) {
                                    CourseRow(event: event, now: context.date)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var upcomingDays: some View {
        let days = nextBusyDays(count: 3)
        return Group {
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "La suite", subtitle: "Tes prochains jours de cours", symbol: "arrow.forward")
                    ForEach(days, id: \.self) { day in
                        let events = schedule.visibleEvents(on: day)
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(DateText.fullDay.string(from: day).capitalizedFirst)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    Spacer()
                                    Text("\(events.count) cours")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                ForEach(events.prefix(3)) { event in
                                    Button { selected = event } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(CourseColor.color(for: event))
                                                .frame(width: 7, height: 7)
                                            Text(DateText.time.string(from: event.start))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundStyle(Theme.textSecondary)
                                            Text(event.title)
                                                .font(.system(size: 13, design: .rounded))
                                                .foregroundStyle(Theme.textPrimary)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if events.count > 3 {
                                    Text("+ \(events.count - 3) autre(s)")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func nextBusyDays(count: Int) -> [Date] {
        var result: [Date] = []
        var cursor = Date().adding(days: 1).startOfDay
        var guardCounter = 0
        while result.count < count, guardCounter < 21 {
            if !schedule.visibleEvents(on: cursor).isEmpty { result.append(cursor) }
            cursor = cursor.adding(days: 1)
            guardCounter += 1
        }
        return result
    }
}

// MARK: - Hero

/// The one card that answers "what am I supposed to be doing right now?".
private struct HeroCard: View {
    let now: Date
    var onOpen: (CourseEvent) -> Void

    @Environment(ScheduleStore.self) private var schedule

    var body: some View {
        if let event = schedule.current(at: now) {
            card(event: event, live: true)
        } else if let event = schedule.next(after: now) {
            card(event: event, live: false)
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.accent.gradient)
                    Text("Plus rien de prévu")
                        .font(.display(24))
                    Text("Aucun cours à venir dans ton planning.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func card(event: CourseEvent, live: Bool) -> some View {
        let color = CourseColor.color(for: event)
        let tagColor = live ? Theme.live : color
        return Button { onOpen(event) } label: {
            GlassCard(padding: 20, tint: live ? Theme.live : color) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        if live {
                            ProgressRing(progress: event.progress(at: now), color: Theme.live, lineWidth: 4)
                                .frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(live ? "En cours" : "Prochain cours")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(live ? Theme.live : color)
                                .textCase(.uppercase)
                            Text(event.title)
                                .font(.display(25))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(countdown(for: event, live: live))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(live ? Theme.live : Theme.accent)

                    HStack(spacing: 6) {
                        TagLabel(text: DateText.range(event.start, event.end), color: tagColor, symbol: "clock.fill")
                        if let room = event.rooms.first?.name {
                            TagLabel(text: room, color: tagColor, symbol: "mappin")
                        }
                        if event.isOnline {
                            TagLabel(text: "En ligne", color: Theme.accent, symbol: "video.fill")
                        }
                    }

                    if let teacher = event.teachersLabel {
                        Text(teacher)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if live {
                        ProgressView(value: event.progress(at: now))
                            .tint(Theme.live)
                        // Where to go once this one ends, without scrolling down.
                        if let after = schedule.next(after: now), after.start.isSameDay(as: now) {
                            Label(
                                (["Ensuite à \(DateText.time.string(from: after.start))", after.title] + [after.rooms.first?.name].compactMap { $0 })
                                    .joined(separator: " · "),
                                systemImage: "arrow.turn.down.right"
                            )
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func countdown(for event: CourseEvent, live: Bool) -> String {
        let target = live ? event.end : event.start
        let remaining = max(0, target.timeIntervalSince(now))
        if remaining >= 3600 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            return live ? "\(hours) h \(String(format: "%02d", minutes)) restantes" : "dans \(hours) h \(String(format: "%02d", minutes))"
        }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let clock = "\(minutes):\(String(format: "%02d", seconds))"
        return live ? "\(clock) restantes" : "dans \(clock)"
    }
}

// MARK: - Day summary

extension HomeScreen {
    /// "4 cours · 6 h 30 · fin à 16:30" — the day in one line, under "Ta journée".
    static func daySummary(_ events: [CourseEvent]) -> String {
        let held = events.filter { !$0.isCancelled }
        guard let end = held.map(\.end).max() else { return events.isEmpty ? "Rien de prévu" : "Cours annulés" }
        let total = held.reduce(0) { $0 + $1.duration }
        return "\(held.count) cours · \(DateText.duration(total)) · fin à \(DateText.time.string(from: end))"
    }
}
