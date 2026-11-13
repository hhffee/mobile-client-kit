let defaults = UserDefaults.standard
let key = "personal.ayu.saveDeleted"
let mediaKey = "personal.ayu.saveDisappearingMedia"
defaults.set(true, forKey: key)
defaults.set(true, forKey: mediaKey)
defer { defaults.removeObject(forKey: key); defaults.removeObject(forKey: mediaKey) }

let transaction = Transaction()
let textId = MessageId(namespace: 0, id: 1)
let fileId = MessageId(namespace: 0, id: 2)
let serviceId = MessageId(namespace: 0, id: 3)
let missingId = MessageId(namespace: 0, id: 4)
let localId = MessageId(namespace: 99, id: 5)
let file = TelegramMediaFile()
transaction.messages[textId] = Message(id: textId, text: "hello", media: [])
transaction.messages[fileId] = Message(id: fileId, text: "", attributes: [AyuMessageRetentionAttribute(mediaTimeout: 2147483647)], media: [file])
transaction.messages[serviceId] = Message(id: serviceId, text: "", media: [TelegramMediaAction()])
transaction.messages[localId] = Message(id: localId, text: "local", media: [])
let kept = ayuRetainDeletedMessages(transaction: transaction, ids: [textId, textId, fileId, serviceId, missingId, localId])
precondition(kept == Set([textId, fileId]), "Only existing cloud content is retained")
let stored = transaction.updates[fileId]!
precondition(stored.media.first === file, "Retain the actual media, not a text placeholder")
precondition(stored.id == fileId && stored.timestamp == 123 && stored.authorId == 42)
precondition(stored.groupingKey == 55 && stored.threadId == 33 && stored.flags.contains(.Incoming))
let marker = stored.attributes.first as! AyuMessageRetentionAttribute
precondition(marker.deletedAt != nil && marker.mediaTimeout == 2147483647)
let encoder = PostboxEncoder()
marker.encode(encoder)
let decoded = AyuMessageRetentionAttribute(decoder: PostboxDecoder(encoder.values))
precondition(decoded.deletedAt == marker.deletedAt && decoded.mediaTimeout == marker.mediaTimeout)
_ = ayuRetainDeletedMessages(transaction: transaction, ids: [fileId])
let repeated = transaction.updates[fileId]!.attributes.compactMap { $0 as? AyuMessageRetentionAttribute }
precondition(repeated.count == 1 && repeated[0].deletedAt == marker.deletedAt)
defaults.set(false, forKey: key)
precondition(ayuRetainDeletedMessages(transaction: transaction, ids: [textId]).isEmpty)
precondition(ayuCloudMediaTimeoutAttribute(timeout: 7) is AyuMessageRetentionAttribute)
defaults.set(false, forKey: mediaKey)
precondition(ayuCloudMediaTimeoutAttribute(timeout: 7) is AutoclearTimeoutMessageAttribute)
print("PASS: retained bubbles, media identity, persisted markers, replay idempotence, option gates")

