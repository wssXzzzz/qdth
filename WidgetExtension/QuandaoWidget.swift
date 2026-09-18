import SwiftUI
import WidgetKit

struct ClipEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var unavailable = false

    static var preview: ClipEntry {
        ClipEntry(date: .now, snapshot: WidgetSnapshot(clips: [
            WidgetClip(id: UUID(), text: "保持好奇，慢慢来。\n把偶然遇见的句子，留给未来的自己。", isPinned: true, isFavorite: true, createdAt: .now),
            WidgetClip(id: UUID(), text: "好的工具，让想法自然发生。", isPinned: false, isFavorite: true, createdAt: .now)
        ]))
    }
}

struct ClipProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (ClipEntry) -> Void) {
        completion(context.isPreview ? .preview : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
    private func read() -> ClipEntry {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.groupID),
              let snapshot = try? WidgetSnapshotRepository(root: root).load() else {
            return ClipEntry(date: .now, snapshot: WidgetSnapshot(), unavailable: true)
        }
        return ClipEntry(date: .now, snapshot: snapshot)
    }
}

struct ClipWidgetView: View {
    let entry: ClipEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }
    private var ink: Color { dark ? Color(red: 0.89, green: 0.91, blue: 0.85) : Color(red: 0.16, green: 0.22, blue: 0.18) }
    private var accent: Color { dark ? Color(red: 0.57, green: 0.72, blue: 0.57) : Color(red: 0.29, green: 0.42, blue: 0.32) }
    private var paper: Color { dark ? Color(red: 0.11, green: 0.15, blue: 0.12) : Color(red: 0.97, green: 0.97, blue: 0.93) }
    private var capacity: Int { family == .systemLarge ? 4 : family == .systemMedium ? 2 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
            HStack(spacing: 6) {
                InkflowMark(size: 17)
                Text("全岛铁盒").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if family != .systemSmall { Text("常用文字").font(.system(size: 10)).foregroundStyle(accent) }
            }
            if entry.snapshot.clips.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(emptyTitle).font(.system(size: family == .systemSmall ? 18 : 20, weight: .semibold, design: .serif))
                    Text(emptySubtitle).font(.system(size: 11)).foregroundStyle(ink.opacity(0.65)).lineLimit(3)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                    ForEach(Array(entry.snapshot.clips.prefix(capacity))) { clip in
                        if family == .systemSmall { row(clip) }
                        else { Link(destination: WidgetRoute.clip(clip.id).url) { row(clip) } }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .privacySensitive()
            }
            if family == .systemSmall {
                Label(entry.snapshot.clips.isEmpty ? "轻点打开铁盒" : "轻点查看与复制", systemImage: "arrow.up.right")
                    .font(.system(size: 10)).foregroundStyle(accent)
            } else {
                HStack(spacing: 10) {
                    shortcut("收集文字", symbol: "plus", route: .capture)
                    shortcut("历史", symbol: "clock", route: .library)
                    shortcut("收藏", symbol: "star", route: .favorites)
                }
            }
        }
        .foregroundStyle(ink)
        .containerBackground(paper, for: .widget)
        .widgetURL(entry.snapshot.clips.first.map { WidgetRoute.clip($0.id).url } ?? WidgetRoute.library.url)
    }

    private func row(_ clip: WidgetClip) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if family != .systemMedium {
                Label(clip.isPinned ? "置顶" : "收藏", systemImage: clip.isPinned ? "pin.fill" : "star.fill")
                    .font(.system(size: 9)).foregroundStyle(accent)
            }
            HStack(alignment: .top, spacing: 7) {
                if family == .systemMedium {
                    Image(systemName: clip.isPinned ? "pin.fill" : "star.fill").font(.system(size: 10)).foregroundStyle(accent).padding(.top, 3)
                }
                Text(clip.text).font(.system(size: family == .systemSmall ? 14 : 13))
                    .lineSpacing(3).lineLimit(family == .systemSmall ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(clip.isPinned ? "置顶" : "收藏")：\(clip.text)，打开查看")
    }

    private func shortcut(_ title: String, symbol: String, route: WidgetRoute) -> some View {
        Link(destination: route.url) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }.foregroundStyle(accent)
    }

    private var emptyTitle: String {
        entry.unavailable ? "打开铁盒，更新内容" : entry.snapshot.isContentVisible ? "常用的，放在手边。" : "文字已隐藏"
    }
    private var emptySubtitle: String {
        entry.unavailable ? "解锁并打开 App 后重试。" : entry.snapshot.isContentVisible ? "在 App 里置顶或收藏一段文字，就会出现在这里。" : "可在 App 设置里开启展示。"
    }
}

@main
struct QuandaoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStorage.kind, provider: ClipProvider()) { ClipWidgetView(entry: $0) }
            .configurationDisplayName("常用文字")
            .description("把置顶与收藏放在手边，轻点查看、复制或收集文字。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
