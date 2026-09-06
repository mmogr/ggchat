import CoreGraphics
import XCTest

/// The one claim in the README that nothing has ever run: that Reduce
/// Transparency is the system's to honour, because the three glass surfaces
/// are the system's own rather than hand-drawn.
///
/// There is no launch argument for it. `-UIAccessibilityReduceTransparencyEnabled`
/// is accepted, reaches `UserDefaults`, and changes nothing, which is worse
/// than the type-size argument next door: that one at least works when it is
/// spelled right. `xcrun simctl ui` has no option for it either. So the only
/// way to set it is Settings, and the only thing worth asserting afterwards
/// is that the glass actually went flat.
final class ReduceTransparencyUITests: XCTestCase {
    private var app: XCUIApplication!

    /// A band with no glass in it, and the band the composer's glass fills.
    /// Fractions of the screenshot's own height: `XCUIScreen` has no bounds,
    /// and both bands have to describe the same picture on any device.
    private static let controlBand = (top: 0.10, bottom: 0.75)
    private static let glassBand = (top: 0.83, bottom: 0.94)

    /// The measured drop is about 0.028, and two baseline runs in separate
    /// `xcodebuild test` invocations agreed to sixteen digits — the noise
    /// floor is zero. A third of the measured drop is still nowhere near it,
    /// and leaves room for the system to draw the effect a little differently.
    private static let leastConvincingDrop = 0.01

    @MainActor
    func testGlassGoesFlatWhenTransparencyIsReduced() throws {
        // Reduce Transparency is device state, not app state. A run that
        // crashed before its restore leaves it on, and the baseline would
        // then be taken in the same mode as the reading it is compared with:
        // the drop collapses to nothing and this test accuses the app of
        // ignoring a setting it had honoured all along.
        setReduceTransparency(false)
        defer { setReduceTransparency(false) }

        let transparent = try glassAgainstItsBackground(screenshot: "glass-transparent")
        setReduceTransparency(true)
        let flat = try glassAgainstItsBackground(screenshot: "glass-flat")

        XCTAssertGreaterThan(
            transparent - flat, Self.leastConvincingDrop,
            "the glass did not flatten under Reduce Transparency: \(transparent) to \(flat)")
    }

    /// Walks to a conversation and returns how bright the composer's glass is
    /// next to a glass-free band of the same picture. A ratio rather than a
    /// luminance, because it cancels everything the two readings share — the
    /// wallpaper, the clock in the status bar, the transcript behind.
    @MainActor
    private func glassAgainstItsBackground(screenshot: String) throws -> Double {
        app = launchFreshApp()
        addMockProvider()
        app.buttons["New conversation"].firstMatch.tap()
        XCTAssertTrue(waitUntilHittable(composer(in: app), timeout: 20), "the composer never appeared")

        let shot = app.screenshot()
        attach(shot, name: screenshot)
        let control = try meanLuminance(of: shot, band: Self.controlBand)
        let glass = try meanLuminance(of: shot, band: Self.glassBand)
        XCTAssertGreaterThan(control, 0, "the control band is pure black, so a ratio would say nothing")
        return glass / control
    }

    /// The mean brightness of one horizontal band of a screenshot.
    @MainActor
    private func meanLuminance(of shot: XCUIScreenshot, band: (top: Double, bottom: Double)) throws -> Double {
        let whole = try XCTUnwrap(shot.image.cgImage, "the screenshot carried no image")
        let top = Int(Double(whole.height) * band.top)
        let height = Int(Double(whole.height) * band.bottom) - top
        let width = whole.width
        let slice = try XCTUnwrap(
            whole.cropping(to: CGRect(x: 0, y: top, width: width, height: height)),
            "the band falls outside the screenshot")

        var pixels = [UInt8](repeating: 0, count: width * height)
        var drew = false
        pixels.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.draw(slice, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }
        XCTAssertTrue(drew, "the band could not be drawn into a grayscale buffer")
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
    }

    /// Sets Reduce Transparency the only way there is. Nothing here asserts
    /// that the setting took: that is what the picture is for.
    @MainActor
    private func setReduceTransparency(_ on: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()

        // Settings can come back where it was last left, so walk out first.
        for _ in 0..<4 where !settings.navigationBars["Settings"].exists {
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            if back.exists, back.isHittable { back.tap() }
        }

        let accessibility = settings.staticTexts["Accessibility"].firstMatch
        XCTAssertTrue(reveal(accessibility, in: settings), "Settings never offered Accessibility")
        accessibility.tap()

        let display = settings.staticTexts["Display & Text Size"].firstMatch
        XCTAssertTrue(reveal(display, in: settings), "Accessibility has no Display & Text Size")
        display.tap()

        // The named element is the whole row, and tapping a row leaves the
        // switch exactly as it was, silently. The switch is its child.
        let row = settings.switches["Reduce Transparency"].firstMatch
        XCTAssertTrue(reveal(row, in: settings), "Display & Text Size has no Reduce Transparency")
        let wanted = on ? "1" : "0"
        if row.value as? String != wanted {
            row.switches.firstMatch.tap()
        }
        wait(
            for: [expectation(for: NSPredicate(format: "value == %@", wanted), evaluatedWith: row)],
            timeout: 10)
        settings.terminate()
    }

    /// Settings is a long list, and a row below the fold is in the tree but
    /// not tappable. Existence is not reachability here.
    @MainActor
    private func reveal(_ element: XCUIElement, in settings: XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout: 30) else { return false }
        for _ in 0..<8 where !element.isHittable {
            settings.swipeUp()
        }
        return element.isHittable
    }

    @MainActor
    private func addMockProvider() {
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30))
        addProvider.tap()
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
    }

    /// Takes the screenshot as an argument rather than shooting its own: the
    /// picture attached has to be the one the numbers were read from.
    @MainActor
    private func attach(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
