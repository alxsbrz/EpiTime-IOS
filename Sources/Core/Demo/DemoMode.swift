import Foundation

/// A fully offline tour of the app with made-up data — for App Review (who has no
/// EPITA account) and for anyone curious before signing in. Every network entry
/// point checks `isActive` and answers from `DemoData` instead.
enum DemoMode {
    private static let key = "epitime.demo"

    static var isActive: Bool { UserDefaults.standard.bool(forKey: key) }

    static func setActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: key)
    }

    static let profile = MicrosoftProfile(
        id: "demo",
        displayName: "Camille Laurent",
        mail: "camille.laurent@epita.fr",
        userPrincipalName: "camille.laurent@epita.fr"
    )

    static let defaultGroup = (id: "demo-ing1-b", name: "ING1 · Groupe B")
}

/// Launch-argument hooks used to stage the App Store screenshots. Debug builds only.
enum Screenshots {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    static let isActive = arguments.contains("-screenshots")
    static let opensLiveEvent = arguments.contains("-openLiveEvent")
    static let expandsGrades = arguments.contains("-expandGrades")
    static let initialTab: AppTab? = {
        guard let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count else { return nil }
        return AppTab(rawValue: arguments[index + 1])
    }()
    #else
    static let isActive = false
    static let opensLiveEvent = false
    static let expandsGrades = false
    static let initialTab: AppTab? = nil
    #endif
}

enum DemoData {
    // MARK: Courses

    private struct Course {
        var name: String
        var type: String
        var room: String
        var teacher: String
        var online = false
    }

    private static let algo = Course(name: "Algorithmique avancée", type: "CourseType.Lecture", room: "Amphi 4", teacher: "Hélène Marchand")
    private static let langages = Course(name: "Théorie des langages", type: "CourseType.TD", room: "KB 604", teacher: "Julien Morel")
    private static let systemes = Course(name: "Systèmes d'exploitation", type: "CourseType.Practice", room: "SM 14", teacher: "Nicolas Garnier")
    private static let reseaux = Course(name: "Réseaux & protocoles", type: "CourseType.Practice", room: "SM 22", teacher: "Sarah Benali")
    private static let probas = Course(name: "Probabilités & statistiques", type: "CourseType.IntegratedLecture", room: "Amphi 2", teacher: "Marc Lefèvre")
    private static let anglais = Course(name: "Business English", type: "CourseType.TD", room: "VJ 212", teacher: "Emily Carter")
    private static let projet = Course(name: "Projet — point d'étape", type: "CourseType.Workshop", room: "KB 401", teacher: "Thomas Roux")
    private static let partiel = Course(name: "Partiel — Algorithmique", type: "CourseType.Exam", room: "Amphi 1", teacher: "Hélène Marchand")
    private static let rush = Course(name: "Rush Unix", type: "CourseType.Rush", room: "SM 14", teacher: "Équipe ACU")
    private static let conference = Course(name: "Conférence : IA et éthique", type: "CourseType.Conference", room: "En ligne", teacher: "Claire Dubois", online: true)

    /// Hour, minute, length in minutes, course — per weekday (1 = Sunday … 7 = Saturday).
    private static let week: [Int: [(Int, Int, Int, Course)]] = [
        2: [(9, 0, 90, algo), (10, 45, 90, langages), (13, 30, 180, systemes)],
        3: [(9, 0, 90, probas), (10, 45, 90, anglais), (13, 30, 120, reseaux), (15, 45, 90, projet)],
        4: [(9, 0, 120, systemes), (13, 30, 90, langages), (15, 15, 90, anglais)],
        5: [(9, 0, 90, algo), (10, 45, 90, probas), (14, 0, 90, conference), (15, 45, 90, reseaux)],
        6: [(9, 0, 120, partiel), (13, 30, 240, rush)],
    ]

    static func events(from start: Date, to end: Date) -> [CourseEvent] {
        var result: [CourseEvent] = []
        var day = start.startOfDay
        while day < end {
            result += events(on: day)
            day = day.adding(days: 1)
        }
        return result.filter { $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
    }

    private static func events(on day: Date) -> [CourseEvent] {
        let calendar = Calendar.epitime
        if day.isToday { return today() }

        let weekday = calendar.component(.weekday, from: day)
        // Thursday's lecture is cancelled every other week, so the cancelled style shows up.
        let weekIndex = calendar.component(.weekOfYear, from: day)
        return (week[weekday] ?? []).enumerated().map { index, slot in
            let start = calendar.date(bySettingHour: slot.0, minute: slot.1, second: 0, of: day) ?? day
            let cancelled = weekday == 5 && index == 1 && weekIndex.isMultiple(of: 2)
            return event(slot.3, start: start, minutes: slot.2, cancelled: cancelled)
        }
    }

    /// Today is built around the current time so there is always a course in progress.
    private static func today() -> [CourseEvent] {
        let calendar = Calendar.epitime
        let now = Date()
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        parts.minute = (parts.minute ?? 0) / 15 * 15
        let anchor = calendar.date(from: parts) ?? now
        let liveStart = anchor.adding(minutes: -45)
        let liveEnd = liveStart.adding(minutes: 120)
        let nextStart = liveEnd.adding(minutes: 15)
        return [
            event(langages, start: liveStart.adding(minutes: -105), minutes: 90),
            event(algo, start: liveStart, minutes: 120),
            event(reseaux, start: nextStart, minutes: 90),
            event(projet, start: nextStart.adding(minutes: 105), minutes: 90),
        ]
    }

    private static func event(_ course: Course, start: Date, minutes: Int, cancelled: Bool = false) -> CourseEvent {
        let id = "demo-\(Int(start.timeIntervalSince1970))"
        return CourseEvent(
            id: id,
            reservationID: nil,
            name: course.name,
            typeName: course.type,
            courseTypeName: course.type,
            code: nil,
            url: course.online ? "https://teams.microsoft.com" : nil,
            start: start,
            end: start.adding(minutes: minutes),
            rooms: [EventRoom(id: "room-\(course.room)", name: course.room)],
            teachers: [EventTeacher(id: "teacher-\(course.teacher)", name: course.teacher)],
            groups: [EventGroup(id: DemoMode.defaultGroup.id, name: DemoMode.defaultGroup.name)],
            isOnline: course.online,
            isCancelled: cancelled,
            cancellationReason: cancelled ? "Enseignant absent — cours reporté" : nil
        )
    }

    // MARK: Groups

    static let groups: [StudyGroup] = [
        StudyGroup(id: "demo-epita", name: "EPITA Paris", parentID: nil),
        StudyGroup(id: "demo-prepa", name: "Cycle préparatoire", parentID: "demo-epita"),
        StudyGroup(id: "demo-sup", name: "SUP", parentID: "demo-prepa"),
        StudyGroup(id: "demo-spe", name: "SPÉ", parentID: "demo-prepa"),
        StudyGroup(id: "demo-ing", name: "Cycle ingénieur", parentID: "demo-epita"),
        StudyGroup(id: "demo-ing1", name: "ING1", parentID: "demo-ing"),
        StudyGroup(id: "demo-ing1-a", name: "ING1 · Groupe A", parentID: "demo-ing1"),
        StudyGroup(id: DemoMode.defaultGroup.id, name: DemoMode.defaultGroup.name, parentID: "demo-ing1"),
        StudyGroup(id: "demo-ing1-c", name: "ING1 · Groupe C", parentID: "demo-ing1"),
        StudyGroup(id: "demo-ing2", name: "ING2", parentID: "demo-ing"),
        StudyGroup(id: "demo-ing2-scia", name: "ING2 · SCIA", parentID: "demo-ing2"),
        StudyGroup(id: "demo-ing2-srs", name: "ING2 · SRS", parentID: "demo-ing2"),
        StudyGroup(id: "demo-ing2-gistre", name: "ING2 · GISTRE", parentID: "demo-ing2"),
    ]

    // MARK: Rooms

    static let roomTypes: [RoomType] = [
        RoomType(id: "1", type: "Amphithéâtre"),
        RoomType(id: "2", type: "Salle de cours"),
        RoomType(id: "3", type: "Salle machines"),
        RoomType(id: "4", type: "Salle de réunion"),
    ]

    static let locations: [LocationNode] = [
        LocationNode(id: "loc-kb", name: "Kremlin-Bicêtre", type: "Location", typeID: 0, children: [
            LocationNode(id: "loc-kb-a", name: "Bâtiment KB", type: "Location", typeID: 0, parentID: "loc-kb"),
            LocationNode(id: "loc-kb-sm", name: "Bâtiment SM", type: "Location", typeID: 0, parentID: "loc-kb"),
        ]),
        LocationNode(id: "loc-vj", name: "Villejuif", type: "Location", typeID: 0, children: [
            LocationNode(id: "loc-vj-a", name: "Bâtiment VJ", type: "Location", typeID: 0, parentID: "loc-vj"),
        ]),
    ]

    static let rooms: [Room] = [
        Room(id: "r1", name: "Amphi 1", capacity: 320, roomTypeID: "1", parentID: "loc-kb-a"),
        Room(id: "r2", name: "Amphi 2", capacity: 180, roomTypeID: "1", parentID: "loc-kb-a"),
        Room(id: "r3", name: "KB 401", capacity: 36, roomTypeID: "2", parentID: "loc-kb-a"),
        Room(id: "r4", name: "KB 402", capacity: 36, roomTypeID: "2", parentID: "loc-kb-a"),
        Room(id: "r5", name: "KB 604", capacity: 42, roomTypeID: "2", parentID: "loc-kb-a"),
        Room(id: "r6", name: "KB 607", capacity: 24, roomTypeID: "4", parentID: "loc-kb-a"),
        Room(id: "r7", name: "SM 14", capacity: 48, roomTypeID: "3", parentID: "loc-kb-sm"),
        Room(id: "r8", name: "SM 16", capacity: 48, roomTypeID: "3", parentID: "loc-kb-sm"),
        Room(id: "r9", name: "SM 22", capacity: 30, roomTypeID: "3", parentID: "loc-kb-sm"),
        Room(id: "r10", name: "VJ 108", capacity: 30, roomTypeID: "2", parentID: "loc-vj-a"),
        Room(id: "r11", name: "VJ 212", capacity: 28, roomTypeID: "2", parentID: "loc-vj-a"),
        Room(id: "r12", name: "VJ 305", capacity: 12, roomTypeID: "4", parentID: "loc-vj-a"),
    ]

    static func availableRooms(from start: Date, location: String?, roomType: String?, capacity: Int?) -> [Room] {
        let allowedParents: Set<String>? = location.map { id in
            let node = locations.flatMap(\.flattened).first { $0.id == id }
            return Set(node?.flattened.map(\.id) ?? [id])
        }
        // A few rooms are "taken" depending on the hour, so results move with the slot.
        let hour = Calendar.epitime.component(.hour, from: start)
        return rooms.enumerated().compactMap { index, room in
            if (index + hour) % 4 == 0 { return nil }
            if let allowedParents, !allowedParents.contains(room.parentID ?? "") { return nil }
            if let roomType, room.roomTypeID != roomType { return nil }
            if let capacity, (room.capacity ?? 0) < capacity { return nil }
            return room
        }
    }

    // MARK: Grades

    static let grades: [AurigaGrade] = {
        let rows: [(String, String, Double, Double)] = [
            ("2026_1_S05_MIF_ALGORITHMIQUE_EXA_1", "Examen", 15.5, 0.6),
            ("2026_1_S05_MIF_ALGORITHMIQUE_CC_1", "Contrôle continu", 17, 0.4),
            ("2026_1_S05_MIF_PROBABILITÉS_EXA_1", "Examen", 12.75, 0.7),
            ("2026_1_S05_MIF_PROBABILITÉS_QCM_1", "QCM", 14, 0.3),
            ("2026_1_S05_LANGAGES_THÉORIE_DES_LANGAGES_EXA_1", "Examen", 13.5, 1),
            ("2026_1_S05_BASES_SYSTÈMES_TP_1", "TP", 16.25, 0.5),
            ("2026_1_S05_BASES_SYSTÈMES_EXA_1", "Examen", 11.5, 0.5),
            ("2026_1_S05_BASES_RÉSEAUX_TP_1", "TP", 18, 0.4),
            ("2026_1_S05_BASES_RÉSEAUX_EXA_1", "Examen", 14.5, 0.6),
            ("2026_1_S05_SHSJC_ANGLAIS_ORAL_1", "Oral", 16, 0.5),
            ("2026_1_S05_SHSJC_ANGLAIS_CC_1", "Contrôle continu", 15, 0.5),
            ("2026_1_S05_PROJET_INNOVATION_ORAL_1", "Soutenance", 17.5, 1),
            ("2025_2_S04_MIF_ANALYSE_EXA_1", "Examen", 13, 0.6),
            ("2025_2_S04_MIF_ANALYSE_CC_1", "Contrôle continu", 15.5, 0.4),
            ("2025_2_S04_MIF_ALGÈBRE_LINÉAIRE_EXA_1", "Examen", 12, 1),
            ("2025_2_S04_BASES_PROGRAMMATION_C_TP_1", "TP", 17, 0.5),
            ("2025_2_S04_BASES_PROGRAMMATION_C_EXA_1", "Examen", 14.25, 0.5),
            ("2025_2_S04_SHSJC_ANGLAIS_ORAL_1", "Oral", 15.5, 1),
            ("2025_2_S04_PROJET_JEU_VIDÉO_ORAL_1", "Soutenance", 16.5, 1),
        ]
        var grades = rows.map { name, type, value, coefficient in
            AurigaGrade(code: name, type: type, name: name, semester: Int(name.split(separator: "_")[2].dropFirst()) ?? 0,
                        value: value, coefficient: coefficient, alphaMark: nil)
        }
        grades.append(AurigaGrade(code: "SHSJC_DROIT", type: "Validation", name: "2026_1_S05_SHSJC_DROIT_DU_NUMÉRIQUE_CC_1",
                                  semester: 5, value: 0, coefficient: 1, alphaMark: "VA"))
        return grades
    }()
}
