import SwiftUI

struct WorkflowsView: View {
    @Environment(ClipStore.self) private var store
    @State private var editing: Workflow?
    @State private var running: Workflow?
    @State private var pendingDelete: Workflow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("把重复的事，交给动作。").font(.system(size: 29, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text("清理、转换、整理，一次完成。\n每次处理都能先预览，再决定是否保存。")
                        .font(.subheadline).lineSpacing(6).foregroundStyle(Palette.muted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(store.index.workflows) { workflow in
                        Button { running = workflow } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Image(systemName: workflow.symbol).font(.title2).foregroundStyle(Palette.accent)
                                        .frame(width: 48, height: 48).background(Palette.softGreen, in: RoundedRectangle(cornerRadius: 15))
                                    Spacer()
                                    Image(systemName: "play.fill").font(.caption).foregroundStyle(Palette.accent)
                                }
                                Text(workflow.name).font(.headline).foregroundStyle(Palette.ink)
                                Text(workflow.steps.map { $0.kind.title }.joined(separator: " → "))
                                    .font(.caption).foregroundStyle(Palette.muted).lineLimit(2).frame(height: 35, alignment: .topLeading)
                                Text("\(workflow.steps.count) 个步骤").font(.caption2.monospaced()).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button("编辑动作", systemImage: "pencil") { editing = workflow }
                                Button("删除动作", systemImage: "trash", role: .destructive) { pendingDelete = workflow }
                            }
                    }
                }
                Label("长按动作卡片可以编辑步骤", systemImage: "hand.tap").font(.caption).foregroundStyle(Palette.muted)
            }.padding(28).frame(maxWidth: 1_000).frame(maxWidth: .infinity)
        }.background(Palette.canvas).navigationTitle("文本动作").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建动作", systemImage: "plus") { editing = Workflow(name: "我的动作", steps: [.init(.trim)]) }
                }
            }
            .sheet(item: $editing) { WorkflowEditor(workflow: $0) }
            .sheet(item: $running) { ProcessorView(clipID: nil, initialText: "", initialWorkflow: $0) }
            .confirmationDialog("删除这个动作？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("删除动作", role: .destructive) { if let workflow = pendingDelete { store.commit { $0.workflows.removeAll { $0.id == workflow.id } } }; pendingDelete = nil }
            }
    }
}

struct WorkflowEditor: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var workflow: Workflow
    var body: some View {
        NavigationStack {
            Form {
                Section("动作名称") { TextField("名称", text: $workflow.name) }
                Section {
                    ForEach($workflow.steps) { $step in
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("处理方式", selection: $step.kind) {
                                ForEach(TransformKind.allCases) { Text($0.title).tag($0) }
                            }
                            if step.kind == .replace {
                                TextField("查找文字（按原文匹配）", text: $step.search)
                                TextField("替换为（留空则删除）", text: $step.replacement)
                            }
                        }.padding(.vertical, 4)
                    }.onDelete { workflow.steps.remove(atOffsets: $0) }.onMove { workflow.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button("添加步骤", systemImage: "plus") { workflow.steps.append(.init(.trim)) }
                } header: { Text("从上到下依次执行") } footer: { Text("点“编辑”调整顺序；向左滑动步骤可以删除。") }
            }.navigationTitle("编辑动作").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            workflow.name = workflow.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if store.commit({ value in
                                if let i = value.workflows.firstIndex(where: { $0.id == workflow.id }) { value.workflows[i] = workflow }
                                else { value.workflows.append(workflow) }
                            }) { dismiss() }
                        }.disabled(workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workflow.steps.isEmpty)
                    }
                }
        }
    }
}

struct ProcessorView: View {
    @Environment(ClipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let clipID: UUID?
    var initialText: String
    var initialWorkflow: Workflow? = nil
    @State private var input = ""
    @State private var selectedID: UUID?
    @State private var output: String?
    @State private var showingHistory = false
    @State private var initialized = false

    private var workflow: Workflow? { store.index.workflows.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("选择动作", selection: $selectedID) {
                        Text("选择一个动作").tag(nil as UUID?)
                        ForEach(store.index.workflows) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu)
                    if let workflow {
                        Text(workflow.steps.map { $0.kind.title }.joined(separator: " → ")).font(.caption).foregroundStyle(Palette.muted)
                    }
                    HStack {
                        Text("原始内容").font(.headline)
                        Spacer()
                        if clipID == nil {
                            Button("从历史选择") { showingHistory = true }.font(.caption)
                            ClipboardPasteButton { input = $0.joined(separator: "\n") }
                        }
                    }
                    TextEditor(text: $input).font(.body).frame(minHeight: 180).scrollContentBackground(.hidden)
                        .padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("待处理的文字")
                    Button {
                        guard let workflow else { return }
                        guard input.utf8.count <= 5 * 1_024 * 1_024 else { store.error = "文字超过 5 MB，请分段处理。"; return }
                        output = TextActions.run(workflow.steps, on: input)
                    } label: {
                        Label("运行并预览", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(workflow == nil || input.isEmpty)
                    if let output {
                        HStack {
                            Text("处理结果").font(.headline)
                            Spacer()
                            Text(input == output ? "内容未发生变化" : "\(input.count) → \(output.count) 字").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Text(output.isEmpty ? "（处理结果为空）" : output).textSelection(.enabled).font(.body).lineSpacing(6)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .padding(18).background(Palette.softGreen, in: RoundedRectangle(cornerRadius: 16))
                        HStack {
                            Button("复制结果", systemImage: "doc.on.doc") { store.copy(Clip(text: output)) }.buttonStyle(.bordered)
                            Spacer()
                            Button(clipID == nil ? "保存为片段" : "替换原文") {
                                if let clipID { if store.saveText(output, id: clipID) { dismiss() } }
                                else if store.capture(output, source: "文本动作") != nil { dismiss() }
                            }.buttonStyle(.borderedProminent).disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if clipID != nil { Text("替换后，可在片段菜单里恢复上一次的原文。").font(.caption).foregroundStyle(Palette.muted) }
                    }
                }.padding(24)
            }.background(Palette.canvas).navigationTitle("文本处理").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .onAppear {
                    guard !initialized else { return }
                    input = initialText
                    selectedID = initialWorkflow?.id ?? store.index.workflows.first?.id
                    initialized = true
                }
                .onChange(of: input) { _, _ in output = nil }
                .onChange(of: selectedID) { _, _ in output = nil }
                .sheet(isPresented: $showingHistory) {
                    NavigationStack {
                        List(store.index.clips) { clip in
                            Button { input = clip.text; showingHistory = false } label: { Text(clip.title).lineLimit(2) }
                        }.navigationTitle("选择历史片段")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showingHistory = false } } }
                    }
                }
        }
    }
}
