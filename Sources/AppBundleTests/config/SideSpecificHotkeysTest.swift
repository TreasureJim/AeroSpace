@testable import AppBundle
import AppKit
import HotKey
import XCTest

final class SideSpecificHotkeysTest: XCTestCase {
    func testMatchingRequiresConfiguredPhysicalModifier() {
        let binding = HotkeyBinding(
            .option,
            .h,
            .cmd(FocusCommand.new(direction: .left)),
            descriptionWithKeyNotation: "left-alt-h",
            sideSpecificModifiers: [.alt(.left)],
        )

        XCTAssertTrue(
            SideSpecificHotkeyMatching.matches(
                binding: binding,
                keyCode: Int64(Key.h.carbonKeyCode),
                modifiers: [.option],
                pressedModifiers: [.alt(.left)],
            ),
        )
        XCTAssertFalse(
            SideSpecificHotkeyMatching.matches(
                binding: binding,
                keyCode: Int64(Key.h.carbonKeyCode),
                modifiers: [.option],
                pressedModifiers: [.alt(.right)],
            ),
        )
    }

    func testMatchingRequiresExactKeyboardModifiers() {
        let binding = HotkeyBinding(
            .option,
            .h,
            .cmd(FocusCommand.new(direction: .left)),
            descriptionWithKeyNotation: "left-alt-h",
            sideSpecificModifiers: [.alt(.left)],
        )

        XCTAssertFalse(
            SideSpecificHotkeyMatching.matches(
                binding: binding,
                keyCode: Int64(Key.h.carbonKeyCode),
                modifiers: [.option, .shift],
                pressedModifiers: [.alt(.left)],
            ),
        )
    }

    func testModifierMapsPhysicalKeyCodes() {
        XCTAssertEqual(
            SideSpecificHotkeyMatching.modifier(for: Int64(Key.option.carbonKeyCode)),
            .alt(.left),
        )
        XCTAssertEqual(
            SideSpecificHotkeyMatching.modifier(for: Int64(Key.rightOption.carbonKeyCode)),
            .alt(.right),
        )
        XCTAssertEqual(
            SideSpecificHotkeyMatching.modifier(for: Int64(Key.shift.carbonKeyCode)),
            .shift(.left),
        )
        XCTAssertNil(SideSpecificHotkeyMatching.modifier(for: Int64(Key.h.carbonKeyCode)))
    }
}
