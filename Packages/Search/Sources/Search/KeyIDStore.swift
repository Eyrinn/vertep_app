// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Security
import Synchronization

/// Keeps the id of the app's App Attest key between launches.
public protocol KeyIDStore: Sendable {
    /// The stored key id, or nil when none is stored.
    func load() -> String?
    func save(_ keyID: String)
    func delete()
}

/// Keeps the key id in the Keychain.
///
/// The item is readable after the first unlock since the device started, and only on this
/// device: an App Attest key never leaves the device that created it, so its id is not
/// restored to another device from a backup.
public struct KeychainKeyIDStore: KeyIDStore {
    private let service: String
    private let account = "app-attest-key-id"

    /// `service` names the Keychain item. Different values keep different keys.
    public init(service: String) {
        self.service = service
    }

    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ keyID: String) {
        delete()
        var item = baseQuery
        item[kSecValueData as String] = Data(keyID.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Keeps the key id in memory only, so every new instance starts without a key. A test
/// uses it to make the app attest a new key.
public final class InMemoryKeyIDStore: KeyIDStore {
    private let keyID: Mutex<String?>

    public init(keyID: String? = nil) {
        self.keyID = Mutex(keyID)
    }

    public func load() -> String? {
        keyID.withLock { $0 }
    }

    public func save(_ keyID: String) {
        self.keyID.withLock { $0 = keyID }
    }

    public func delete() {
        keyID.withLock { $0 = nil }
    }
}
