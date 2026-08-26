import XCTest
@testable import OptiRecordCapture
@testable import OptiRecordCore

final class TargetWatchTests: XCTestCase {
    func testDisplayTargetHasNothingToWatch() {
        let snapshot = ShareableContentSnapshot.empty
        XCTAssertNil(TargetWatch.bundleIdentifierToWatch(for: .display(id: 1), in: snapshot))
    }

    func testApplicationTargetWatchesItsOwnBundleIdentifier() {
        let snapshot = ShareableContentSnapshot.empty
        XCTAssertEqual(TargetWatch.bundleIdentifierToWatch(for: .application(bundleIdentifier: "us.zoom.xos", displayID: 1), in: snapshot), "us.zoom.xos")
    }

    func testWindowTargetWatchesOwningApplication() {
        let window = ShareableContentSnapshot.Window(id: 5, title: "Standup", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: .zero, isOnScreen: true)
        let snapshot = ShareableContentSnapshot(displays: [], windows: [window], applications: [])
        XCTAssertEqual(TargetWatch.bundleIdentifierToWatch(for: .window(id: 5), in: snapshot), "us.zoom.xos")
    }

    func testWindowTargetWithUnknownWindowWatchesNothing() {
        let snapshot = ShareableContentSnapshot.empty
        XCTAssertNil(TargetWatch.bundleIdentifierToWatch(for: .window(id: 999), in: snapshot))
    }

    func testWindowTargetWithNoOwningApplicationWatchesNothing() {
        let window = ShareableContentSnapshot.Window(id: 5, title: "Untitled", applicationName: "", bundleIdentifier: nil, frame: .zero, isOnScreen: true)
        let snapshot = ShareableContentSnapshot(displays: [], windows: [window], applications: [])
        XCTAssertNil(TargetWatch.bundleIdentifierToWatch(for: .window(id: 5), in: snapshot))
    }
}
