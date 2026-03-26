import Foundation

public enum SharedStorage {
    public static func containerDirectory() -> URL {
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            ensureDirectory(appGroupURL)
            return appGroupURL
        }

        let fallback = applicationSupportDirectory(named: AppConstants.supportDirectoryName)
        let legacyFallback = applicationSupportDirectory(named: AppConstants.legacySupportDirectoryName)
        let resolvedFallback = resolvedFallbackDirectory(preferred: fallback, legacy: legacyFallback)
        ensureDirectory(resolvedFallback)
        return resolvedFallback
    }

    public static let settingsURL = containerDirectory().appendingPathComponent("settings.json")
    public static let statsURL = containerDirectory().appendingPathComponent("stats.json")
    public static let latestFrameURL = containerDirectory().appendingPathComponent("latest-frame.json")

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func applicationSupportDirectory(named name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static func resolvedFallbackDirectory(preferred preferredURL: URL, legacy legacyURL: URL) -> URL {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: preferredURL.path), fileManager.fileExists(atPath: legacyURL.path) else {
            return preferredURL
        }

        do {
            try fileManager.moveItem(at: legacyURL, to: preferredURL)
            return preferredURL
        } catch {
            return legacyURL
        }
    }
}

public final class SharedSettingsStore: @unchecked Sendable {
    public static let shared = SharedSettingsStore()

    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AutoFrameSettings {
        lock.lock()
        defer { lock.unlock() }

        guard
            let data = try? Data(contentsOf: SharedStorage.settingsURL),
            let settings = try? decoder.decode(AutoFrameSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    public func save(_ settings: AutoFrameSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try encoder.encode(settings)
        try data.write(to: SharedStorage.settingsURL, options: .atomic)
    }

    public func update(_ mutate: (inout AutoFrameSettings) -> Void) throws {
        var current = load()
        mutate(&current)
        try save(current)
    }
}

public final class SharedStatsStore: @unchecked Sendable {
    public static let shared = SharedStatsStore()

    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var lastPersistDate = Date.distantPast

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> FrameStatistics? {
        lock.lock()
        defer { lock.unlock() }

        guard
            let data = try? Data(contentsOf: SharedStorage.statsURL),
            let stats = try? decoder.decode(FrameStatistics.self, from: data)
        else {
            return nil
        }

        return stats
    }

    public func save(_ stats: FrameStatistics, minimumInterval: TimeInterval = 1.0) {
        lock.lock()
        defer { lock.unlock() }

        guard Date().timeIntervalSince(lastPersistDate) >= minimumInterval else {
            return
        }

        lastPersistDate = Date()
        guard let data = try? encoder.encode(stats) else { return }
        try? data.write(to: SharedStorage.statsURL, options: .atomic)
    }

    public func update(minimumInterval: TimeInterval = 1.0, _ mutate: (inout FrameStatistics) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard Date().timeIntervalSince(lastPersistDate) >= minimumInterval else {
            return
        }

        var stats: FrameStatistics
        if
            let data = try? Data(contentsOf: SharedStorage.statsURL),
            let decoded = try? decoder.decode(FrameStatistics.self, from: data)
        {
            stats = decoded
        } else {
            stats = .empty
        }

        mutate(&stats)

        lastPersistDate = Date()
        guard let data = try? encoder.encode(stats) else { return }
        try? data.write(to: SharedStorage.statsURL, options: .atomic)
    }
}
