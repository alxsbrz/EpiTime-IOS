import Foundation

extension Calendar {
    /// One shared calendar with Monday-first weeks and the French locale, matching
    /// how the schedule is read at EPITA.
    static let epitime: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }()
}

extension Date {
    var startOfDay: Date { Calendar.epitime.startOfDay(for: self) }

    var endOfDay: Date { Calendar.epitime.date(byAdding: .day, value: 1, to: startOfDay) ?? self }

    var startOfWeek: Date {
        let calendar = Calendar.epitime
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)?.startOfDay ?? startOfDay
    }

    func adding(days: Int) -> Date {
        Calendar.epitime.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(minutes: Int) -> Date {
        Calendar.epitime.date(byAdding: .minute, value: minutes, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.epitime.isDate(self, inSameDayAs: other)
    }

    var isToday: Bool { Calendar.epitime.isDateInToday(self) }

    /// Minutes since midnight — the vertical coordinate in the week grid.
    var minutesIntoDay: Double {
        let components = Calendar.epitime.dateComponents([.hour, .minute, .second], from: self)
        return Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0) + Double(components.second ?? 0) / 60
    }
}

enum DateText {
    nonisolated(unsafe) private static let locale = Locale(identifier: "fr_FR")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = .epitime
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    nonisolated(unsafe) static let time = formatter("HHmm")
    nonisolated(unsafe) static let weekdayShort = formatter("EEE")
    nonisolated(unsafe) static let dayNumber = formatter("d")
    nonisolated(unsafe) static let monthYear = formatter("MMMMyyyy")
    nonisolated(unsafe) static let fullDay = formatter("EEEEdMMMM")
    nonisolated(unsafe) static let compactDay = formatter("dMMM")

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time.string(from: start)) – \(time.string(from: end))"
    }

    /// "1 h 30", "45 min" — used on cards and in the countdown.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval.rounded() / 60)
        guard minutes >= 60 else { return "\(max(0, minutes)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", remainder))"
    }

    static func relativeStart(_ date: Date, from reference: Date = .now) -> String {
        let interval = date.timeIntervalSince(reference)
        if interval <= 0 { return "maintenant" }
        if interval < 60 { return "dans moins d'une minute" }
        return "dans \(duration(interval))"
    }
}
