import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let store = AyuHistoryStore(root: root)
func record(_ account: Int64, _ text: String) -> AyuHistoryRecord {
    return AyuHistoryRecord(accountId: account, peerId: 42, namespace: 0, messageId: 7,
        authorId: 5, sentAt: 100, kind: "deleted", text: text, hasMedia: false)
}
func loaded(_ store: AyuHistoryStore, _ account: Int64) -> [AyuHistoryRecord] {
    var answer: [AyuHistoryRecord]?
    store.load(accountId: account) { records, error in
        precondition(error == nil, "Archive error: \(error ?? "")")
        answer = records
    }
    let deadline = Date().addingTimeInterval(15)
    while answer == nil && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(answer != nil, "Archive callback timed out")
    return answer!
}
store.append([record(1, "first 🐈"), record(2, "separate account"), record(1, "second")])
precondition(loaded(store, 1).map { $0.text } == ["second", "first 🐈"])
let reopened = AyuHistoryStore(root: root)
precondition(loaded(reopened, 2).map { $0.text } == ["separate account"])
// A crash-truncated JSONL tail must not destroy older records.
let path = root.appendingPathComponent("1.jsonl")
let handle = try FileHandle(forWritingTo: path)
try handle.seekToEnd()
try handle.write(contentsOf: Data("{incomplete".utf8))
try handle.close()
precondition(loaded(store, 1).count == 2)
store.append([record(1, "after crash")])
precondition(loaded(store, 1).map { $0.text } == ["after crash", "second", "first 🐈"])
var cleared = false
store.clear(accountId: 1) { error in precondition(error == nil); cleared = true }
let deadline = Date().addingTimeInterval(15)
while !cleared && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
precondition(cleared)
precondition(loaded(store, 1).isEmpty)
precondition(loaded(store, 2).count == 1)
// Rotation is bounded even when text is much larger than a typical message.
store.append((0..<3000).map { record(3, "\($0):" + String(repeating: "x", count: 5000)) })
let retained = loaded(store, 3)
precondition(!retained.isEmpty && retained.count <= 2000)
let bytes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("3.jsonl").path)[.size] as! NSNumber
precondition(bytes.intValue <= 8 * 1024 * 1024)
print("Archive checks passed: persistence, account isolation, Unicode, crash tail, clearing, bounded rotation")
