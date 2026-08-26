import XCTest
import CoreGraphics
@testable import AizuchiCapture
@testable import AizuchiCore

final class ContentFilterBuilderTests: XCTestCase {
    func testExcludesOwnBundleIdentifierOnly() {
        let all = ["us.zoom.xos", "app.aizuchi.Aizuchi", "com.apple.finder"]
        let excluded = ContentFilterBuilder.bundleIdentifiersToExcludeFromDisplay(allBundleIdentifiers: all, ownBundleIdentifier: "app.aizuchi.Aizuchi")
        XCTAssertEqual(excluded, ["app.aizuchi.Aizuchi"])
    }

    func testExcludesNothingWhenOwnBundleIdentifierIsNil() {
        let all = ["us.zoom.xos", "com.apple.finder"]
        let excluded = ContentFilterBuilder.bundleIdentifiersToExcludeFromDisplay(allBundleIdentifiers: all, ownBundleIdentifier: nil)
        XCTAssertTrue(excluded.isEmpty)
    }

    func testExcludesNothingWhenOwnBundleIdentifierIsNotRunning() {
        let all = ["us.zoom.xos", "com.apple.finder"]
        let excluded = ContentFilterBuilder.bundleIdentifiersToExcludeFromDisplay(allBundleIdentifiers: all, ownBundleIdentifier: "app.aizuchi.Aizuchi")
        XCTAssertTrue(excluded.isEmpty)
    }

    func testTargetExistsForKnownDisplay() {
        let snapshot = ShareableContentSnapshot(
            displays: [ShareableContentSnapshot.Display(id: 1, name: "Built-in", width: 1920, height: 1080, scaleFactor: 2, isMain: true)],
            windows: [],
            applications: []
        )
        XCTAssertTrue(ContentFilterBuilder.targetExists(.display(id: 1), in: snapshot))
        XCTAssertFalse(ContentFilterBuilder.targetExists(.display(id: 2), in: snapshot))
    }

    func testTargetExistsForKnownWindow() {
        let window = ShareableContentSnapshot.Window(id: 9, title: "Standup", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: .zero, isOnScreen: true)
        let snapshot = ShareableContentSnapshot(displays: [], windows: [window], applications: [])
        XCTAssertTrue(ContentFilterBuilder.targetExists(.window(id: 9), in: snapshot))
        XCTAssertFalse(ContentFilterBuilder.targetExists(.window(id: 10), in: snapshot))
    }

    func testTargetExistsForApplicationRequiresBothAppAndDisplay() {
        let display = ShareableContentSnapshot.Display(id: 1, name: "Built-in", width: 1920, height: 1080, scaleFactor: 2, isMain: true)
        let application = ShareableContentSnapshot.Application(id: "us.zoom.xos", name: "Zoom", processID: 1, windowCount: 1)
        let snapshot = ShareableContentSnapshot(displays: [display], windows: [], applications: [application])

        XCTAssertTrue(ContentFilterBuilder.targetExists(.application(bundleIdentifier: "us.zoom.xos", displayID: 1), in: snapshot))
        XCTAssertFalse(ContentFilterBuilder.targetExists(.application(bundleIdentifier: "us.zoom.xos", displayID: 2), in: snapshot))
        XCTAssertFalse(ContentFilterBuilder.targetExists(.application(bundleIdentifier: "com.apple.finder", displayID: 1), in: snapshot))
    }
}
