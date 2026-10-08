import AppKit
import Common
import Foundation
import HotKey

@MainActor private var hotkeys: [String: HotKey] = [:]

@MainActor func resetHotKeys() {
    // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
    // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
    for (_, key) in hotkeys {
        key.isEnabled = false
    }
    hotkeys = [:]
    SideSpecificHotkeys.setBindings([:])
}

extension HotKey {
    var isEnabled: Bool {
        get { !isPaused }
        set {
            if isEnabled != newValue {
                isPaused = !newValue
            }
        }
    }
}

@MainActor var activeMode: String? = mainModeId
@MainActor func activateMode_nonCancellable(_ targetMode: String?) async {
    let targetBindings = targetMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    for binding in targetBindings.values where binding.sideSpecificModifiers.isEmpty && !hotkeys.keys.contains(binding.descriptionWithKeyCode) {
        hotkeys[binding.descriptionWithKeyCode] = HotKey(key: binding.keyCode, modifiers: binding.modifiers, keyDownHandler: {
            triggerHotkeyBinding(binding)
        })
    }
    for (binding, key) in hotkeys {
        key.isEnabled = targetBindings.keys.contains(binding)
    }
    SideSpecificHotkeys.setBindings(targetBindings.filter { !$0.value.sideSpecificModifiers.isEmpty })
    let oldMode = activeMode
    activeMode = targetMode
    if oldMode != targetMode {
        broadcastEvent(.modeChanged(mode: targetMode))
        _ = await config.onModeChanged.run(.defaultEnv, .emptyStdin)
    }
}

@MainActor func triggerHotkeyBinding(_ binding: HotkeyBinding) {
    Task.startUnstructured {
        if let activeMode {
            broadcastEvent(.bindingTriggered(
                mode: activeMode,
                binding: binding.descriptionWithKeyNotation,
            ))
            try await runLightSession(.hotkeyBinding, .checkServerIsEnabledOrDie()) { () throws in
                _ = await config.modes[activeMode]?.bindings[binding.descriptionWithKeyCode]?.commands
                    .run(.defaultEnv, .emptyStdin)
            }
        }
    }
}

enum ModifierSide: Hashable, Sendable {
    case left, right
}

enum SideSpecificModifier: Hashable, Sendable {
    case alt(ModifierSide)
    case ctrl(ModifierSide)
    case cmd(ModifierSide)
    case shift(ModifierSide)

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
            case .alt: .option
            case .ctrl: .control
            case .cmd: .command
            case .shift: .shift
        }
    }

    var notation: String {
        let side: ModifierSide
        let modifier: String
        switch self {
            case let .alt(value): side = value; modifier = "alt"
            case let .ctrl(value): side = value; modifier = "ctrl"
            case let .cmd(value): side = value; modifier = "cmd"
            case let .shift(value): side = value; modifier = "shift"
        }
        return "\(side == .left ? "left" : "right")-\(modifier)"
    }
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: Key
    let sideSpecificModifiers: Set<SideSpecificModifier>
    let commands: Shell<any Command>
    let descriptionWithKeyCode: String
    let descriptionWithKeyNotation: String

    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: Shell<any Command>, descriptionWithKeyNotation: String, sideSpecificModifiers: Set<SideSpecificModifier> = []) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.sideSpecificModifiers = sideSpecificModifiers
        self.commands = commands
        let modifiersDescription = modifiersDescription(modifiers, sideSpecificModifiers)
        self.descriptionWithKeyCode = modifiers.isEmpty
            ? keyCode.toString()
            : modifiersDescription + "-" + keyCode.toString()
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.modifiers == rhs.modifiers &&
            lhs.keyCode == rhs.keyCode &&
            lhs.sideSpecificModifiers == rhs.sideSpecificModifiers &&
            lhs.descriptionWithKeyCode == rhs.descriptionWithKeyCode &&
            lhs.commands.strictEquals(rhs.commands)
    }
}

func parseBindings(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> [String: HotkeyBinding] {
    guard let rawTable = raw.asDictOrNil else {
        c.errors += [expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace)]
        return [:]
    }
    var result: [String: HotkeyBinding] = [:]
    for (binding, rawCommand): (String, OrderedJson) in rawTable {
        let backtrace = backtrace + .key(binding)
        let binding = parseBinding(binding, backtrace, mapping)
            .map { modifiers, key, sideSpecificModifiers -> HotkeyBinding in
                let commands = parseShellOfCommandsForConfig(rawCommand, backtrace, &c)
                return HotkeyBinding(modifiers, key, commands, descriptionWithKeyNotation: binding, sideSpecificModifiers: sideSpecificModifiers)
            }
            .getOrNil(appendErrorTo: &c.errors)
        if let binding {
            if result.keys.contains(binding.descriptionWithKeyCode) {
                c.errors.append(.init(backtrace, "'\(binding.descriptionWithKeyCode)' Binding redeclaration"))
            }
            result[binding.descriptionWithKeyCode] = binding
        }
    }
    return result
}

func parseBinding(_ raw: String, _ backtrace: ConfigBacktrace, _ mapping: [String: Key]) -> ResOrConfigParseDiagnostic<(NSEvent.ModifierFlags, Key, Set<SideSpecificModifier>)> {
    let rawKeys = raw
        .replacingOccurrences(of: "left-alt", with: "leftAlt")
        .replacingOccurrences(of: "right-alt", with: "rightAlt")
        .replacingOccurrences(of: "left-ctrl", with: "leftCtrl")
        .replacingOccurrences(of: "right-ctrl", with: "rightCtrl")
        .replacingOccurrences(of: "left-cmd", with: "leftCmd")
        .replacingOccurrences(of: "right-cmd", with: "rightCmd")
        .replacingOccurrences(of: "left-shift", with: "leftShift")
        .replacingOccurrences(of: "right-shift", with: "rightShift")
        .split(separator: "-")
    var modifiers: NSEvent.ModifierFlags = []
    var sideSpecificModifiers: Set<SideSpecificModifier> = []
    for rawModifier in rawKeys.dropLast() {
        let sideSpecificModifier: SideSpecificModifier? = switch rawModifier {
            case "leftAlt", "lalt": .alt(.left)
            case "rightAlt", "ralt": .alt(.right)
            case "leftCtrl", "lctrl": .ctrl(.left)
            case "rightCtrl", "rctrl": .ctrl(.right)
            case "leftCmd", "lcmd": .cmd(.left)
            case "rightCmd", "rcmd": .cmd(.right)
            case "leftShift", "lshift": .shift(.left)
            case "rightShift", "rshift": .shift(.right)
            default: nil
        }
        if let sideSpecificModifier {
            if sideSpecificModifiers.contains(where: { $0.modifierFlag == sideSpecificModifier.modifierFlag }) {
                return .failure(.init(backtrace, "Can't parse modifiers in '\(raw)' binding"))
            }
            sideSpecificModifiers.insert(sideSpecificModifier)
            modifiers.insert(sideSpecificModifier.modifierFlag)
        } else {
            guard let modifier = modifiersMap[String(rawModifier)] else {
                return .failure(.init(backtrace, "Can't parse modifiers in '\(raw)' binding"))
            }
            modifiers.insert(modifier)
        }
    }
    let key: ResOrConfigParseDiagnostic<Key> = rawKeys.last.flatMap { mapping[String($0)] }
        .toResult(.init(backtrace, "Can't parse the key in '\(raw)' binding"))
    return key.map { key in
        (modifiers, key, sideSpecificModifiers)
    }
}

private func modifiersDescription(_ modifiers: NSEvent.ModifierFlags, _ sideSpecificModifiers: Set<SideSpecificModifier>) -> String {
    [
        (.option, "alt"),
        (.control, "ctrl"),
        (.command, "cmd"),
        (.shift, "shift"),
    ]
        .compactMap { modifier, genericNotation in
            guard modifiers.contains(modifier) else { return nil }
            return sideSpecificModifiers.first(where: { $0.modifierFlag == modifier })?.notation ?? genericNotation
        }
        .joined(separator: "-")
}
