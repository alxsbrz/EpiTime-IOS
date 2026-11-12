import SwiftUI

struct GradesScreen: View {
    @State private var grades = GradesStore()
    @State private var showLogin = false
    @State private var selectedSemester: Int?
    @State private var expanded: Set<String> = []
    @Namespace private var semesterNamespace

    private var period: GradesPeriod? {
        guard !grades.periods.isEmpty else { return nil }
        if let selectedSemester, let match = grades.periods.first(where: { $0.semester == selectedSemester }) { return match }
        return grades.periods.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch grades.state {
                    case .signedOut:
                        connectPrompt
                    case .loading:
                        VStack(spacing: 12) {
                            SkeletonBlock(height: 170, radius: Metrics.cardRadius)
                            ForEach(0 ..< 3, id: \.self) { _ in SkeletonBlock(height: 74) }
                        }
                    case let .failed(message):
                        InlineBanner(kind: .error, message: message) {
                            Task { await grades.sync(force: true) }
                        }
                        connectPrompt
                    case .ready:
                        if let period {
                            if grades.servedFromCache, let synced = grades.lastSyncedAt {
                                InlineBanner(kind: .offline, message: "Données du \(DateText.compactDay.string(from: synced)).")
                            }
                            averageCard(period: period)
                            if grades.periods.count > 1 { semesterPicker }
                            ueList(period: period)
                        } else {
                            EmptyStateView(
                                symbol: "tray",
                                title: "Aucune note",
                                message: "Auriga ne renvoie encore aucune note pour ton cursus."
                            )
                        }
                    }
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .auroraBackdrop()
            .navigationTitle("Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if grades.state == .ready {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Actualiser", systemImage: "arrow.clockwise") {
                                Task { await grades.sync(force: true) }
                            }
                            Button("Déconnecter Auriga", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                grades.signOut()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .refreshable { await grades.sync(force: true) }
            .task {
                await grades.bootstrap()
                if Screenshots.expandsGrades, let first = grades.periods.first?.ues.first { expanded = [first.id] }
            }
            .sheet(isPresented: $showLogin) {
                AurigaLoginSheet {
                    showLogin = false
                    Task { await grades.didSignIn() }
                }
            }
        }
    }

    // MARK: Sections

    private var connectPrompt: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "lock.shield.fill",
                title: "Connecte Auriga",
                message: "Tes notes viennent d'Auriga, un service distinct de ton compte Microsoft. Une seule connexion suffit, elle est conservée sur ton appareil.",
                actionTitle: "Connecter Auriga",
                action: { showLogin = true }
            )
        }
    }

    private func averageCard(period: GradesPeriod) -> some View {
        GlassCard(padding: 22, tint: color(for: period.average)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Moyenne — \(period.name)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(period.average.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.display(56))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(color(for: period.average))
                    Text("/ 20")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                    ProgressRing(progress: (period.average ?? 0) / 20, color: color(for: period.average), lineWidth: 6)
                        .frame(width: 54, height: 54)
                }

                HStack(spacing: 6) {
                    TagLabel(text: "\(period.gradeCount) notes", color: Theme.accent, symbol: "number")
                    TagLabel(text: "\(period.ues.count) UE", color: CourseColor.palette[4], symbol: "square.stack.3d.up.fill")
                    if let synced = grades.lastSyncedAt {
                        TagLabel(text: DateText.time.string(from: synced), color: Theme.textTertiary, symbol: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var semesterPicker: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(grades.periods) { candidate in
                        let isSelected = candidate.semester == (period?.semester ?? -1)
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { selectedSemester = candidate.semester }
                        } label: {
                            Text(candidate.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .glassEffect(isSelected ? .regular.tint(Theme.accent.opacity(0.4)) : .regular, in: .capsule)
                        .glassEffectID(candidate.id, in: semesterNamespace)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func ueList(period: GradesPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Unités d'enseignement", symbol: "square.stack.3d.up.fill")
            ForEach(period.ues) { ue in
                GlassCard(padding: 15) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(Motion.snappy) { toggle(ue.id) }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ue.name)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Theme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text("\(ue.subjects.count) matière\(ue.subjects.count > 1 ? "s" : "")")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer(minLength: 0)
                                Text(ue.average.map { String(format: "%.2f", $0) } ?? "—")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(color(for: ue.average))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary)
                                    .rotationEffect(.degrees(expanded.contains(ue.id) ? 90 : 0))
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if expanded.contains(ue.id) {
                            VStack(spacing: 8) {
                                ForEach(ue.subjects) { subject in
                                    SubjectBlock(subject: subject, color: color(for: subject.average))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func color(for average: Double?) -> Color {
        guard let average else { return Theme.textTertiary }
        if average >= 10 { return Theme.success }
        if average >= 8 { return Theme.warning }
        return Theme.danger
    }
}

private struct SubjectBlock: View {
    let subject: DisplaySubject
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(subject.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if subject.isValidationOnly {
                    TagLabel(
                        text: subject.hasFailedValidation ? "Non validé" : "Validé",
                        color: subject.hasFailedValidation ? Theme.danger : Theme.success
                    )
                } else {
                    Text(subject.average.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }

            ForEach(subject.grades) { grade in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.hairline)
                        .frame(width: 4, height: 4)
                    Text(grade.label)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if grade.coefficient != 1 {
                        Text("×\(String(format: "%.2g", grade.coefficient))")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let alpha = grade.alphaMark {
                        Text(alpha == "VA" ? "Validé" : "Non validé")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(alpha == "VA" ? Theme.success : Theme.danger)
                    } else {
                        Text(String(format: "%.2f", grade.value))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSoft.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Wraps the Keycloak web view in a dismissible sheet.
struct AurigaLoginSheet: View {
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attempt = AurigaAuthFlow.start()
    @State private var isExchanging = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AurigaLoginWebView(
                    attempt: attempt,
                    onCode: { code in
                        isExchanging = true
                        Task {
                            do {
                                let tokens = try await AurigaAuthFlow.finish(code: code, attempt: attempt)
                                AurigaSession.shared.store(tokens)
                                Haptics.success()
                                onSuccess()
                            } catch {
                                isExchanging = false
                                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    },
                    onFailure: { error = $0 }
                )
                .opacity(isExchanging ? 0.2 : 1)

                if isExchanging {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Connexion à Auriga…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if let error {
                    VStack {
                        InlineBanner(kind: .error, message: error)
                            .padding()
                        Spacer()
                    }
                }
            }
            .navigationTitle("Auriga")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
