import AppKit
import Carbon
import Combine

@MainActor
final class GlobalHotKey: ObservableObject {
    @Published private(set) var isRegistered = false
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return }
        let id = EventHotKeyID(signature: 0x5054444F, id: 1)
        isRegistered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                          GetApplicationEventTarget(), 0, &reference) == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
        isRegistered = false
    }
}
