import SwiftUI
import AppKit

struct QuickEntryView: View {
    var initialText: String = ""
    var isEditing = false
    var submit: (String) -> Bool
    var cancel: () -> Void
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isEditing ? "pencil" : "printer").font(.system(size: 12))
                Text(isEditing ? "修改这条待办" : "给想法，打一张纸条").font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).accessibilityLabel("关闭输入框")
            }
            .foregroundStyle(Color(hex: 0x7A826E)).padding(.bottom, 22)

            EntryTextView(text: $text, submit: commit, cancel: cancel)
                .frame(height: 83)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("想做什么？")
                            .font(.system(size: 20)).foregroundStyle(Color.mutedInk.opacity(0.6))
                            .padding(.top, 5).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 3)
                .background(alignment: .bottom) { Perforation().padding(.bottom, 3) }

            HStack(spacing: 5) {
                Text(invalid ? "请填写 1–500 个字的待办" : "↵ 打印   ·   ⇧↵ 换行   ·   esc 收起")
                    .font(.system(size: 10)).foregroundStyle(invalid ? Color(hex: 0xA75B49) : Color.mutedInk)
                Spacer()
                Text("\(text.count)/500").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.mutedInk)
                Button(action: commit) {
                    HStack(spacing: 7) { Text(isEditing ? "保存" : "打印"); Image(systemName: "return") }
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).frame(height: 34)
                }
                .buttonStyle(TactileButtonStyle(primary: true)).padding(.leading, 10)
            }.padding(.top, 17)
        }
        .padding(25)
        .frame(width: 568, height: 246)
        .background {
            Color(hex: 0xF6F5EA)
            Grain(opacity: 0.06)
            RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.9), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .preferredColorScheme(.light)
        .onAppear { text = initialText }
    }

    private func commit() {
        if submit(text) { invalid = false } else { invalid = true; NSSound.beep() }
    }
}

struct EntryTextView: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = CommitTextView()
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        view.textColor = NSColor(Color.ink)
        view.insertionPointColor = NSColor(Color.moss)
        view.textContainerInset = NSSize(width: 0, height: 5)
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.onCommit = submit
        view.onCancel = cancel
        view.setAccessibilityLabel("待办内容")
        scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? CommitTextView else { return }
        context.coordinator.parent = self
        if view.string != text, !view.hasMarkedText() {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        view.onCommit = submit
        view.onCancel = cancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EntryTextView
        init(_ parent: EntryTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}

final class CommitTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Let the input method finish a marked Chinese/Japanese composition first.
        if !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) { super.keyDown(with: event) }
            else { onCommit?() }
            return
        }
        if event.keyCode == 53, !hasMarkedText() { onCancel?(); return }
        super.keyDown(with: event)
    }
}
