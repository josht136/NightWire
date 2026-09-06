import Foundation
import Network

struct HostValidationError: Error {
    let message: String
}

enum HostValidator {
    static func normalize(_ raw: String) -> Result<String, HostValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(HostValidationError(message: "Enter an IP or hostname"))
        }
        guard trimmed.count <= 253 else {
            return .failure(HostValidationError(message: "Host is too long"))
        }
        guard !trimmed.contains(where: \.isWhitespace) else {
            return .failure(HostValidationError(message: "Host cannot contain spaces"))
        }

        let banned = CharacterSet(charactersIn: ";|&$`<>\\\"'{}()[]!*?#%^\n\r\t")
        if trimmed.unicodeScalars.contains(where: { banned.contains($0) }) {
            return .failure(HostValidationError(message: "Invalid characters in host"))
        }

        if IPv4Address(trimmed) != nil {
            return .success(trimmed)
        }
        if IPv6Address(trimmed) != nil {
            return .success(trimmed)
        }

        if trimmed.hasPrefix(".") || trimmed.hasSuffix(".") || trimmed.contains("..") {
            return .failure(HostValidationError(message: "Invalid hostname"))
        }

        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else {
            return .failure(HostValidationError(message: "Invalid hostname"))
        }

        for label in labels {
            guard (1...63).contains(label.count) else {
                return .failure(HostValidationError(message: "Invalid hostname"))
            }
            guard let first = label.first, first.isLetter || first.isNumber else {
                return .failure(HostValidationError(message: "Invalid hostname"))
            }
            guard label.last != "-" else {
                return .failure(HostValidationError(message: "Invalid hostname"))
            }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                return .failure(HostValidationError(message: "Invalid hostname"))
            }
        }

        return .success(trimmed.lowercased())
    }
}
