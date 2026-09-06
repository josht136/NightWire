import Foundation
import SwiftUI

enum PingOutcome: Equatable, Sendable {
    case success(milliseconds: Double)
    case timeout
    case unresolved
    case failed(String)

    var latencyMs: Double? {
        if case .success(let milliseconds) = self {
            return milliseconds
        }
        return nil
    }

    var display: String {
        switch self {
        case .success(let milliseconds):
            if milliseconds < 10 {
                return String(format: "%.1f ms", milliseconds)
            }
            return String(format: "%.0f ms", milliseconds)
        case .timeout:
            return "timeout"
        case .unresolved:
            return "unresolved"
        case .failed:
            return "error"
        }
    }
}

struct PingSample: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let latencyMs: Double?

    init(id: UUID = UUID(), timestamp: Date = Date(), latencyMs: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.latencyMs = latencyMs
    }
}

enum TargetRole: String, Codable, Sendable {
    case user
    case gateway
}

@Observable
final class TrackedTarget: Identifiable {
    let id: UUID
    var address: String
    var label: String
    var isVisibleOnChart: Bool
    var colorIndex: Int
    var colorHex: String?
    var groupName: String
    var role: TargetRole
    var samples: [PingSample]
    var lastResult: PingOutcome?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        address: String,
        label: String = "",
        isVisibleOnChart: Bool = true,
        colorIndex: Int,
        colorHex: String? = nil,
        groupName: String = "",
        role: TargetRole = .user,
        samples: [PingSample] = [],
        lastResult: PingOutcome? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.label = label
        self.isVisibleOnChart = isVisibleOnChart
        self.colorIndex = colorIndex
        self.colorHex = colorHex
        self.groupName = groupName
        self.role = role
        self.samples = samples
        self.lastResult = lastResult
        self.createdAt = createdAt
    }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCustomLabel: Bool {
        !trimmedLabel.isEmpty
    }

    var displayName: String {
        hasCustomLabel ? trimmedLabel : address
    }

    var color: Color {
        if let colorHex, let parsed = Color(hex: colorHex) {
            return parsed
        }
        return Theme.hostColor(at: colorIndex)
    }

    var latestLatency: Double? {
        lastResult?.latencyMs ?? samples.last(where: { $0.latencyMs != nil })?.latencyMs
    }

    var trimmedGroup: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasGroup: Bool {
        !trimmedGroup.isEmpty
    }
}

enum TimeWindow: String, CaseIterable, Codable, Identifiable {
    case all
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .all: return nil
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }
}

struct ChartSettings: Equatable, Codable {
    var yAuto: Bool
    var yMin: Double
    var yMax: Double
    var timeWindow: TimeWindow

    init(
        yAuto: Bool = true,
        yMin: Double = 0,
        yMax: Double = 100,
        timeWindow: TimeWindow = .all
    ) {
        self.yAuto = yAuto
        self.yMin = yMin
        self.yMax = yMax
        self.timeWindow = timeWindow
    }

    var clampedYDomain: ClosedRange<Double> {
        let lower = max(0, min(yMin, yMax))
        let upper = max(lower + 1, max(yMin, yMax))
        return lower...upper
    }
}

struct ChartPaneModel: Identifiable {
    let id: String
    let title: String
    let isGroup: Bool
    let targets: [TrackedTarget]
}
