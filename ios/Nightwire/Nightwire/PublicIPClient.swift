import Darwin
import Foundation
import Network

enum PublicIPClient {
    /// Looks up the public address through `interface` only.
    /// A missing interface fails closed so another network's address is not shown.
    static func fetch(interface: NWInterface?) async -> String? {
        guard let interface else { return nil }
        let attempt = Attempt(interface: interface)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                attempt.start(continuation)
            }
        } onCancel: {
            attempt.cancel()
        }
    }

    fileprivate static func parse(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let body = text.components(separatedBy: "\r\n\r\n").last ?? text
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAddress(token) else { return nil }
        return token
    }

    private static func isAddress(_ text: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, text, &ipv4) == 1 { return true }
        var ipv6 = in6_addr()
        return inet_pton(AF_INET6, text, &ipv6) == 1
    }
}

private final class Attempt: @unchecked Sendable {
    private let connection: NWConnection
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var finished = false

    init(interface: NWInterface) {
        let parameters = NWParameters(tls: NWProtocolTLS.Options())
        parameters.requiredInterface = interface
        connection = NWConnection(host: "api.ipify.org", port: 443, using: parameters)
    }

    func start(_ continuation: CheckedContinuation<String?, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendRequest()
            case .failed, .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "nightwire.public-ip"))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finish(nil)
        }
    }

    func cancel() {
        finish(nil)
    }

    private func sendRequest() {
        let request = "GET / HTTP/1.0\r\nHost: api.ipify.org\r\nUser-Agent: Nightwire\r\n\r\n"
        connection.send(content: Data(request.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.finish(nil)
                return
            }
            self.receive(into: Data())
        })
    }

    private func receive(into data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var combined = data
            if let chunk {
                combined.append(chunk)
            }
            if error != nil || isComplete || combined.count >= 16_384 {
                self.finish(PublicIPClient.parse(combined))
                return
            }
            self.receive(into: combined)
        }
    }

    private func finish(_ value: String?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        connection.cancel()
        continuation?.resume(returning: value)
    }
}
