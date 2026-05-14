import Carbon
import Foundation

enum FloatingShortcutConfiguration {
    static let keyCode = UInt32(kVK_Space)
    static let modifiers = UInt32(optionKey)
    static let displayName = "Option + Space"
}

final class FloatingShortcutMonitor {
    private static let hotKeySignature = fourCharCode("OCLK")

    private let hotKeyID: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init?(keyCode: UInt32, modifiers: UInt32, hotKeyID: UInt32 = 1, action: @escaping @MainActor () -> Void) {
        self.hotKeyID = hotKeyID
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            return nil
        }

        let identifier = EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyID)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    fileprivate func receiveHotKey(event: EventRef?) -> OSStatus {
        guard let event else {
            return noErr
        }

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == Self.hotKeySignature, identifier.id == hotKeyID else {
            return noErr
        }

        let action = self.action
        MainActor.assumeIsolated {
            action()
        }
        return noErr
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.prefix(4).reduce(0) { partialResult, character in
        (partialResult << 8) + OSType(character)
    }
}

private func handleHotKeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return noErr
    }

    let monitor = Unmanaged<FloatingShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    return monitor.receiveHotKey(event: event)
}
