import Foundation

/// Small JSON cache under Application Support. Everything the app shows offline —
/// events, groups, rooms, grades — lands here so a cold launch on the métro still works.
actor DiskCache {
    static let shared = DiskCache()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var memory: [String: Data] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("EpiTimeCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("\(safe).json")
    }

    struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        var value: Value
        var storedAt: Date

        func isFresh(within interval: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) < interval
        }
    }

    func save<Value: Codable & Sendable>(_ value: Value, for key: String) {
        let entry = Entry(value: value, storedAt: .now)
        guard let data = try? encoder.encode(entry) else { return }
        memory[key] = data
        try? data.write(to: url(for: key), options: .atomic)
    }

    func load<Value: Codable & Sendable>(_ type: Value.Type, for key: String) -> Entry<Value>? {
        let data = memory[key] ?? (try? Data(contentsOf: url(for: key)))
        guard let data else { return nil }
        memory[key] = data
        return try? decoder.decode(Entry<Value>.self, from: data)
    }

    func remove(_ key: String) {
        memory[key] = nil
        try? FileManager.default.removeItem(at: url(for: key))
    }

    func clear() {
        memory.removeAll()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents { try? FileManager.default.removeItem(at: file) }
    }

    func sizeOnDisk() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return contents.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
