import Foundation

/// Reads only this UI submission's existing Example status records.
struct ExampleClientConnectionObservation {
    enum State: Equatable {
        case pending
        case accepted
        case connected
        case failed(Int32)
    }

    let statusLog: String
    private let byteOffset: Int

    init(statusLog: String) {
        self.statusLog = statusLog
        byteOffset = (try? Data(contentsOf: URL(fileURLWithPath: statusLog)).count) ?? 0
    }

    static func state(in data: Data, after byteOffset: Int) -> State {
        let text = String(decoding: data.dropFirst(byteOffset), as: UTF8.self)
        var state = State.pending
        // A writer may still be appending its final line.
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            let fields = line.split(separator: " ")
            func code(_ key: String) -> Int32? {
                fields.first(where: { $0.hasPrefix(key + "=") })
                    .flatMap { Int32($0.dropFirst(key.count + 1)) }
            }
            if line.hasPrefix("connect-start "), let result = code("connect") {
                if result != 0 { return .failed(result) }
                if state == .pending { state = .accepted }
            } else if line == "connected" {
                state = .connected
            } else if line.hasPrefix("disconnected "), let result = code("error"), result != 0 {
                return .failed(result)
            } else if line.hasPrefix("user-facing-error "), fields.contains("context=connect"),
                let result = code("code"), result != 0
            {
                return .failed(result)
            }
        }
        return state
    }

    func state() -> State {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusLog)) else {
            return .pending
        }
        return Self.state(in: data, after: byteOffset)
    }

    func waitForConnected(timeout: TimeInterval) -> State {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            let current = state()
            switch current {
            case .connected, .failed: return current
            case .pending, .accepted: break
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return state()
    }
}
