// /AdlerCRM/Services/HMACSigner.swift  08/04/2026 05:30:00 EDT
import Foundation
import CryptoKit

enum HMACSigner {
    private static let keychainKey = "adler_hmac_secret"

    /// Store the HMAC secret in Keychain (called after TOTP verify)
    static func storeSecret(_ hexString: String) {
        KeychainHelper.save(key: keychainKey, value: hexString)
    }

    /// Clear the HMAC secret from Keychain (called on logout)
    static func clearSecret() {
        KeychainHelper.delete(key: keychainKey)
    }

    /// Check if an HMAC secret is available
    static var hasSecret: Bool {
        KeychainHelper.load(key: keychainKey) != nil
    }

    /// Sign a URLRequest in-place with HMAC headers.
    /// If no secret is stored (pre-login), headers are not added.
    static func sign(_ request: inout URLRequest) {
        guard let hexString = KeychainHelper.load(key: keychainKey) else {
            // No secret available (pre-login) — skip signing
            return
        }

        // Convert hex string to raw bytes for SymmetricKey
        var bytes = [UInt8]()
        var idx = hexString.startIndex
        while idx < hexString.endIndex {
            let nextIdx = hexString.index(idx, offsetBy: 2)
            let byteStr = hexString[idx..<nextIdx]
            if let byte = UInt8(byteStr, radix: 16) {
                bytes.append(byte)
            }
            idx = nextIdx
        }
        let secret = SymmetricKey(data: bytes)

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString

        // Extract path from URL (path + query)
        let path: String
        if let url = request.url {
            var p = url.path
            if let query = url.query { p += "?\(query)" }
            path = p
        } else {
            path = "/"
        }

        let method = (request.httpMethod ?? "GET").uppercased()

        // Body hash: SHA256 of body for JSON requests, empty for multipart/no-body
        let bodyHash: String
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json"), let bodyData = request.httpBody {
            bodyHash = SHA256.hash(data: bodyData).compactMap { String(format: "%02x", $0) }.joined()
        } else if request.httpBody == nil || contentType.contains("multipart") {
            bodyHash = ""
        } else {
            bodyHash = ""
        }

        // message = method\npath\ntimestamp\nnonce\nbodyHash
        let message = [method, path, timestamp, nonce, bodyHash].joined(separator: "\n")
        let messageData = Data(message.utf8)

        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: secret)
        let signatureHex = signature.compactMap { String(format: "%02x", $0) }.joined()

        request.setValue(timestamp, forHTTPHeaderField: "X-App-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-App-Nonce")
        request.setValue(signatureHex, forHTTPHeaderField: "X-App-Signature")
    }
}
