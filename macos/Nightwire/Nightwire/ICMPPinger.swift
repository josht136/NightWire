import Darwin
import Foundation

struct ICMPPinger: Sendable {
    func ping(host: String, timeout: TimeInterval = 1.0) async -> PingOutcome {
        await Task.detached(priority: .userInitiated) {
            pingSync(host: host, timeout: timeout)
        }.value
    }

    private func pingSync(host: String, timeout: TimeInterval) -> PingOutcome {
        if let ipv4 = resolve(host: host, family: AF_INET) {
            let icmp = pingIPv4(address: ipv4, timeout: 0.25)
            if case .success = icmp {
                return icmp
            }
        }
        return pingWithUtility(host: host, timeout: timeout)
    }

    private func resolve(host: String, family: Int32) -> Data? {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM

        var info: UnsafeMutablePointer<addrinfo>?
        let status = host.withCString { hostname in
            getaddrinfo(hostname, nil, &hints, &info)
        }
        guard status == 0, let info else { return nil }
        defer { freeaddrinfo(info) }
        guard let addr = info.pointee.ai_addr else { return nil }
        return Data(bytes: addr, count: Int(info.pointee.ai_addrlen))
    }

    private func pingIPv4(address: Data, timeout: TimeInterval) -> PingOutcome {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            return .failed(errnoMessage())
        }
        defer { close(fd) }

        var timeoutValue = timeval(
            tv_sec: Int(timeout),
            tv_usec: suseconds_t(max((timeout - floor(timeout)) * 1_000_000, 1))
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 1...UInt16.max)
        let sequence: UInt16 = 1
        var packet = Data(count: 16)
        packet[0] = 8
        packet[1] = 0
        packet.replaceSubrange(4..<6, with: withUnsafeBytes(of: identifier.bigEndian, Array.init))
        packet.replaceSubrange(6..<8, with: withUnsafeBytes(of: sequence.bigEndian, Array.init))
        let sum = internetChecksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xff)

        let started = CFAbsoluteTimeGetCurrent()
        let sent = address.withUnsafeBytes { addrBytes -> Int in
            guard let sa = addrBytes.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return -1
            }
            return packet.withUnsafeBytes { payload in
                sendto(fd, payload.baseAddress, packet.count, 0, sa, socklen_t(address.count))
            }
        }
        guard sent == packet.count else {
            return .failed(errnoMessage())
        }

        var reply = [UInt8](repeating: 0, count: 256)
        var from = sockaddr_storage()
        var fromLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let received = reply.withUnsafeMutableBytes { buffer in
            withUnsafeMutablePointer(to: &from) { fromPtr in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, buffer.baseAddress, buffer.count, 0, sa, &fromLen)
                }
            }
        }

        if received < 8 {
            return .timeout
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        var offset = 0
        if received >= 28, reply[0] >> 4 == 4 {
            offset = Int(reply[0] & 0x0f) * 4
        }
        guard received >= offset + 8 else { return .timeout }

        let type = reply[offset]
        let replyIdentifier = UInt16(reply[offset + 4]) << 8 | UInt16(reply[offset + 5])
        let replySequence = UInt16(reply[offset + 6]) << 8 | UInt16(reply[offset + 7])
        guard type == 0, replyIdentifier == identifier, replySequence == sequence else {
            return .timeout
        }
        return .success(milliseconds: max(elapsed, 0.1))
    }

    private func pingWithUtility(host: String, timeout: TimeInterval) -> PingOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        let waitMs = max(Int(timeout * 1000), 200)
        process.arguments = ["-c", "1", "-n", "-W", "\(waitMs)", host]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout + 1.4)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return .timeout
        }

        let output = string(from: stdout) + string(from: stderr)
        let lowered = output.lowercased()

        if lowered.contains("cannot resolve") || lowered.contains("unknown host") {
            return .unresolved
        }
        if lowered.contains("100.0% packet loss") || lowered.contains("100% packet loss") {
            return .timeout
        }
        if let match = output.range(of: #"time=([0-9.]+)\s*ms"#, options: .regularExpression) {
            let token = String(output[match])
            let digits = token
                .replacingOccurrences(of: "time=", with: "")
                .replacingOccurrences(of: " ms", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let value = Double(digits) {
                return .success(milliseconds: value)
            }
        }
        return .timeout
    }

    private func string(from pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func internetChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        let bytes = [UInt8](data)
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum &+= UInt32(bytes[index]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xffff) &+ (sum >> 16)
        }
        return UInt16(truncatingIfNeeded: ~sum)
    }

    private func errnoMessage() -> String {
        String(cString: strerror(errno))
    }
}
