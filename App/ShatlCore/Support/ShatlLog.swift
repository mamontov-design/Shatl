// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import OSLog

enum ShatlLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case notice = "NOTICE"
    case error = "ERROR"
}

nonisolated final class ShatlFileLogger: @unchecked Sendable {
    static let shared = ShatlFileLogger()
    static let diskDiagnostics = ShatlFileLogger(fileName: "Shatl Disk Diagnostics.log")
    static let metricAnimationDiagnostics = ShatlFileLogger(
        fileName: "Shatl Metric Animation Diagnostics.log"
    )
    static let snapshotDiagnostics = ShatlFileLogger(
        fileName: "Shatl Snapshot Diagnostics.log"
    )
    static let addTorrentReviewDiagnostics = ShatlFileLogger(
        fileName: "Shatl Add Torrent Review Diagnostics.log"
    )
    static let cardLayoutDiagnostics = ShatlFileLogger(
        fileName: "Shatl Card Layout Diagnostics.log"
    )

    private static let queueSpecificKey = DispatchSpecificKey<Void>()

    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private let directoryURL: URL
    private let fileURL: URL
    private let maxFileSizeBytes: UInt64
    private let fileManager: FileManager

    private var isEnabledStorage: Bool

    init(
        directoryURL: URL = AppPreferences.defaultLogsDirectoryURL(),
        fileName: String = "Shatl.log",
        maxFileSizeBytes: UInt64 = 5 * 1024 * 1024,
        fileManager: FileManager = .default,
        initiallyEnabled: Bool = false,
        queue: DispatchQueue = DispatchQueue(label: "mamontov.design.shatl.file-logger")
    ) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        self.maxFileSizeBytes = maxFileSizeBytes
        self.fileManager = fileManager
        self.isEnabledStorage = initiallyEnabled
        self.queue = queue
        self.queue.setSpecific(key: Self.queueSpecificKey, value: ())
    }

    var loggingEnabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isEnabledStorage
    }

    func setEnabled(_ enabled: Bool) {
        #if DEBUG
        let effectiveEnabled = enabled
        #else
        // File diagnostics are a development tool and must stay inactive in release builds,
        // even when preferences persisted by an earlier development build contain `true`.
        let effectiveEnabled = false
        #endif

        stateLock.lock()
        let wasEnabled = isEnabledStorage
        isEnabledStorage = effectiveEnabled
        stateLock.unlock()

        guard wasEnabled != effectiveEnabled else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.appendLine(
                "[\(self.timestamp())] [Logging] [NOTICE] Logging \(effectiveEnabled ? "enabled" : "disabled").",
                force: true
            )
        }
    }

    func write(level: ShatlLogLevel, category: String, message: String, flush: Bool = false) {
        guard loggingEnabled else { return }

        let line = "[\(timestamp())] [\(category)] [\(level.rawValue)] \(message)"
        let append: () -> Void = { [weak self] in
            self?.appendLine(line, force: false)
        }

        if flush {
            if DispatchQueue.getSpecific(key: Self.queueSpecificKey) != nil {
                append()
            } else {
                queue.sync(execute: append)
            }
        } else {
            queue.async {
                append()
            }
        }
    }

    func flushForTests() {
        queue.sync { }
    }

    private func appendLine(_ line: String, force: Bool) {
        if !force, !loggingEnabled {
            return
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try rotateIfNeeded()

            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let data = Data((line + "\n").utf8)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Logger(subsystem: "mamontov.design.shatl", category: "Logging")
                .error("Failed to write log file: \((error as NSError).localizedDescription, privacy: .public)")
        }
    }

    private func rotateIfNeeded() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        guard fileSize >= maxFileSizeBytes else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        // Each log archives under its own name, so a rotated snapshot or disk
        // diagnostics file is not mistaken for the main `Shatl.log`.
        let logName = fileURL.deletingPathExtension().lastPathComponent
        var archiveURL = directoryURL.appendingPathComponent(
            "\(logName)-\(formatter.string(from: Date())).log",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: archiveURL.path) {
            archiveURL = directoryURL.appendingPathComponent(
                "\(logName)-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).log",
                isDirectory: false
            )
        }

        try fileManager.moveItem(at: fileURL, to: archiveURL)
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

nonisolated enum ShatlDiskDiagnosticsLog {
    static var isEnabled: Bool {
        ShatlFileLogger.diskDiagnostics.loggingEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        ShatlFileLogger.diskDiagnostics.setEnabled(enabled)
    }

    static func event(
        _ name: String,
        fields: @autoclosure () -> [String: String] = [:],
        flush: Bool = true
    ) {
        guard isEnabled else { return }
        let fields = fields()

        var orderedFields: [(String, String)] = [("event", name)]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            orderedFields.append((key, value))
        }

        let message = orderedFields
            .map { "\($0.0)=\(escapedValue($0.1))" }
            .joined(separator: " ")

        ShatlFileLogger.diskDiagnostics.write(
            level: .notice,
            category: "MissingContent",
            message: message,
            flush: flush
        )
    }

    private static func escapedValue(_ value: String) -> String {
        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\"" || character == "\\"
        }

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Card heights as they change. Written in the background: a card that
/// appears must not wait for the disk.
nonisolated enum ShatlCardLayoutDiagnosticsLog {
    static var isEnabled: Bool {
        ShatlFileLogger.cardLayoutDiagnostics.loggingEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        ShatlFileLogger.cardLayoutDiagnostics.setEnabled(enabled)
    }

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        ShatlFileLogger.cardLayoutDiagnostics.write(level: .debug, category: "CardLayout", message: message())
    }
}

nonisolated enum ShatlMetricAnimationDiagnosticsLog {
    static var isEnabled: Bool {
        ShatlFileLogger.metricAnimationDiagnostics.loggingEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        ShatlFileLogger.metricAnimationDiagnostics.setEnabled(enabled)
    }

    static func event(
        _ name: String,
        fields: @autoclosure () -> [String: String] = [:],
        flush: Bool = false
    ) {
        guard isEnabled else { return }
        let fields = fields()

        var orderedFields: [(String, String)] = [("event", name)]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            orderedFields.append((key, value))
        }

        let message = orderedFields
            .map { "\($0.0)=\(escapedValue($0.1))" }
            .joined(separator: " ")

        ShatlFileLogger.metricAnimationDiagnostics.write(
            level: .notice,
            category: "MetricAnimation",
            message: message,
            flush: flush
        )
    }

    private static func escapedValue(_ value: String) -> String {
        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\"" || character == "\\"
        }

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

nonisolated enum ShatlSnapshotDiagnosticsLog {
    static var isEnabled: Bool {
        ShatlFileLogger.snapshotDiagnostics.loggingEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        ShatlFileLogger.snapshotDiagnostics.setEnabled(enabled)
    }

    static func event(
        _ name: String,
        fields: @autoclosure () -> [String: String] = [:],
        flush: Bool = true
    ) {
        guard isEnabled else { return }
        let fields = fields()

        var orderedFields: [(String, String)] = [("event", name)]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            orderedFields.append((key, value))
        }

        let message = orderedFields
            .map { "\($0.0)=\(escapedValue($0.1))" }
            .joined(separator: " ")

        ShatlFileLogger.snapshotDiagnostics.write(
            level: .notice,
            category: "Snapshot",
            message: message,
            flush: flush
        )
    }

    private static func escapedValue(_ value: String) -> String {
        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\"" || character == "\\"
        }

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

nonisolated enum ShatlAddTorrentReviewDiagnosticsLog {
    static var isEnabled: Bool {
        ShatlFileLogger.addTorrentReviewDiagnostics.loggingEnabled
    }

    static func setEnabled(_ enabled: Bool) {
        ShatlFileLogger.addTorrentReviewDiagnostics.setEnabled(enabled)
    }

    static func event(
        _ name: String,
        fields: @autoclosure () -> [String: String] = [:],
        flush: Bool = false
    ) {
        guard isEnabled else { return }
        let fields = fields()

        var orderedFields: [(String, String)] = [("event", name)]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            orderedFields.append((key, value))
        }

        let message = orderedFields
            .map { "\($0.0)=\(escapedValue($0.1))" }
            .joined(separator: " ")

        ShatlFileLogger.addTorrentReviewDiagnostics.write(
            level: .notice,
            category: "AddTorrentReview",
            message: message,
            flush: flush
        )
    }

    private static func escapedValue(_ value: String) -> String {
        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\"" || character == "\\"
        }

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

nonisolated struct ShatlLog: Sendable {
    static let appStore = ShatlLog(category: "AppStore")
    static let trace = ShatlLog(category: "Trace")
    static let bridge = ShatlLog(category: "Bridge")
    static let payload = ShatlLog(category: "Payload")
    static let ui = ShatlLog(category: "UI")

    private let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: "mamontov.design.shatl", category: category)
    }

    func debug(_ message: @autoclosure () -> String) {
        emit(level: .debug, message)
    }

    func criticalDebug(_ message: @autoclosure () -> String) {
        emit(level: .debug, message, flush: true)
    }

    func info(_ message: @autoclosure () -> String) {
        emit(level: .info, message)
    }

    func criticalInfo(_ message: @autoclosure () -> String) {
        emit(level: .info, message, flush: true)
    }

    func notice(_ message: @autoclosure () -> String) {
        emit(level: .notice, message)
    }

    func criticalNotice(_ message: @autoclosure () -> String) {
        emit(level: .notice, message, flush: true)
    }

    func error(_ message: @autoclosure () -> String) {
        emit(level: .error, message)
    }

    func criticalError(_ message: @autoclosure () -> String) {
        emit(level: .error, message, flush: true)
    }

    private func emit(
        level: ShatlLogLevel,
        _ message: () -> String,
        flush: Bool = false
    ) {
        guard ShatlFileLogger.shared.loggingEnabled else { return }
        let message = message()

        switch level {
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .notice:
            osLogger.notice("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        }

        ShatlFileLogger.shared.write(level: level, category: category, message: message, flush: flush)
    }
}

@objc(ShatlSnapshotDiagnosticsBridge)
@objcMembers
final class ShatlSnapshotDiagnosticsBridge: NSObject {
    class func loggingEnabled() -> Bool {
        ShatlSnapshotDiagnosticsLog.isEnabled
    }

    @objc(logWithEvent:fields:flush:)
    class func log(event: String, fields: [String: String], flush: Bool) {
        ShatlSnapshotDiagnosticsLog.event(event, fields: fields, flush: flush)
    }
}

@objc(ShatlDiagnosticsBridge)
@objcMembers
final class ShatlDiagnosticsBridge: NSObject {
    class func loggingEnabled() -> Bool {
        ShatlFileLogger.shared.loggingEnabled
    }

    @objc(logWithCategory:level:message:flush:)
    class func log(category: String, level: String, message: String, flush: Bool) {
        guard let normalizedLevel = ShatlLogLevel(rawValue: level.uppercased()) else { return }

        let logger: ShatlLog
        switch category {
        case "Trace":
            logger = .trace
        case "Bridge":
            logger = .bridge
        case "Payload":
            logger = .payload
        case "AppStore":
            logger = .appStore
        default:
            logger = ShatlLog(category: category)
        }

        switch normalizedLevel {
        case .debug:
            flush ? logger.criticalDebug(message) : logger.debug(message)
        case .info:
            flush ? logger.criticalInfo(message) : logger.info(message)
        case .notice:
            flush ? logger.criticalNotice(message) : logger.notice(message)
        case .error:
            flush ? logger.criticalError(message) : logger.error(message)
        }
    }
}
