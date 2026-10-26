import Foundation
import TiRTC

#if !os(macOS)
    private final class RestartPCMCounts: @unchecked Sendable {
        private let lock = NSLock()
        private var captured = 0
        private var submitted = 0
        private var error: Int32 = 0

        func record(_ code: Int32) {
            lock.lock()
            defer { lock.unlock() }
            captured += 1
            if code == 0 { submitted += 1 } else if error == 0 { error = code }
        }

        func snapshot() -> [Int] {
            lock.lock()
            defer { lock.unlock() }
            return [captured, submitted, Int(error)]
        }
    }

    // Test-owned public SDK consumer; keeps one input throughout all five cycles.
    @MainActor
    func runTalkbackRestartCase(
        audio: TiRtcAudioInput, connection: TiRtcConn, status: (String) -> Void
    ) async throws -> [String: Any] {
        func requireCode(_ operation: String, _ code: Int32, expected: Int32 = 0) throws {
            guard code == expected else {
                throw NSError(
                    domain: "TalkbackRestart", code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: "\(operation): expected \(expected), got \(code)"])
            }
        }
        let modes = [false, true, true, false, false]
        var previousRobot: Bool?
        var cycles = [[String: Any]]()
        for (index, robot) in modes.enumerated() {
            let reusedBinding = previousRobot == robot
            if previousRobot != nil && !reusedBinding {
                try requireCode("cycle \(index + 1) mode-change detach", audio.detach(connection: connection))
            }
            let options = TiRtcAudioInputOptions()
            options.media = 2
            options.sampleRate = .rate16k
            options.mode = robot ? .custom : .builtIn
            options.captureEnabled = true
            try requireCode("cycle \(index + 1) stopped setOptions reused=\(reusedBinding)", audio.setOptions(options))
            if !reusedBinding {
                try requireCode("cycle \(index + 1) attach", audio.attach(connection: connection, streamId: 14))
            }
            let changed = TiRtcAudioInputOptions()
            changed.mode = robot ? .builtIn : .custom
            try requireCode("bound route change", audio.setOptions(changed), expected: 6026)
            let counts = RestartPCMCounts()
            let effect = ExampleRobotVoiceEffect(sampleRate: 16000)
            if robot {
                audio.onPCMCaptured = { [weak audio] pcm in
                    guard let audio else { return }
                    counts.record(audio.submitPCM(effect.process(pcm)))
                }
            } else {
                audio.onPCMCaptured = nil
            }
            try requireCode("cycle \(index + 1) start", audio.start())
            try requireCode("running configuration", audio.setOptions(options), expected: 6026)
            status("talkback_restart_started cycle=\(index + 1) robot=\(robot) reused_binding=\(reusedBinding)")
            try await Task.sleep(nanoseconds: 1_100_000_000)
            try requireCode("cycle \(index + 1) stop", audio.stop())
            audio.onPCMCaptured = nil
            let stopped = counts.snapshot()
            try await Task.sleep(nanoseconds: 500_000_000)
            guard stopped == counts.snapshot(), stopped[2] == 0,
                !robot || (stopped[0] > 0 && stopped[1] > 0)
            else {
                throw NSError(
                    domain: "TalkbackRestart", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "cycle \(index + 1) custom PCM or post-stop quiet failed: \(stopped)"
                    ])
            }
            cycles.append([
                "robot": robot, "reused_binding": reusedBinding,
                "captured_blocks": stopped[0], "submitted_blocks": stopped[1], "post_stop_quiet": true,
            ])
            previousRobot = robot
        }
        return [
            "schema": "tirtc.talkback-restart/v1", "cycles": cycles,
            "start_count": 5, "stop_count": 5, "attach_count": 3, "input_reused": true,
            "bound_route_change_rejected": true, "running_configuration_rejected": true,
        ]
    }
#endif
