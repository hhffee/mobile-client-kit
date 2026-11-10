import Foundation

public struct AyuHistoryRecord: Codable, Sendable {
    public let accountId: Int64
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public let authorId: Int64?
    public let sentAt: Int32
    public let capturedAt: Double
    public let kind: String
    public let text: String
    public let hasMedia: Bool

    public init(accountId: Int64, peerId: Int64, namespace: Int32, messageId: Int32,
                authorId: Int64?, sentAt: Int32, kind: String, text: String, hasMedia: Bool) {
        self.accountId = accountId
        self.peerId = peerId
        self.namespace = namespace
        self.messageId = messageId
        self.authorId = authorId
        self.sentAt = sentAt
        self.capturedAt = Date().timeIntervalSince1970
        self.kind = kind
        self.text = text
        self.hasMedia = hasMedia
    }
}

/// Independent of the Telegram cache. No network, shared container or credentials.
/// All disk work is serialized; replay only passes immutable snapshots to this queue.
public final class AyuHistoryStore: @unchecked Sendable {
    public static let shared = AyuHistoryStore()
    private let queue = DispatchQueue(label: "personal.ayu.history", qos: .utility)
    private let root: URL
    private let maxBytes = 8 * 1024 * 1024
    private var lastErrors: [Int64: String] = [:]

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalAyuHistory", isDirectory: true)
    }

    private func file(_ accountId: Int64) -> URL {
        return self.root.appendingPathComponent("\(accountId).jsonl")
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var url = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    private func read(_ accountId: Int64) throws -> [AyuHistoryRecord] {
        let url = self.file(accountId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        // A crash can leave one partial trailing line; older records remain readable.
        return data.split(separator: 10).compactMap { try? decoder.decode(AyuHistoryRecord.self, from: Data($0)) }
            .filter { $0.accountId == accountId }
    }

    public func append(_ records: [AyuHistoryRecord]) {
        guard !records.isEmpty else { return }
        self.queue.async {
            for (accountId, batch) in Dictionary(grouping: records, by: { $0.accountId }) {
                do {
                    try self.prepareDirectory()
                    let url = self.file(accountId)
                    var data = Data()
                    for record in batch {
                        data.append(try JSONEncoder().encode(record))
                        data.append(10)
                    }
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try Data().write(to: url, options: .atomic)
                        try self.protect(url)
                    }
                    let handle = try FileHandle(forUpdating: url)
                    defer { try? handle.close() }
                    let end = try handle.seekToEnd()
                    if end > 0 {
                        try handle.seek(toOffset: end - 1)
                        let last = try handle.read(upToCount: 1)
                        try handle.seekToEnd()
                        if last != Data([10]) { try handle.write(contentsOf: Data([10])) }
                    }
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                    if size > self.maxBytes {
                        var lines: [Data] = []
                        var totalBytes = 0
                        for record in try self.read(accountId).suffix(2000).reversed() {
                            var line = try JSONEncoder().encode(record)
                            line.append(10)
                            if totalBytes + line.count > self.maxBytes / 2 { break }
                            lines.append(line)
                            totalBytes += line.count
                        }
                        var compacted = Data()
                        for line in lines.reversed() { compacted.append(line) }
                        try compacted.write(to: url, options: .atomic)
                        try self.protect(url)
                    }
                    self.lastErrors[accountId] = nil
                } catch {
                    self.lastErrors[accountId] = error.localizedDescription
                }
            }
        }
    }

    public func load(accountId: Int64, completion: @escaping ([AyuHistoryRecord], String?) -> Void) {
        self.queue.async {
            do {
                let records = Array(try self.read(accountId).suffix(2000).reversed())
                let error = self.lastErrors[accountId]
                DispatchQueue.main.async { completion(records, error) }
            } catch {
                let description = error.localizedDescription
                DispatchQueue.main.async { completion([], description) }
            }
        }
    }

    public func clear(accountId: Int64, completion: @escaping (String?) -> Void) {
        self.queue.async {
            do {
                let url = self.file(accountId)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                self.lastErrors[accountId] = nil
                DispatchQueue.main.async { completion(nil) }
            } catch {
                let description = error.localizedDescription
                DispatchQueue.main.async { completion(description) }
            }
        }
    }
}
