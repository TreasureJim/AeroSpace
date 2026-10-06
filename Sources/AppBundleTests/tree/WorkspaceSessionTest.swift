@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceSessionTest: XCTestCase {
    func testFrozenWorldRoundTripsThroughPropertyList() throws {
        let window = FrozenWindow(id: 42, pid: 1234, weight: 0.5)
        let container = FrozenContainer(
            children: [.window(window)],
            layout: .tiles,
            orientation: .h,
            weight: 1,
        )
        let monitor = FrozenMonitor(topLeftCorner: .zero, visibleWorkspace: "1")
        let workspace = FrozenWorkspace(
            name: "1",
            monitor: monitor,
            rootTilingNode: container,
            floatingWindows: [],
            macosUnconventionalWindows: [],
        )
        let world = FrozenWorld(workspaces: [workspace], monitors: [monitor], windowIds: [42])

        let encoded = try PropertyListEncoder().encode(world)
        let decoded = try PropertyListDecoder().decode(FrozenWorld.self, from: encoded)

        XCTAssertEqual(decoded.workspaces.first?.name, "1")
        XCTAssertEqual(decoded.workspaces.first?.rootTilingNode.children.count, 1)
        XCTAssertEqual(decoded.windowIds, Set([UInt32(42)]))
        if case .window(let decodedWindow) = decoded.workspaces[0].rootTilingNode.children[0] {
            XCTAssertEqual(decodedWindow.pid, 1234)
        } else {
            XCTFail("Expected a frozen window")
        }
    }
}
