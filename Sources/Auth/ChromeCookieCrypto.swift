import Foundation
import Security
import CommonCrypto

/// Chrome cookie decryption without exposing keys on the process table.
///
/// Previously the Python helper ran:
/// `openssl enc -K <hex> ...` — the derived key was visible via `ps`.
/// Now Python only extracts `encrypted_value` blobs (base64); decryption
/// happens in-process via CommonCrypto, and the Safe Storage password is
/// read via Security.framework instead of the `security` CLI.
enum ChromeCookieCrypto {
    private static let salt = Data("saltysalt".utf8)
    private static let iterations: UInt32 = 1003
    private static let iv = Data(repeating: 0x20, count: 16) // 16 spaces, Chrome legacy

    private static let lock = NSLock()
    private static var cachedPassword: String?
    private static var cachedKey: Data?

    /// Password for "Chrome Safe Storage" / account "Chrome" from the login keychain.
    /// Cached per-launch: Chrome's item usually prompts on every access
    /// unless "Always Allow"ed, and cookie reads happen each poll.
    static func safeStoragePassword() -> String? {
        lock.lock()
        if let hit = cachedPassword, !hit.isEmpty { lock.unlock(); return hit }
        lock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecAttrAccount as String: "Chrome",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let pwd = String(data: data, encoding: .utf8),
              !pwd.isEmpty
        else { return nil }
        lock.lock(); cachedPassword = pwd; lock.unlock()
        return pwd
    }

    /// Derived AES key, cached per-launch alongside the password.
    static func cachedDerivedKey() -> Data? {
        lock.lock()
        if let hit = cachedKey { lock.unlock(); return hit }
        lock.unlock()
        guard let pwd = safeStoragePassword(),
              let key = deriveKey(password: pwd) else { return nil }
        lock.lock(); cachedKey = key; lock.unlock()
        return key
    }

    /// PBKDF2-HMAC-SHA1, matching Chrome's `hashlib.pbkdf2_hmac('sha1', ...)`.
    static func deriveKey(password: String) -> Data? {
        guard let pwdData = password.data(using: .utf8) else { return nil }
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { keyPtr in
            pwdData.withUnsafeBytes { pwdPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pwdData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        kCCKeySizeAES128
                    )
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    /// Decrypt a `v10` Chrome blob (3-byte header stripped before calling).
    static func decryptV10(ciphertext: Data, key: Data) -> String? {
        guard key.count == kCCKeySizeAES128, !ciphertext.isEmpty else { return nil }
        var out = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var outLen = 0
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { outPtr in
            ciphertext.withUnsafeBytes { ctPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress,
                            key.count,
                            ivPtr.baseAddress,
                            ctPtr.baseAddress,
                            ciphertext.count,
                            outPtr.baseAddress,
                            outCapacity,
                            &outLen
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLen
        guard let text = String(data: out, encoding: .utf8),
              !text.isEmpty,
              text.allSatisfy({ $0.isASCII && ($0.asciiValue ?? 0) >= 32 || $0 == "\t" || $0 == " " })
        else { return nil }
        return text
    }

    /// Convenience: base64 `encrypted_value` (with `v10` header) -> plaintext.
    static func decryptV10Base64(_ b64: String, key: Data) -> String? {
        guard let blob = Data(base64Encoded: b64),
              blob.count > 3,
              blob.prefix(3).elementsEqual(Data("v10".utf8))
        else { return nil }
        return decryptV10(ciphertext: blob.dropFirst(3) as Data, key: key)
    }
}
