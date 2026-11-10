"""Apply a version-checked overlay to Telegram iOS; never silently patch a different revision."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CORE = "submodules/TelegramCore/Sources/"
STATE = CORE + "State/"
MESSAGES = CORE + "TelegramEngine/Messages/"
PEER = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/"


def replacement(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"{label}: expected exactly one anchor, got {text.count(old)}")
    return text.replace(old, new, 1)


def prepare(source: Path, unsigned: bool = False) -> None:
    lock = json.loads((ROOT / "upstream.lock.json").read_text())
    head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if head != lock["commit"]:
        raise ValueError(f"Wrong upstream revision: {head}; required {lock['commit']}")
    if (source / ".ayu-overlay.json").exists():
        raise ValueError("Overlay already applied. Use a fresh checkout to avoid mixing versions.")

    # Validate every anchor before writing anything, so an upstream drift cannot half-apply the overlay.
    edits: dict[str, str] = {}

    def edit(path: str, old: str, new: str) -> None:
        text = edits.get(path)
        if text is None:
            text = (source / path).read_text(encoding="utf-8")
        edits[path] = replacement(text, old, new, path)

    def gate(path: str, signature: str, result: str = "return", option: str = "hideReadReceipts") -> None:
        edit(path, signature, signature + f"\n    if AyuOption.{option}.enabled {{ {result} }}\n")

    edit(STATE + "ManagedAccountPresence.swift",
         "    private func updatePresence(_ isOnline: Bool) {",
         "    private func updatePresence(_ requestedOnline: Bool) {\n        let isOnline = requestedOnline && !AyuOption.hideOnline.enabled")
    gate(STATE + "ManagedLocalInputActivities.swift",
         "private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {",
         "return .complete()", "hideTyping")
    # Preserve local unread counters as well as withholding the server request. A second gate
    # in pushPeerReadState also covers already-queued read operations on enabling the setting.
    for signature, result in [
        ("func _internal_applyMaxReadMessageIdInteractively(postbox: Postbox, stateManager: AccountStateManager, messageId: MessageId) -> Signal<Bool, NoError> {", "return .single(false)"),
        ("func _internal_applyMaxReadIndexInteractively(transaction: Transaction, stateManager: AccountStateManager, index: MessageIndex) {", "return"),
        ("func _internal_toggleForumThreadUnreadMarkInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, threadId: Int64, setToValue: Bool?) {", "return"),
        ("func _internal_markForumThreadAsReadInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, threadId: Int64) {", "return"),
        ("func _internal_togglePeerUnreadMarkInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, setToValue: Bool? = nil) {", "return"),
        ("func _internal_readPeerHistoryToTopInteractively(transaction: Transaction, peer: Peer, principalNamespace: MessageId.Namespace) {", "return"),
        ("func _internal_markAllChatsAsReadInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?) {", "return"),
    ]:
        gate(MESSAGES + "ApplyMaxReadIndexInteractively.swift", signature, result)
    gate(STATE + "SynchronizePeerReadState.swift",
         "private func pushPeerReadState(network: Network, postbox: Postbox, stateManager: AccountStateManager, peerId: PeerId, readState: PeerReadState) -> Signal<PeerReadState, PeerReadStateValidationError> {",
         "return .single(readState)")
    gate(MESSAGES + "MarkAllChatsAsRead.swift",
         "func _internal_markAllChatsAsRead(postbox: Postbox, network: Network, stateManager: AccountStateManager) -> Signal<Void, NoError> {",
         "return .complete()")
    gate(MESSAGES + "ReplyThreadHistory.swift", "    func applyMaxReadIndex(messageIndex: MessageIndex) {")

    for path, signature in [
        (STATE + "ManagedSynchronizeConsumeMessageContentsOperations.swift", "private func synchronizeConsumeMessageContents(transaction: Transaction, network: Network, stateManager: AccountStateManager, peerId: PeerId, operation: SynchronizeConsumeMessageContentsOperation) -> Signal<Void, NoError> {"),
        (STATE + "ManagedConsumePersonalMessagesActions.swift", "private func synchronizeConsumeMessageContents(transaction: Transaction, postbox: Postbox, network: Network, stateManager: AccountStateManager, id: MessageId) -> Signal<Void, NoError> {"),
        (STATE + "ManagedConsumePersonalMessagesActions.swift", "private func synchronizeReadMessageReactionsOrPollVotes(transaction: Transaction, postbox: Postbox, network: Network, stateManager: AccountStateManager, id: MessageId) -> Signal<Void, NoError> {"),
    ]:
        gate(path, signature, "return .complete()")
    gate(STATE + "AccountViewTracker.swift", "    public func updateSeenLiveLocationForMessageIds(messageIds: Set<MessageId>) {")

    # Snapshot old cloud text before server edits/deletions. Keep official deletion/replay and
    # state advancement intact. This is an archive, not resurrected messages in Postbox.
    edit(STATE + "Sync/StateReplay+Messages.swift", "    func applyDeleteMessagesWithGlobalIds(_ ids: [Int32]) {",
         "    func applyDeleteMessagesWithGlobalIds(_ ids: [Int32]) {\n        ayuCaptureMessages(transaction: transaction, accountPeerId: accountPeerId, ids: transaction.messageIdsForGlobalIds(ids), kind: \"deleted\")")
    edit(STATE + "Sync/StateReplay+Messages.swift", "    func applyDeleteMessages(_ ids: [MessageId]) {",
         "    func applyDeleteMessages(_ ids: [MessageId]) {\n        ayuCaptureMessages(transaction: transaction, accountPeerId: accountPeerId, ids: ids, kind: \"deleted\")")
    edit(STATE + "Sync/StateReplay+Messages.swift", "    func applyEditMessage(_ id: MessageId, _ message: StoreMessage) {",
         "    func applyEditMessage(_ id: MessageId, _ message: StoreMessage) {\n        if let previous = transaction.getMessage(id), previous.text != message.text {\n            ayuCaptureMessages(transaction: transaction, accountPeerId: accountPeerId, ids: [id], kind: \"edited\")\n        }")

    # Hide cached as well as freshly-fetched ads. Reopening the app recreates ad contexts.
    edit(MESSAGES + "AdMessages.swift", "        if messageId == nil {\n            self.state.set(CachedState.getCached",
         "        if !AyuOption.hideAds.enabled && messageId == nil {\n            self.state.set(CachedState.getCached")
    edit(MESSAGES + "AdMessages.swift", "    func activate() {\n        if self.isActivated {",
         "    func activate() {\n        if AyuOption.hideAds.enabled {\n            self.stateValue = State(interPostInterval: nil, messages: [])\n            return\n        }\n        if self.isActivated {")

    edit(PEER + "PeerInfoScreen.swift", "enum PeerInfoSettingsSection {\n", "enum PeerInfoSettingsSection {\n    case ayuPersonal\n")
    edit(PEER + "PeerInfoSettingsItems.swift", "    let notificationsWarning: Bool\n",
         "    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 9001, text: \"Ayu Personal\", icon: PresentationResourcesSettings.security, action: {\n        interaction.openSettings(.ayuPersonal)\n    }))\n\n    let notificationsWarning: Bool\n")
    edit(PEER + "PeerInfoScreenSettingsActions.swift", "        switch section {\n        case .avatar:",
         "        switch section {\n        case .ayuPersonal:\n            let settings = AyuSettingsController(accountId: self.context.account.peerId.toInt64())\n            let navigation = UINavigationController(rootViewController: settings)\n            self.controller?.present(navigation, animated: true)\n        case .avatar:")

    edit("Telegram/BUILD", "    <string>Telegram</string>\n    <key>CFBundleIdentifier</key>\n    <string>{telegram_bundle_id}</string>",
         "    <string>Ayu Personal</string>\n    <key>CFBundleIdentifier</key>\n    <string>{telegram_bundle_id}</string>")
    edit("Telegram/BUILD", 'name = "AppNameInfoPlist",\n    extension = "plist",\n    template =\n    """\n    <key>CFBundleDisplayName</key>\n    <string>Telegram</string>',
         'name = "AppNameInfoPlist",\n    extension = "plist",\n    template =\n    """\n    <key>CFBundleDisplayName</key>\n    <string>Ayu Personal</string>')
    icon = "Telegram/Telegram-iOS/Telegram.icon/icon.json"
    edit(icon, "display-p3:0.21569,0.68627,0.89020,1.00000", "display-p3:0.58039,0.32549,0.92157,1.00000")
    edit(icon, "srgb:0.11373,0.57647,0.82353,1.00000", "srgb:0.29020,0.16078,0.60784,1.00000")
    edit(icon, "srgb:0.00000,0.47843,1.00000,1.00000", "srgb:0.44314,0.26275,0.82745,1.00000")

    if unsigned:
        # A separate, opt-in build mode; never disable signing for normal Telegram builds.
        # rules_apple's disable_legacy_signing bypasses signing and profile validation. GBox
        # must later provide a valid device signature and matching entitlement profile.
        edit("build-system/Make/Make.py", "        self.common_build_args = [\n        ]",
             "        self.common_build_args = [\n            '--//Telegram:disableProvisioningProfiles',\n            '--//Telegram:disableExtensions',\n            '--features=disable_legacy_signing',\n        ]")

    docs = "docs/state-sync.md"
    if (source / docs).exists():
        edits[docs] = (source / docs).read_text(encoding="utf-8") + "\n\n## Personal Ayu overlay\n\nCloud deletion and edit replays enqueue immutable text snapshots for an account-scoped local archive before applying official operations. The overlay never retains a transaction or changes state advancement. The archive is asynchronous, bounded, excluded from backup, and can lose queued snapshots on process termination. It covers explicit deletion/edit updates; bulk history clearing, gap reconciliation, media and secret chats are not archived. Read/privacy gates are opt-in; with them off the original paths execute. See the overlay repository for the feature matrix and validation status.\n"

    copies = {CORE + name: ROOT / "Sources" / name for name in ["AyuSettings.swift", "AyuHistoryStore.swift", "AyuHistoryBridge.swift"]}
    copies[PEER + "AyuSettingsController.swift"] = ROOT / "Sources/AyuSettingsController.swift"
    copies["Telegram/Telegram-iOS/Telegram.icon/Assets/Plane.svg"] = ROOT / "Sources/AyuMark.svg"
    for path, contents in edits.items():
        (source / path).write_text(contents, encoding="utf-8", newline="\n")
    for destination, origin in copies.items():
        (source / destination).parent.mkdir(parents=True, exist_ok=True)
        (source / destination).write_text(origin.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    (source / ".ayu-overlay.json").write_text(json.dumps({"upstream": head, "unsigned": unsigned}, indent=2), encoding="utf-8")
    print(f"Applied overlay: {len(edits)} edited files, {len(copies)} added files; upstream {head}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--unsigned", action="store_true")
    args = parser.parse_args()
    prepare(args.source.resolve(), args.unsigned)
