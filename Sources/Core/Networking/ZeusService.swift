import Foundation

/// Every EpiTime backend endpoint the app calls, in one place.
enum ZeusService {
    // MARK: Schedule

    struct EventQuery: Hashable, Sendable {
        var groups: [String] = []
        var teachers: [String] = []
        var rooms: [String] = []

        var isEmpty: Bool { groups.isEmpty && teachers.isEmpty && rooms.isEmpty }

        /// Stable key used for the offline cache bucket.
        var cacheKey: String {
            [groups, teachers, rooms].map { $0.sorted().joined(separator: ",") }.joined(separator: "|")
        }
    }

    static func events(from start: Date, to end: Date, query: EventQuery) async throws -> [CourseEvent] {
        if DemoMode.isActive { return DemoData.events(from: start, to: end) }
        var items: [URLQueryItem] = [
            .init(name: "start", value: ZeusDate.iso8601(start)),
            .init(name: "end", value: ZeusDate.iso8601(end)),
        ]
        items += query.groups.map { URLQueryItem(name: "groups", value: $0) }
        items += query.teachers.map { URLQueryItem(name: "teachers", value: $0) }
        items += query.rooms.map { URLQueryItem(name: "rooms", value: $0) }

        let raw: [RawZeusEvent] = try await APIClient.shared.get("/api/events", query: items)
        return raw.compactMap(CourseEvent.init(raw:)).sorted { $0.start < $1.start }
    }

    // MARK: Course details

    /// List events carry only `typeName`; the human-readable course type lives behind a
    /// two-step join — reservation details give `idType`, which resolves to a label.
    struct ReservationDetails: Decodable, Sendable {
        var idType: ZeusID?
        var courseTypeName: String?
        var name: String?
        var url: String?
        var description: String?
    }

    static func reservationDetails(id: String) async throws -> ReservationDetails {
        try await APIClient.shared.get("/api/reservation/\(id)/details")
    }

    static func courseTypeLabel(id: String) async throws -> String? {
        struct Payload: Decodable, Sendable { var type: String? }
        let payload: Payload = try await APIClient.shared.get("/api/coursetype/\(id)")
        return payload.type.map(CourseEvent.typeLabel(for:))
    }

    /// Best-effort resolution of a course's real type label, cached on disk because a
    /// given reservation's type never changes.
    static func resolvedCourseType(for event: CourseEvent) async -> String? {
        if let name = event.courseTypeName, !name.isEmpty { return CourseEvent.typeLabel(for: name) }
        guard let reservationID = event.reservationID else { return nil }
        let key = "coursetype.\(reservationID)"
        if let cached = await DiskCache.shared.load(String.self, for: key) { return cached.value }
        guard let details = try? await reservationDetails(id: reservationID) else { return nil }
        if let name = details.courseTypeName, !name.isEmpty {
            let label = CourseEvent.typeLabel(for: name)
            await DiskCache.shared.save(label, for: key)
            return label
        }
        guard let typeID = details.idType?.raw,
              let label = ((try? await courseTypeLabel(id: typeID)) ?? nil) else { return nil }
        await DiskCache.shared.save(label, for: key)
        return label
    }

    // MARK: Reference data

    static func groups() async throws -> [StudyGroup] {
        if DemoMode.isActive { return DemoData.groups }
        return try await APIClient.shared.get("/api/groups")
    }

    static func rooms() async throws -> [Room] {
        if DemoMode.isActive { return DemoData.rooms }
        return try await APIClient.shared.get("/api/rooms")
    }

    static func teachers() async throws -> [Teacher] {
        if DemoMode.isActive { return [] }
        return try await APIClient.shared.get("/api/teachers")
    }

    static func roomTypes() async throws -> [RoomType] {
        if DemoMode.isActive { return DemoData.roomTypes }
        return try await APIClient.shared.get("/api/roomtypes")
    }

    static func locations() async throws -> [LocationNode] {
        if DemoMode.isActive { return DemoData.locations }
        return try await APIClient.shared.get("/api/locations")
    }

    // MARK: Free rooms

    struct AvailableRoomsRequest: Encodable, Sendable {
        var startDate: String
        var endDate: String
        var groups: [Int]?
        var location: Int?
        var roomType: Int?
        var capacity: Int?
    }

    static func availableRooms(
        from start: Date,
        to end: Date,
        location: String? = nil,
        roomType: String? = nil,
        capacity: Int? = nil
    ) async throws -> [Room] {
        if DemoMode.isActive {
            return DemoData.availableRooms(from: start, location: location, roomType: roomType, capacity: capacity)
        }
        let body = AvailableRoomsRequest(
            startDate: ZeusDate.iso8601(start),
            endDate: ZeusDate.iso8601(end),
            groups: nil,
            location: location.flatMap(Int.init),
            roomType: roomType.flatMap(Int.init),
            capacity: capacity
        )
        return try await APIClient.shared.post("/api/rooms/available", body: body)
    }
}
