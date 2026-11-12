import Foundation

/// One row as Auriga returns it, already parsed.
struct AurigaGrade: Codable, Sendable, Hashable {
    var code: String
    var type: String
    var name: String
    var semester: Int
    var value: Double
    /// Auriga expresses coefficients as percentages; stored here already divided by 100.
    var coefficient: Double
    /// "VA" / "NV" for pass-fail items, which carry no numeric value.
    var alphaMark: String?

    var isNumeric: Bool { alphaMark == nil }
}

struct DisplayGrade: Identifiable, Sendable, Hashable {
    var id: String
    var label: String
    var value: Double
    var coefficient: Double
    var alphaMark: String?

    var isNumeric: Bool { alphaMark == nil }
}

struct DisplaySubject: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var ueCode: String
    var average: Double?
    var totalCoefficient: Double
    var grades: [DisplayGrade]
    var isValidationOnly: Bool
    var hasFailedValidation: Bool
}

struct DisplayUE: Identifiable, Sendable, Hashable {
    var id: String
    var code: String
    var name: String
    var average: Double?
    var subjects: [DisplaySubject]
}

struct GradesPeriod: Identifiable, Sendable, Hashable {
    var id: String { "S\(semester)" }
    var semester: Int
    var average: Double?
    var ues: [DisplayUE]

    var gradeCount: Int {
        ues.flatMap(\.subjects).flatMap(\.grades).filter(\.isNumeric).count
    }

    var name: String { semester > 0 ? "Semestre \(semester)" : "Autres" }
}

enum GradesEngine {
    /// EPITA's teaching-unit codes, spelled out.
    static let ueNames: [String: String] = [
        "PR": "Produire", "AG": "Agir", "CN": "Concevoir", "PROJET": "Projet",
        "PL": "Piloter", "SH": "Sciences humaines", "STOUV": "Stage ouvrier",
        "CDSF": "Cahier des spécifications fonctionnel",
        "MIF": "Mathématiques et informatique fondamentales",
        "MIA": "Mathématiques et informatique avancées",
        "LANGAGES": "Ingénierie des sciences du numérique — Langages",
        "BASES": "Ingénierie des sciences du numérique — Bases",
        "CYBER": "Cybersécurité",
        "SHSJC": "Sciences humaines, sociales, juridiques et de communication",
        "ENT": "Rapport de stage",
    ]

    private static let examTypes: Set<String> = [
        "EXA", "EXF", "EXP", "EXB", "EXR", "EX", "EXAM", "RAT", "CC", "CB", "CT",
        "CONT", "DS", "DM", "QCM", "ORAL", "TP", "TPNOTE",
    ]

    /// Strips the `YYYY_X_SNN_` prefix Auriga puts in front of every item code.
    static func subjectCode(from name: String) -> String {
        guard let range = name.range(of: #"_S\d{2}_"#, options: .regularExpression) else { return name }
        return String(name[range.upperBound...])
    }

    /// Splits `MATH_ANALYSE_EXA_1` into the course (`MATH_ANALYSE`) and the assessment (`EXA_1`).
    static func splitExam(_ fullCode: String) -> (course: String, exam: String) {
        let parts = fullCode.split(separator: "_").map(String.init)
        if parts.count >= 3, Int(parts[parts.count - 1]) != nil, examTypes.contains(parts[parts.count - 2].uppercased()) {
            return (parts.dropLast(2).joined(separator: "_"), parts.suffix(2).joined(separator: "_"))
        }
        if parts.count >= 2, examTypes.contains(parts[parts.count - 1].uppercased()) {
            return (parts.dropLast().joined(separator: "_"), parts[parts.count - 1])
        }
        return (fullCode, "")
    }

    static func humanize(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Weighted mean over numeric grades; nil when nothing countable is present.
    static func weightedAverage(_ pairs: [(value: Double, weight: Double)]) -> Double? {
        let usable = pairs.filter { $0.weight > 0 && $0.value.isFinite }
        guard !usable.isEmpty else { return nil }
        let totalWeight = usable.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return usable.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
    }

    static func build(from grades: [AurigaGrade]) -> [GradesPeriod] {
        let bySemester = Dictionary(grouping: grades, by: \.semester)

        return bySemester.keys.sorted(by: >).compactMap { semester -> GradesPeriod? in
            let rows = bySemester[semester] ?? []
            guard !rows.isEmpty else { return nil }

            // Group rows into courses, then courses into teaching units.
            var subjectsByCode: [String: [AurigaGrade]] = [:]
            for row in rows {
                let full = subjectCode(from: row.name)
                subjectsByCode[splitExam(full).course, default: []].append(row)
            }

            var subjects = subjectsByCode.map { code, rows -> DisplaySubject in
                let displayGrades = rows.map { row -> DisplayGrade in
                    let full = subjectCode(from: row.name)
                    let exam = splitExam(full).exam
                    return DisplayGrade(
                        id: row.name,
                        label: exam.isEmpty ? humanize(row.type.isEmpty ? "Évaluation" : row.type) : humanize(exam),
                        value: row.value,
                        coefficient: row.coefficient > 0 ? row.coefficient : 1,
                        alphaMark: row.alphaMark
                    )
                }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

                let numeric = displayGrades.filter(\.isNumeric)
                return DisplaySubject(
                    id: "\(semester)-\(code)",
                    name: humanize(code),
                    ueCode: code.split(separator: "_").first.map(String.init)?.uppercased() ?? "AUTRE",
                    average: weightedAverage(numeric.map { ($0.value, $0.coefficient) }),
                    totalCoefficient: numeric.reduce(0) { $0 + $1.coefficient },
                    grades: displayGrades,
                    isValidationOnly: numeric.isEmpty && !displayGrades.isEmpty,
                    hasFailedValidation: displayGrades.contains { $0.alphaMark == "NV" }
                )
            }
            subjects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let ues = Dictionary(grouping: subjects, by: \.ueCode)
                .map { code, subjects -> DisplayUE in
                    DisplayUE(
                        id: "\(semester)-\(code)",
                        code: code,
                        name: ueNames[code] ?? humanize(code),
                        average: weightedAverage(subjects.compactMap { subject in
                            subject.average.map { ($0, max(subject.totalCoefficient, 1)) }
                        }),
                        subjects: subjects
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let overall = weightedAverage(ues.compactMap { ue in
                ue.average.map { ($0, ue.subjects.reduce(0) { $0 + max($1.totalCoefficient, 1) }) }
            })

            return GradesPeriod(semester: semester, average: overall, ues: ues)
        }
    }
}
