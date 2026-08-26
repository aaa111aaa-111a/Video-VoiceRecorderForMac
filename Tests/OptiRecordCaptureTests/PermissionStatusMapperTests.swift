import XCTest
import AVFoundation
@testable import OptiRecordCapture
@testable import OptiRecordCore

final class PermissionStatusMapperTests: XCTestCase {
    func testMapsAuthorizationStatuses() {
        XCTAssertEqual(PermissionStatusMapper.map(.authorized), .authorized)
        XCTAssertEqual(PermissionStatusMapper.map(.denied), .denied)
        XCTAssertEqual(PermissionStatusMapper.map(.restricted), .restricted)
        XCTAssertEqual(PermissionStatusMapper.map(.notDetermined), .notDetermined)
    }

    func testScreenRecordingStatusWithAccessIsAlwaysAuthorized() {
        XCTAssertEqual(PermissionStatusMapper.screenRecordingStatus(hasAccess: true, hasRequestedBefore: false), .authorized)
        XCTAssertEqual(PermissionStatusMapper.screenRecordingStatus(hasAccess: true, hasRequestedBefore: true), .authorized)
    }

    func testScreenRecordingStatusWithoutAccessDistinguishesFirstAskFromDenied() {
        XCTAssertEqual(PermissionStatusMapper.screenRecordingStatus(hasAccess: false, hasRequestedBefore: false), .notDetermined)
        XCTAssertEqual(PermissionStatusMapper.screenRecordingStatus(hasAccess: false, hasRequestedBefore: true), .denied)
    }
}
