import Foundation

enum RateFormat {
    static func bits(_ bytesPerSecond: Double) -> String {
        let bits = max(0, bytesPerSecond) * 8
        if bits >= 1_000_000_000 {
            return String(format: "%.1f Gbps", bits / 1_000_000_000)
        }
        if bits >= 1_000_000 {
            return String(format: "%.1f Mbps", bits / 1_000_000)
        }
        if bits >= 1_000 {
            return String(format: "%.0f kbps", bits / 1_000)
        }
        return String(format: "%.0f bps", bits)
    }
}
