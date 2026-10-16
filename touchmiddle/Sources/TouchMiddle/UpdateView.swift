import SwiftUI

struct UpdateView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let installed = checker.installed {
                Text("目前版本：\(installed.version.description)（build \(installed.build)）")
                    .font(.headline)
            }
            HStack {
                Text(checker.statusMessage)
                Spacer()
                if checker.isChecking { ProgressView().controlSize(.small) }
                Button("檢查更新") { Task { await checker.check() } }
                    .disabled(checker.isChecking || checker.installed == nil)
            }
            Text("App 執行期間每 24 小時自動檢查一次，也可隨時手動檢查。")
                .font(.caption).foregroundStyle(.secondary)
            if let date = checker.lastSuccess {
                Text("上次成功檢查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = checker.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let release = checker.availableUpdate {
                Divider()
                HStack {
                    Text(release.name?.isEmpty == false ? release.name! : release.tagName).font(.headline)
                    if release.isPrerelease || release.version?.isPrerelease == true {
                        Text("測試版").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("更新內容").font(.subheadline.bold())
                ScrollView {
                    // Display release text without loading remote images or executing HTML.
                    Text(release.body?.isEmpty == false ? release.body! : "此版本未提供更新內容。")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                Button("開啟下載頁", systemImage: "arrow.up.right.square") { checker.openDownloadPage() }
                    .buttonStyle(.borderedProminent)
                Text("下載後需結束 App 並手動替換；更新後可能需要重新授予輔助使用權限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
