import Foundation
import Postbox

func ayuCaptureMessages(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId], kind: String) {
    let option: AyuOption = kind == "deleted" ? .saveDeleted : .saveEdits
    guard option.enabled else { return }
    let records = ids.compactMap { id -> AyuHistoryRecord? in
        guard let message = transaction.getMessage(id), id.namespace == Namespaces.Message.Cloud else { return nil }
        return AyuHistoryRecord(accountId: accountPeerId.toInt64(), peerId: id.peerId.toInt64(),
            namespace: id.namespace, messageId: id.id, authorId: message.author?.id.toInt64(),
            sentAt: message.timestamp, kind: kind, text: message.text, hasMedia: !message.media.isEmpty)
    }
    AyuHistoryStore.shared.append(records)
}
