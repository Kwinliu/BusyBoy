import Foundation
import Combine

struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var completedAt: Date?
    var tornAt: Date?

    var isCompleted: Bool { completedAt != nil }

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

enum ReceiptFilter: String, CaseIterable, Identifiable {
    case pending, all, completed, archive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pending: return "待办纸条"
        case .all: return "全部事项"
        case .completed: return "完成存根"
        case .archive: return "撕下的纸条"
        }
    }
    var symbol: String {
        switch self {
        case .pending: return "tray"
        case .all: return "list.bullet.rectangle"
        case .completed: return "checkmark.seal"
        case .archive: return "archivebox"
        }
    }
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published var filter: ReceiptFilter = .all
    @Published var query = ""
    @Published private(set) var lastAddedID: UUID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var canUndo = false
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "mechanicalSoundEnabled") }
    }

    private let fileURL: URL?
    private var undoSnapshot: [TodoItem]?
    private var sourceIsUnreadable = false

    var currentItems: [TodoItem] { items.filter { $0.tornAt == nil } }
    var pendingCount: Int { currentItems.filter { !$0.isCompleted }.count }
    var completedCount: Int { currentItems.filter(\.isCompleted).count }
    var visibleItems: [TodoItem] {
        items.filter { item in
            guard filter == .archive ? item.tornAt != nil : item.tornAt == nil else { return false }
            let matchesFilter = filter == .all || (filter == .completed ? item.isCompleted : !item.isCompleted)
            return (filter == .archive || matchesFilter) && (query.isEmpty || item.text.localizedStandardContains(query))
        }
    }
    var dataURL: URL? { fileURL }

    init(fileURL: URL? = TodoStore.defaultURL, demo: Bool = false) {
        self.fileURL = fileURL
        self.soundEnabled = UserDefaults.standard.object(forKey: "mechanicalSoundEnabled") as? Bool ?? true
        if demo {
            let now = Date()
            items = [
                TodoItem(text: "把脑海里的想法，变成第一版", createdAt: now.addingTimeInterval(-3600)),
                TodoItem(text: "留半小时，读几页喜欢的书", createdAt: now.addingTimeInterval(-2400), completedAt: now.addingTimeInterval(-1200)),
                TodoItem(text: "傍晚出门走走，顺便买一束花", createdAt: now.addingTimeInterval(-600))
            ]
        } else { load() }
    }

    nonisolated static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["PAPERTODO_DATA_DIR"] {
            return URL(fileURLWithPath: path).appendingPathComponent("todos.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperTodo", isDirectory: true).appendingPathComponent("todos.json")
    }

    @discardableResult
    func add(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { return false }
        checkpoint()
        let item = TodoItem(text: text)
        items.append(item)
        filter = .all
        query = ""
        lastAddedID = item.id
        save()
        return true
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        items[index].completedAt = items[index].isCompleted ? nil : Date()
        save()
    }

    func edit(_ id: UUID, text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500,
              let index = items.firstIndex(where: { $0.id == id }), items[index].text != text else { return }
        checkpoint()
        items[index].text = text
        save()
    }

    func delete(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        checkpoint()
        items.removeAll { $0.id == id }
        save()
    }

    func undo() {
        guard let snapshot = undoSnapshot else { return }
        items = snapshot
        undoSnapshot = nil
        canUndo = false
        save()
    }

    func tearCurrentPaper() {
        guard !currentItems.isEmpty else { return }
        checkpoint()
        let date = Date()
        for index in items.indices where items[index].tornAt == nil { items[index].tornAt = date }
        filter = .all
        query = ""
        save()
    }

    func dismissError() { errorMessage = nil }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    private func checkpoint() {
        undoSnapshot = items
        canUndo = true
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([TodoItem].self, from: Data(contentsOf: fileURL))
        } catch {
            sourceIsUnreadable = true
            errorMessage = "无法读取本机清单，原文件已保留。请先备份数据，再重新打开。\n\(error.localizedDescription)"
        }
    }

    private func save() {
        guard let fileURL else { return }
        // Never overwrite an unreadable source file with an empty list.
        guard !sourceIsUnreadable else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try export(to: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "这次更改暂未保存到本机。请检查磁盘空间与文件夹权限，再导出一份备份。\n\(error.localizedDescription)"
        }
    }
}
