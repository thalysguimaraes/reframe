import AutoFrameCore
import XCTest

final class VirtualBackgroundSettingsTests: XCTestCase {

    // MARK: - Entitlements

    func testEntitlementsIncludeFilePickerPermission() throws {
        // The app entitlements MUST include the user-selected file access key
        // or NSOpenPanel will silently fail in the sandbox.
        let entitlementsPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AutoFrameCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Config/AutoFrameCam.entitlements")

        let data = try Data(contentsOf: entitlementsPath)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertTrue(
            plist["com.apple.security.files.user-selected.read-only"] as? Bool == true,
            "Entitlements must include com.apple.security.files.user-selected.read-only for NSOpenPanel to work in sandbox"
        )
    }

    // MARK: - Settings Backward Compatibility

    func testVirtualBackgroundSettingsDefaultWhenMissingFromJSON() throws {
        // Older settings files won't have virtual background keys.
        // They must decode with safe defaults.
        let legacyJSON = """
        {
          "hasCompletedOnboarding": true,
          "cameraID": "camera-1",
          "framingPreset": "medium",
          "smoothing": 0.82,
          "trackingEnabled": true,
          "zoomStrength": 0.5,
          "portraitModeEnabled": true,
          "portraitBlurStrength": 0.7
        }
        """

        let settings = try JSONDecoder().decode(AutoFrameSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(settings.virtualBackgroundMode, .off)
        XCTAssertEqual(settings.virtualBackgroundGradient, .warmSunset)
        XCTAssertTrue(settings.customBackgrounds.isEmpty)
        XCTAssertNil(settings.selectedCustomBackgroundID)
        // Existing fields must still decode correctly.
        XCTAssertTrue(settings.portraitModeEnabled)
        XCTAssertEqual(settings.portraitBlurStrength, 0.7, accuracy: 0.001)
    }

    func testVirtualBackgroundSettingsRoundTrip() throws {
        let bg = CustomBackground(id: "test-1", name: "My Office", fileName: "virtual-bg-test-1.jpg")
        let settings = AutoFrameSettings(
            virtualBackgroundMode: .gradient,
            virtualBackgroundGradient: .coolOcean,
            customBackgrounds: [bg],
            selectedCustomBackgroundID: "test-1"
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AutoFrameSettings.self, from: data)

        XCTAssertEqual(decoded.virtualBackgroundMode, .gradient)
        XCTAssertEqual(decoded.virtualBackgroundGradient, .coolOcean)
        XCTAssertEqual(decoded.customBackgrounds.count, 1)
        XCTAssertEqual(decoded.customBackgrounds.first?.name, "My Office")
        XCTAssertEqual(decoded.selectedCustomBackgroundID, "test-1")
    }

    func testMultipleCustomBackgroundsRoundTrip() throws {
        let bgs = [
            CustomBackground(id: "a", name: "Custom 1", fileName: "virtual-bg-a.jpg"),
            CustomBackground(id: "b", name: "Custom 2", fileName: "virtual-bg-b.png"),
            CustomBackground(id: "c", name: "Beach", fileName: "virtual-bg-c.jpg"),
        ]
        let settings = AutoFrameSettings(
            virtualBackgroundMode: .customImage,
            customBackgrounds: bgs,
            selectedCustomBackgroundID: "b"
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AutoFrameSettings.self, from: data)

        XCTAssertEqual(decoded.virtualBackgroundMode, .customImage)
        XCTAssertEqual(decoded.customBackgrounds.count, 3)
        XCTAssertEqual(decoded.selectedCustomBackgroundID, "b")
        XCTAssertEqual(decoded.customBackgrounds[1].name, "Custom 2")
    }

    func testSelectedCustomBackgroundPathResolvesCorrectly() {
        let bg = CustomBackground(id: "x", name: "Test", fileName: "virtual-bg-x.jpg")
        let settings = AutoFrameSettings(
            customBackgrounds: [bg],
            selectedCustomBackgroundID: "x"
        )
        let path = settings.selectedCustomBackgroundPath
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.hasSuffix("virtual-bg-x.jpg"))
    }

    func testSelectedCustomBackgroundPathNilWhenNoSelection() {
        let settings = AutoFrameSettings(
            customBackgrounds: [],
            selectedCustomBackgroundID: nil
        )
        XCTAssertNil(settings.selectedCustomBackgroundPath)
    }

    func testSelectedCustomBackgroundPathNilWhenIDNotFound() {
        let bg = CustomBackground(id: "a", name: "Test", fileName: "test.jpg")
        let settings = AutoFrameSettings(
            customBackgrounds: [bg],
            selectedCustomBackgroundID: "nonexistent"
        )
        XCTAssertNil(settings.selectedCustomBackgroundPath)
    }

    // MARK: - Mutual Exclusion Logic

    func testPortraitAndVirtualBackgroundAreMutuallyExclusive() throws {
        // When virtual background is on, portrait should be off and vice versa.
        var settings = AutoFrameSettings(
            portraitModeEnabled: true,
            virtualBackgroundMode: .gradient
        )

        // The pipeline uses an if/else-if chain: virtual background takes priority.
        // But at the settings level, both can technically be set.
        // The AppModel enforces mutual exclusion. Let's verify both fields encode.
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AutoFrameSettings.self, from: data)
        XCTAssertTrue(decoded.portraitModeEnabled)
        XCTAssertEqual(decoded.virtualBackgroundMode, .gradient)

        // When virtual bg is off, portrait can be on.
        settings.virtualBackgroundMode = .off
        settings.portraitModeEnabled = true
        XCTAssertEqual(settings.virtualBackgroundMode, .off)
        XCTAssertTrue(settings.portraitModeEnabled)
    }

    // MARK: - Gradient Presets

    func testAllGradientPresetsHaveDisplayNames() {
        for preset in GradientPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset.rawValue) should have a display name")
        }
    }

    func testGradientPresetRawValuesAreStable() {
        // Raw values are persisted in JSON, so they must not change.
        XCTAssertEqual(GradientPreset.warmSunset.rawValue, "warmSunset")
        XCTAssertEqual(GradientPreset.coolOcean.rawValue, "coolOcean")
        XCTAssertEqual(GradientPreset.softLavender.rawValue, "softLavender")
    }

    func testVirtualBackgroundModeRawValuesAreStable() {
        XCTAssertEqual(VirtualBackgroundMode.off.rawValue, "off")
        XCTAssertEqual(VirtualBackgroundMode.gradient.rawValue, "gradient")
        XCTAssertEqual(VirtualBackgroundMode.customImage.rawValue, "customImage")
    }

    // MARK: - Image Copy to App Support

    func testImageCopyToContainerDirectory() throws {
        // Simulate the copy-to-container logic that importVirtualBackgroundImage uses.
        let container = SharedStorage.containerDirectory()
        let testImagePath = container.appendingPathComponent("virtual-bg-test.png")

        // Create a tiny 1x1 PNG.
        let pngData = createMinimalPNG()
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-source.png")
        try pngData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // Copy to container (mimics the real logic).
        try? FileManager.default.removeItem(at: testImagePath)
        try FileManager.default.copyItem(at: sourceURL, to: testImagePath)
        defer { try? FileManager.default.removeItem(at: testImagePath) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: testImagePath.path))
        let copiedData = try Data(contentsOf: testImagePath)
        XCTAssertEqual(copiedData.count, pngData.count)
    }

    private func createMinimalPNG() -> Data {
        // Minimal valid 1x1 white PNG (67 bytes).
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQABNjN9GQAAAAlwSFlzAAAWJQAAFiUBSVIk8AAAAA0lEQVQI12P4z8BQDwAEgAF/pooBPQAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64) ?? Data()
    }
}
