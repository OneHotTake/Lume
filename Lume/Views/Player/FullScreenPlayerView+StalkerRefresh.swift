//
//  FullScreenPlayerView+StalkerRefresh.swift
//  Lume
//
//  A fresh Stalker stream URL for an engine reconnecting after the portal
//  refused the old one (HTTP 401/403), kept out of the main file (which is at
//  its length cap).
//

import OSLog
import SwiftData
import SwiftUI

extension FullScreenPlayerView {
    /// `freshStalkerURL` for a Stalker stream, `nil` for sources that reconnect
    /// through their original URL.
    var stalkerURLRefresh: (() async -> URL?)? {
        guard StalkerLink.isPlaceholder(activeMedia.url) else { return nil }
        return { await freshStalkerURL() }
    }

    /// A fresh `create_link` URL for the active Stalker stream, for a reconnect
    /// after the portal refused the old one. Leaves `resolvedMedia` alone: the
    /// engine swaps the URL into its running stream, and a new `media` would
    /// restart it as a new stream with a fresh reconnect budget. `nil` when
    /// the portal can't resolve one, so the reconnect retries the old URL.
    func freshStalkerURL() async -> URL? {
        do {
            return try await StalkerStreamResolver.resolve(activeMedia, container: modelContext.container).url
        } catch {
            let detail = (error as? StalkerError)?.logDescription ?? LogRedaction.describe(error)
            Logger.player.error("Stalker re-resolution for a reconnect failed: \(detail, privacy: .public)")
            return nil
        }
    }
}
