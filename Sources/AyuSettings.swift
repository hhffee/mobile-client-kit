import Foundation

/// Installation-wide preferences. Message archives are always separated by account.
public enum AyuOption: String, CaseIterable {
    case hideOnline, hideTyping, hideReadReceipts, saveDeleted, saveEdits, hideAds

    public var enabled: Bool {
        let key = "personal.ayu.\(self.rawValue)"
        if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            return value
        }
        switch self {
        case .saveDeleted, .saveEdits, .hideAds: return true
        default: return false
        }
    }

    public func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "personal.ayu.\(self.rawValue)")
    }
}
