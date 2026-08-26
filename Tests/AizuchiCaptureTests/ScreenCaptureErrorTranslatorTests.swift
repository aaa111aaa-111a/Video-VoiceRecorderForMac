import XCTest
@testable import AizuchiCapture
@testable import AizuchiCore

final class ScreenCaptureErrorTranslatorTests: XCTestCase {
    private struct SampleError: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    func testMissingScreenRecordingAccessAlwaysWinsRegardlessOfContext() {
        let error = ScreenCaptureErrorTranslator.translate(SampleError(), context: .startCapture, hasScreenRecordingAccess: false)
        XCTAssertEqual(error, .screenRecordingPermissionDenied)
    }

    func testAvailableContentFailureWithAccessBecomesNoCaptureTarget() {
        let error = ScreenCaptureErrorTranslator.translate(SampleError(), context: .availableContent, hasScreenRecordingAccess: true)
        XCTAssertEqual(error, .noCaptureTargetAvailable)
    }

    func testStartCaptureFailureWithAccessCarriesDetail() {
        let error = ScreenCaptureErrorTranslator.translate(SampleError(), context: .startCapture, hasScreenRecordingAccess: true)
        XCTAssertEqual(error, .captureStartFailed("boom"))
    }

    func testStreamStoppedFailureWithAccessCarriesDetail() {
        let error = ScreenCaptureErrorTranslator.translate(SampleError(), context: .streamStopped, hasScreenRecordingAccess: true)
        XCTAssertEqual(error, .captureStopped("boom"))
    }

    func testFilterErrorsBecomeCaptureTargetDisappeared() {
        XCTAssertEqual(
            ScreenCaptureErrorTranslator.translate(ContentFilterBuilder.FilterError.displayNotFound, context: .startCapture, hasScreenRecordingAccess: true),
            .captureTargetDisappeared
        )
        XCTAssertEqual(
            ScreenCaptureErrorTranslator.translate(ContentFilterBuilder.FilterError.windowNotFound, context: .startCapture, hasScreenRecordingAccess: true),
            .captureTargetDisappeared
        )
        XCTAssertEqual(
            ScreenCaptureErrorTranslator.translate(ContentFilterBuilder.FilterError.applicationNotFound, context: .startCapture, hasScreenRecordingAccess: true),
            .captureTargetDisappeared
        )
    }

    func testAlreadyTranslatedRecorderErrorPassesThrough() {
        let error = ScreenCaptureErrorTranslator.translate(RecorderError.alreadyRecording, context: .startCapture, hasScreenRecordingAccess: true)
        XCTAssertEqual(error, .alreadyRecording)
    }
}
