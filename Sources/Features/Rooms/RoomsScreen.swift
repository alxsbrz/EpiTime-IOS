import SwiftUI

@MainActor
@Observable
final class RoomFinderStore {
    var start: Date
    var end: Date
    var locationID: String?
    var roomTypeID: String?
    var minimumCapacity: Int = 0

    private(set) var results: [Room] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    var error: String?

    private static let cacheKey = "rooms.lastSearch"

    init() {
        let now = Date()
        let rounded = RoomFinderStore.roundedToQuarter(now)
        start = rounded
        end = rounded.adding(minutes: 120)
    }

    /// Rounds up to the next quarter hour — nobody books a room at 14:07.
    static func roundedToQuarter(_ date: Date) -> Date {
        let calendar = Calendar.epitime
        let minute = calendar.component(.minute, from: date)
        let bump = (15 - minute % 15) % 15
        return calendar.date(bySetting: .second, value: 0, of: date.adding(minutes: bump)) ?? date
    }

    func restoreCache() async {
        guard results.isEmpty, let cached = await DiskCache.shared.load([Room].self, for: Self.cacheKey) else { return }
        results = cached.value
        hasSearched = true
    }

    func search() async {
        guard end > start else {
            error = "La fin doit être après le début."
            return
        }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let rooms = try await ZeusService.availableRooms(
                from: start,
                to: end,
                location: locationID,
                roomType: roomTypeID,
                capacity: minimumCapacity > 0 ? minimumCapacity : nil
            )
            results = rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            hasSearched = true
            await DiskCache.shared.save(results, for: Self.cacheKey)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            hasSearched = true
        }
    }

    func apply(preset: RoomPreset) {
        let now = RoomFinderStore.roundedToQuarter(.now)
        switch preset {
        case .now: start = now; end = now.adding(minutes: 60)
        case .twoHours: start = now; end = now.adding(minutes: 120)
        case .afternoon:
            let base = Calendar.epitime.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now
            start = base; end = base.adding(minutes: 180)
        case .tomorrow:
            let base = Calendar.epitime.date(bySettingHour: 9, minute: 0, second: 0, of: now.adding(days: 1)) ?? now
            start = base; end = base.adding(minutes: 180)
        }
    }
}

enum RoomPreset: String, CaseIterable, Identifiable {
    case now, twoHours, afternoon, tomorrow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .now: "Maintenant"
        case .twoHours: "+2 h"
        case .afternoon: "Cet après-midi"
        case .tomorrow: "Demain matin"
        }
    }
}

struct RoomsScreen: View {
    @Environment(ReferenceStore.self) private var reference
    @State private var store = RoomFinderStore()
    @State private var search = ""

    private var filtered: [Room] {
        let term = search.trimmed
        guard !term.isEmpty else { return store.results }
        return store.results.filter { $0.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    slotCard(store: store)
                    filterRow(store: store)

                    Button {
                        Haptics.tap()
                        Task { await store.search() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isSearching { ProgressView().controlSize(.small) }
                            Text(store.isSearching ? "Recherche…" : "Chercher une salle")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .disabled(store.isSearching)

                    if let error = store.error {
                        InlineBanner(kind: .error, message: error) {
                            Task { await store.search() }
                        }
                    }

                    results
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .auroraBackdrop()
            .searchable(text: $search, prompt: "Filtrer par nom")
            .navigationTitle("Salles libres")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await store.restoreCache()
                await reference.loadRoomMetadata()
                if Screenshots.isActive { await store.search() }
            }
        }
    }

    // MARK: Pieces

    private func slotCard(store: RoomFinderStore) -> some View {
        @Bindable var store = store
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Quand ?", symbol: "clock.fill")
                DatePicker("Début", selection: $store.start)
                    .font(.system(.subheadline, design: .rounded))
                DatePicker("Fin", selection: $store.end)
                    .font(.system(.subheadline, design: .rounded))

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(RoomPreset.allCases) { preset in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { store.apply(preset: preset) }
                            } label: {
                                Text(preset.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Theme.accent.opacity(0.14), in: .capsule)
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func filterRow(store: RoomFinderStore) -> some View {
        @Bindable var store = store
        let buildings = reference.locations.flatMap(\.flattened).filter(\.isLocation)

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Filtres", symbol: "line.3.horizontal.decrease")

                Picker("Bâtiment", selection: $store.locationID) {
                    Text("Tous les bâtiments").tag(String?.none)
                    ForEach(buildings) { node in
                        Text(node.name).tag(String?.some(node.id))
                    }
                }
                .font(.system(.subheadline, design: .rounded))

                Picker("Type de salle", selection: $store.roomTypeID) {
                    Text("Tous les types").tag(String?.none)
                    ForEach(reference.roomTypes) { type in
                        Text(type.type).tag(String?.some(type.id))
                    }
                }
                .font(.system(.subheadline, design: .rounded))

                Stepper(
                    store.minimumCapacity == 0 ? "Capacité : indifférente" : "Capacité : \(store.minimumCapacity)+ places",
                    value: $store.minimumCapacity,
                    in: 0 ... 200,
                    step: 10
                )
                .font(.system(.subheadline, design: .rounded))
            }
        }
    }

    private var results: some View {
        Group {
            if store.isSearching, store.results.isEmpty {
                VStack(spacing: 10) {
                    ForEach(0 ..< 5, id: \.self) { _ in SkeletonBlock(height: 62) }
                }
            } else if filtered.isEmpty, store.hasSearched, store.error == nil {
                EmptyStateView(
                    symbol: "door.left.hand.closed",
                    title: "Aucune salle libre",
                    message: "Essaie d'élargir le créneau ou de retirer un filtre."
                )
            } else if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: "\(filtered.count) salle\(filtered.count > 1 ? "s" : "") libre\(filtered.count > 1 ? "s" : "")",
                        subtitle: DateText.range(store.start, store.end),
                        symbol: "checkmark.seal.fill"
                    )
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { room in
                            RoomTile(room: room, typeName: reference.roomTypeName(for: room.roomTypeID))
                        }
                    }
                }
            }
        }
    }
}

private struct RoomTile: View {
    let room: Room
    let typeName: String?

    var body: some View {
        GlassCard(radius: Metrics.tileRadius, padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(room.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 7, height: 7)
                }
                // Side by side when the tile is wide enough, stacked otherwise — never
                // let a tag break mid-word.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { tags }
                    VStack(alignment: .leading, spacing: 5) { tags }
                }
            }
        }
    }

    @ViewBuilder private var tags: some View {
        if let capacity = room.capacity, capacity > 0 {
            TagLabel(text: "\(capacity) places", color: Theme.accent, symbol: "person.2.fill")
                .fixedSize()
        }
        if let typeName, !typeName.isEmpty {
            TagLabel(text: typeName, color: CourseColor.color(seed: typeName))
                .fixedSize()
        }
    }
}
