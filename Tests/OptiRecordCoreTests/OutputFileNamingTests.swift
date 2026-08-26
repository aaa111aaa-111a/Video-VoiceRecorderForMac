import XCTest
@testable import OptiRecordCore

final class OutputFileNamingTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_756_200_232) // 2025-08-26 09:23:52 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testDefaultTemplateProducesReadableName() {
        let name = OutputFileNaming.fileName(sourceLabel: "Zoom", date: referenceDate, timeZone: utc)
        XCTAssertEqual(name, "Zoom_2025-08-26_09-23-52")
    }

    func testSlashesAndColonsAreReplaced() {
        XCTAssertEqual(OutputFileNaming.sanitize("Weekly 1/1 : Design"), "Weekly 1-1 - Design")
    }

    func testEmptyLabelFallsBackToAppName() {
        let name = OutputFileNaming.fileName(template: "{app}", sourceLabel: "", date: referenceDate, timeZone: utc)
        XCTAssertEqual(name, AppInfo.name)
    }

    func testNilLabelFallsBackToAppName() {
        let name = OutputFileNaming.fileName(template: "{app}", sourceLabel: nil, date: referenceDate, timeZone: utc)
        XCTAssertEqual(name, AppInfo.name)
    }

    func testLongLabelIsTruncated() {
        let long = String(repeating: "あ", count: 200)
        let name = OutputFileNaming.fileName(template: "{app}", sourceLabel: long, date: referenceDate, timeZone: utc)
        XCTAssertLessThanOrEqual(name.count, 80)
        XCTAssertFalse(name.isEmpty)
    }

    func testUnknownTokensAreLeftAlone() {
        let name = OutputFileNaming.fileName(template: "{app}-{nope}", sourceLabel: "Teams", date: referenceDate, timeZone: utc)
        XCTAssertEqual(name, "Teams-{nope}")
    }

    func testUniqueURLAppendsSuffixLikeFinder() {
        let directory = URL(fileURLWithPath: "/tmp/recordings")
        let taken: Set<String> = ["Zoom.mp4", "Zoom 2.mp4"]
        let url = OutputFileNaming.uniqueURL(directory: directory, fileName: "Zoom", fileExtension: "mp4") { candidate in
            taken.contains(candidate.lastPathComponent)
        }
        XCTAssertEqual(url.lastPathComponent, "Zoom 3.mp4")
    }

    func testUniqueURLKeepsNameWhenFree() {
        let url = OutputFileNaming.uniqueURL(directory: URL(fileURLWithPath: "/tmp"), fileName: "Meet", fileExtension: "mp4") { _ in false }
        XCTAssertEqual(url.lastPathComponent, "Meet.mp4")
    }

    func testSidecarSitsNextToTheVideo() {
        let video = URL(fileURLWithPath: "/tmp/recordings/Zoom_2025-08-26.mp4")
        let mic = OutputFileNaming.sidecarURL(for: video, source: .microphone)
        XCTAssertEqual(mic.path, "/tmp/recordings/Zoom_2025-08-26.microphone.m4a")
    }
}
