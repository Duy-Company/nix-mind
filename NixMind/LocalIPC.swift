import Foundation
import Darwin

enum LocalIPC {
    static var directory: String { "/private/tmp/nixmind-\(getuid())" }
    static var path: String { directory + "/app.sock" }
    static func address() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        return address
    }
    static func configure(_ fd: Int32) {
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    static func read(_ fd: Int32) throws -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { throw AIError("The local Nix Mind connection closed or timed out.") }
            if let end = buffer.prefix(count).firstIndex(of: 10) {
                guard data.count + end <= 16_000_000 else { throw AIError("Local request exceeds 16 MB.") }
                data.append(contentsOf: buffer[..<end]); return data
            }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 16_000_000 else { throw AIError("Local request exceeds 16 MB.") }
        }
    }
    static func write(_ data: Data, to fd: Int32) throws {
        var payload = data; payload.append(10)
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                guard count > 0 else { throw AIError("Cannot write to the local Nix Mind connection.") }
                sent += count
            }
        }
    }
    static func request(_ object: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AIError("Cannot create local socket.") }
        defer { close(fd) }
        configure(fd)
        var addr = address()
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw AIError("Open Nix Mind and enable local MCP from the bottom toolbar first.") }
        try write(JSONSerialization.data(withJSONObject: object), to: fd)
        guard let response = try JSONSerialization.jsonObject(with: read(fd)) as? [String: Any] else { throw AIError("Invalid response from Nix Mind.") }
        if let message = response["error"] as? String { throw AIError(message) }
        return response["result"] as? [String: Any] ?? [:]
    }
}

/// The UI process owns the socket. Same-user clients exchange one JSON request per connection.
final class LocalMCPService: @unchecked Sendable {
    private var fd: Int32 = -1
    @MainActor func start() throws {
        guard fd < 0 else { return }
        let manager = FileManager.default
        if !manager.fileExists(atPath: LocalIPC.directory) {
            try manager.createDirectory(atPath: LocalIPC.directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try manager.attributesOfItem(atPath: LocalIPC.directory)
        guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw AIError("Local MCP directory has an unexpected owner or type.") }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: LocalIPC.directory)
        if manager.fileExists(atPath: LocalIPC.path) {
            if (try? LocalIPC.request(["action": "ping"])) != nil { throw AIError("Another Nix Mind instance already owns the local MCP connection.") }
            let attributes = try manager.attributesOfItem(atPath: LocalIPC.path)
            guard attributes[.type] as? FileAttributeType == .typeSocket, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw AIError("Refusing to replace an unexpected local socket file.") }
            try manager.removeItem(atPath: LocalIPC.path)
        }
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw AIError("Cannot create local MCP listener.") }
        var addr = LocalIPC.address()
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(listener); throw AIError("Cannot bind local MCP socket.") }
        chmod(LocalIPC.path, 0o600)
        guard listen(listener, 8) == 0 else { close(listener); unlink(LocalIPC.path); throw AIError("Cannot listen for local MCP clients.") }
        fd = listener
        DispatchQueue.global(qos: .userInitiated).async {
            let limit = DispatchSemaphore(value: 8)
            while true {
                let client = Darwin.accept(listener, nil, nil)
                if client < 0 { break }
                limit.wait()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { close(client); limit.signal() }
                    LocalIPC.configure(client)
                    do {
                        let data = try LocalIPC.read(client)
                        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MapError.invalid }
                        let done = DispatchSemaphore(value: 0)
                        Task { @MainActor in
                            defer { done.signal() }
                            let response: [String: Any]
                            do { response = ["result": try await MCPAppBridge.handle(object)] }
                            catch { response = ["error": error.localizedDescription] }
                            if let encoded = try? JSONSerialization.data(withJSONObject: response) { try? LocalIPC.write(encoded, to: client) }
                        }
                        done.wait()
                    } catch {
                        if let encoded = try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]) { try? LocalIPC.write(encoded, to: client) }
                    }
                }
            }
        }
    }
    @MainActor func stop() {
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR); close(fd); fd = -1
        unlink(LocalIPC.path)
    }
}
