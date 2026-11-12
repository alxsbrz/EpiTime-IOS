import SwiftUI

struct OnboardingScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Preferences.self) private var preferences

    @State private var step = 0

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                ProgressDots(count: 3, index: step)
                    .padding(.top, 16)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: groups
                    default: reminders
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(Motion.smooth, value: step)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Bienvenue" + (auth.profile.map { " \($0.shortName)" } ?? ""))
                .font(.display(34))
                .multilineTextAlignment(.center)
            Text("Choisis tes groupes pour qu'EpiTime affiche exactement ton emploi du temps.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("C'est parti") {
                withAnimation(Motion.smooth) { step = 1 }
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding(.bottom, 44)
        }
    }

    private var groups: some View {
        NavigationStack {
            GroupPickerScreen(isOnboarding: true) {
                withAnimation(Motion.smooth) { step = 2 }
            }
        }
    }

    private var reminders: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 50))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Ne rate plus un cours")
                .font(.display(30))
                .multilineTextAlignment(.center)
            Text("EpiTime peut te prévenir quelques minutes avant chaque cours. Tout reste sur ton appareil.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 10) {
                Button("Activer les rappels") {
                    Task {
                        let granted = await CourseNotifications.shared.requestAuthorization()
                        preferences.remindersEnabled = granted
                        finish()
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)

                Button("Plus tard") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 44)
        }
    }

    private func finish() {
        Haptics.success()
        preferences.hasCompletedOnboarding = true
    }
}

private struct ProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Theme.accent : Theme.hairline)
                    .frame(width: position == index ? 22 : 7, height: 7)
                    .animation(Motion.snappy, value: index)
            }
        }
    }
}
