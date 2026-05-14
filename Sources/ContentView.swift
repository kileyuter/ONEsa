import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppStateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenClaw 悬浮客户端")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("macOS SwiftUI 骨架已就绪，后续任务将接入悬浮球和聊天窗口。")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("当前状态")
                    .font(.headline)

                Label(appState.connectionState.title, systemImage: statusIconName)
                    .font(.title3)

                Text(appState.connectionState.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 240)
    }

    private var statusIconName: String {
        switch appState.connectionState {
        case .notConfigured:
            "gearshape"
        case .notLoggedIn:
            "person.crop.circle.badge.exclamationmark"
        case .connected:
            "checkmark.circle"
        case .error:
            "exclamationmark.triangle"
        }
    }
}
