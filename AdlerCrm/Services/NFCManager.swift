// /AdlerCRM/Services/NFCManager.swift  17/05/2026 23:38:00 EDT
import Foundation
import Combine
import CoreNFC

@MainActor
class NFCManager: NSObject, ObservableObject {
    static let shared = NFCManager()

    @Published var lastTagId: String?
    @Published var lastTagType: String?
    @Published var isScanning = false
    @Published var error: String?

    private nonisolated(unsafe) var readSession: NFCNDEFReaderSession?
    private nonisolated(unsafe) var writeSession: NFCNDEFReaderSession?
    private nonisolated(unsafe) var writePayload: String?
    private nonisolated(unsafe) var onRead: ((String, String?) -> Void)?
    private nonisolated(unsafe) var onWrite: ((Bool, String?) -> Void)?

    private override init() { super.init() }

    // MARK: - Read Tag

    func scan(completion: @escaping (String, String?) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            error = "NFC is not available on this device."
            return
        }
        onRead = completion
        error = nil
        isScanning = true

        readSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        readSession?.alertMessage = "Hold your iPhone near the NFC tag on the drum."
        readSession?.begin()
    }

    // MARK: - Write Tag

    func write(payload: String, completion: @escaping (Bool, String?) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device.")
            return
        }
        writePayload = payload
        onWrite = completion
        error = nil
        isScanning = true

        writeSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        writeSession?.alertMessage = "Hold your iPhone near the NFC tag to write."
        writeSession?.begin()
    }

}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCManager: NFCNDEFReaderSessionDelegate {

    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Session is active
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            isScanning = false
            // Don't show error if user cancelled
            let nfcError = error as? NFCReaderError
            if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
                self.error = error.localizedDescription
            }
            readSession = nil
            writeSession = nil
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Called for read-only sessions
        guard let message = messages.first, let record = message.records.first else {
            session.invalidate(errorMessage: "No data found on tag.")
            return
        }

        let tagId = extractPayload(from: record)
        let tagType = detectTagTypeFromRecord(record)

        Task { @MainActor in
            lastTagId = tagId
            lastTagType = tagType
            isScanning = false
            onRead?(tagId, tagType)
            onRead = nil
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected.")
            return
        }

        Task {
            do {
                try await session.connect(to: tag)
                let (status, capacity) = try await tag.queryNDEFStatus()

                let tagType = detectTagTypeFromCapacity(capacity)

                if session === self.writeSession {
                    // Write mode
                    guard status == .readWrite else {
                        session.invalidate(errorMessage: "Tag is not writable.")
                        await MainActor.run {
                            isScanning = false
                            onWrite?(false, "Tag is read-only.")
                            onWrite = nil
                        }
                        return
                    }
                    guard let payload = self.writePayload else {
                        session.invalidate(errorMessage: "No data to write.")
                        return
                    }

                    let textPayload = NFCNDEFPayload(
                        format: .nfcWellKnown,
                        type: "T".data(using: .utf8)!,
                        identifier: Data(),
                        payload: buildTextPayload(payload)
                    )
                    let message = NFCNDEFMessage(records: [textPayload])

                    try await tag.writeNDEF(message)
                    session.alertMessage = "Tag written successfully!"
                    session.invalidate()

                    await MainActor.run {
                        isScanning = false
                        onWrite?(true, nil)
                        onWrite = nil
                    }
                } else {
                    // Read mode
                    let message = try await tag.readNDEF()
                    guard let record = message.records.first else {
                        // Blank tag — use tag UID/identifier if available
                        let blankId = "BLANK_\(UUID().uuidString.prefix(8))"
                        session.invalidate()
                        await MainActor.run {
                            lastTagId = blankId
                            lastTagType = tagType
                            isScanning = false
                            onRead?(blankId, tagType)
                            onRead = nil
                        }
                        return
                    }

                    let tagId = extractPayload(from: record)
                    session.invalidate()

                    await MainActor.run {
                        lastTagId = tagId
                        lastTagType = tagType
                        isScanning = false
                        onRead?(tagId, tagType)
                        onRead = nil
                    }
                }
            } catch {
                session.invalidate(errorMessage: "Failed: \(error.localizedDescription)")
                await MainActor.run {
                    isScanning = false
                    self.error = error.localizedDescription
                    onRead = nil
                    onWrite?(false, error.localizedDescription)
                    onWrite = nil
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func extractPayload(from record: NFCNDEFPayload) -> String {
        // Handle text records (type "T")
        if record.typeNameFormat == .nfcWellKnown,
           let type = String(data: record.type, encoding: .utf8), type == "T" {
            let payload = record.payload
            if payload.count > 1 {
                let langCodeLength = Int(payload[0] & 0x3F)
                let textStart = 1 + langCodeLength
                if textStart < payload.count {
                    return String(data: payload[textStart...], encoding: .utf8) ?? payload.map { String(format: "%02X", $0) }.joined()
                }
            }
        }
        // Handle URI records (type "U")
        if record.typeNameFormat == .nfcWellKnown,
           let type = String(data: record.type, encoding: .utf8), type == "U" {
            if let url = record.wellKnownTypeURIPayload() {
                return url.absoluteString
            }
        }
        // Fallback: raw hex
        let payload = record.payload
        if payload.isEmpty {
            return "EMPTY_\(UUID().uuidString.prefix(8))"
        }
        return payload.map { String(format: "%02X", $0) }.joined()
    }

    nonisolated private func detectTagTypeFromRecord(_ record: NFCNDEFPayload) -> String? {
        // Can't reliably detect from record alone
        return nil
    }

    nonisolated private func detectTagTypeFromCapacity(_ capacity: Int) -> String? {
        switch capacity {
        case 1...144:   return "NTAG213"
        case 145...504: return "NTAG215"
        case 505...888: return "NTAG216"
        default:        return capacity > 0 ? "NDEF (\(capacity) bytes)" : nil
        }
    }

    nonisolated private func buildTextPayload(_ text: String) -> Data {
        let lang = "en"
        let langData = lang.data(using: .utf8)!
        let textData = text.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(langData.count))
        payload.append(langData)
        payload.append(textData)
        return payload
    }
}
