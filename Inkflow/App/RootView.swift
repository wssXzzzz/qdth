import SwiftUI
import Combine

enum Destination: String, CaseIterable, Identifiable {
    case library = "剪贴板", favorites = "收藏", actions = "文本动作", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .library: "square.on.square"
        case .favorites: "star"
        case .actions: "wand.and.stars"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("captureOnOpen") private var captureOnOpen = false
    @State private var destination: Destination? = .library
    @State private var widgetSheet: WidgetSheet?
    @State private var navigationPaths: [Destination: [UUID]] = [:]

    var body: some View {
        Group {
            if !store.isReady {
                ContentUnavailableView {
                    Label("资料库暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.error ?? "请重试，原有数据已保留。")
                } actions: { Button("重新打开") { store.reload() }.buttonStyle(.borderedProminent) }
            } else if sizeClass == .compact {
                TabView(selection: $destination) {
                    ForEach(Destination.allCases) { item in
                        NavigationStack(path: path(for: item)) { page(item) }
                            .tag(Optional(item))
                            .tabItem { Label(item.rawValue, systemImage: item.symbol) }
                    }
                }
            } else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            InkflowMark()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("全岛铁盒").font(.title2.bold())
                                Text("QUANDAO TIEHE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                            }
                        }.padding(24).padding(.top, 12)
                        List(Destination.allCases, selection: $destination) { item in
                            Label(item.rawValue, systemImage: item.symbol).padding(.vertical, 8).tag(item)
                        }.scrollContentBackground(.hidden).listStyle(.sidebar)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("你的文字，只属于你", systemImage: "lock.shield")
                            Text("\(store.index.clips.count) 段内容 · \(store.isCloudEnabled ? "iCloud 已开启" : "本机保存")").font(.caption)
                        }.font(.footnote).foregroundStyle(Palette.muted).padding(24)
                    }.background(Palette.canvas).navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
                } detail: {
                    NavigationStack(path: path(for: destination ?? .library)) { page(destination ?? .library) }
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 13)
                    .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.07), radius: 20, y: 6)
                    .padding(.top, 8).accessibilityAddTraits(.updatesFrequently).allowsHitTesting(false)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil && store.isReady }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.checkForegroundClipboard(enabled: captureOnOpen)
                store.refreshWidget()
                Task { await store.cloud.resume() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            if scenePhase == .active { store.checkForegroundClipboard(enabled: captureOnOpen) }
        }
        .onChange(of: captureOnOpen) { _, enabled in if enabled { store.checkForegroundClipboard(enabled: true) } }
        .onOpenURL { url in
            guard let route = WidgetRoute(url: url) else { return }
            widgetSheet = nil
            switch route {
            case .library: navigationPaths[.library] = []; destination = .library
            case .favorites: navigationPaths[.favorites] = []; destination = .favorites
            case .capture: navigationPaths[.library] = []; destination = .library; widgetSheet = .capture
            case .clip(let id): navigationPaths[.library] = []; destination = .library; widgetSheet = .clip(id)
            }
        }
        .sheet(item: $widgetSheet) { sheet in
            NavigationStack {
                Group {
                    switch sheet {
                    case .capture: WidgetCaptureView()
                    case .clip(let id): ClipDetailView(clipID: id)
                    }
                }.toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("关闭") { widgetSheet = nil } }
                }
            }
        }
    }

    // Keep the NavigationStack identity stable across deep links. Replacing it
    // with .id(UUID()) during activation makes iOS 18 reuse a navigation item
    // across two UINavigationBars and abort in layoutSubviews.
    private func path(for item: Destination) -> Binding<[UUID]> {
        Binding(get: { navigationPaths[item] ?? [] }, set: { navigationPaths[item] = $0 })
    }

    @ViewBuilder private func page(_ item: Destination) -> some View {
        switch item {
        case .library: LibraryView(favoritesOnly: false)
        case .favorites: LibraryView(favoritesOnly: true)
        case .actions: WorkflowsView()
        case .settings: SettingsView()
        }
    }
}

private enum WidgetSheet: Identifiable {
    case capture, clip(UUID)
    var id: String {
        switch self { case .capture: "capture"; case .clip(let id): id.uuidString }
    }
}

private struct WidgetCaptureView: View {
    @Environment(ClipStore.self) private var store
    @State private var captured = false
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: captured ? "checkmark.circle" : "tray.and.arrow.down")
                .font(.system(size: 50, weight: .light)).foregroundStyle(Palette.accent)
            Text(captured ? "已留在铁盒里" : "收集此刻的剪贴板").font(.title2.bold())
            Text(captured ? "回到历史记录，即可置顶、收藏或处理文字。" : "轻点下方粘贴按钮，保存你刚复制的文字。")
                .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            ClipboardPasteButton { strings in
                captured = strings.reduce(false) { saved, text in store.capture(text) != nil || saved }
            }.accessibilityLabel("粘贴并收集到历史记录")
            Spacer()
        }.padding(30).padding(.top, 45).frame(maxWidth: .infinity)
            .background(Palette.canvas).navigationTitle("收集文字").navigationBarTitleDisplayMode(.inline)
    }
}
