// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import DeviceCheck
import Foundation

/// The App Attest client of a real device, built on `DCAppAttestService`.
///
/// Which App Attest environment an attestation uses is not decided here: it comes from
/// the app's `com.apple.developer.devicecheck.appattest-environment` entitlement, which
/// is `development` for debug builds and `production` for release builds.
public struct DeviceAppAttestation: AppAttestation {
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws(AppAttestationError) -> String {
        guard isSupported else { throw .unsupported }
        do {
            return try await DCAppAttestService.shared.generateKey()
        } catch {
            throw Self.map(error)
        }
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data {
        guard isSupported else { throw .unsupported }
        do {
            return try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data {
        guard isSupported else { throw .unsupported }
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    /// Apple's documentation says to replace a key that the service reports as invalid,
    /// and to try again later after any other failure.
    private static func map(_ error: any Error) -> AppAttestationError {
        guard let error = error as? DCError else { return .failed }
        switch error.code {
        case .invalidKey: return .invalidKey
        case .featureUnsupported: return .unsupported
        default: return .failed
        }
    }
}
