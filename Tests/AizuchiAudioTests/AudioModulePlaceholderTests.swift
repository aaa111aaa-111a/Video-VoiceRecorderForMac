import XCTest
@testable import AizuchiAudio
@testable import AizuchiCore

/// Workstream A replaces this with real mixer tests.
final class AudioModulePlaceholderTests: XCTestCase {
    func testCanonicalFormatIsFortyEightKilohertzStereo() {
        XCTAssertEqual(AudioStreamFormat.canonical.sampleRate, 48_000)
        XCTAssertEqual(AudioStreamFormat.canonical.channelCount, 2)
    }
}
