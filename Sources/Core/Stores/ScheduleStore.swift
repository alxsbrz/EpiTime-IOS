import Foundation
import Observation

/// Owns every course the app knows about, fetched week by week and merged into a
/// single sorted timeline. Weeks are cached on disk so the UI paints instantly and
/// revalidates behind the scenes.
@MainActor
@Observable
final class ScheduleStore {
    private(set) var events: [CourseEvent] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var lastSyncedAt: Date?
    private(set) var servedFromCache = false
    var error: String?

    /// Weeks already merged into `events`, keyed by their Monday.
    private var loadedWeeks: Set<Date> = []
    private var inFlight: [Date: Task<Void, Never>] = [:]
    private var query = ZeusService.EventQuery()

    private let preferences: Preferences

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        query = preferences.eventQuery
    }

    // MARK: Querying

    func events(on day: Date) -> [CourseEvent] {
        let start = day.startOfDay
        let end = start.endOfDay
        return events.filter { $0.start < end && $0.end > start }
    }

    func visibleEvents(on day: Date) -> [CourseEvent] {
        let list = events(on: day)
        return preferences.hideCancelled ? list.filter { !$0.isCancelled } : list
    }

    func events(from start: Date, to end: Date) -> [CourseEvent] {
        events.filter { $0.start < end && $0.end > start }
    }

    func current(at date: Date = .now) -> CourseEvent? {
        events.first { !$0.isCancelled && $0.isLive(at: date) }
    }

    func next(after date: Date = .now) -> CourseEvent? {
        events.first { !$0.isCancelled && $0.start > date }
    }

    /// Days in the given span that hold at least one course — drives the dots on the
    /// day strip.
    func daysWithEvents(from start: Date, days: Int) -> Set<Date> {
        var result: Set<Date> = []
        for event in events where !(preferences.hideCancelled && event.isCancelled) {
            let day = event.start.startOfDay
            if day >= start.startOfDay, day < start.startOfDay.adding(days: days) {
                result.insert(day)
            }
        }
        return result
    }

    // MARK: Loading

    func groupsDidChange() {
        let next = preferences.eventQuery
        guard next != query else { return }
        query = next
        events = []
        loadedWeeks = []
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
    }

    /// Makes sure the week containing `date`, plus its neighbours, are loaded.
    func ensureLoaded(around date: Date, neighbours: Int = 1) async {
        guard !query.isEmpty else { return }
        let weeks = (-neighbours ... neighbours).map { date.startOfWeek.adding(days: $0 * 7) }
        await withTaskGroup(of: Void.self) { group in
            for week in weeks where !loadedWeeks.contains(week) {
                group.addTask { @MainActor [weak self] in
                    await self?.load(week: week)
                }
            }
        }
    }

    func refresh(around date: Date) async {
        guard !query.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let weeks = (-1 ... 1).map { date.startOfWeek.adding(days: $0 * 7) }
        for week in weeks {
            loadedWeeks.remove(week)
        }
        await ensureLoaded(around: date)
    }

    private func load(week: Date) async {
        if let existing = inFlight[week] {
            await existing.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = week
            let end = week.adding(days: 7)
            let key = "events.\(self.query.cacheKey).\(ISO8601DateFormatter.weekKey.string(from: week))"

            // Paint whatever we already have for this week before hitting the network.
            if let cached = await DiskCache.shared.load([CourseEvent].self, for: key) {
                self.merge(cached.value, week: week)
                self.servedFromCache = true
            }

            if self.events.isEmpty { self.isLoading = true }
            defer { self.isLoading = false }

            do {
                let fresh = try await ZeusService.events(from: start, to: end, query: self.query)
                self.merge(fresh, week: week)
                self.loadedWeeks.insert(week)
                self.lastSyncedAt = .now
                self.servedFromCache = false
                self.error = nil
                await DiskCache.shared.save(fresh, for: key)
            } catch is CancellationError {
                return
            } catch {
                if let apiError = error as? APIError, case .unauthorized = apiError {
                    self.error = apiError.localizedDescription
                } else {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        inFlight[week] = task
        await task.value
        inFlight[week] = nil
    }

    /// Replaces the slice of `events` covering `week` with `incoming`, keeping the
    /// whole array sorted.
    private func merge(_ incoming: [CourseEvent], week: Date) {
        let start = week
        let end = week.adding(days: 7)
        var kept = events.filter { $0.start < start || $0.start >= end }
        kept.append(contentsOf: incoming)
        events = kept.sorted { $0.start < $1.start }
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let weekKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
