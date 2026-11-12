import SwiftUI

struct EventDetailSheet: View {
    let event: CourseEvent

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedType: String?
    @State private var icsURL: URL?

    private var color: Color { CourseColor.color(for: event) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    GlassCard(tint: color) {
                        VStack(alignment: .leading, spacing: 14) {
                            detail(symbol: "clock.fill", title: "Horaire",
                                   value: DateText.range(event.start, event.end),
                                   note: DateText.duration(event.duration))
                            Divider().opacity(0.25)
                            detail(symbol: "calendar", title: "Date",
                                   value: DateText.fullDay.string(from: event.start).capitalizedFirst,
                                   note: nil)
                            if let rooms = event.roomsLabel {
                                Divider().opacity(0.25)
                                detail(symbol: "mappin.and.ellipse", title: "Salle", value: rooms, note: nil)
                            }
                            if let teachers = event.teachersLabel {
                                Divider().opacity(0.25)
                                detail(symbol: "person.fill", title: "Intervenant", value: teachers, note: nil)
                            }
                        }
                    }

                    if !event.groups.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Groupes", symbol: "person.3.fill")
                                FlowRow(spacing: 6) {
                                    ForEach(event.groups) { group in
                                        TagLabel(text: group.name, color: Theme.accent)
                                    }
                                }
                            }
                        }
                    }

                    if event.isCancelled {
                        InlineBanner(kind: .error, message: event.cancellationReason ?? "Ce cours est annulé.")
                    }

                    actions
                }
                .padding(Metrics.gutter)
            }
            .scrollContentBackground(.hidden)
            .auroraBackdrop(animated: false)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                resolvedType = await ZeusService.resolvedCourseType(for: event)
                icsURL = ICSWriter.write(event)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(32)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TagLabel(text: resolvedType ?? event.kindLabel, color: color)
                if event.isOnline { TagLabel(text: "En ligne", color: Theme.accent, symbol: "video.fill") }
            }
            Text(event.title)
                .font(.display(30))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let code = event.code, !code.isEmpty {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let raw = event.url, let url = URL(string: raw) {
                Link(destination: url) {
                    Label("Rejoindre le cours en ligne", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
            if let room = event.rooms.first?.name,
               let mapURL = URL(string: "https://maps.apple.com/?q=EPITA%20\(room.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: mapURL) {
                    Label("Ouvrir dans Plans", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            if let icsURL {
                ShareLink(item: icsURL) {
                    Label("Ajouter à mon calendrier", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func detail(symbol: String, title: String, value: String, note: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
            if let note {
                Text(note)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Minimal iCalendar export so a course can be dropped into any calendar app
/// without asking for EventKit permission.
enum ICSWriter {
    static func write(_ event: CourseEvent) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")

        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: "\n", with: "\\n")
        }

        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//EpiTime//FR", "BEGIN:VEVENT",
            "UID:\(event.id)@epitime",
            "DTSTAMP:\(formatter.string(from: .now))",
            "DTSTART:\(formatter.string(from: event.start))",
            "DTEND:\(formatter.string(from: event.end))",
            "SUMMARY:\(escape(event.title))",
        ]
        if let rooms = event.roomsLabel { lines.append("LOCATION:\(escape(rooms))") }
        var description = event.kindLabel
        if let teachers = event.teachersLabel { description += " — \(teachers)" }
        lines.append("DESCRIPTION:\(escape(description))")
        lines.append(contentsOf: ["END:VEVENT", "END:VCALENDAR"])

        let name = "EpiTime-\(event.id.replacingOccurrences(of: "/", with: "-")).ics"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        do {
            try lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// Wrapping row used for group chips — `LazyVGrid` cannot size to content here.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
