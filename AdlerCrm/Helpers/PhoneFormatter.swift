// AdlerCRM/Helpers/PhoneFormatter.swift  07/04/2026 20:18:54
import Foundation

enum PhoneFormatter {
    /// Format a phone string as (xxx) xxx-xxxx for display
    static func format(_ phone: String?) -> String {
        guard let phone = phone, !phone.isEmpty else { return "" }
        let digits = phone.filter { $0.isNumber }
        guard digits.count == 10 else {
            // Return as-is if not exactly 10 digits
            return phone
        }
        let area = digits.prefix(3)
        let mid = digits.dropFirst(3).prefix(3)
        let last = digits.dropFirst(6)
        return "(\(area)) \(mid)-\(last)"
    }

    /// Auto-format as user types — strips non-digits then applies (xxx) xxx-xxxx
    static func autoFormat(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(10))

        switch limited.count {
        case 0:
            return ""
        case 1...3:
            return "(\(limited)"
        case 4...6:
            let area = limited.prefix(3)
            let mid = limited.dropFirst(3)
            return "(\(area)) \(mid)"
        case 7...10:
            let area = limited.prefix(3)
            let mid = limited.dropFirst(3).prefix(3)
            let last = limited.dropFirst(6)
            return "(\(area)) \(mid)-\(last)"
        default:
            return limited
        }
    }

    /// Extract raw digits from formatted phone for storage
    static func rawDigits(_ phone: String) -> String {
        return phone.filter { $0.isNumber }
    }
}
