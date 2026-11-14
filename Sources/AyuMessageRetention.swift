import Foundation
import Postbox
import SwiftSignalKit

/// Local metadata only. Never serialized into a Telegram API request.
public final class AyuMessageRetentionAttribute: MessageAttribute {
    public let deletedAt: Int32?
    public let mediaTimeout: Int32?
    public var associatedMessageIds: [MessageId] { return [] }

    public init(deletedAt: Int32? = nil, mediaTimeout: Int32? = nil) {
        self.deletedAt = deletedAt
        self.mediaTimeout = mediaTimeout
    }

    public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeOptionalInt32ForKey("d")
        self.mediaTimeout = decoder.decodeOptionalInt32ForKey("m")
    }

    public func encode(_ encoder: PostboxEncoder) {
        if let value = self.deletedAt { encoder.encodeInt32(value, forKey: "d") } else { encoder.encodeNil(forKey: "d") }
        if let value = self.mediaTimeout { encoder.encodeInt32(value, forKey: "m") } else { encoder.encodeNil(forKey: "m") }
    }
}

/// Only preserve messages already present on this device. Keep their real id,
/// author, timestamp, grouping and media so existing bubbles and viewers apply.
func ayuRetainDeletedMessages(transaction: Transaction, ids: [MessageId]) -> Set<MessageId> {
    AyuLocalDiagnostics.increment("deleteRequested", by: ids.count)
    AyuLocalDiagnostics.increment("deleteFound", by: ids.filter { transaction.getMessage($0) != nil }.count)
    guard AyuOption.saveDeleted.enabled else { return [] }
    var retained = Set<MessageId>()
    for id in Set(ids) {
        guard id.namespace == Namespaces.Message.Cloud, let message = transaction.getMessage(id),
              !message.media.contains(where: { $0 is TelegramMediaAction }),
              !message.text.isEmpty || !message.media.isEmpty else { continue }
        transaction.updateMessage(id, update: { current in
            let previous = current.attributes.compactMap { $0 as? AyuMessageRetentionAttribute }.first
            var attributes = current.attributes.filter { !($0 is AyuMessageRetentionAttribute) }
            attributes.append(AyuMessageRetentionAttribute(
                deletedAt: previous?.deletedAt ?? Int32(Date().timeIntervalSince1970),
                mediaTimeout: previous?.mediaTimeout))
            let forward = current.forwardInfo.map {
                StoreMessageForwardInfo(authorId: $0.author?.id, sourceId: $0.source?.id,
                    sourceMessageId: $0.sourceMessageId, date: $0.date, authorSignature: $0.authorSignature,
                    psaType: $0.psaType, flags: $0.flags)
            }
            return .update(StoreMessage(id: current.id, customStableId: nil,
                globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey,
                threadId: current.threadId, timestamp: current.timestamp,
                flags: StoreMessageFlags(current.flags), tags: current.tags,
                globalTags: current.globalTags, localTags: current.localTags,
                forwardInfo: forward, authorId: current.author?.id, text: current.text,
                attributes: attributes, media: current.media))
        })
        retained.insert(id)
    }
    AyuLocalDiagnostics.increment("deleteRetained", by: retained.count)
    return retained
}

/// Cloud media only. Removing the local self-destruct attribute makes the
/// ordinary photo/file/instant-video viewer apply; it does not restore bytes
/// already removed by the server or keep resources through explicit cache clearing.
func ayuCloudMediaTimeoutAttribute(timeout: Int32) -> MessageAttribute {
    if AyuOption.saveDisappearingMedia.enabled {
        return AyuMessageRetentionAttribute(mediaTimeout: timeout)
    }
    return AutoclearTimeoutMessageAttribute(timeout: timeout, countdownBeginTime: nil)
}

/// Upgrade path for timed media already in Postbox before this build was installed.
/// Replacing the timeout attribute also removes its timestamp-queue entry.
func ayuRetainTimedMedia(transaction: Transaction, id: MessageId) -> Bool {
    guard AyuOption.saveDisappearingMedia.enabled, id.namespace == Namespaces.Message.Cloud,
          let message = transaction.getMessage(id),
          message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }),
          let timer = message.attributes.first(where: { $0 is AutoclearTimeoutMessageAttribute }) as? AutoclearTimeoutMessageAttribute else { return false }
    transaction.updateMessage(id, update: { current in
        let previous = current.attributes.compactMap { $0 as? AyuMessageRetentionAttribute }.first
        var attributes = current.attributes.filter { !($0 is AutoclearTimeoutMessageAttribute) && !($0 is AyuMessageRetentionAttribute) }
        attributes.append(AyuMessageRetentionAttribute(deletedAt: previous?.deletedAt, mediaTimeout: timer.timeout))
        let forward = current.forwardInfo.map {
            StoreMessageForwardInfo(authorId: $0.author?.id, sourceId: $0.source?.id,
                sourceMessageId: $0.sourceMessageId, date: $0.date, authorSignature: $0.authorSignature,
                psaType: $0.psaType, flags: $0.flags)
        }
        return .update(StoreMessage(id: current.id, customStableId: nil,
            globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey,
            threadId: current.threadId, timestamp: current.timestamp,
            flags: StoreMessageFlags(current.flags), tags: current.tags,
            globalTags: current.globalTags, localTags: current.localTags,
            forwardInfo: forward, authorId: current.author?.id, text: current.text,
            attributes: attributes, media: current.media))
    })
    return true
}

/// Begin fetching newly received timed media before it can disappear remotely.
/// Work runs outside the Postbox transaction. Normal MediaBox fetches coalesce
/// duplicate resource requests; failed downloads are not claimed as saved.
func ayuPrefetchTimedMedia(mediaBox: MediaBox, messages: [StoreMessage]) {
    guard AyuOption.saveDisappearingMedia.enabled else { return }
    var resources: [MediaResource] = []
    for message in messages {
        guard message.flags.contains(.Incoming),
              message.attributes.contains(where: { ($0 as? AyuMessageRetentionAttribute)?.mediaTimeout != nil }) else { continue }
        for media in message.media {
            if let image = media as? TelegramMediaImage, let representation = image.representations.last {
                resources.append(representation.resource)
            } else if let file = media as? TelegramMediaFile {
                resources.append(file.resource)
            }
        }
    }
    guard !resources.isEmpty else { return }
    let pending = resources
    DispatchQueue.global(qos: .utility).async {
        for resource in pending {
            _ = mediaBox.fetchedResource(resource, parameters: nil).startStandalone(error: { _ in })
        }
    }
}

