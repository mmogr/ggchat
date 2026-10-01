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

    /// How far the composer's glass, against a glass-free band of the same
    /// picture, must move when the setting is turned on, in either direction.
    /// The system's flat surface is darker than the glass on iOS 26.5 and
    /// lighter on iOS 27.0, so a test that wanted a drop failed on 27.0 for
    /// a surface that had gone flat (#129).
    ///
    /// Measured on an iPhone 17 Pro: -0.043 on iOS 26.5 and +0.0079 on iOS
    /// 27.0, each the same to sixteen digits in two separate `xcodebuild`
    /// runs, so the noise floor is zero. With the composer told the setting
    /// was off, the glass moved 0.000006 at most. A third of the smaller
    /// change is still nowhere near either.
    private static let leastConvincingChange = 0.0025

    @MainActor
    func testGlassGoesFlatWhenTransparencyIsReduced() throws {
        // Reduce Transparency is device state, not app state. A run that
        // crashed before its restore leaves it on, and the baseline would
        // then be taken in the same mode as the reading it is compared with:
        // the change collapses to nothing and this test accuses the app of
        // ignoring a setting it had honoured all along.
        setReduceTransparency(false)
        defer { setReduceTransparency(false) }

        let transparent = try glassAgainstItsBackground(screenshot: "glass-transparent")
        setReduceTransparency(true)
        let flat = try glassAgainstItsBackground(screenshot: "glass-flat")

        XCTAssertGreaterThan(
            abs(transparent - flat), Self.leastConvincingChange,
            "the glass did not change under Reduce Transparency: \(transparent) to \(flat)")
    }

    /// Walks to a conversation and returns how bright the composer's glass is
    /// next to a glass-free band of the same picture. A ratio rather than a
    /// luminance, because it cancels everything the two readings share — the
    /// wallpaper, the clock in the status bar, the transcript behind.
    ///
    /// Both regions come from the screen's own elements rather than from
    /// fractions of the picture, which described an iPhone's screen and no
    /// other: the glass is the message field, inside the composer's glass,
    /// and the band is the empty transcript between the navigation bar and
    /// the model pill, with a margin from each.
    @MainActor
    private func glassAgainstItsBackground(screenshot: String) throws -> Double {
        app = launchFreshApp()
        addMockProvider()
        let pill = openConversation(in: app)
        let field = composer(in: app)
        XCTAssertTrue(waitUntilHittable(field, timeout: 20), "the composer never appeared")

        let shot = app.screenshot()
        attach(shot, name: screenshot)
        let image = try XCTUnwrap(shot.image.cgImage, "the screenshot carried no image")
        let screen = app.frame
        let scale = Double(image.width) / screen.width
        let top = app.navigationBars.firstMatch.frame.maxY + Self.margin
        let bottom = pill.frame.minY - Self.margin
        XCTAssertGreaterThan(bottom - top, 100, "no glass-free band between the navigation bar and the pill")
        let band = CGRect(x: screen.minX, y: top, width: screen.width, height: bottom - top)
        let control = try meanLuminance(of: image, in: band, scale: scale)
        let glass = try meanLuminance(of: image, in: field.frame, scale: scale)
        XCTAssertGreaterThan(control, 0, "the control band is pure black, so a ratio would say nothing")
        return glass / control
    }

    /// Points kept between the control band and the bars around it, clear of
    /// the soft edge the system draws where content meets a bar.
    private static let margin = 24.0

    /// The mean brightness of a region of a screenshot, given in points.
    @MainActor
    private func meanLuminance(of whole: CGImage, in region: CGRect, scale: Double) throws -> Double {
        let pixels = CGRect(
            x: region.minX * scale, y: region.minY * scale, width: region.width * scale,
            height: region.height * scale
        ).integral
        let slice = try XCTUnwrap(whole.cropping(to: pixels), "the region falls outside the screenshot")
        let width = slice.width
        let height = slice.height

        var grey = [UInt8](repeating: 0, count: width * height)
        var drew = false
        grey.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.draw(slice, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }
        XCTAssertTrue(drew, "the region could not be drawn into a grayscale buffer")
        return Double(grey.reduce(0) { $0 + Int($1) }) / Double(grey.count)
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
