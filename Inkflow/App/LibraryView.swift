import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    let favoritesOnly: Bool
    @State private var search = ""
    @State private var filter = "全部"
    @State private var showingCompose = false
    @State private var showingImport = false
    @State private var pendingDelete: Clip?
    private let filters = ["全部", "文本", "链接"]

    private var clips: [Clip] {
        store.index.clips.filter { clip in
            (!favoritesOnly || clip.isFavorite) &&
            (search.isEmpty || clip.text.localizedStandardContains(search)) &&
            (filter == "全部" || (filter == "链接" ? clip.isLink : !clip.isLink))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heading
                if !favoritesOnly { captureCard }
                searchBar
                HStack(spacing: 9) {
                    ForEach(filters, id: \.self) { name in
                        Button { filter = name } label: {
                            Text(name).font(.subheadline.weight(filter == name ? .semibold : .regular))
                                .padding(.horizontal, 19).padding(.vertical, 9)
                                .foregroundStyle(filter == name ? Palette.canvas : Palette.muted)
                                .background(filter == name ? Palette.accent : Palette.card, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(filter == name ? .isSelected : [])
                    }
                    Spacer()
                    Text("\(clips.count) 条").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                }
                if clips.isEmpty {
                    EmptyLibrary(title: emptyTitle, subtitle: emptySubtitle, symbol: favoritesOnly ? "star" : "square.on.square")
                } else {
                    let pinned = clips.filter(\.isPinned)
                    let recent = clips.filter { !$0.isPinned }
                    if !pinned.isEmpty { clipSection("置顶", subtitle: "常用的，放在手边", symbol: "pin.fill", items: pinned) }
                    if !recent.isEmpty { clipSection(favoritesOnly ? "我的收藏" : "历史记录", subtitle: "按收集时间排列", symbol: "clock", items: recent) }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").font(.caption)
                    Text(store.index.sync?.enabled == true ? "本机保存 · 已开启 iCloud 同步" : "本机保存 · 随时取用").font(.caption)
                }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(sizeClass == .compact ? 20 : 36).frame(maxWidth: 1_120).frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle(favoritesOnly ? "收藏" : "剪贴板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("手动记一段", systemImage: "square.and.pencil") { showingCompose = true }
                    Button("导入文本文件", systemImage: "square.and.arrow.down") { showingImport = true }
                } label: { Image(systemName: "plus").accessibilityLabel("添加内容") }
            }
        }
        .navigationDestination(for: UUID.self) { id in ClipDetailView(clipID: id) }
        .sheet(isPresented: $showingCompose) { ComposeView() }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 5 * 1_024 * 1_024 else { throw VaultError.oversizedFile }
                    store.capture(try VaultRepository.decode(Data(contentsOf: url)), source: "文件导入")
                }
            } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("删除这条片段？删除后无法恢复。", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除片段", role: .destructive) { if let clip = pendingDelete { store.delete(clip.id) }; pendingDelete = nil }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text(favoritesOnly ? "YOUR LITTLE COLLECTION" : "A LITTLE SPACE FOR YOUR MIND")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
            }
            Text(favoritesOnly ? "值得留住的，\n都在这里。" : "留住每一次灵感。")
                .font(.system(size: sizeClass == .compact ? 29 : 36, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
            Text(favoritesOnly ? "收藏喜欢的内容，让好文字不再走散。" : "复制、收集、整理。让零散的文字，有处安放。")
                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
        }.padding(.top, 8)
    }

    private var captureCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 23, weight: .light))
                .foregroundStyle(Palette.accent).frame(width: 50, height: 54)
                .background(Palette.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text("收集此刻的剪贴板").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("轻点粘贴，留住这段文字").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            ClipboardPasteButton { strings in strings.forEach { store.capture($0) } }
                .tint(Palette.accent)
                .accessibilityLabel("粘贴并收集到历史记录")
        }.padding(18).background(Palette.softGreen, in: RoundedRectangle(cornerRadius: 24))
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField("搜索你的文字、链接、灵感…", text: $search).font(.subheadline).submitLabel(.search)
                .accessibilityIdentifier("clip-search")
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(Palette.muted).accessibilityLabel("清除搜索") }
        }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line, lineWidth: 1))
    }

    private func clipSection(_ title: String, subtitle: String, symbol: String, items: [Clip]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.caption).foregroundStyle(Palette.accent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? 290 : 260), spacing: 16)], spacing: 16) {
                ForEach(items) { clip in
                    ClipCard(clip: clip, delete: { pendingDelete = clip })
                }
            }
        }
    }

    private var emptyTitle: String { !search.isEmpty ? "没有找到这段文字" : favoritesOnly ? "给喜欢的文字一颗星" : "第一段文字，从这里开始" }
    private var emptySubtitle: String {
        !search.isEmpty ? "试试更短的关键词，或切换内容类型。" : favoritesOnly ? "点击片段上的星标，就能在这里找到它。" : "复制一段文字，再轻点上方的粘贴按钮。\n也可以通过右上角，手动记下一个想法。"
    }
}

struct ClipCard: View {
    @Environment(ClipStore.self) private var store
    let clip: Clip
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: clip.id) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Label(clip.isLink ? "链接" : "文本", systemImage: clip.isLink ? "link" : "text.alignleft")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                        Spacer()
                        if clip.isPinned { Image(systemName: "pin.fill").font(.system(size: 11)).rotationEffect(.degrees(30)).foregroundStyle(Palette.accent) }
                    }
                    Text(clip.text).font(.system(size: 15)).foregroundStyle(Palette.ink).lineSpacing(7)
                        .lineLimit(5).frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
                }.padding(20).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(spacing: 4) {
                Text(clip.createdAt, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.system(size: 10, design: .monospaced))
                Text("· \(clip.text.count) 字").font(.system(size: 10)).lineLimit(1)
                Spacer(minLength: 0)
                Button { store.update(clip.id) { $0.isFavorite.toggle() } } label: {
                    Image(systemName: clip.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(clip.isFavorite ? Palette.gold : Palette.muted).frame(width: 40, height: 44)
                }.accessibilityLabel(clip.isFavorite ? "取消收藏" : "收藏")
                Button { store.copy(clip) } label: { Image(systemName: "square.on.square").frame(width: 40, height: 44) }
                    .accessibilityLabel("复制片段")
            }.font(.system(size: 14)).foregroundStyle(Palette.muted).padding(.horizontal, 16).padding(.bottom, 3)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 20) }
        }.background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(clip.isPinned ? Palette.accent.opacity(0.25) : Palette.line, lineWidth: 1))
            .contextMenu {
                Button("复制", systemImage: "doc.on.doc") { store.copy(clip) }
                Button(clip.isPinned ? "取消置顶" : "置顶", systemImage: "pin") { store.update(clip.id) { $0.isPinned.toggle() } }
                Button(clip.isFavorite ? "取消收藏" : "收藏", systemImage: "star") { store.update(clip.id) { $0.isFavorite.toggle() } }
                ShareLink(item: clip.text)
                Button("删除", systemImage: "trash", role: .destructive, action: delete)
            }
    }
}

struct ComposeView: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("记下一个想法，或粘贴一段喜欢的文字。").font(.subheadline).foregroundStyle(Palette.muted)
                TextEditor(text: $text).focused($focused).font(.body).scrollContentBackground(.hidden)
                    .accessibilityLabel("片段内容").accessibilityIdentifier("compose-editor")
            }.padding(24).background(Palette.canvas).navigationTitle("记一段").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { if store.capture(text, source: "手动记录") != nil { dismiss() } }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).fontWeight(.semibold)
                    }
                }.onAppear { focused = true }
        }
    }
}
