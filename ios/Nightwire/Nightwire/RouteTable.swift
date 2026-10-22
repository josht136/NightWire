import Darwin
import Foundation

enum RouteTable {
    struct Record: Equatable, Sendable {
        var destination: String
        var gateway: String
        var mac: String
        var ifname: String
        var isDefault: Bool
        var isNeighbor: Bool
    }

    struct Media: Equatable, Sendable {
        var valid: Bool
        var type: Int32
        var subtype: Int32
        var status: Int32
    }

    enum ReadFailure: Error {
        case unavailable
    }

    static func read() -> Result<[Record], ReadFailure> {
        let capacity = 1024
        let bytes = capacity * MemoryLayout<nw_route_record>.stride
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bytes,
            alignment: MemoryLayout<nw_route_record>.alignment
        )
        defer { buffer.deallocate() }
        memset(buffer, 0, bytes)
        let pointer = buffer.bindMemory(to: nw_route_record.self, capacity: capacity)
        let count = nw_copy_routes(pointer, Int32(capacity))
        guard count >= 0 else { return .failure(.unavailable) }

        var records: [Record] = []
        records.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let raw = pointer[index]
            records.append(
                Record(
                    destination: cString(raw.destination),
                    gateway: cString(raw.gateway),
                    mac: cString(raw.mac),
                    ifname: cString(raw.ifname),
                    isDefault: raw.is_default != 0,
                    isNeighbor: raw.is_neighbor != 0
                )
            )
        }
        return .success(records)
    }

    static func systemDNS() -> [String] {
        let capacity = 8
        let slot = 48
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity * slot)
        defer { buffer.deallocate() }
        let count = Int(nw_copy_dns(buffer, Int32(capacity)))
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            let text = String(cString: buffer.advanced(by: index * slot))
            return text.isEmpty ? nil : text
        }
    }

    static func media(for name: String) -> Media {
        name.withCString { pointer in
            let info = nw_read_media(pointer)
            return Media(
                valid: info.valid != 0,
                type: info.type,
                subtype: info.subtype,
                status: info.status
            )
        }
    }

    private static func cString<T>(_ value: T) -> String {
        withUnsafePointer(to: value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
