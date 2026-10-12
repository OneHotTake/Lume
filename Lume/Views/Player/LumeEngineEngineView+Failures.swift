//
//  LumeEngineEngineView+Failures.swift
//  Lume
//
//  What the LumeEngine host does when a stream fails to start or drops, kept
//  out of the main file (which is at its length cap).
//

import OSLog
import SwiftUI

extension LumeEngineEngineView {
    /// Mid-stream drop: bounded backoff, then give up loudly. A missing stream
    /// gives up at once, a refused one reconnects through a fresh URL, and an
    /// overloaded source gets the slower schedule.
    func reconnect(after failure: LumeEngineFailure) {
        guard failure != .notFound else {
            Logger.player.error("LumeEngine stream not found → failure overlay, no reconnect")
            reconnector.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { loadFailed = true }
            return
        }
        if !reconnector.hasGivenUp {
            let cause = failure.rawValue
            Logger.player.warning("LumeEngine dropped (\(cause, privacy: .public)) → scheduling engine reload")
            reconnector.scheduleRetry(pace: failure == .overloaded ? .overloaded : .normal) {
                guard failure == .unauthorized, let refreshStreamURL else {
                    coordinator.reload()
                    return
                }
                urlRefresh = Task {
                    let url = await refreshStreamURL()
                    guard !Task.isCancelled else { return }
                    coordinator.reload(replacingURL: url)
                }
            }
        }
        // Checked after scheduling too: the attempt that spends the budget only
        // marks it spent, and a failed session sends nothing further.
        if reconnector.hasGivenUp {
            Logger.player.error("LumeEngine reconnects exhausted → failure overlay")
            withAnimation(.easeInOut(duration: 0.25)) { loadFailed = true }
        }
    }

    /// The coordinator reported it can't start the stream. On an initial-load
    /// failure with a fallback engine available, hand off to the host (which
    /// switches engines); otherwise raise the failure overlay. A 404 skips the
    /// fallback: every engine would be asking for the same missing stream.
    func reportFailure(_ failure: LumeEngineFailure) {
        guard !loadFailed else { return }
        let fallsBack = reportsStartupFailure && !coordinator.hasStartedPlayback && failure != .notFound
        let cause = failure.rawValue
        Logger.player.error("LumeEngine startup failure (\(cause, privacy: .public)) → \(fallsBack ? "falling back to next engine" : "failure overlay", privacy: .public)")
        if fallsBack {
            onPlaybackFailed?()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { loadFailed = true }
    }
}
