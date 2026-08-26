import XCTest
import CoreGraphics
@testable import AizuchiCapture
@testable import AizuchiCore

final class ShareableContentMapperTests: XCTestCase {
    func testWindowWithEmptyTitleIsExcluded() {
        let window = RawWindow(windowID: 1, title: "", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true)
        XCTAssertFalse(ShareableContentMapper.shouldInclude(window: window))
    }

    func testWindowWithNilTitleIsExcluded() {
        let window = RawWindow(windowID: 1, title: nil, applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true)
        XCTAssertFalse(ShareableContentMapper.shouldInclude(window: window))
    }

    func testTinyWindowIsExcluded() {
        let tooNarrow = RawWindow(windowID: 1, title: "Meeting", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 39, height: 600), isOnScreen: true)
        let tooShort = RawWindow(windowID: 2, title: "Meeting", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 800, height: 39), isOnScreen: true)
        XCTAssertFalse(ShareableContentMapper.shouldInclude(window: tooNarrow))
        XCTAssertFalse(ShareableContentMapper.shouldInclude(window: tooShort))
    }

    func testWindowAtMinimumDimensionIsIncluded() {
        let window = RawWindow(windowID: 1, title: "Meeting", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 40, height: 40), isOnScreen: true)
        XCTAssertTrue(ShareableContentMapper.shouldInclude(window: window))
    }

    func testMapWindowsFiltersAndPreservesFields() {
        let good = RawWindow(windowID: 10, title: "Team Sync", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true)
        let bad = RawWindow(windowID: 11, title: "", applicationName: "Finder", bundleIdentifier: "com.apple.finder", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true)
        let mapped = ShareableContentMapper.mapWindows([good, bad])
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].id, 10)
        XCTAssertEqual(mapped[0].title, "Team Sync")
        XCTAssertEqual(mapped[0].applicationName, "Zoom")
        XCTAssertEqual(mapped[0].bundleIdentifier, "us.zoom.xos")
        XCTAssertTrue(mapped[0].isOnScreen)
    }

    func testApplicationWithoutIncludedWindowsIsExcluded() {
        let apps = [RawApplication(bundleIdentifier: "com.apple.dock", applicationName: "Dock", processID: 100)]
        let mapped = ShareableContentMapper.mapApplications(apps, includedWindows: [])
        XCTAssertTrue(mapped.isEmpty)
    }

    func testApplicationWithIncludedWindowsCountsThem() {
        let window1 = ShareableContentSnapshot.Window(id: 1, title: "A", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: .zero, isOnScreen: true)
        let window2 = ShareableContentSnapshot.Window(id: 2, title: "B", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: .zero, isOnScreen: true)
        let apps = [RawApplication(bundleIdentifier: "us.zoom.xos", applicationName: "Zoom", processID: 42)]
        let mapped = ShareableContentMapper.mapApplications(apps, includedWindows: [window1, window2])
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].windowCount, 2)
        XCTAssertEqual(mapped[0].processID, 42)
        XCTAssertEqual(mapped[0].name, "Zoom")
    }

    func testMapDisplaysMarksMainDisplayAndFallsBackName() {
        let displays = [
            RawDisplay(displayID: 1, width: 1920, height: 1080),
            RawDisplay(displayID: 2, width: 2560, height: 1440)
        ]
        let mapped = ShareableContentMapper.mapDisplays(displays, mainDisplayID: 2)
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped[0].name, "Display 1")
        XCTAssertFalse(mapped[0].isMain)
        XCTAssertEqual(mapped[1].name, "Display 2")
        XCTAssertTrue(mapped[1].isMain)
        XCTAssertEqual(mapped[0].scaleFactor, 1)
    }

    func testMapDisplaysUsesProvidedMetadata() {
        let displays = [RawDisplay(displayID: 7, width: 1920, height: 1080)]
        let mapped = ShareableContentMapper.mapDisplays(displays, mainDisplayID: 7) { _ in
            ShareableContentMapper.DisplayMetadata(name: "Studio Display", scaleFactor: 2)
        }
        XCTAssertEqual(mapped[0].name, "Studio Display")
        XCTAssertEqual(mapped[0].scaleFactor, 2)
    }

    func testFullSnapshotEndToEnd() {
        let displays = [RawDisplay(displayID: 1, width: 1920, height: 1080)]
        let windows = [
            RawWindow(windowID: 5, title: "Standup", applicationName: "Zoom", bundleIdentifier: "us.zoom.xos", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true),
            RawWindow(windowID: 6, title: "", applicationName: "Dock", bundleIdentifier: "com.apple.dock", frame: CGRect(x: 0, y: 0, width: 300, height: 60), isOnScreen: true)
        ]
        let apps = [
            RawApplication(bundleIdentifier: "us.zoom.xos", applicationName: "Zoom", processID: 1),
            RawApplication(bundleIdentifier: "com.apple.dock", applicationName: "Dock", processID: 2)
        ]
        let snapshot = ShareableContentMapper.snapshot(rawDisplays: displays, rawWindows: windows, rawApplications: apps, mainDisplayID: 1)
        XCTAssertEqual(snapshot.displays.count, 1)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.applications.count, 1)
        XCTAssertEqual(snapshot.applications.first?.id, "us.zoom.xos")
        XCTAssertTrue(snapshot.mainDisplay?.isMain ?? false)
    }
}
