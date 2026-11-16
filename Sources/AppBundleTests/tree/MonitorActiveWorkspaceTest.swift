@testable import AppBundle
import Common
import XCTest

private struct StaleMonitorInfo: MonitorInfo {
    let monitorAppKitNsScreenScreensId = 2
    let name = "Disconnected Monitor"
    let rect = Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
    var visibleRect: Rect { rect }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    let isMain = false
}

@MainActor
final class MonitorActiveWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testActiveWorkspaceOfStaleMonitorDoesNotRecurseInfinitely() {
        let workspace = StaleMonitorInfo().visibleWorkspace
        XCTAssertEqual(workspace, mainMonitorInfo.visibleWorkspace)
    }
}
