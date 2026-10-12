import AppKit
import HotKey

/// Handles bindings that need to distinguish physical left and right modifier keys.
///
/// Carbon's global-hotkey API has no left-only modifier. A Quartz event tap lets us
/// track physical modifier keys and consume matching key events.
@MainActor enum SideSpecificHotkeys {
    private static var tapState: SideSpecificHotkeyTapState?

    static func setBindings(_ newBindings: [String: HotkeyBinding]) {
        removeEventTap()
        guard !newBindings.isEmpty else {
            return
        }
        installEventTap(bindings: Array(newBindings.values))
    }

    private static func installEventTap(bindings: [HotkeyBinding]) {
        let state = SideSpecificHotkeyTapState(bindings: bindings)
        let eventMask =
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(state).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: sideSpecificHotkeyEventTapCallback,
            userInfo: userInfo,
        ) else {
            return
        }
        state.tap = tap
        tapState = state
        state.thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            state.runLoop = runLoop
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        state.thread?.start()
    }

    private static func removeEventTap() {
        guard let state = tapState else { return }
        state.stop()
        tapState = nil
    }
}

private final class SideSpecificHotkeyTapState: @unchecked Sendable {
    private let lock = NSLock()
    private var bindings: [HotkeyBinding]
    private var pressedModifiers: Set<SideSpecificModifier> = []
    var tap: CFMachPort?
    var runLoop: CFRunLoop?
    var thread: Thread?

    init(bindings: [HotkeyBinding]) {
        self.bindings = bindings
    }

    func stop() {
        lock.lock()
        pressedModifiers = []
        let runLoop = self.runLoop
        let tap = self.tap
        lock.unlock()
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    func handle(_ type: CGEventType, event: CGEvent) -> HotkeyBinding? {
        lock.lock()
        defer { lock.unlock() }
        if type == .flagsChanged {
            if let modifier = SideSpecificHotkeyMatching.modifier(for: event.getIntegerValueField(.keyboardEventKeycode)) {
                if pressedModifiers.contains(modifier) {
                    pressedModifiers.remove(modifier)
                } else {
                    pressedModifiers.insert(modifier)
                }
            }
            return nil
        }
        guard type == .keyDown else { return nil }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return bindings.first {
            SideSpecificHotkeyMatching.matches(
                binding: $0,
                keyCode: keyCode,
                modifiers: modifiers,
                pressedModifiers: pressedModifiers,
            )
        }
    }
}

enum SideSpecificHotkeyMatching {
    static func matches(
        binding: HotkeyBinding,
        keyCode: Int64,
        modifiers: NSEvent.ModifierFlags,
        pressedModifiers: Set<SideSpecificModifier>,
    ) -> Bool {
        binding.keyCode.carbonKeyCode == UInt32(keyCode) &&
            binding.modifiers == modifiers.intersection([.shift, .option, .control, .command]) &&
            binding.sideSpecificModifiers.isSubset(of: pressedModifiers)
    }

    static func modifier(for keyCode: Int64) -> SideSpecificModifier? {
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

private func sideSpecificHotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let state = Unmanaged<SideSpecificHotkeyTapState>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = state.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard let binding = state.handle(type, event: event) else {
        return Unmanaged.passUnretained(event)
    }
    Task { @MainActor in
        triggerHotkeyBinding(binding)
    }
    return nil
}
