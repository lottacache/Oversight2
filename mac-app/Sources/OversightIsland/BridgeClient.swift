import Foundation

final class BridgeClient: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let queue = DispatchQueue(label: "oversight.island.bridge")
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    init() throws {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bridge/src/island/sidecar.js")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../src/island/sidecar.js")
        guard let script = [bundled, development].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw NSError(domain: "OversightIsland", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "TradingView bridge was not bundled with the app"])
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.currentDirectoryURL = script.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            self?.queue.async { self?.consume(bytes) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.failAll("TradingView bridge exited") }
        }
        try process.run()
    }

    deinit {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func send(_ message: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.process.isRunning else {
                    continuation.resume(throwing: self.error("TradingView bridge is not running"))
                    return
                }
                let id = self.nextID
                self.nextID += 1
                var request = message
                request["id"] = id
                do {
                    var bytes = try JSONSerialization.data(withJSONObject: request)
                    bytes.append(0x0A)
                    self.pending[id] = continuation
                    try self.input.fileHandleForWriting.write(contentsOf: bytes)
                } catch {
                    self.pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func consume(_ bytes: Data) {
        guard !bytes.isEmpty else { failAll("TradingView bridge closed its output"); return }
        buffer.append(bytes)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let response = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = response["id"] as? Int,
                  let continuation = pending.removeValue(forKey: id) else { continue }
            if response["ok"] as? Bool == true {
                continuation.resume(returning: response["data"] as? [String: Any] ?? [:])
            } else {
                continuation.resume(throwing: error(response["error"] as? String ?? "Bridge request failed"))
            }
        }
    }

    private func failAll(_ message: String) {
        for continuation in pending.values { continuation.resume(throwing: error(message)) }
        pending.removeAll()
    }

    private func error(_ message: String) -> Error {
        NSError(domain: "OversightIsland", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
