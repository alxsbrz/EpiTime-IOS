import SwiftUI

@main
struct EpiTimeApp: App {
    @State private var auth = AuthStore()
    @State private var schedule = ScheduleStore()
    @State private var reference = ReferenceStore()
    @State private var preferences = Preferences.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(schedule)
                .environment(reference)
                .environment(preferences)
                .preferredColorScheme(preferences.appearance.colorScheme)
                .tint(Theme.accent)
                .task { await auth.bootstrap() }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif

        #if os(macOS)
        Settings {
            SettingsScreen()
                .environment(auth)
                .environment(schedule)
                .environment(reference)
                .environment(preferences)
                .frame(width: 520, height: 560)
        }
        #endif
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
