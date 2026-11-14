import Foundation

/// On-disk format for a macro library or an exported set of macros.
public struct MacroLibraryFile: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var macros: [Macro]

    public init(macros: [Macro]) {
        self.version = Self.currentVersion
        self.macros = macros
    }
}

public enum MacroStoreError: LocalizedError {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "The macro file could not be read: \(detail)"
        }
    }
}

/// Reads and writes the macro library as JSON.
public struct MacroStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/MacroForMac/macros.json`
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacroForMac", isDirectory: true).appendingPathComponent("macros.json")
    }

    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Returns `nil` when no library has been saved yet.
    public func load() throws -> [Macro]? {
        guard fileExists else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decode(data)
    }

    public func save(_ macros: [Macro]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(macros).write(to: fileURL, options: .atomic)
    }

    /// Moves an unreadable library aside so it is never overwritten. Returns the backup location.
    @discardableResult
    public func quarantineCorruptFile() -> URL? {
        guard fileExists else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("macros.unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    public static func encode(_ macros: [Macro]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(MacroLibraryFile(macros: macros))
    }

    /// Accepts a library file, a bare array of macros, or a single macro.
    public static func decode(_ data: Data) throws -> [Macro] {
        let decoder = JSONDecoder()
        var firstError: Error?
        do {
            return try decoder.decode(MacroLibraryFile.self, from: data).macros
        } catch {
            firstError = error
        }
        if let macros = try? decoder.decode([Macro].self, from: data) { return macros }
        if let macro = try? decoder.decode(Macro.self, from: data), !(macro.steps.isEmpty && macro.name == "Untitled Macro") {
            return [macro]
        }
        throw MacroStoreError.unreadable(firstError.map { String(describing: $0) } ?? "unknown format")
    }

    /// Prepares imported macros so they don't collide with existing ones:
    /// fresh IDs, and shortcuts already in use are dropped.
    public static func prepareForImport(_ imported: [Macro], existing: [Macro]) -> [Macro] {
        var usedHotkeys = Set(existing.compactMap(\.hotkey))
        return imported.map { macro in
            var copy = macro.duplicated(name: macro.name)
            if let hotkey = macro.hotkey, !usedHotkeys.contains(hotkey) {
                copy.hotkey = hotkey
                usedHotkeys.insert(hotkey)
            }
            return copy
        }
    }
}
