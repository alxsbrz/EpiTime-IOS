import Foundation
import Observation

enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

enum ScheduleLayout: String, CaseIterable, Codable, Sendable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String { self == .day ? "Jour" : "Semaine" }
    var symbol: String { self == .day ? "rectangle.grid.1x2" : "calendar" }
}

/// User-facing settings, persisted in `UserDefaults` and observed by the UI.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var selectedGroupIDs: [String] {
        didSet { defaults.set(selectedGroupIDs, forKey: Keys.groups) }
    }

    var selectedGroupNames: [String: String] {
        didSet { defaults.set(selectedGroupNames, forKey: Keys.groupNames) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var scheduleLayout: ScheduleLayout {
        didSet { defaults.set(scheduleLayout.rawValue, forKey: Keys.layout) }
    }

    var hideCancelled: Bool {
        didSet { defaults.set(hideCancelled, forKey: Keys.hideCancelled) }
    }

    var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Keys.reminder) }
    }

    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.remindersEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    private enum Keys {
        static let groups = "epitime.groups"
        static let groupNames = "epitime.groupNames"
        static let appearance = "epitime.appearance"
        static let layout = "epitime.layout"
        static let hideCancelled = "epitime.hideCancelled"
        static let reminder = "epitime.reminderMinutes"
        static let remindersEnabled = "epitime.remindersEnabled"
        static let onboarded = "epitime.onboarded"
        static let reduceMotion = "epitime.reduceMotion"
    }

    private init() {
        selectedGroupIDs = defaults.stringArray(forKey: Keys.groups) ?? []
        selectedGroupNames = defaults.dictionary(forKey: Keys.groupNames) as? [String: String] ?? [:]
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        scheduleLayout = ScheduleLayout(rawValue: defaults.string(forKey: Keys.layout) ?? "") ?? .day
        hideCancelled = defaults.object(forKey: Keys.hideCancelled) as? Bool ?? false
        reminderMinutes = defaults.object(forKey: Keys.reminder) as? Int ?? 15
        remindersEnabled = defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? false
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        reduceMotion = defaults.bool(forKey: Keys.reduceMotion)
    }

    var eventQuery: ZeusService.EventQuery {
        ZeusService.EventQuery(groups: selectedGroupIDs)
    }

    var groupsSummary: String {
        guard !selectedGroupIDs.isEmpty else { return "Aucun groupe" }
        let names = selectedGroupIDs.compactMap { selectedGroupNames[$0] }
        return names.isEmpty ? "\(selectedGroupIDs.count) groupe(s)" : names.joined(separator: " · ")
    }

    func select(_ node: GroupNode) {
        if selectedGroupIDs.contains(node.id) {
            selectedGroupIDs.removeAll { $0 == node.id }
            selectedGroupNames[node.id] = nil
        } else {
            selectedGroupIDs.append(node.id)
            selectedGroupNames[node.id] = node.name
        }
    }

    func clearGroups() {
        selectedGroupIDs = []
        selectedGroupNames = [:]
    }
}
