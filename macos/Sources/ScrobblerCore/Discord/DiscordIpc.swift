import Darwin
import Foundation

struct DiscordIpcError: Error, CustomStringConvertible {
    let description: String
}

/// Talks to the Discord desktop app over its local Unix socket ($TMPDIR/discord-ipc-N), the same
/// "Rich Presence" protocol the official SDKs use. Frames are [int32 opcode][int32 length][UTF-8 JSON],
/// little-endian. Calls block, so use them off the main thread.
final class DiscordIpc: @unchecked Sendable {
    private enum Opcode: Int32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    private let lock = NSLock()
    private let writeLock = NSLock()
    private var fd: Int32 = -1
    private var connected = false

    var isConnected: Bool { lock.withLock { connected } }

    /// Errors Discord reports for a command (e.g. an invalid activity), for the log. Called on a background thread.
    var onError: ((String) -> Void)?

    func connect(clientId: String) throws {
        let dir = NSTemporaryDirectory()
        for i in 0..<10 where fd < 0 {
            fd = Self.open(path: (dir as NSString).appendingPathComponent("discord-ipc-\(i)"))
        }
        if fd < 0 { throw DiscordIpcError(description: "Discord isn't running") }

        try write(.handshake, ActivityBuilder.json(["v": 1, "client_id": clientId]))
        let (op, payload) = try readFrame()
        if op != Opcode.frame.rawValue || !payload.contains("\"READY\"") {
            throw DiscordIpcError(description: "Discord refused the connection: \(payload)")
        }

        lock.withLock { connected = true }
        Thread.detachNewThread { [self] in readLoop() }
    }

    /// Shows an activity (a JSON object) or clears it (nil).
    func setActivity(_ activityJson: String?) throws {
        let command = "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":\(getpid()),\"activity\":\(activityJson ?? "null")},\"nonce\":\"\(UUID().uuidString)\"}"
        try write(.frame, command)
    }

    func close() {
        lock.withLock {
            connected = false
            if fd >= 0 {
                shutdown(fd, SHUT_RDWR) // wakes up the read loop
                Darwin.close(fd)
                fd = -1
            }
        }
    }

    deinit { close() }

    private static func open(path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }

        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        if s < 0 { return -1 }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) // a closed Discord must not kill the app
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 {
            Darwin.close(s)
            return -1
        }
        return s
    }

    private func readLoop() {
        while isConnected {
            guard let (op, payload) = try? readFrame() else { break }
            switch Opcode(rawValue: op) {
            case .ping: try? write(.pong, payload)
            case .close: lock.withLock { connected = false }
            case .frame: if payload.contains("\"evt\":\"ERROR\"") { onError?(payload) }
            default: break
            }
        }
        // Discord quit or the socket broke; the owner reconnects later.
        lock.withLock { connected = false }
    }

    private func write(_ op: Opcode, _ json: String) throws {
        let body = Array(json.utf8)
        var frame = [UInt8]()
        frame.reserveCapacity(8 + body.count)
        withUnsafeBytes(of: op.rawValue.littleEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(body.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(contentsOf: body)

        try writeLock.withLock {
            var sent = 0
            while sent < frame.count {
                let n = frame.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, frame.count - sent) }
                if n <= 0 {
                    lock.withLock { connected = false }
                    throw DiscordIpcError(description: "Lost the connection to Discord")
                }
                sent += n
            }
        }
    }

    private func readFrame() throws -> (Int32, String) {
        let header = try readExactly(8)
        let op = header.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: Int32.self)) }
        let length = header.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: Int32.self)) }
        if length < 0 || length > 1_000_000 { throw DiscordIpcError(description: "Unexpected data from Discord") }
        let body = try readExactly(Int(length))
        return (op, String(decoding: body, as: UTF8.self))
    }

    private func readExactly(_ count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + got, count - got) }
            if n <= 0 { throw DiscordIpcError(description: "Discord closed the connection") }
            got += n
        }
        return buffer
    }
}
