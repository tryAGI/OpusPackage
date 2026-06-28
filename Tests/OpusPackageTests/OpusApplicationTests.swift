import Opus // for OPUS_APPLICATION_* C constants

// Always use english in comments
import OpusKit
import OpusTypes
import XCTest

final class OpusApplicationTests: XCTestCase {
    func testValues() {
        // Verify Swift enum maps to libopus constants
        XCTAssertEqual(Opus.Application.audio.cValue, OPUS_APPLICATION_AUDIO)
        XCTAssertEqual(Opus.Application.voip.cValue, OPUS_APPLICATION_VOIP)
        XCTAssertEqual(Opus.Application.restrictedLowDelay.cValue, OPUS_APPLICATION_RESTRICTED_LOWDELAY)
    }
}
