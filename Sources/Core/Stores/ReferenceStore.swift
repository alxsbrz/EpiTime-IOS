import Foundation
import Observation

/// Slow-moving reference data (group tree, rooms, room types, locations). Cached
/// aggressively — it changes at most once a semester.
@MainActor
@Observable
final class ReferenceStore {
    private(set) var groupTree: [GroupNode] = []
    private(set) var rooms: [Room] = []
    private(set) var roomTypes: [RoomType] = []
    private(set) var locations: [LocationNode] = []
    private(set) var isLoadingGroups = false
    var error: String?

    private var didLoadGroups = false
    private var didLoadRoomMetadata = false
    /// Demo and real data never share a load: switching modes forces a fresh one.
    private var loadedInDemo = DemoMode.isActive

    private enum CacheKey {
        static let groups = "reference.groups"
        static let rooms = "reference.rooms"
        static let roomTypes = "reference.roomTypes"
        static let locations = "reference.locations"
    }

    func loadGroups(force: Bool = false) async {
        resetIfModeChanged()
        guard force || !didLoadGroups else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }

        if !force, !DemoMode.isActive, let cached = await DiskCache.shared.load([StudyGroup].self, for: CacheKey.groups) {
            groupTree = GroupTree.build(from: cached.value)
            didLoadGroups = true
            if cached.isFresh(within: 60 * 60 * 24 * 3) { return }
        }

        do {
            let groups = try await ZeusService.groups()
            groupTree = GroupTree.build(from: groups)
            didLoadGroups = true
            error = nil
            if !DemoMode.isActive { await DiskCache.shared.save(groups, for: CacheKey.groups) }
        } catch {
            if groupTree.isEmpty {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadRoomMetadata(force: Bool = false) async {
        resetIfModeChanged()
        guard force || !didLoadRoomMetadata else { return }

        if !force, !DemoMode.isActive {
            if let cached = await DiskCache.shared.load([Room].self, for: CacheKey.rooms) { rooms = cached.value }
            if let cached = await DiskCache.shared.load([RoomType].self, for: CacheKey.roomTypes) { roomTypes = cached.value }
            if let cached = await DiskCache.shared.load([LocationNode].self, for: CacheKey.locations) { locations = cached.value }
            if !rooms.isEmpty, !locations.isEmpty { didLoadRoomMetadata = true }
        }

        async let roomsResult = try? ZeusService.rooms()
        async let typesResult = try? ZeusService.roomTypes()
        async let locationsResult = try? ZeusService.locations()

        let (fetchedRooms, fetchedTypes, fetchedLocations) = await (roomsResult, typesResult, locationsResult)

        if let fetchedRooms, !fetchedRooms.isEmpty {
            rooms = fetchedRooms
            if !DemoMode.isActive { await DiskCache.shared.save(fetchedRooms, for: CacheKey.rooms) }
        }
        if let fetchedTypes, !fetchedTypes.isEmpty {
            roomTypes = fetchedTypes
            if !DemoMode.isActive { await DiskCache.shared.save(fetchedTypes, for: CacheKey.roomTypes) }
        }
        if let fetchedLocations, !fetchedLocations.isEmpty {
            locations = fetchedLocations
            if !DemoMode.isActive { await DiskCache.shared.save(fetchedLocations, for: CacheKey.locations) }
        }
        didLoadRoomMetadata = !rooms.isEmpty
    }

    private func resetIfModeChanged() {
        guard loadedInDemo != DemoMode.isActive else { return }
        loadedInDemo = DemoMode.isActive
        groupTree = []
        rooms = []
        roomTypes = []
        locations = []
        didLoadGroups = false
        didLoadRoomMetadata = false
    }

    func roomTypeName(for id: String?) -> String? {
        guard let id else { return nil }
        return roomTypes.first { $0.id == id }?.type
    }
}
