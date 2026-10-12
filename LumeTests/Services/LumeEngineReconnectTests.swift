import Foundation
@testable import Lume
import Testing

// `LumeEngineFailure.init(_:)` itself isn't covered here: the test bundle
// doesn't link LumeEngine, so it can't build an `EngineError`.

@MainActor
struct LumeEngineShutdownWaitTests {
    @Test func `opens right after a shutdown that finishes quickly`() async {
        let shutdown = Task<Void, Never> {}
        let start = ContinuousClock.now
        await LumeEngineCoordinator.waitForShutdown(shutdown)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func `stops waiting for a shutdown that hangs once the grace period passes`() async {
        let shutdown = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let start = ContinuousClock.now
        await LumeEngineCoordinator.waitForShutdown(shutdown)
        let waited = ContinuousClock.now - start
        shutdown.cancel()
        #expect(waited >= LumeEngineCoordinator.shutdownGrace)
        #expect(waited < LumeEngineCoordinator.shutdownGrace + .seconds(3))
    }

    @Test func `nothing to wait for without a previous session`() async {
        let start = ContinuousClock.now
        await LumeEngineCoordinator.waitForShutdown(nil)
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}

@MainActor
struct PlaybackRetryPaceTests {
    @Test func `an overloaded source waits longer before every attempt`() {
        let normal = PlaybackRetryController.Pace.normal.schedule
        let overloaded = PlaybackRetryController.Pace.overloaded.schedule
        #expect(zip(normal, overloaded).allSatisfy { $0 < $1 })
    }

    @Test func `both paces spend the same attempt budget`() {
        #expect(PlaybackRetryController.Pace.overloaded.schedule.count == PlaybackRetryController.Pace.normal.schedule.count)
    }
}
