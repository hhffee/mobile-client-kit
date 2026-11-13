import Foundation
import Security
import UIKit

// An unsigned, single-app build may be signed without App Group entitlements.
// Keep its database in the app sandbox and its credentials in an explicit,
// OS-assigned keychain group. Never fall back after a keychain read failure.
struct AyuStartupStorage {
    // A noninteractive overlay leaves Telegram's window/controller ownership intact.
    // Stage names contain no account, session, or message data.
    private static var startupView: UITextView?
    private static var stage = ""
    private static var startedAt = Date()

    static func begin(in window: UIWindow) {
        startedAt = Date()
        let text = UITextView()
        text.isEditable = false
        text.isUserInteractionEnabled = false
        text.backgroundColor = .systemBackground
        text.textColor = .label
        text.font = .preferredFont(forTextStyle: .body)
        text.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            text.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 16),
            text.heightAnchor.constraint(equalToConstant: 240)
        ])
        startupView = text
        mark("window-created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            guard let text = startupView else { return }
            text.text = diagnosticText + "\n\nЗапуск ещё не завершён. Сохрани снимок этого экрана для диагностики."
            window.bringSubviewToFront(text)
        }
    }

    private static var diagnosticText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "Ayu Personal · запуск\n\nЭтап: \(stage)\nСборка: \(version)\niOS: \(UIDevice.current.systemVersion)\nВремя: \(Int(Date().timeIntervalSince(startedAt))) с"
    }

    static func mark(_ value: String) {
        stage = value
        startupView?.text = diagnosticText
        NSLog("[AyuStartup] %@", value)
    }

    static func finish() {
        mark("interface-ready")
        startupView?.removeFromSuperview()
        startupView = nil
    }

    let url: URL
    let isolatedKeychainAccessGroup: String?

    static func resolve(appGroupName: String) throws -> AyuStartupStorage {
        let manager = FileManager.default
        let defaults = UserDefaults.standard
        let privateModeKey = "AyuPersonal.privateStorage.v1"
        if !defaults.bool(forKey: privateModeKey),
           let shared = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) {
            return AyuStartupStorage(url: shared, isolatedKeychainAccessGroup: nil)
        }

        // Ask Security for the actual signing profile's default group, which
        // may differ from TEAM_ID + bundle identifier after GBox re-signing.
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "AyuPersonal.startup-probe",
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data([0])
        ]
        var insertion = probe
        insertion[kSecReturnAttributes as String] = true
        var attributes: CFTypeRef?
        let status = SecItemAdd(insertion as CFDictionary, &attributes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        defer {
            var removal = probe
            removal.removeValue(forKey: kSecValueData as String)
            removal.removeValue(forKey: kSecAttrAccessible as String)
            SecItemDelete(removal as CFDictionary)
        }
        guard let group = (attributes as? [String: Any])?[kSecAttrAccessGroup as String] as? String,
              !group.isEmpty, !group.hasPrefix("group.") else {
            throw NSError(domain: "AyuPersonal.Startup", code: 1)
        }
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("AyuPersonal", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        // Keep the same storage on later launches, even if a new signature
        // acquires App Groups. Do not switch away from existing account data.
        defaults.set(true, forKey: privateModeKey)
        return AyuStartupStorage(url: directory, isolatedKeychainAccessGroup: group)
    }

    static func showFailure(_ error: Error, in window: UIWindow?) {
        guard let window = window else { return }
        finish()
        let failure = error as NSError
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let text = UITextView()
        text.isEditable = false
        text.font = .preferredFont(forTextStyle: .body)
        text.text = "Ayu Personal\n\nНе удалось открыть защищённое хранилище.\n\nКод: \(failure.domain) \(failure.code)\nПриложение: \(Bundle.main.bundleIdentifier ?? "unknown")\niOS: \(UIDevice.current.systemVersion)\n\nСделай снимок этого экрана и пришли его для исправления."
        text.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            text.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            text.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 24),
            text.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }
}

