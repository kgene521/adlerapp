// AdlerCRM/Services/HMACSigner.swift  07/04/2026 19:36:19
import Foundation
import CryptoKit

enum HMACSigner {
    // Obfuscated shared secret — XOR encoded at build time
    // To update: change plainSecret below, the xorKey, and recompute encoded bytes
    private static let xorKey: UInt8 = 0xA7
    private static let encodedSecret: [UInt8] = {
        // Original: 609ecd45cd7ef4ebbce0cd37b4ffe66cbeef6cac03a2b49aa2c2677819b3b56c
        let hex = "609ecd45cd7ef4ebbce0cd37b4ffe66cbeef6cac03a2b49aa2c2677819b3b56c"
        return Array(hex.utf8)
    }()

    private static var secret: SymmetricKey = {
        let hexString = String(bytes: encodedSecret, encoding: .utf8)!
        // Convert hex string to bytes
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
        return SymmetricKey(data: bytes)
    }()

    /// Sign a URLRequest in-place with HMAC headers
    static func sign(_ request: inout URLRequest) {
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
