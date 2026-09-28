import Foundation
import GGChatCore

/// When each pipe's machine was last heard, and whether it has failed to
/// answer.
///
/// Stamped with the model's `now` at a handful of moments, never for each
/// token: the pipe connects; a reply finishes; a model list or a status answer
/// arrives; an error arrives carrying a code the machine wrote; the pipe
/// stops being connected. `tunnel_unavailable` is not hearing, because this
/// device's end of the pipe writes it when no tunnel is up, and a transport
/// error is not either. The time is kept in the store on the provider's row,
/// so it outlives a relaunch and goes when the provider does.
///
/// The caption under the pill waits for more than a pipe that is looking,
/// because every return to the foreground dials again, and a dial looks
/// before it connects. A provider is marked as not answering when its dial
/// fails, its pipe closes on its own, its connected pipe falls back to
/// looking, or a request through it is refused with `tunnel_unavailable`;
/// the mark goes when the pipe next connects. A hang-up this app performs
/// does not set it, and there is no timer.
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

    /// The line under the pill while this conversation's machine is not
    /// answering: "home · last heard 08:12", or "home · not heard from yet".
    /// Nil for a server added by address, for a pipe that is connected, and
    /// for one that is only looking.
    public func silenceCaption(for conversation: Conversation, locale: Locale, calendar: Calendar) -> String? {
        guard let config = provider(for: conversation), unanswered.contains(config.id) else { return nil }
        return "\(config.name) · \(lastHeardLine(for: config.id, locale: locale, calendar: calendar))"
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
    /// no tunnel is up, so the machine has not answered. An error with no
    /// code says nothing.
    func note(_ error: any Error, from providerID: UUID) {
        guard let code = (error as? ProviderError)?.code else { return }
        if code == ProviderError.Code.tunnelUnavailable.rawValue {
            notAnswering(providerID)
        } else {
            heard(providerID)
        }
    }

    /// What a change of status says. A pipe that connects, and one that stops
    /// being connected, was heard then. Connecting clears the mark; closing
    /// on its own, or falling back from connected to looking, sets it.
    ///
    /// - Parameter closedOnItsOwn: whether the session itself reported the
    ///   close, which a hang-up this app performs never does: it stops
    ///   listening to the session before it shuts it down.
    func notePipeStatus(
        _ providerID: UUID, from previous: PipeStatus?, to status: PipeStatus?, closedOnItsOwn: Bool
    ) {
        let wasConnected = previous?.isConnected == true
        let isConnected = status?.isConnected == true
        if wasConnected != isConnected { heard(providerID) }
        if isConnected {
            unanswered.remove(providerID)
        } else if closedOnItsOwn || (wasConnected && status == .idle) {
            notAnswering(providerID)
        }
    }

    /// Marks a pipe's machine as having failed to answer, unless the pipe
    /// reads as connected or the provider is gone. Connecting clears it, so a
    /// marked pipe is never a connected one.
    func notAnswering(_ providerID: UUID) {
        guard providers.first(where: { $0.id == providerID })?.isPipe == true,
            pipeStatuses[providerID]?.isConnected != true
        else { return }
        unanswered.insert(providerID)
    }

    /// Forgets a removed provider's time and mark. The row the time was kept
    /// on went with the delete.
    func forgetLastHeard(_ providerID: UUID) {
        lastHeardAt[providerID] = nil
        unanswered.remove(providerID)
    }
}
