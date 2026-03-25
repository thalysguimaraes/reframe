import AutoFrameCore
import XCTest

final class AutoFrameSettingsTests: XCTestCase {
    func testMenuBarSettingsDefaultToEnabledForOlderSavedPayloads() throws {
        let legacyJSON = """
        {
          "cameraID": "camera-1",
          "framingPreset": "medium",
          "hasCompletedOnboarding": true,
          "outputResolution": "1080p",
          "portraitModeEnabled": false,
          "smoothing": 0.82,
          "trackingEnabled": true,
          "zoomStrength": 0.5
        }
        """

        let settings = try JSONDecoder().decode(AutoFrameSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertTrue(settings.showDockIcon)
        XCTAssertTrue(settings.keepRunningOnClose)
    }

    func testMenuBarSettingsRoundTripThroughCodable() throws {
        let settings = AutoFrameSettings(
            hasCompletedOnboarding: true,
            cameraID: "camera-2",
            showInMenuBar: false,
            showDockIcon: false,
            keepRunningOnClose: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AutoFrameSettings.self, from: data)

        XCTAssertFalse(decoded.showInMenuBar)
        XCTAssertFalse(decoded.showDockIcon)
        XCTAssertTrue(decoded.keepRunningOnClose)
    }
}
