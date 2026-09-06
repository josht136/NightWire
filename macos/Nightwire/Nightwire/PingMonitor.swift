import Foundation
import Observation

@MainActor
@Observable
final class PingMonitor {
    var targets: [TrackedTarget] = []
    var addText = ""
    var addError: String?
    var isRunning = false
    var lastTick: Date?
    var chartSettings = ChartSettings()

    private let store: HostStore
    private let pinger = ICMPPinger()
    private var loop: Task<Void, Never>?

    static let defaultHosts = ["8.8.8.8", "1.1.1.1"]
    static let interval: Duration = .seconds(2)
    static let historyLimit = 450

    init(store: HostStore? = nil) {
        if let store {
            self.store = store
        } else {
            let directory = Self.supportDirectory()
            do {
                self.store = try HostStore(directory: directory)
            } catch {
                preconditionFailure("Unable to open Nightwire store: \(error)")
            }
        }
        bootstrap()
    }

    func start() {
        guard loop == nil else { return }
        isRunning = true
        loop = Task { [weak self] in
            await self?.tick()
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { break }
                await self.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    @discardableResult
    func addCurrent() -> Bool {
        let raw = addText
        switch HostValidator.normalize(raw) {
        case .failure(let error):
            addError = error.message
            return false
        case .success(let address):
            if targets.contains(where: { $0.address.caseInsensitiveCompare(address) == .orderedSame }) {
                addError = "Already tracking \(address)"
                return false
            }
            let colorIndex = nextColorIndex()
            let target = TrackedTarget(address: address, colorIndex: colorIndex)
            targets.append(target)
            store.upsert(target)
            addText = ""
            addError = nil
            Task { await pingOne(target) }
            return true
        }
    }

    func remove(_ target: TrackedTarget) {
        if target.role == .gateway {
            AppSettings.shared.autoTrackGateway = false
        }
        targets.removeAll { $0.id == target.id }
        store.delete(id: target.id)
    }

    func syncGateway(_ address: String?) {
        guard AppSettings.shared.autoTrackGateway else { return }
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }

        if let existing = targets.first(where: { $0.role == .gateway }) {
            if existing.address.caseInsensitiveCompare(trimmed) == .orderedSame {
                return
            }
            if let other = targets.first(where: {
                $0.id != existing.id && $0.address.caseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                other.role = .gateway
                if !other.hasCustomLabel {
                    other.label = "Gateway"
                }
                store.upsert(other)
                targets.removeAll { $0.id == existing.id }
                store.delete(id: existing.id)
                return
            }
            existing.address = trimmed
            if !existing.hasCustomLabel || existing.trimmedLabel == "Gateway" {
                existing.label = "Gateway"
            }
            store.upsert(existing)
            Task { await pingOne(existing) }
            return
        }

        if let other = targets.first(where: { $0.address.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            other.role = .gateway
            if !other.hasCustomLabel {
                other.label = "Gateway"
            }
            store.upsert(other)
            return
        }

        let target = TrackedTarget(
            address: trimmed,
            label: "Gateway",
            colorIndex: nextColorIndex(),
            colorHex: Theme.hostColorHex(at: 4),
            role: .gateway
        )
        targets.append(target)
        store.upsert(target)
        Task { await pingOne(target) }
    }

    func toggleVisibility(_ target: TrackedTarget) {
        target.isVisibleOnChart.toggle()
        store.upsert(target)
    }

    func persist(_ target: TrackedTarget) {
        store.upsert(target)
    }

    func setLabel(_ target: TrackedTarget, _ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        target.label = String(trimmed.prefix(80))
        store.upsert(target)
    }

    func setColor(_ target: TrackedTarget, hex: String, paletteIndex: Int?) {
        target.colorHex = hex
        if let paletteIndex {
            target.colorIndex = paletteIndex
        }
        store.upsert(target)
    }

    func setGroup(_ target: TrackedTarget, _ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        target.groupName = String(trimmed.prefix(40))
        store.upsert(target)
    }

    func updateChartSettings(_ mutate: (inout ChartSettings) -> Void) {
        mutate(&chartSettings)
        chartSettings.yMin = max(0, min(chartSettings.yMin, 10_000))
        chartSettings.yMax = max(chartSettings.yMin + 1, min(chartSettings.yMax, 10_000))
        store.saveChartSettings(chartSettings)
    }

    var visibleTargets: [TrackedTarget] {
        targets.filter(\.isVisibleOnChart)
    }

    var knownGroups: [String] {
        let names = Set(targets.map(\.trimmedGroup).filter { !$0.isEmpty })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func chartPanes() -> [ChartPaneModel] {
        let visible = visibleTargets
        var groups: [String: [TrackedTarget]] = [:]
        var solos: [TrackedTarget] = []
        for target in visible {
            if target.hasGroup {
                groups[target.trimmedGroup, default: []].append(target)
            } else {
                solos.append(target)
            }
        }

        let named = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var panes: [ChartPaneModel] = named.map { name in
            ChartPaneModel(
                id: "group:\(name.lowercased())",
                title: name,
                isGroup: true,
                targets: groups[name] ?? []
            )
        }
        panes.append(contentsOf: solos.map { target in
            ChartPaneModel(
                id: "solo:\(target.id.uuidString)",
                title: target.displayName,
                isGroup: false,
                targets: [target]
            )
        })
        return panes
    }

    private func bootstrap() {
        chartSettings = store.loadChartSettings()
        var loaded = store.loadTargets()
        if loaded.isEmpty {
            for (index, host) in Self.defaultHosts.enumerated() {
                let target = TrackedTarget(address: host, colorIndex: index)
                store.upsert(target)
                loaded.append(target)
            }
        }
        for target in loaded {
            target.samples = store.loadSamples(targetId: target.id, limit: Self.historyLimit)
            if let last = target.samples.last {
                if let ms = last.latencyMs {
                    target.lastResult = .success(milliseconds: ms)
                } else {
                    target.lastResult = .timeout
                }
            }
        }
        targets = loaded
    }

    private func tick() async {
        lastTick = Date()
        let snapshot = targets.map { (id: $0.id, address: $0.address) }
        let engine = pinger
        await withTaskGroup(of: (UUID, PingOutcome).self) { group in
            for item in snapshot {
                group.addTask {
                    let outcome = await engine.ping(host: item.address)
                    return (item.id, outcome)
                }
            }
            for await (id, outcome) in group {
                apply(id: id, outcome: outcome)
            }
        }
        store.prune(keepLast: Self.historyLimit * max(targets.count, 1))
    }

    private func pingOne(_ target: TrackedTarget) async {
        let outcome = await pinger.ping(host: target.address)
        apply(id: target.id, outcome: outcome)
    }

    private func apply(id: UUID, outcome: PingOutcome) {
        guard let target = targets.first(where: { $0.id == id }) else { return }
        let sample = PingSample(latencyMs: outcome.latencyMs)
        target.lastResult = outcome
        target.samples.append(sample)
        if target.samples.count > Self.historyLimit {
            target.samples.removeFirst(target.samples.count - Self.historyLimit)
        }
        store.insertSample(targetId: target.id, timestamp: sample.timestamp, latencyMs: sample.latencyMs)
        store.upsert(target)
    }

    private func nextColorIndex() -> Int {
        let used = Set(targets.map(\.colorIndex))
        if let free = (0..<Theme.hostColors.count).first(where: { !used.contains($0) }) {
            return free
        }
        return targets.count
    }

    static func supportDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("Nightwire", isDirectory: true)
    }
}
