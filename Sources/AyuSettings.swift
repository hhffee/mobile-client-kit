import Foundation

/// Installation-wide preferences. Message archives are always separated by account.
public enum AyuOption: String, CaseIterable {
    case hideOnline, hideTyping, hideReadReceipts, saveDeleted, saveEdits, hideAds, saveDisappearingMedia

    public var enabled: Bool {
        let key = "personal.ayu.\(self.rawValue)"
        if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            return value
        }
        switch self {
        case .saveDeleted, .saveEdits, .hideAds, .saveDisappearingMedia: return true
        default: return false
        }
    }

    public func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "personal.ayu.\(self.rawValue)")
    }
}

/// Local counters contain no message text, identifiers or account credentials.
public enum AyuLocalDiagnostics {
    private static let lock = NSLock()
    public static func increment(_ name: String, by count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let key = "karigram.diagnostics." + name
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + count, forKey: key)
    }
    public static var summary: String {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        return "Удалений получено: \(defaults.integer(forKey: "karigram.diagnostics.deleteRequested"))\nСообщений найдено: \(defaults.integer(forKey: "karigram.diagnostics.deleteFound"))\nОставлено в чате: \(defaults.integer(forKey: "karigram.diagnostics.deleteRetained"))\nСохранение включено: \(AyuOption.saveDeleted.enabled ? "да" : "нет")"
    }
}

