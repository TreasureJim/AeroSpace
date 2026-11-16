import Common

@MainActor private var lastKnownNativeFocusedWindowId: OpaqueWindowId? = nil
@MainActor private var expectedNativeFocusedWindow: Window? = nil

/// Keep AeroSpace focus authoritative until macOS acknowledges a focus request.
///
/// Some apps can keep reporting their previously focused window while an explicit
/// workspace switch is in progress. This is especially visible when the two
/// windows are on separate monitors, where both workspaces remain visible.
@MainActor func expectNativeFocus(_ window: Window) {
    expectedNativeFocusedWindow = window
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if let expected = expectedNativeFocusedWindow {
        if nativeFocused == expected {
            expectedNativeFocusedWindow = nil
        } else if nativeFocused?.app.pid == expected.app.pid {
            return
        } else {
            expectedNativeFocusedWindow = nil
        }
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    (nativeFocused as? MacWindow)?.macApp.lastFocusedNativeWindowOpaqueId = nativeFocused?.windowId
}
