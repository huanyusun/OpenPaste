import Foundation
import Carbon.HIToolbox

/// 全局快捷键：RegisterEventHotKey（⇧⌘V 打开面板 + ⌘1-9 快速粘贴）
final class HotKeyCenter {
    static var panelHandler: (() -> Void)?
    static var numberHandler: ((Int) -> Void)?

    // C 回调必须是顶层/静态闭包，不能捕获 self
    private static let eventCallback: EventHandlerUPP = { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        switch id.id {
        case 1: panelHandler?()
        case 10...18: numberHandler?(Int(id.id - 10))
        default: break
        }
        return noErr
    }

    private static var handlerInstalled = false

    func register(handler: @escaping () -> Void) {
        Self.panelHandler = handler
        Self.installHandlerIfNeeded()
        // ⇧⌘V
        var hotkeyRef = EventHotKeyRef?(nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F505354) /* OPST */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(shiftKey | cmdKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func registerPasteNumbers(handler: @escaping (Int) -> Void) {
        Self.numberHandler = handler
        Self.installHandlerIfNeeded()
        // ⌘1 - ⌘9（id 10-18）
        let keyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]
        for n in 1...9 {
            var hotkeyRef = EventHotKeyRef?(nil)
            let hotKeyID = EventHotKeyID(signature: OSType(0x4F505354), id: UInt32(9 + n))
            RegisterEventHotKey(keyCodes[n - 1], UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), eventCallback, 1, &eventType, nil, nil)
    }
}
