// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Proves to a server that requests come from a genuine copy of the app, with keys that
/// the device keeps and Apple attests.
///
/// The methods follow Apple's App Attest service. A test supplies a fake, so that code
/// built on this contract runs without a device.
public protocol AppAttestation: Sendable {
    /// Whether this device can create and attest keys. The Simulator cannot.
    var isSupported: Bool { get }

    /// Creates a new key on the device and returns its key id.
    func generateKey() async throws(AppAttestationError) -> String

    /// Asks Apple to attest the key, and returns the attestation object.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data

    /// Signs `clientDataHash` with the key, and returns the assertion object.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data
}

/// Why an attestation step failed.
public enum AppAttestationError: Error, Sendable, Hashable {
    /// This device cannot attest keys.
    case unsupported
    /// The key does not exist on this device or cannot be used any more. A new key has to
    /// be created and attested.
    case invalidKey
    /// The step failed for another reason, for example because Apple's service did not
    /// answer. A later attempt can succeed.
    case failed
}
