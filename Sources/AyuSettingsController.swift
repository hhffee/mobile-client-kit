import Foundation
import UIKit
import TelegramCore

final class AyuSettingsController: UITableViewController {
    private let accountId: Int64
    private let options: [(AyuOption, String, String)] = [
        (.hideOnline, "Скрывать онлайн", "Не отправлять запрос «онлайн». Отправка сообщений может раскрывать активность."),
        (.hideTyping, "Скрывать набор и запись", "Не отправлять индикаторы набора, записи и загрузки."),
        (.hideReadReceipts, "Не отмечать чаты прочитанными", "Блокирует локальное прочтение чатов и комментариев. Другие устройства работают независимо."),
        (.saveDeleted, "Сохранять удалённые сообщения", "Оставлять полученные облачные сообщения в переписке с отметкой корзины у времени."),
        (.saveDisappearingMedia, "Сохранять исчезающие медиа", "Открывать полученные облачные фото, видео и кружки как обычные медиа. Не восстанавливает уже исчезнувшие файлы. Включай до получения сообщения."),
        (.saveEdits, "Сохранять версии текста", "Сохранять текст перед полученной правкой сообщения."),
        (.hideAds, "Скрывать рекламу Telegram", "Не загружать рекламные сообщения каналов. Перезапусти приложение после изменения.")
    ]

    init(accountId: Int64) {
        self.accountId = accountId
        super.init(style: .insetGrouped)
        self.title = "karigram"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
    }
    @objc private func close() { self.dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { return 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? self.options.count : (section == 1 ? 2 : 1)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return ["Приватность и история", "Архив этого аккаунта", "О приложении"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "После изменения невидимки перезапусти приложение: уже отправленные запросы отменить нельзя. Настройки действуют на все аккаунты этой установки." }
        if section == 1 { return "Архив хранит только текст, отдельно от кэша, на этом устройстве. При размере больше 8 МБ остаются последние 2000 записей. Секретные чаты и медиа не архивируются. Архив остаётся после выхода из аккаунта — очисти его здесь перед выходом." }
        return "Личный неофициальный клиент на базе Telegram iOS. AyuSync, сохранение медиа, локальный Premium и остальные функции AyuGram пока не перенесены. Push-уведомления зависят от профиля подписи и собственного push-сервиса."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        if indexPath.section == 0 {
            let (option, title, detail) = self.options[indexPath.row]
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = detail
            let control = UISwitch()
            control.isOn = option.enabled
            control.tag = indexPath.row
            control.accessibilityLabel = title
            control.addTarget(self, action: #selector(toggle(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none
        } else if indexPath.section == 1 {
            cell.textLabel?.text = indexPath.row == 0 ? "Открыть историю" : "Очистить историю"
            cell.textLabel?.textColor = indexPath.row == 0 ? .label : .systemRed
            cell.accessoryType = indexPath.row == 0 ? .disclosureIndicator : .none
        } else {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            cell.textLabel?.text = "karigram · сборка \(version)"
            cell.detailTextLabel?.text = AyuLocalDiagnostics.summary
            cell.selectionStyle = .none
        }
        return cell
    }
    @objc private func toggle(_ control: UISwitch) {
        self.options[control.tag].0.setEnabled(control.isOn)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        if indexPath.row == 0 {
            self.navigationController?.pushViewController(AyuHistoryController(accountId: self.accountId), animated: true)
        } else {
            let alert = UIAlertController(title: "Очистить локальную историю?", message: "Удаляются записи только этого аккаунта. Это действие необратимо.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Очистить", style: .destructive, handler: { [weak self] _ in
                guard let self else { return }
                AyuHistoryStore.shared.clear(accountId: self.accountId) { [weak self] error in
                    if let error { self?.showError(error) }
                }
            }))
            self.present(alert, animated: true)
        }
    }
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Ошибка архива", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        self.present(alert, animated: true)
    }
}

private final class AyuHistoryController: UITableViewController, UISearchResultsUpdating {
    private let accountId: Int64
    private var records: [AyuHistoryRecord] = []
    private var filtered: [AyuHistoryRecord] = []
    private let search = UISearchController(searchResultsController: nil)
    private let dateFormat = DateFormatter()
    init(accountId: Int64) {
        self.accountId = accountId
        super.init(style: .plain)
        self.title = "История сообщений"
        self.dateFormat.dateStyle = .short
        self.dateFormat.timeStyle = .short
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.search.searchResultsUpdater = self
        self.search.obscuresBackgroundDuringPresentation = false
        self.search.searchBar.placeholder = "Текст или ID чата"
        self.navigationItem.searchController = self.search
        self.definesPresentationContext = true
        AyuHistoryStore.shared.load(accountId: self.accountId) { [weak self] records, error in
            guard let self else { return }
            self.records = records
            self.updateSearchResults(for: self.search)
            if let error {
                let alert = UIAlertController(title: "Ошибка архива", message: error, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        self.filtered = query.isEmpty ? self.records : self.records.filter {
            $0.text.localizedCaseInsensitiveContains(query) || String($0.peerId).contains(query)
        }
        let empty = UILabel()
        empty.text = self.records.isEmpty ? "Сохранённых версий пока нет" : "Ничего не найдено"
        empty.textAlignment = .center
        empty.textColor = .secondaryLabel
        self.tableView.backgroundView = self.filtered.isEmpty ? empty : nil
        self.tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.filtered.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = self.filtered[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = record.text.isEmpty ? "[Медиа: текст отсутствует]" : record.text
        cell.textLabel?.numberOfLines = 4
        let kind = record.kind == "deleted" ? "Удалено" : "До правки"
        cell.detailTextLabel?.text = "\(kind) · чат \(record.peerId) · #\(record.messageId)\n\(self.dateFormat.string(from: Date(timeIntervalSince1970: record.capturedAt)))"
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = self.filtered[indexPath.row]
        let detail = UIViewController()
        detail.title = "Сообщение #\(record.messageId)"
        let text = UITextView()
        text.isEditable = false
        text.font = .preferredFont(forTextStyle: .body)
        text.adjustsFontForContentSizeCategory = true
        text.text = "Чат: \(record.peerId)\nОтправитель: \(record.authorId.map(String.init) ?? "—")\n\(record.text)"
        detail.view = text
        self.navigationController?.pushViewController(detail, animated: true)
    }
}

