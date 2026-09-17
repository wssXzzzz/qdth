import SwiftUI

struct ClipDetailView: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let clipID: UUID
    @State private var editing = false
    @State private var draft = ""
    @State private var processing = false
    @State private var confirmDelete = false
    @State private var confirmRestore = false
    private var clip: Clip? { store.index.clips.first { $0.id == clipID } }

    var body: some View {
        Group {
            if let clip {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Label(clip.isLink ? "链接" : "文本片段", systemImage: clip.isLink ? "link" : "text.alignleft")
                        Spacer()
                        Text("\(editing ? draft.count : clip.text.count) 字").monospacedDigit()
                    }.font(.caption).foregroundStyle(Palette.muted).padding(22)
                    if editing {
                        TextEditor(text: $draft).font(.body).scrollContentBackground(.hidden).padding(.horizontal, 18)
                            .accessibilityLabel("编辑片段内容")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                Text(clip.text).font(.system(size: 18)).lineSpacing(9).textSelection(.enabled)
                                    .foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                                if clip.isLink, let url = URL(string: clip.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                    Link(destination: url) { Label("在浏览器中打开", systemImage: "arrow.up.right") }.font(.subheadline)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("收集于 \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    Text("来源：\(clip.source)")
                                }.font(.caption).foregroundStyle(Palette.muted)
                            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
                        }
                    }
                }.background(Palette.canvas)
                    .safeAreaInset(edge: .bottom) {
                        if !editing {
                            HStack(spacing: 12) {
                                Button { processing = true } label: {
                                    Label("文本处理", systemImage: "wand.and.stars").frame(maxWidth: .infinity).padding(.vertical, 7)
                                }.buttonStyle(.bordered)
                                Button { store.copy(clip) } label: {
                                    Label("复制内容", systemImage: "square.on.square").frame(maxWidth: .infinity).padding(.vertical, 7)
                                }.buttonStyle(.borderedProminent)
                            }.font(.subheadline.weight(.medium)).padding(18).background(.bar)
                        }
                    }
                    .toolbar {
                        if editing {
                            ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.saveText(draft, id: clipID) { editing = false } } }
                        } else {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button { store.update(clipID) { $0.isPinned.toggle() } } label: {
                                    Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                                }.accessibilityLabel(clip.isPinned ? "取消置顶" : "置顶")
                                Button { store.update(clipID) { $0.isFavorite.toggle() } } label: {
                                    Image(systemName: clip.isFavorite ? "star.fill" : "star")
                                }.accessibilityLabel(clip.isFavorite ? "取消收藏" : "收藏")
                                Menu {
                                    Button("编辑文字", systemImage: "pencil") { draft = clip.text; editing = true }
                                    ShareLink(item: clip.text)
                                    if clip.previousText != nil {
                                        Button("恢复上次修改前的内容", systemImage: "arrow.uturn.backward") { confirmRestore = true }
                                    }
                                    Button("删除片段", systemImage: "trash", role: .destructive) { confirmDelete = true }
                                } label: { Image(systemName: "ellipsis").accessibilityLabel("更多操作") }
                            }
                        }
                    }
                    .sheet(isPresented: $processing) { ProcessorView(clipID: clipID, initialText: clip.text) }
            } else { ContentUnavailableView("片段已不存在", systemImage: "tray") }
        }
        .navigationTitle(editing ? "编辑片段" : "片段详情").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editing)
        .confirmationDialog("删除这条片段？删除后无法恢复。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除片段", role: .destructive) { store.delete(clipID); if clip == nil { dismiss() } }
        }
        .confirmationDialog("恢复上次修改前的文字？当前版本会保留为可恢复版本。", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复") { if let previous = clip?.previousText { _ = store.saveText(previous, id: clipID) } }
        }
    }
}
