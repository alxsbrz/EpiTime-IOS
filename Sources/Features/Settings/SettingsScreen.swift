import SwiftUI

struct SettingsScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ScheduleStore.self) private var schedule
    @Environment(Preferences.self) private var preferences

    @State private var cacheSize = 0
    @State private var confirmSignOut = false
    @State private var confirmClearCache = false

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    account
                    groupsSection
                    appearance(preferences: preferences)
                    reminders(preferences: preferences)
                    data
                    about
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .auroraBackdrop()
            .navigationTitle("Réglages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { cacheSize = await DiskCache.shared.sizeOnDisk() }
        }
    }

    // MARK: Sections

    private var account: some View {
        GlassCard {
            HStack(spacing: 14) {
                Text(auth.profile?.initials ?? "?")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.35)), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.profile?.displayName ?? "Compte EPITA")
                        .font(.system(.headline, design: .rounded))
                    Text(auth.profile?.mail ?? auth.profile?.userPrincipalName ?? "")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if DemoMode.isActive {
                        TagLabel(text: "Mode démo", color: Theme.warning, symbol: "sparkles")
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)

                Button("Déconnexion", role: .destructive) { confirmSignOut = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .confirmationDialog("Se déconnecter d'EpiTime ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                CourseNotifications.shared.cancelAll()
                auth.signOut()
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var groupsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Mes groupes", subtitle: preferences.groupsSummary, symbol: "person.3.fill")
                NavigationLink {
                    GroupPickerScreen()
                } label: {
                    HStack {
                        Text("Modifier la sélection")
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func appearance(preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Apparence", symbol: "paintbrush.fill")
                Picker("Thème", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle("Masquer les cours annulés", isOn: $preferences.hideCancelled)
                    .font(.system(.subheadline, design: .rounded))
                Toggle("Réduire les animations", isOn: $preferences.reduceMotion)
                    .font(.system(.subheadline, design: .rounded))
            }
        }
    }

    private func reminders(preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Rappels", subtitle: "Notifications locales avant chaque cours", symbol: "bell.fill")

                Toggle("Activer les rappels", isOn: $preferences.remindersEnabled)
                    .font(.system(.subheadline, design: .rounded))
                    .onChange(of: preferences.remindersEnabled) { _, enabled in
                        Task {
                            if enabled {
                                let granted = await CourseNotifications.shared.requestAuthorization()
                                if !granted { preferences.remindersEnabled = false }
                            }
                            await CourseNotifications.shared.reschedule(
                                for: schedule.events,
                                minutesBefore: preferences.reminderMinutes,
                                enabled: preferences.remindersEnabled
                            )
                        }
                    }

                if preferences.remindersEnabled {
                    Picker("Prévenir", selection: $preferences.reminderMinutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { value in
                            Text("\(value) min").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preferences.reminderMinutes) { _, minutes in
                        Task {
                            await CourseNotifications.shared.reschedule(
                                for: schedule.events,
                                minutesBefore: minutes,
                                enabled: true
                            )
                        }
                    }
                }
            }
        }
    }

    private var data: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Données", symbol: "internaldrive.fill")
                row(label: "Cache", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                if let synced = schedule.lastSyncedAt {
                    row(label: "Dernière synchro", value: DateText.time.string(from: synced))
                }
                Button("Vider le cache", role: .destructive) { confirmClearCache = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .confirmationDialog("Vider le cache hors ligne ?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Vider", role: .destructive) {
                Task {
                    await DiskCache.shared.clear()
                    cacheSize = await DiskCache.shared.sizeOnDisk()
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var about: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "À propos", symbol: "info.circle.fill")
                row(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Link(destination: URL(string: "https://epitime.epita.it")!) {
                    linkRow(label: "Site EpiTime", symbol: "safari.fill")
                }
                // App Review 5.1.1(i): the privacy policy must be reachable from inside the app.
                Link(destination: URL(string: "https://epitime.epita.it/legal")!) {
                    linkRow(label: "Confidentialité et mentions légales", symbol: "hand.raised.fill")
                }
                Link(destination: URL(string: "https://github.com/alexistb2904/EpiTime")!) {
                    linkRow(label: "Code source", symbol: "chevron.left.forwardslash.chevron.right")
                }
                Text("Projet indépendant, non affilié à EPITA, IONIS, Zeus ou Auriga.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func linkRow(label: String, symbol: String) -> some View {
        HStack {
            Label(label, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(.rect)
    }
}
