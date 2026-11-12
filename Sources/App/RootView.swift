import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Preferences.self) private var preferences

    var body: some View {
        ZStack {
            switch auth.phase {
            case .booting:
                LaunchView()
                    .transition(.opacity)
            case .signedOut:
                SignInScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            case .signedIn:
                if preferences.selectedGroupIDs.isEmpty {
                    OnboardingScreen()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    MainShell()
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.smooth, value: auth.phase)
        .animation(Motion.smooth, value: preferences.selectedGroupIDs)
    }
}

/// Brief branded splash while the keychain session is read.
struct LaunchView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 18) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.accent.gradient)
                    .symbolEffect(.pulse)
                Text("EpiTime")
                    .font(.display(34))
            }
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(Motion.bouncy) { appeared = true } }
    }
}

// MARK: - Main navigation

enum AppTab: String, CaseIterable, Hashable {
    case today, schedule, grades, rooms, settings

    var title: String {
        switch self {
        case .today: "Aujourd'hui"
        case .schedule: "Planning"
        case .grades: "Notes"
        case .rooms: "Salles"
        case .settings: "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sparkles"
        case .schedule: "calendar"
        case .grades: "chart.bar.fill"
        case .rooms: "door.left.hand.open"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainShell: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(Preferences.self) private var preferences
    @State private var selection: AppTab = Screenshots.initialTab ?? .today

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.today.title, systemImage: AppTab.today.symbol, value: AppTab.today) {
                HomeScreen()
            }
            Tab(AppTab.schedule.title, systemImage: AppTab.schedule.symbol, value: AppTab.schedule) {
                ScheduleScreen()
            }
            Tab(AppTab.grades.title, systemImage: AppTab.grades.symbol, value: AppTab.grades) {
                GradesScreen()
            }
            Tab(AppTab.rooms.title, systemImage: AppTab.rooms.symbol, value: AppTab.rooms) {
                RoomsScreen()
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: AppTab.settings) {
                SettingsScreen()
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowAccessory(onOpen: { selection = .today })
        }
        #else
        .tabViewStyle(.sidebarAdaptable)
        #endif
        .task(id: preferences.selectedGroupIDs) {
            schedule.groupsDidChange()
            await schedule.ensureLoaded(around: .now)
        }
    }
}

/// The little always-on strip above the tab bar: what is happening right now, or
/// what comes next. It is the reason you open the app at all.
struct NowAccessory: View {
    @Environment(ScheduleStore.self) private var schedule
    #if os(iOS)
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    #endif
    var onOpen: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let live = schedule.current(at: now)
            let upcoming = schedule.next(after: now)

            Button(action: onOpen) {
                HStack(spacing: 10) {
                    if let event = live {
                        ProgressRing(progress: event.progress(at: now), color: Theme.live)
                            .frame(width: 22, height: 22)
                        label(title: event.title, detail: "se termine \(DateText.relativeStart(event.end, from: now))")
                    } else if let event = upcoming {
                        Circle()
                            .fill(CourseColor.color(for: event).gradient)
                            .frame(width: 10, height: 10)
                        label(title: event.title, detail: DateText.relativeStart(event.start, from: now).capitalizedFirst)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        label(title: "Rien de prévu", detail: "Profites-en")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func label(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Thin ring used for "course in progress".
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.smooth, value: progress)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
