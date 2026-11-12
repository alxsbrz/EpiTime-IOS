import SwiftUI

// MARK: - Aurora backdrop

/// A slow-drifting mesh gradient sitting behind the glass. It is what gives the
/// Liquid Glass layers something worth refracting; without it glass reads as grey.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animated = true

    @State private var phase: CGFloat = 0

    private var colors: [Color] { scheme == .dark ? Theme.auroraDark : Theme.auroraLight }

    var body: some View {
        TimelineView(.animation(minimumInterval: animated && !reduceMotion ? 1 / 20 : .infinity, paused: !animated || reduceMotion)) { context in
            let t = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40) * 2 * .pi
            MeshGradient(
                width: 3,
                height: 3,
                points: points(t: reduceMotion ? 0 : t),
                colors: colors,
                smoothsColors: true
            )
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
    }

    private func points(t: CGFloat) -> [SIMD2<Float>] {
        func wobble(_ base: SIMD2<Float>, _ amount: CGFloat, _ offset: CGFloat) -> SIMD2<Float> {
            SIMD2(
                base.x + Float(sin(t + offset) * amount),
                base.y + Float(cos(t * 0.8 + offset) * amount)
            )
        }
        return [
            SIMD2(0, 0), wobble(SIMD2(0.5, 0), 0.06, 0.4), SIMD2(1, 0),
            wobble(SIMD2(0, 0.5), 0.05, 1.1), wobble(SIMD2(0.5, 0.5), 0.09, 2.0), wobble(SIMD2(1, 0.5), 0.05, 2.7),
            SIMD2(0, 1), wobble(SIMD2(0.5, 1), 0.06, 3.4), SIMD2(1, 1),
        ]
    }
}

extension View {
    /// Standard screen backdrop: aurora mesh under whatever the screen draws.
    func auroraBackdrop(animated: Bool = true) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuroraBackground(animated: animated))
    }
}

// MARK: - Glass surfaces

/// The app's default raised surface. One place to tune corner radius, padding and
/// the glass recipe for every card in the app.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = Metrics.cardRadius
    var padding: CGFloat = Metrics.gutter
    var tint: Color?
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                glass,
                in: .rect(cornerRadius: radius, style: .continuous)
            )
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.28)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A compact capsule of glass — used for chips, counters and inline badges.
struct GlassPill<Content: View>: View {
    var tint: Color?
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(pillGlass, in: .capsule)
    }

    private var pillGlass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Small coloured tag that is *not* glass — for dense lists where glass-on-glass
/// would turn to mud.
struct TagLabel: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: .rect(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Structural pieces

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// Non-blocking failure strip. Errors never take the content away — stale data
/// stays on screen underneath.
struct InlineBanner: View {
    enum Kind { case error, offline, info

        var symbol: String {
            switch self {
            case .error: "exclamationmark.triangle.fill"
            case .offline: "wifi.slash"
            case .info: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: Theme.danger
            case .offline: Theme.warning
            case .info: Theme.accent
            }
        }
    }

    var kind: Kind
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let retry {
                Button("Réessayer", action: retry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(kind.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(kind.tint.opacity(0.22)), in: .rect(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Skeleton block used while the first payload is in flight.
struct SkeletonBlock: View {
    var height: CGFloat
    var radius: CGFloat = Metrics.tileRadius
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surfaceSoft)
            .frame(height: height)
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .offset(x: shimmer ? 260 : -260)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { shimmer = true }
            }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func select() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
