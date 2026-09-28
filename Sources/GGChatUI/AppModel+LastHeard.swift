import Foundation
import GGChatCore

/// When each pipe's machine was last heard.
///
/// Stamped with the model's `now` at a handful of moments, never for each
/// token: the pipe connects; a reply finishes; a model list or a status answer
/// arrives; an error arrives carrying a code the machine wrote; the pipe
/// stops being connected. `tunnel_unavailable` is not hearing, because this
/// device's end of the pipe writes it when no tunnel is up, and a transport
/// error is not either. The time is kept in the store on the provider's row,
/// so it outlives a relaunch and goes when the provider does.
extension AppModel {
    /// When this provider's machine was last heard, or nil if it never has
    /// been.
    public func lastHeard(for providerID: UUID) -> Date? {
        lastHeardAt[providerID]
    }

    /// "last heard 08:12", with the date in front when it was not today by
    /// the model's clock, or "not heard from yet".
    public func lastHeardLine(for providerID: UUID, locale: Locale, calendar: Calendar) -> String {
        Self.lastHeardLine(lastHeardAt[providerID], now: now(), locale: locale, calendar: calendar)
    }

    /// The time in the locale's short style, with the date in its short style
    /// in front when it is not the day `now` falls on in `calendar`.
    static func lastHeardLine(_ date: Date?, now: Date, locale: Locale, calendar: Calendar) -> String {
        guard let date else { return "not heard from yet" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = calendar.isDate(date, inSameDayAs: now) ? .none : .short
        formatter.timeStyle = .short
        return "last heard \(formatter.string(from: date))"
    }

    /// Something the machine wrote arrived, or its pipe changed between
    /// connected and not. Kept for a pipe provider still on the list only: a
    /// provider being removed is hung up after it has left it.
    func heard(_ providerID: UUID) {
        guard let config = providers.first(where: { $0.id == providerID }), config.isPipe else { return }
        let stamp = now()
        lastHeardAt[providerID] = stamp
        do {
            try store.save(lastHeard: stamp, forProvider: providerID)
        } catch {
            log.log(.error, "could not keep when \(config.name) was last heard (\(StoreDirectory.describe(error)))")
        }
    }

    /// What a failed request says about the machine. A code it wrote is
    /// hearing. `tunnel_unavailable` is this device's end of the pipe saying
    /// no tunnel is up, and an error with no code says nothing.
    func note(_ error: any Error, from providerID: UUID) {
        guard let code = (error as? ProviderError)?.code, code != ProviderError.Code.tunnelUnavailable.rawValue
        else { return }
        heard(providerID)
    }

    /// Hearing in a change of status: a pipe that connects, and one that
    /// stops being connected, was heard then.
    func notePipeStatus(_ providerID: UUID, from previous: PipeStatus?, to status: PipeStatus?) {
        if (previous?.isConnected == true) != (status?.isConnected == true) {
            heard(providerID)
        }
    }

    /// Forgets a removed provider's time. The row it was kept on went with
    /// the delete.
    func forgetLastHeard(_ providerID: UUID) {
        lastHeardAt[providerID] = nil
    }
}
