// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import os

/// Tells whether the device can reach the network now, so that the app sends no request
/// while it is offline.
protocol NetworkStatus: Sendable {
    func isOnline() async -> Bool
}

/// `NetworkStatus` from the system's network path monitor.
final class SystemNetworkStatus: NetworkStatus {
    private struct State {
        /// Nil until the monitor reports the first path.
        var isOnline: Bool?
        var waiting: [CheckedContinuation<Bool, Never>] = []
    }

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {
        monitor.pathUpdateHandler = { [state] path in
            let isOnline = path.status == .satisfied
            let waiting = state.withLock { state in
                state.isOnline = isOnline
                defer { state.waiting = [] }
                return state.waiting
            }
            for continuation in waiting {
                continuation.resume(returning: isOnline)
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.vertep.ios.network-status"))
    }

    deinit {
        monitor.cancel()
    }

    /// The status of the current path. A call made before the monitor reported the first
    /// path waits for it.
    func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let known = state.withLock { state -> Bool? in
                if let isOnline = state.isOnline { return isOnline }
                state.waiting.append(continuation)
                return nil
            }
            if let known {
                continuation.resume(returning: known)
            }
        }
    }
}
