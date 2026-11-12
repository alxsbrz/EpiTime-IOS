import SwiftUI

/// The course line reused across Today, the day agenda and any multi-day list.
struct CourseRow: View {
    let event: CourseEvent
    var now: Date = .now
    var showsDate: Bool = false

    private var color: Color { CourseColor.color(for: event) }
    private var isPast: Bool { event.end <= now }
    private var isLive: Bool { event.isLive(at: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(color.gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .opacity(event.isCancelled ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(DateText.range(event.start, event.end))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isLive ? Theme.live : Theme.textSecondary)
                    if showsDate {
                        Text(DateText.compactDay.string(from: event.start))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if isLive { LivePulse() }
                }

                Text(event.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(event.isCancelled, color: Theme.danger)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    TagLabel(text: event.kindLabel, color: color)
                    if event.isOnline { TagLabel(text: "En ligne", color: Theme.accent, symbol: "video.fill") }
                    if event.isCancelled { TagLabel(text: "Annulé", color: Theme.danger, symbol: "xmark") }
                }

                if let rooms = event.roomsLabel {
                    metaLine(symbol: "mappin.and.ellipse", text: rooms)
                }
                if let teachers = event.teachersLabel {
                    metaLine(symbol: "person.fill", text: teachers)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(isPast && !isLive ? 0.45 : 1)
        .animation(Motion.quick, value: isLive)
    }

    private func metaLine(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Two-dot breathing indicator for a course happening right now.
struct LivePulse: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.live)
                .frame(width: 6, height: 6)
                .scaleEffect(on ? 1.35 : 0.85)
                .opacity(on ? 1 : 0.5)
            Text("EN COURS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.live)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
    }
}
