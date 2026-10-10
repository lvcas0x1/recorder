import XCTest
@testable import Selection

private final class FakeProvider: ScreenCapturePermissionProviding {
    var isGranted: Bool
    var requestCount = 0
    init(granted: Bool) { isGranted = granted }
    func request() -> Bool { requestCount += 1; return isGranted }
}

final class PermissionServiceTests: XCTestCase {
    func testActionDoesNotRunWithoutPermission() {
        let service = PermissionService(provider: FakeProvider(granted: false))
        var ran = false, denied = false
        service.guarded({ ran = true }, onDenied: { denied = true })
        XCTAssertFalse(ran)
        XCTAssertTrue(denied)
    }

    func testActionRunsWithPermission() {
        let service = PermissionService(provider: FakeProvider(granted: true))
        var ran = false, denied = false
        service.guarded({ ran = true }, onDenied: { denied = true })
        XCTAssertTrue(ran)
        XCTAssertFalse(denied)
    }

    func testMonitorReportsGrantOnce() {
        let provider = FakeProvider(granted: false)
        let monitor = PermissionMonitor(provider: provider, interval: 0.02)
        let granted = expectation(description: "granted")
        var count = 0
        monitor.start { count += 1; granted.fulfill() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { provider.isGranted = true }
        wait(for: [granted], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(count, 1)
    }
}
