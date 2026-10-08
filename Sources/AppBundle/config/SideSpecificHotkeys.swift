import AppKit
import HotKey

/// Handles bindings that need to distinguish physical left and right modifier keys.
///
/// Carbon's global-hotkey API has no left-only modifier. A global event monitor lets us
/// track physical modifier keys and preserves the existing Carbon path for all others.
@MainActor enum SideSpecificHotkeys {
    private static var bindings: [String: HotkeyBinding] = [:]
    private static var eventMonitor: Any?
    private static var pressedModifiers: Set<SideSpecificModifier> = []

    static func setBindings(_ newBindings: [String: HotkeyBinding]) {
        bindings = newBindings
        guard !bindings.isEmpty else {
            removeEventMonitor()
            return
        }
        installEventMonitorIfNeeded()
    }

    private static func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let type = event.type
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            Task { @MainActor in
                handleEvent(type: type, keyCode: keyCode, modifiers: modifiers)
            }
        }
    }

    private static func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        pressedModifiers = []
    }

    private static func handleEvent(type: NSEvent.EventType, keyCode: UInt16, modifiers: UInt) {
        if type == .flagsChanged {
            if let modifier = modifier(for: keyCode) {
                if pressedModifiers.contains(modifier) {
                    pressedModifiers.remove(modifier)
                } else {
                    pressedModifiers.insert(modifier)
                }
            }
            return
        }
        guard type == .keyDown else { return }

        let modifiers = NSEvent.ModifierFlags(rawValue: modifiers)
        let keyboardModifiers: NSEvent.ModifierFlags = [.shift, .option, .control, .command]
        for binding in bindings.values where
            binding.keyCode.carbonKeyCode == UInt32(keyCode) &&
            binding.modifiers == modifiers.intersection(keyboardModifiers) &&
            binding.sideSpecificModifiers.isSubset(of: pressedModifiers)
        {
            triggerHotkeyBinding(binding)
        }
    }

    private static func modifier(for keyCode: UInt16) -> SideSpecificModifier? {
        switch UInt32(keyCode) {
            case Key.option.carbonKeyCode: .alt(.left)
            case Key.rightOption.carbonKeyCode: .alt(.right)
            case Key.control.carbonKeyCode: .ctrl(.left)
            case Key.rightControl.carbonKeyCode: .ctrl(.right)
            case Key.command.carbonKeyCode: .cmd(.left)
            case Key.rightCommand.carbonKeyCode: .cmd(.right)
            case Key.shift.carbonKeyCode: .shift(.left)
            case Key.rightShift.carbonKeyCode: .shift(.right)
            default: nil
        }
    }
}
