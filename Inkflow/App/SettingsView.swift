import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(ClipStore.self) private var store
    @AppStorage("captureOnOpen") private var captureOnOpen = false
    @AppStorage("appearance") private var appearance = "system"
    @State private var exporting = false
    @State private var importing = false
    @State private var backup = BackupDocument(data: Data())
    @State private var incoming: VaultIndex?
    @State private var confirmingCloud = false
    @State private var confirmingReupload = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    InkflowMark(size: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("全岛铁盒").font(.title3.bold())
                        Text("给零散的文字，一个安静的家。").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 10)
                }
            }
            Section {
                Toggle("iCloud 同步", isOn: Binding(get: { store.index.sync?.enabled == true }, set: { enabled in
                    if enabled { confirmingCloud = true }
                    else { Task { await store.cloud.setEnabled(false) } }
                }))
                HStack(spacing: 10) {
                    if store.cloud.isBusy { ProgressView() }
                    else { Image(systemName: store.cloud.issue == nil ? "icloud" : "icloud.slash").foregroundStyle(Palette.muted) }
                    Text(store.cloud.status).font(.subheadline)
                }.accessibilityElement(children: .combine)
                if let issue = store.cloud.issue {
                    Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if store.index.sync?.enabled == true {
                    LabeledContent("待上传", value: "\(store.index.sync?.pendingCount ?? 0) 项")
                    if let date = store.index.sync?.lastSuccess {
                        LabeledContent("最近完成", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("立即同步", systemImage: "arrow.triangle.2.circlepath") { Task { await store.cloud.syncNow() } }
                        .disabled(store.cloud.isBusy)
                    if store.index.sync?.zoneWasDeleted == true {
                        Button("重新上传本机资料库", systemImage: "icloud.and.arrow.up") { confirmingReupload = true }
                    }
                }
            } header: { Text("iCloud") } footer: {
                Text("默认关闭。开启后，文字、置顶、收藏和文本动作会上传到你自己的 iCloud 私有数据库，同一 Apple 账号的设备可以同步。删除也会同步；关闭不会删除已上传内容。外观和剪贴板读取设置不参与同步。")
            }
            Section {
                Toggle("打开 App 时收集剪贴板", isOn: $captureOnOpen)
            } header: { Text("收集") } footer: {
                Text("开启后，仅在全岛铁盒位于前台时读取新复制的文字，系统可能询问粘贴权限。关闭时，可点击首页粘贴按钮手动收集。iOS 不支持在后台记录每一次复制；首次安装也无法取回系统之前的剪贴板历史。")
            }
            Section {
                Label("选中文字 → 分享 → 全岛铁盒", systemImage: "square.and.arrow.up")
            } header: { Text("从其他 App 收集") } footer: { Text("第一次使用时，可以在系统分享菜单的“更多”中添加全岛铁盒。分享的内容会在下次打开全岛铁盒时进入历史记录。") }
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色纸张").tag("light")
                    Text("深色墨色").tag("dark")
                }
            }
            Section {
                LabeledContent("历史记录", value: "\(store.index.clips.count) 条")
                LabeledContent("已置顶", value: "\(store.index.clips.filter(\.isPinned).count) 条")
                LabeledContent("已收藏", value: "\(store.index.clips.filter(\.isFavorite).count) 条")
                Button("导出完整备份", systemImage: "square.and.arrow.up") {
                    do { backup = BackupDocument(data: try JSONEncoder().encode(store.index.portableBackup)); exporting = true }
                    catch { store.error = error.localizedDescription }
                }
                Button("从备份导入", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("数据") } footer: { Text("备份包含文字、置顶、收藏和自定义动作。可以保存到 iCloud Drive 或其他位置；导入时合并内容，不覆盖现有片段。备份是明文文件，请妥善保管。") }
            Section {
                Label("无需额外注册账号", systemImage: "person.crop.circle.badge.checkmark")
                Label("无广告、无统计；云同步由你开启", systemImage: "lock.shield")
                LabeledContent("版本", value: "1.1.0")
            } header: { Text("关于全岛铁盒") } footer: { Text("一个受 Taio 使用体验启发的独立应用。当前支持纯文本和链接收集。") }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .alert("开启 iCloud 同步？", isPresented: $confirmingCloud) {
                Button("取消", role: .cancel) { }
                Button("开启同步") { Task { await store.cloud.setEnabled(true) } }
            } message: { Text("现有和以后收集的文字、置顶、收藏及动作会上传到当前 Apple 账号的 iCloud，并与其他设备合并。删除记录也会同步。请避免收集密码等敏感内容。") }
            .confirmationDialog("将本机内容重新上传到 iCloud？", isPresented: $confirmingReupload, titleVisibility: .visible) {
                Button("确认重新上传") { Task { await store.cloud.reuploadAfterZoneRemoval() } }
            } message: { Text("iCloud 中被移除的资料库将重新建立。本机当前保留的内容会再次上传。") }
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "全岛铁盒备份-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result {
                case .success: store.showToast("备份已导出")
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50 * 1_024 * 1_024 else { throw BackupError.tooLarge }
                    let value = try JSONDecoder().decode(VaultIndex.self, from: Data(contentsOf: url))
                    guard value.version == 1 else { throw VaultError.unsupportedVersion(value.version) }
                    incoming = value
                } catch { store.error = "无法导入备份：\(error.localizedDescription)" }
            }
            .confirmationDialog("将备份内容合并到当前资料库？", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } }), titleVisibility: .visible) {
                Button("合并 \(incoming?.clips.count ?? 0) 条片段") {
                    guard let incoming else { return }
                    if store.commit({ $0.merge(incoming) }) { store.showToast("备份已合并") }
                    self.incoming = nil
                }
            }
    }
}

enum BackupError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "备份超过 50 MB，请拆分后导入。" }
}
