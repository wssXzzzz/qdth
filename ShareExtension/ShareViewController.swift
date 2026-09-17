import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(context: extensionContext))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareCaptureView: View {
    let context: NSExtensionContext?
    @State private var text = ""
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("留给未来的自己", systemImage: "quote.opening").font(.headline).foregroundStyle(.secondary)
                if loading { ProgressView("读取分享内容…") }
                TextEditor(text: $text).font(.body).accessibilityLabel("收集的文字")
                Text("下次打开全岛铁盒时，这段文字会出现在历史记录里。").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(24).navigationTitle("收集到全岛铁盒").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { context?.completeRequest(returningItems: nil) } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("收集") { save() }.disabled(loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.task { await load() }
        }.tint(Color(red: 0.24, green: 0.42, blue: 0.34))
    }

    @MainActor private func load() async {
        var parts: [String] = []
        for item in context?.inputItems as? [NSExtensionItem] ?? [] {
            if let value = item.attributedContentText?.string, !value.isEmpty { parts.append(value) }
            for provider in item.attachments ?? [] {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
                guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
                let value: String? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        if let url = item as? URL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { continuation.resume(returning: url.absoluteString) }
                        else if let string = item as? String { continuation.resume(returning: string) }
                        else if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let value, !parts.contains(value) { parts.append(value) }
            }
        }
        text = parts.joined(separator: "\n\n")
        loading = false
        if text.isEmpty { error = "没有找到可收集的文字或链接。" }
    }

    private func save() {
        guard text.utf8.count <= 5 * 1_024 * 1_024 else { error = "文字超过 5 MB，请分段分享。"; return }
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.qdth.inkflow") else {
            error = "分享收集暂时不可用，请打开全岛铁盒使用粘贴按钮收集。"; return
        }
        do {
            let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: inbox.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt"), options: .atomic)
            context?.completeRequest(returningItems: nil)
        } catch { self.error = "未能保存，请重试：\(error.localizedDescription)" }
    }
}
