//
//  LumeEngineCoordinator+Failures.swift
//  Lume
//
//  Where a failed LumeEngine session is routed, the startup watchdog, and the
//  wait for the previous session's shutdown before the next one opens. Split
//  out of LumeEngineCoordinator to keep that file within the project's size
//  limit.
//

import Foundation
import LumeEngine
import OSLog

extension LumeEngineCoordinator {
    /// How long a new session waits for the previous one to close its
    /// connection. The engine bounds its own shutdown at 5 s; past this, a
    /// channel switch would feel stuck, so the new session opens regardless.
    static let shutdownGrace: Duration = .seconds(2)

    /// The session is finished: it failed, or never started within the startup
    /// window. Reported once per session. A stream that has played goes to the
    /// reconnect path (`onStalled`), anything else to the startup-failure path.
    func streamFailed(_ failure: LumeEngineFailure) {
        guard !reportedFailure else { return }
        reportedFailure = true
        // Local copies: os_log interpolation is an autoclosure; swiftformat strips `self.`
        let started = hasStartedPlayback
        let played = hasPlayedStream
        let cause = failure.rawValue
        if failure == .sourceEnded {
            Logger.player.info("LumeEngine live source ended (hasStartedPlayback: \(started), hasPlayedStream: \(played))")
        } else {
            Logger.player.error("LumeEngine failed: \(cause, privacy: .public) (hasStartedPlayback: \(started), hasPlayedStream: \(played))")
        }
        if started || played {
            onStalled?(failure)
        } else {
            PlaybackQoE.shared.noteStartupFailure()
            onPlaybackFailure?(failure)
        }
    }

    /// Startup failure watchdog. The window is rolling while the engine
    /// demonstrably downloads: a multi-second buffer target on a ~1× link
    /// legitimately pre-buffers past any fixed window, while a dead stream
    /// shows no byte progress and still fails within `startupTimeout`. A hard
    /// cap bounds pathological "downloads but never starts" cases.
    func makeStartupWatchdog() -> Task<Void, Never> {
        Task { [startupTimeout] in
            let hardDeadline = Date(timeIntervalSinceNow: max(startupTimeout * 3, 60))
            var deadline = Date(timeIntervalSinceNow: startupTimeout)
            var lastBytes: Int64 = 0
            while !Task.isCancelled, !self.hasStartedPlayback {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, !self.hasStartedPlayback else { return }
                if let session = self.session {
                    let bytes = await session.diagnostics.deliveredBytes
                    if bytes > lastBytes {
                        lastBytes = bytes
                        deadline = min(Date(timeIntervalSinceNow: startupTimeout), hardDeadline)
                    }
                }
                if Date() >= deadline {
                    Logger.player.error("LumeEngine startup window elapsed (read \(lastBytes) bytes, never played)")
                    self.streamFailed(.interrupted)
                    return
                }
            }
        }
    }

    /// Returns once `shutdown` has finished, or after `shutdownGrace`.
    /// Awaiting a task's value can't be cancelled, so a task-group race would
    /// still wait the shutdown out; the gate resumes on whichever comes first.
    static func waitForShutdown(_ shutdown: Task<Void, Never>?) async {
        guard let shutdown else { return }
        let gate = ShutdownGate()
        await withCheckedContinuation { continuation in
            gate.continuation = continuation
            Task {
                await shutdown.value
                gate.open(timedOut: false)
            }
            Task {
                try? await Task.sleep(for: shutdownGrace)
                gate.open(timedOut: true)
            }
        }
    }
}

/// Resumes the shutdown wait exactly once, whichever racer gets there first.
private final class ShutdownGate {
    var continuation: CheckedContinuation<Void, Never>?

    func open(timedOut: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        if timedOut {
            Logger.player.warning("LumeEngine previous session still closing; opening the next one anyway")
        }
        continuation.resume()
    }
}
