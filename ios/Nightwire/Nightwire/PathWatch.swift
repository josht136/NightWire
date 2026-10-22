import Foundation
import Network

struct PathSnapshot: Equatable, Sendable {
    var anyInterfaces: [String] = []
    var anyGateways: [String] = []
    var wiredInterfaces: [String] = []
    var wiredGateways: [String] = []
    var wifiInterfaces: [String] = []
    var wifiGateways: [String] = []
    var cellularInterfaces: [String] = []
    var cellularGateways: [String] = []
    var kindsByName: [String: InterfaceKind] = [:]

    static let empty = PathSnapshot()
}

/// Watches the system path plus a path restricted to each interface type.
/// A USB Ethernet adapter shows up as `wiredEthernet` while it is plugged in.
final class PathWatch: @unchecked Sendable {
    var onChange: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return onChangeHandler
        }
        set {
            lock.lock()
            onChangeHandler = newValue
            lock.unlock()
        }
    }

    private enum Key {
        case any
        case wired
        case wifi
        case cellular
    }

    private struct Facts {
        var interfaces: [String] = []
        var gateways: [String] = []
        var kindsByName: [String: InterfaceKind] = [:]
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "nightwire.path")
    private var monitors: [NWPathMonitor] = []
    private var facts: [Key: Facts] = [:]
    private var onChangeHandler: (@Sendable () -> Void)?

    func start() {
        lock.lock()
        let alreadyStarted = !monitors.isEmpty
        lock.unlock()
        guard !alreadyStarted else { return }

        start(key: .any, monitor: NWPathMonitor())
        start(key: .wired, monitor: NWPathMonitor(requiredInterfaceType: .wiredEthernet))
        start(key: .wifi, monitor: NWPathMonitor(requiredInterfaceType: .wifi))
        start(key: .cellular, monitor: NWPathMonitor(requiredInterfaceType: .cellular))
    }

    func stop() {
        lock.lock()
        let current = monitors
        monitors.removeAll()
        facts.removeAll()
        lock.unlock()
        current.forEach { $0.cancel() }
    }

    func snapshot() -> PathSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let any = facts[.any] ?? Facts()
        let wired = facts[.wired] ?? Facts()
        let wifi = facts[.wifi] ?? Facts()
        let cellular = facts[.cellular] ?? Facts()

        var kinds = any.kindsByName
        for (name, kind) in wired.kindsByName where kind != .other {
            kinds[name] = kind
        }
        for (name, kind) in wifi.kindsByName where kind != .other {
            kinds[name] = kind
        }
        for (name, kind) in cellular.kindsByName where kind != .other {
            kinds[name] = kind
        }

        return PathSnapshot(
            anyInterfaces: any.interfaces,
            anyGateways: any.gateways,
            wiredInterfaces: wired.interfaces,
            wiredGateways: wired.gateways,
            wifiInterfaces: wifi.interfaces,
            wifiGateways: wifi.gateways,
            cellularInterfaces: cellular.interfaces,
            cellularGateways: cellular.gateways,
            kindsByName: kinds
        )
    }

    /// Resolves the `NWInterface` for `name` so a connection can be pinned to it.
    func interface(named name: String) -> NWInterface? {
        if let scoped = IPv4Address("0.0.0.0%\(name)")?.interface {
            return scoped
        }
        lock.lock()
        let current = monitors
        lock.unlock()
        for monitor in current {
            if let match = monitor.currentPath.availableInterfaces.first(where: { $0.name == name }) {
                return match
            }
        }
        return nil
    }

    private func start(key: Key, monitor: NWPathMonitor) {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.replace(key, with: path)
            self?.emit()
        }
        monitor.start(queue: queue)
        lock.lock()
        monitors.append(monitor)
        lock.unlock()
        replace(key, with: monitor.currentPath)
    }

    private func replace(_ key: Key, with path: NWPath) {
        var next = Facts()
        next.interfaces = path.availableInterfaces.map(\.name)
        var kinds: [String: InterfaceKind] = [:]
        for interface in path.availableInterfaces {
            kinds[interface.name] = Self.kind(interface.type)
        }
        next.kindsByName = kinds
        next.gateways = path.gateways.compactMap(Self.gatewayText)
        lock.lock()
        facts[key] = next
        lock.unlock()
    }

    private func emit() {
        lock.lock()
        let handler = onChangeHandler
        lock.unlock()
        handler?()
    }

    private static func kind(_ type: NWInterface.InterfaceType) -> InterfaceKind {
        switch type {
        case .wiredEthernet:
            return .usbEthernet
        case .wifi:
            return .wifi
        case .cellular:
            return .cellular
        case .other, .loopback:
            return .other
        @unknown default:
            return .other
        }
    }

    private static func gatewayText(_ endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return GatewayPicker.usable("\(address)")
            case .ipv6(let address):
                return GatewayPicker.usable("\(address)")
            case .name(let name, _):
                return GatewayPicker.usable(name)
            @unknown default:
                return nil
            }
        default:
            return nil
        }
    }
}
