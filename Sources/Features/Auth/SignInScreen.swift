import SwiftUI

struct SignInScreen: View {
    @Environment(AuthStore.self) private var auth
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 62, weight: .light))
                        .foregroundStyle(Theme.accent.gradient)
                        .padding(22)
                        .glassEffect(.regular, in: .circle)
                        .symbolEffect(.bounce, options: .nonRepeating)

                    Text("EpiTime")
                        .font(.display(42))

                    Text("Ton emploi du temps EPITA,\nenfin agréable à regarder.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    ForEach(Array(Self.highlights.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26)
                            Text(item.text)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(Motion.smooth.delay(0.12 * Double(index) + 0.1), value: appeared)
                    }
                }
                .padding(Metrics.gutter)
                .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button {
                        Task { await auth.signIn() }
                    } label: {
                        HStack(spacing: 8) {
                            if auth.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "person.badge.key.fill")
                            }
                            Text(auth.isWorking ? "Connexion…" : "Se connecter avec EPITA")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .disabled(auth.isWorking)

                    Button {
                        Haptics.tap()
                        auth.signInDemo()
                    } label: {
                        Text("Découvrir l'app avec des données de démo")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(auth.isWorking)

                    if let error = auth.lastError {
                        InlineBanner(kind: .error, message: error)
                    }

                    Text("Authentification Microsoft EPITA. Aucun mot de passe ne transite par EpiTime.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: 520)
        }
        .onAppear { withAnimation(Motion.smooth) { appeared = true } }
    }

    private static let highlights: [(symbol: String, text: String)] = [
        ("bolt.fill", "Ton planning, à la seconde près"),
        ("chart.bar.fill", "Tes notes et moyennes calculées"),
        ("door.left.hand.open", "Les salles libres, tout de suite"),
        ("wifi.slash", "Consultable hors connexion"),
    ]
}
