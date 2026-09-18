import Foundation
import Observation
import UIKit

@MainActor @Observable
final class ClipStore {
    var index = VaultIndex()
    var error: String?
    var isReady = false
    var toast: String?
    var widgetIssue: String?
    let repository: VaultRepository
    private var toastTask: Task<Void, Never>?
    private var ownPasteboardChange: Int?
    private var lastObservedChange: Int?
    @ObservationIgnored lazy var cloud = CloudSyncController(store: self)
    static let groupID = "group.com.qdth.inkflow"
    var isCloudEnabled: Bool { BuildFeatures.cloudSync && index.sync?.enabled == true }

    init(root: URL? = nil) {
        let defaultRoot = ProcessInfo.processInfo.arguments.contains("--demo")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Inkflow-Demo", isDirectory: true)
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inkflow", isDirectory: true)
        let base = root ?? defaultRoot
        repository = VaultRepository(root: base)
        reload()
    }

    func reload() {
        do {
            try repository.prepare()
            index = try repository.loadIndex()
            isReady = true
            error = nil
            importInbox()
            refreshWidget()
        } catch {
            self.error = "资料库未能打开，原有数据已保留。\n\(error.localizedDescription)"; isReady = false
            try? WidgetBridge.publish([], visible: false)
        }
    }

    /// Commit metadata before updating the UI, so failed writes never look saved.
    @discardableResult
    func commit(_ change: (inout VaultIndex) -> Void) -> Bool {
        guard isReady else { return false }
        var next = index
        change(&next)
        next.trackChanges(from: index)
        do { try repository.saveIndex(next); index = next; refreshWidget(); cloud.localDidChange(); return true }
        catch { self.error = "保存失败，请重试。\n\(error.localizedDescription)"; return false }
    }

    /// Cloud metadata and remote merges must not create new local edit clocks.
    @discardableResult
    func persistSync(_ change: (inout VaultIndex) -> Void) -> Bool {
        guard isReady else { return false }
        var next = index
        change(&next)
        do { try repository.saveIndex(next); index = next; refreshWidget(); return true }
        catch { self.error = "保存失败，同步已暂停。\n\(error.localizedDescription)"; return false }
    }

    @discardableResult
    func capture(_ text: String, source: String = "剪贴板", notify: Bool = true) -> UUID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if notify { showToast("没有可收集的文字") }; return nil
        }
        guard text.utf8.count <= 5 * 1_024 * 1_024 else { error = "文字超过 5 MB，请分段收集。"; return nil }
        if let existing = index.clips.first(where: { $0.text == text }) {
            if notify { showToast("这段内容已经在历史记录里") }
            return existing.id
        }
        var clip = Clip(text: text)
        clip.source = source
        guard commit({ $0.clips.insert(clip, at: 0) }) else { return nil }
        if notify { showToast("已收集到历史记录") }
        return clip.id
    }

    func update(_ id: UUID, _ change: (inout Clip) -> Void) {
        commit { value in
            guard let i = value.clips.firstIndex(where: { $0.id == id }) else { return }
            change(&value.clips[i])
        }
    }

    func saveText(_ text: String, id: UUID) -> Bool {
        guard index.clips.contains(where: { $0.id == id }) else {
            error = "这条片段已被删除，可能来自另一台设备的同步。请先复制当前文字，再保存为新片段。"; return false
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "内容不能为空。"; return false }
        guard text.utf8.count <= 5 * 1_024 * 1_024 else { error = "文字超过 5 MB，请分段保存。"; return false }
        return commit { value in
            guard let i = value.clips.firstIndex(where: { $0.id == id }) else { return }
            if value.clips[i].text != text {
                value.clips[i].previousText = value.clips[i].text
                value.clips[i].text = text
                value.clips[i].updatedAt = Date()
            }
        }
    }

    func delete(_ id: UUID) { if commit({ $0.clips.removeAll { $0.id == id } }) { showToast("已删除片段") } }

    func copy(_ clip: Clip) {
        UIPasteboard.general.string = clip.text
        ownPasteboardChange = UIPasteboard.general.changeCount
        showToast("已复制，可以去粘贴了")
    }

    func checkForegroundClipboard(enabled: Bool) {
        importInbox()
        guard enabled else { return }
        let board = UIPasteboard.general
        guard board.changeCount != ownPasteboardChange, board.changeCount != lastObservedChange else { return }
        lastObservedChange = board.changeCount
        if let text = board.string { capture(text) }
    }

    func importInbox() {
        guard BuildFeatures.shareExtension, isReady, !ProcessInfo.processInfo.arguments.contains("--demo"), let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) else { return }
        let inbox = group.appendingPathComponent("Inbox", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "txt" {
            do {
                let text = try VaultRepository.decode(Data(contentsOf: url))
                if capture(text, source: "分享菜单", notify: false) != nil { try FileManager.default.removeItem(at: url) }
            } catch { self.error = "有一条分享内容未能导入，已保留原文件。\n\(error.localizedDescription)" }
        }
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func refreshWidget() {
        guard isReady else { return }
        let visible = UserDefaults.standard.object(forKey: "widgetContentVisible") as? Bool ?? true
        do { try WidgetBridge.publish(index.clips, visible: visible); widgetIssue = nil }
        catch { widgetIssue = "小组件暂时无法更新，请检查 App 与小组件的 App Group 签名配置。手机内的记录不受影响。" }
    }

    func seedPreviewIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--demo"), index.clips.isEmpty else { return }
        let texts = [
            "保持好奇，慢慢来。\n\n把偶然遇见的句子、转瞬即逝的灵感，\n留给未来的自己。",
            "周末的小计划\n\n去逛一家没去过的书店\n买一束白色的花\n整理最近收藏的文章\n留一点时间，什么也不做",
            "https://developer.apple.com/design/human-interface-guidelines",
            "好的工具，让想法自然发生。\n\n收集只是开始，真正有意思的是，让零散的内容在某一天产生新的连接。",
            "写作不是把想法写下来，\n写作本身就是思考。",
            "会议要点\n首页保留清晰的搜索入口\n置顶与收藏分别管理\n文本处理之前，先预览结果"
        ]
        commit { value in
            for (i, text) in texts.enumerated() {
                var clip = Clip(text: text)
                clip.createdAt = Date().addingTimeInterval(-Double(i) * 7_200)
                clip.isPinned = i == 0 || i == 2
                clip.isFavorite = i == 0 || i == 4
                value.clips.append(clip)
            }
        }
    }
}
