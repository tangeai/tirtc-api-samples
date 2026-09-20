import SwiftUI

enum ExampleRawDumpButtonState: Equatable {
    case idle, starting, capturing, finalizing, completed, uploading, uploadFailed, captureFailed

    var label: String {
        switch self {
        case .idle: "抓数据"
        case .starting: "准备中"
        case .capturing: "结束上传"
        case .finalizing: "打包中"
        case .completed: "上传数据"
        case .uploading: "上传中"
        case .uploadFailed: "重试上传"
        case .captureFailed: "重新抓取"
        }
    }

    var enabled: Bool {
        self != .starting && self != .finalizing && self != .uploading
    }
}

struct ExampleRawDumpButton: View {
    let state: ExampleRawDumpButtonState
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(state.label)
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 56, height: 56)
                    .foregroundColor(.white)
                    .background(ExampleColors.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!state.enabled)
            .accessibilityIdentifier("raw_dump.button")
            .accessibilityLabel(state.label)
        }
    }
}
