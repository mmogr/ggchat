import Foundation
import GGChatCore
import Observation

/// One opening of the model browser: the reading of this device taken as it
/// opened, when that was, and what the library has said since. Every verdict
/// on it is asked with that one reading, so the rows agree with each other;
/// the next opening reads the device again.
///
/// Holds answers and nothing reckoned: each size and each verdict is the
/// library's, as it gave it.
@Observable
public final class ModelBrowser: Identifiable {
    /// Nil where this device's memory cannot be read, which is anywhere but
    /// iOS; nothing is asked that needs it then.
    public let reading: DeviceReading?
    public let checkedAt: Date
    /// What gglib suggests for this device, best first; nil until it has
    /// answered.
    public internal(set) var suggestions: [Suggestion]?
    public internal(set) var suggestionsFailure: String?
    /// What is typed in the search field, and the search its hits answer.
    public var query = ""
    public internal(set) var searched: String?
    public internal(set) var hits: [SearchHit] = []
    public internal(set) var nextCursor: String?
    public internal(set) var searchFailure: String?
    /// Each repository's quantizations once the library has said, and why
    /// it could not for one it could not.
    public internal(set) var offers: [String: [QuantOffer]] = [:]
    public internal(set) var offerFailures: [String: String] = [:]

    init(reading: DeviceReading?, checkedAt: Date) {
        self.reading = reading
        self.checkedAt = checkedAt
    }
}

/// One quantization of one repository, as a download is chosen.
public struct QuantChoice: Hashable, Sendable {
    public var repo: String
    public var quantization: String
}

extension FitVerdict {
    /// Whether the browser lets this be downloaded: anything but a model
    /// gglib found too big for this device. One it cannot tell about yet is
    /// let through, since downloading it is how gglib finds out.
    var allowsDownload: Bool {
        if case .tooBig = self { return false }
        return true
    }
}

// The model browser: opening it and asking the library. Choosing a model,
// which adds This iPhone the first time, is `AppModel+Downloads`. The view
// shows what these leave on the `ModelBrowser` and computes nothing;
// `OnDeviceState` keeps the browser open. A failure is said on the browser,
// under the section it belongs to, not in an alert the sheet would hide.
extension AppModel {
    /// Whether this build runs models on this device, and so offers the
    /// browser at all. False in a release build until `EngineFactory`
    /// picks gglib's engine, and on the Mac.
    public var runsModelsHere: Bool {
        engine.isAvailable
    }

    /// What the browser says when this device's memory could not be read.
    static let unreadDevice = "This device's memory could not be read, so nothing can be said about what fits it."

    /// Opens the browser, reading this device once for it.
    public func openModelBrowser() {
        openModelBrowser(sample: DeviceReadingSampler.sample)
    }

    /// Opens the browser with the reading `sample` takes, once, as it opens.
    /// Nothing opens where this build runs no model.
    func openModelBrowser(sample: () -> DeviceReading?) {
        guard runsModelsHere else { return }
        onDevice.modelBrowser = ModelBrowser(reading: sample(), checkedAt: now())
    }

    /// "Memory checked at 10:42", or that it could not be read.
    public func checkedLine(for browser: ModelBrowser, locale: Locale, calendar: Calendar) -> String {
        guard browser.reading != nil else { return Self.unreadDevice }
        return "Memory checked at \(Self.shortStamp(browser.checkedAt, now: now(), locale: locale, calendar: calendar))"
    }

    /// Asks what gglib suggests for this device, with the browser's reading.
    public func loadSuggestions(in browser: ModelBrowser) async {
        guard let reading = browser.reading else {
            browser.suggestionsFailure = Self.unreadDevice
            return
        }
        do {
            browser.suggestions = try await library.suggested(reading: reading)
            browser.suggestionsFailure = nil
        } catch {
            // A view task called off, which says nothing about the library;
            // the next appearance asks again.
            guard !Task.isCancelled else { return }
            browser.suggestionsFailure = error.localizedDescription
        }
    }

    /// Searches for the browser's query from the start, or for nothing,
    /// clearing the hits, when it is blank.
    public func search(in browser: ModelBrowser) async {
        let query = browser.query.trimmingCharacters(in: .whitespacesAndNewlines)
        browser.searched = query.isEmpty ? nil : query
        browser.hits = []
        browser.nextCursor = nil
        browser.searchFailure = nil
        guard !query.isEmpty else { return }
        await searchPage(query, from: nil, in: browser)
    }

    /// The next page of the search the hits answer.
    public func searchMore(in browser: ModelBrowser) async {
        guard let query = browser.searched, let cursor = browser.nextCursor else { return }
        await searchPage(query, from: cursor, in: browser)
    }

    /// One page, kept only if the search it answers is still the browser's:
    /// a page arriving after another query was submitted is dropped.
    private func searchPage(_ query: String, from cursor: String?, in browser: ModelBrowser) async {
        do {
            let page = try await library.search(query: query, cursor: cursor)
            guard browser.searched == query else { return }
            browser.hits += page.hits
            browser.nextCursor = page.nextCursor
        } catch {
            guard browser.searched == query, !Task.isCancelled else { return }
            browser.searchFailure = error.localizedDescription
        }
    }

    /// Asks for each quantization `repo` publishes, with how it fits, with
    /// the browser's reading.
    public func loadOffers(of repo: String, in browser: ModelBrowser) async {
        guard let reading = browser.reading else {
            browser.offerFailures[repo] = Self.unreadDevice
            return
        }
        do {
            browser.offers[repo] = try await library.quantizations(repo: repo, reading: reading)
            browser.offerFailures[repo] = nil
        } catch {
            guard !Task.isCancelled else { return }
            browser.offerFailures[repo] = error.localizedDescription
        }
    }
}
