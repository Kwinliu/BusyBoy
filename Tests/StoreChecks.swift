import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

@main
@MainActor
enum StoreChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure.failed(message) }
    }

    static func main() async throws {
        let checks: [(String, () throws -> Void)] = [
            ("新增、编辑、完成／恢复、删除、重启持久化", lifecycle),
            ("空白与超长输入边界", inputBoundaries),
            ("筛选、搜索与新增事项可见性", filtersAndSearch),
            ("损坏的原数据在确认提示后仍不被覆盖", corruptDataProtection),
            ("撤销恢复原顺序与完成状态", undo),
            ("撕纸归档、重启恢复与撤销", tearPaper)
        ]
        for (name, check) in checks {
            try check()
            print("PASS  \(name)")
        }
        try await printQueue()
        print("PASS  接收闪灯、分段送纸、连续打印队列")
        print("\(checks.count + 1) checks passed.")
    }

    static func lifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("todos.json")
        let store = TodoStore(fileURL: url)
        try expect(store.add("  完成 macOS 原型  "), "valid input must be added")
        let id = store.items[0].id
        store.toggle(id)
        store.edit(id, text: "完成拟物原型")
        let restored = TodoStore(fileURL: url)
        try expect(restored.items.first?.id == id, "identity must survive relaunch")
        try expect(restored.items.first?.text == "完成拟物原型", "edit must persist")
        try expect(restored.items.first?.isCompleted == true, "completion must persist")
        restored.toggle(id)
        try expect(restored.pendingCount == 1, "completed task must be restorable")
        restored.delete(id)
        try expect(TodoStore(fileURL: url).items.isEmpty, "deletion must persist")
        restored.undo()
        try expect(TodoStore(fileURL: url).items.first?.id == id, "undo must persist")
    }

    static func inputBoundaries() throws {
        let store = TodoStore(fileURL: nil)
        try expect(!store.add(" \n\t "), "whitespace must be rejected")
        try expect(!store.add(String(repeating: "字", count: 501)), "over 500 characters must be rejected")
        try expect(store.add(String(repeating: "字", count: 500)), "exactly 500 characters must be accepted")
        try expect(store.items.count == 1, "invalid input must not create tasks")
    }

    static func filtersAndSearch() throws {
        let store = TodoStore(fileURL: nil)
        store.add("设计打印机"); store.add("买花")
        store.toggle(store.items[0].id)
        store.filter = .completed
        try expect(store.visibleItems.map(\.text) == ["设计打印机"], "completed filter")
        store.filter = .pending
        try expect(store.visibleItems.map(\.text) == ["买花"], "pending filter")
        store.query = "不存在"
        try expect(store.visibleItems.isEmpty, "unmatched search")
        store.add("新的事项")
        try expect(store.filter == .all && store.query.isEmpty, "new task must become visible")
        try expect(store.visibleItems.count == 3, "new task must not replace existing tasks")
    }

    static func corruptDataProtection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("damaged source".utf8)
        try original.write(to: url)
        let store = TodoStore(fileURL: url)
        try expect(store.errorMessage != nil, "unreadable source must report an error")
        store.dismissError()
        store.add("临时保留的事项")
        let after = try Data(contentsOf: url)
        try expect(after == original, "unreadable original must be preserved")
    }

    static func undo() throws {
        let store = TodoStore(fileURL: nil)
        store.add("第一条"); store.add("第二条")
        store.toggle(store.items[0].id)
        let original = store.items
        store.delete(original[0].id)
        store.undo()
        try expect(store.items == original, "undo must restore order, identity and completion")
        try expect(!store.canUndo, "one-level undo must be consumed")
    }

    static func tearPaper() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("todos.json")
        let store = TodoStore(fileURL: url)
        store.add("保留在历史里的待办")
        store.add("完成的事")
        store.toggle(store.items[1].id)
        let before = store.items
        store.tearCurrentPaper()
        try expect(store.currentItems.isEmpty && store.visibleItems.isEmpty, "tearing must clear the current roll")
        try expect(store.pendingCount == 0 && store.completedCount == 0, "current roll counts must reset")
        let restored = TodoStore(fileURL: url)
        restored.filter = .archive
        try expect(restored.visibleItems.count == 2, "torn paper must survive relaunch in history")
        store.undo()
        try expect(store.items == before, "tear must be reversible with completion state intact")
    }

    static func printQueue() async throws {
        let engine = PrintEngine()
        engine.soundEnabled = false
        let first = TodoItem(text: "第一张")
        let second = TodoItem(text: "第二张")
        engine.enqueue(first); engine.enqueue(second)
        try expect(engine.hiddenIDs == [first.id, second.id], "queued tasks must not appear before printing")
        try await until { engine.phase == .receiving && !engine.ledOn }
        try await until { engine.currentID == first.id && engine.phase == .printing }
        try expect(engine.hiddenIDs.contains(second.id), "second task must wait while first prints")
        try await until { engine.progress > 0 && engine.progress < 1 }
        try await until { !engine.hiddenIDs.contains(first.id) }
        try expect(engine.hiddenIDs.contains(second.id), "queue order must be preserved")
        try await until { engine.phase == .idle && engine.hiddenIDs.isEmpty }
        try expect(engine.currentID == nil && engine.ledOn, "printer must return to ready")
    }

    static func until(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() {
            try expect(Date() < deadline, "print state deadline exceeded")
            try await Task.sleep(for: .milliseconds(35))
        }
    }
}
