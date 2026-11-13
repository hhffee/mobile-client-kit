import Foundation

// In-memory Postbox boundary for exercising the production retention code.
// No copy of its retention decisions lives in this fixture.
public struct MessageId: Hashable { let namespace: Int32; let id: Int32 }
public protocol MessageAttribute: AnyObject {
    init(decoder: PostboxDecoder)
    func encode(_ encoder: PostboxEncoder)
}
public final class PostboxEncoder {
    var values: [String: Int32] = [:]
    func encodeInt32(_ value: Int32, forKey key: String) { values[key] = value }
    func encodeNil(forKey key: String) { values.removeValue(forKey: key) }
}
public final class PostboxDecoder {
    let values: [String: Int32]
    init(_ values: [String: Int32]) { self.values = values }
    func decodeOptionalInt32ForKey(_ key: String) -> Int32? { values[key] }
}
public struct StoreMessageFlags: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    init(_ other: StoreMessageFlags) { self = other }
    static let Incoming = StoreMessageFlags(rawValue: 1)
}
public class Media {}
public class TelegramMediaAction: Media {}
public class MediaResource {}
public struct Representation { let resource: MediaResource }
public class TelegramMediaImage: Media { var representations: [Representation] = [] }
public class TelegramMediaFile: Media { let resource = MediaResource() }
public struct Peer { let id: Int64 }
public struct Forward {
    let author: Peer?; let source: Peer?; let sourceMessageId: MessageId?
    let date: Int32; let authorSignature: String?; let psaType: String?; let flags: Int
}
public struct StoreMessageForwardInfo {
    let authorId: Int64?; let sourceId: Int64?; let sourceMessageId: MessageId?
    let date: Int32; let authorSignature: String?; let psaType: String?; let flags: Int
}
public struct Message {
    let id: MessageId
    let globallyUniqueId: Int64? = 77
    let groupingKey: Int64? = 55
    let threadId: Int64? = 33
    let timestamp: Int32 = 123
    let flags: StoreMessageFlags = .Incoming
    let tags = 1; let globalTags = 2; let localTags = 3
    var forwardInfo: Forward? = nil
    let author: Peer? = Peer(id: 42)
    let text: String
    var attributes: [MessageAttribute] = []
    let media: [Media]
}
public struct StoreMessage {
    let id: MessageId; let customStableId: UInt32?; let globallyUniqueId: Int64?
    let groupingKey: Int64?; let threadId: Int64?; let timestamp: Int32
    let flags: StoreMessageFlags; let tags: Int; let globalTags: Int; let localTags: Int
    let forwardInfo: StoreMessageForwardInfo?; let authorId: Int64?; let text: String
    let attributes: [MessageAttribute]; let media: [Media]
}
public enum UpdateMessage { case update(StoreMessage) }
public final class Transaction {
    var messages: [MessageId: Message] = [:]
    var updates: [MessageId: StoreMessage] = [:]
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func updateMessage(_ id: MessageId, update: (Message) -> UpdateMessage) {
        guard var previous = messages[id] else { return }
        if case let .update(stored) = update(previous) {
            updates[id] = stored
            previous.attributes = stored.attributes
            messages[id] = previous
        }
    }
}
public protocol Disposable { func dispose() }
private final class FakeDisposable: Disposable { func dispose() {} }
public final class FakeFetch {
    // Matches the pinned SwiftSignalKit Signal.startStandalone return contract.
    func startStandalone(error: (Error) -> Void) -> Disposable { FakeDisposable() }
}
public final class MediaBox {
    func fetchedResource(_ resource: MediaResource, parameters: Int?) -> FakeFetch { FakeFetch() }
}
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }
public final class AutoclearTimeoutMessageAttribute: MessageAttribute {
    let timeout: Int32
    init(timeout: Int32, countdownBeginTime: Int32?) { self.timeout = timeout }
    public init(decoder: PostboxDecoder) { timeout = 0 }
    public func encode(_ encoder: PostboxEncoder) {}
}

