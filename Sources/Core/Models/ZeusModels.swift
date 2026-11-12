import Foundation

// MARK: - Loose identifier

/// Zeus hands back identifiers as JSON numbers on some endpoints and as strings on
/// others, sometimes for the very same entity. Normalising on decode keeps every
/// call site free of `String(describing:)` gymnastics.
struct ZeusID: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible, ExpressibleByStringLiteral {
    let raw: String

    var id: String { raw }
    var description: String { raw }
    var intValue: Int? { Int(raw) }

    init(_ raw: String) { self.raw = raw }
    init(_ raw: Int) { self.raw = String(raw) }
    init(stringLiteral value: String) { self.raw = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            raw = String(int)
        } else if let double = try? container.decode(Double.self) {
            raw = String(Int(double))
        } else {
            raw = try container.decode(String.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

// MARK: - Date parsing

enum ZeusDate {
    /// Zeus emits `2026-09-17T08:30:00` with no offset. JavaScript reads that as a
    /// *local* wall-clock time, so the whole web/RN app is calibrated on that reading —
    /// we must match it or every course drifts by the UTC offset.
    nonisolated(unsafe) private static let localFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = $0
            formatter.timeZone = .current
            return formatter
        }
    }()

    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let hasExplicitZone = value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if hasExplicitZone {
            if let date = isoWithFraction.date(from: value) { return date }
            if let date = iso.date(from: value) { return date }
        }
        for formatter in localFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return isoWithFraction.date(from: value) ?? iso.date(from: value)
    }

    /// The format the backend expects for `start` / `end` query parameters.
    static func iso8601(_ date: Date) -> String { iso.string(from: date) }
}

// MARK: - Events

struct EventRoom: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
}

struct EventTeacher: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
}

struct EventGroup: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
}

/// One reservation on the schedule, already normalised out of Zeus' many spellings.
struct CourseEvent: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var reservationID: String?
    var name: String?
    var typeName: String?
    var courseTypeName: String?
    var code: String?
    var url: String?
    var start: Date
    var end: Date
    var rooms: [EventRoom]
    var teachers: [EventTeacher]
    var groups: [EventGroup]
    var isOnline: Bool
    var isCancelled: Bool
    var cancellationReason: String?

    var title: String {
        if let name, !name.isEmpty { return name }
        if let typeName, !typeName.isEmpty { return CourseEvent.typeLabel(for: typeName) }
        return "Cours"
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    var roomsLabel: String? {
        let names = rooms.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    var teachersLabel: String? {
        let names = teachers.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var kindLabel: String {
        let raw = courseTypeName ?? typeName
        guard let raw, !raw.isEmpty else { return "Cours" }
        return CourseEvent.typeLabel(for: raw)
    }

    /// Progress through the course, 0...1, for the "en cours" ring.
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    func isLive(at date: Date) -> Bool { date >= start && date < end }

    static let typeLabels: [String: String] = [
        "CourseType.FollowUp": "Suivi de cours",
        "CourseType.Exam": "Examen",
        "CourseType.Lecture": "Cours magistral",
        "CourseType.Practice": "Travaux pratiques",
        "CourseType.Conference": "Conférence",
        "CourseType.Meeting": "Réunion",
        "CourseType.Defense": "Soutenance",
        "CourseType.Workshop": "Atelier",
        "CourseType.Rush": "Rush",
        "CourseType.TD": "TD",
        "CourseType.EventAsso": "Événement asso",
        "CourseType.LogiWorks": "LogiWorks",
        "CourseType.Remediation": "Remédiation",
        "CourseType.Tutoring": "Tutorat",
        "CourseType.Permanence": "Permanence",
        "CourseType.IntegratedLecture": "Cours intégré",
    ]

    static func typeLabel(for raw: String) -> String {
        typeLabels[raw] ?? raw.replacingOccurrences(of: "CourseType.", with: "")
    }
}

extension CourseEvent {
    /// Decoding lives in an explicit initialiser because the upstream payload mixes
    /// `rooms[].name` with `rooms[].room.name`, `isCancelled` with `isCanceled`, and
    /// numeric with string ids.
    init?(raw: RawZeusEvent) {
        guard let start = ZeusDate.parse(raw.startDate), let end = ZeusDate.parse(raw.endDate) else { return nil }
        let reservation = raw.idReservation?.raw ?? raw.id?.raw
        self.id = reservation ?? "\(raw.name ?? "event")-\(raw.startDate ?? "")-\(raw.endDate ?? "")"
        self.reservationID = reservation
        self.name = raw.name?.trimmed
        self.typeName = raw.typeName
        self.courseTypeName = raw.courseTypeName
        self.code = raw.code
        self.url = raw.url
        self.start = start
        self.end = end
        self.rooms = (raw.rooms ?? []).compactMap { entry in
            let name = entry.name ?? entry.room?.name
            let id = entry.id?.raw ?? entry.room?.id?.raw
            guard let name = name?.trimmed, !name.isEmpty else { return nil }
            return EventRoom(id: id ?? name, name: name)
        }
        self.teachers = (raw.teachers ?? []).compactMap { entry in
            let composed = [entry.firstname, entry.name].compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: " ")
            let name = composed.isEmpty ? (entry.displayname ?? entry.name) : composed
            guard let name = name?.trimmed, !name.isEmpty else { return nil }
            return EventTeacher(id: entry.id?.raw ?? name, name: name)
        }
        self.groups = (raw.groups ?? []).compactMap { entry in
            guard let name = entry.name?.trimmed, !name.isEmpty else { return nil }
            return EventGroup(id: entry.id?.raw ?? name, name: name)
        }
        self.isOnline = raw.isOnline ?? false
        self.isCancelled = raw.isCancelled ?? raw.isCanceled ?? false
        self.cancellationReason = raw.cancellationReason?.trimmed
    }
}

/// Mirror of the untouched Zeus JSON. Kept separate so `CourseEvent` stays clean.
struct RawZeusEvent: Decodable, Sendable {
    struct Room: Decodable, Sendable {
        struct Nested: Decodable, Sendable {
            var id: ZeusID?
            var name: String?
        }
        var id: ZeusID?
        var name: String?
        var room: Nested?
    }
    struct Teacher: Decodable, Sendable {
        var id: ZeusID?
        var name: String?
        var firstname: String?
        var displayname: String?
    }
    struct Group: Decodable, Sendable {
        var id: ZeusID?
        var name: String?
    }

    var id: ZeusID?
    var idReservation: ZeusID?
    var name: String?
    var typeName: String?
    var courseTypeName: String?
    var code: String?
    var url: String?
    var startDate: String?
    var endDate: String?
    var rooms: [Room]?
    var teachers: [Teacher]?
    var groups: [Group]?
    var isOnline: Bool?
    var isCancelled: Bool?
    var isCanceled: Bool?
    var cancellationReason: String?
}

// MARK: - Reference data

struct StudyGroup: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var parentID: String?

    private enum CodingKeys: String, CodingKey { case id, name, idParent }

    init(id: String, name: String, parentID: String?) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ZeusID.self, forKey: .id).raw
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        parentID = (try? container.decodeIfPresent(ZeusID.self, forKey: .idParent))?.raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ZeusID(id), forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(parentID.map { ZeusID($0) }, forKey: .idParent)
    }
}

struct Room: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var capacity: Int?
    var roomTypeID: String?
    var parentID: String?

    private enum CodingKeys: String, CodingKey { case id, name, capacity, idRoomType, id_parent }

    init(id: String, name: String, capacity: Int? = nil, roomTypeID: String? = nil, parentID: String? = nil) {
        self.id = id
        self.name = name
        self.capacity = capacity
        self.roomTypeID = roomTypeID
        self.parentID = parentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ZeusID.self, forKey: .id).raw
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        capacity = try? container.decodeIfPresent(Int.self, forKey: .capacity)
        roomTypeID = (try? container.decodeIfPresent(ZeusID.self, forKey: .idRoomType))?.raw
        parentID = (try? container.decodeIfPresent(ZeusID.self, forKey: .id_parent))?.raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ZeusID(id), forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(capacity, forKey: .capacity)
        try container.encodeIfPresent(roomTypeID.map { ZeusID($0) }, forKey: .idRoomType)
        try container.encodeIfPresent(parentID.map { ZeusID($0) }, forKey: .id_parent)
    }
}

struct Teacher: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String

    private enum CodingKeys: String, CodingKey { case id, name, firstname }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ZeusID.self, forKey: .id).raw
        let last = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        let first = (try? container.decodeIfPresent(String.self, forKey: .firstname)) ?? nil
        name = [first, last].compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ZeusID(id), forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

struct RoomType: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var type: String

    private enum CodingKeys: String, CodingKey { case id, type }

    init(id: String, type: String) {
        self.id = id
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ZeusID.self, forKey: .id).raw
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ZeusID(id), forKey: .id)
        try container.encode(type, forKey: .type)
    }
}

struct LocationNode: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var type: String?
    var typeID: Int?
    var parentID: String?
    var children: [LocationNode]

    private enum CodingKeys: String, CodingKey { case id, name, type, id_type, id_parent, children }

    init(id: String, name: String, type: String? = nil, typeID: Int? = nil, parentID: String? = nil, children: [LocationNode] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.typeID = typeID
        self.parentID = parentID
        self.children = children
    }

    /// `/api/locations` returns campuses, buildings *and* rooms in one tree. Only the
    /// first two are pickable as a location filter.
    var isLocation: Bool {
        (type ?? "").lowercased().contains("location") || typeID == 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ZeusID.self, forKey: .id).raw
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        typeID = (try? container.decodeIfPresent(Int.self, forKey: .id_type)) ?? nil
        parentID = (try? container.decodeIfPresent(ZeusID.self, forKey: .id_parent))?.raw
        children = (try? container.decodeIfPresent([LocationNode].self, forKey: .children)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ZeusID(id), forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(typeID, forKey: .id_type)
        try container.encodeIfPresent(parentID.map { ZeusID($0) }, forKey: .id_parent)
        try container.encode(children, forKey: .children)
    }

    /// Depth-first flattening, used by the location picker.
    var flattened: [LocationNode] {
        [self] + children.flatMap(\.flattened)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
