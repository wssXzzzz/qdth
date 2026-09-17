# 全岛铁盒

给零散的文字，一个安静的家。

受 Taio 使用体验启发的独立原生 iPhone / iPad 剪贴板应用，支持 Mac Catalyst。聚焦历史浏览、置顶、收藏、文本处理及可选的 iCloud 同步。SwiftUI / UIKit / CloudKit，无第三方运行时依赖。

[设置页截图](docs/screenshots/icloud-settings.png) · [iCloud 状态示例](docs/screenshots/icloud-no-account.png)

## 功能

- 剪贴板历史、全文搜索、文字／链接筛选；手动收集时按内容去重。
- 独立置顶与收藏；复制、编辑、分享、删除确认、恢复上一版原文。
- 系统分享扩展，从其他 App 分享文字或链接到「全岛铁盒」。
- 可选前台自动收集，默认关闭；不声称能后台记录所有复制操作。
- 文本动作：清理空白、去空行、行去重、排序、大小写、引用、待办、URL 编解码、字面查找替换。
- 自定义动作和步骤排序；运行后先预览，再确认替换或另存。
- JSON 备份／合并导入，UTF-8 / UTF-16 文本导入。
- **iCloud 同步**：同一 Apple 账号的历史、置顶、收藏与动作增量同步，支持离线队列、删除标记、字段级冲突合并、状态显示和手动重试。默认关闭。
- 深浅色主题、iPhone 底部导航、iPad 自适应侧栏。

## 运行

1. 打开 `Inkflow.xcodeproj`，选择 `Inkflow` scheme。
2. 选择已安装运行时的 iPhone / iPad 模拟器，按 ⌘R，即可查看本地功能。
3. 安装真机时，在两个 target 的 **Signing & Capabilities** 选择你的开发者 Team，并配置应用标识与 App Group。
4. 启用真正的 iCloud 同步前，按照 **[iCloud 配置说明](docs/ICLOUD.md)** 注册容器和能力；需要有效的 Apple Developer Program 会员资格。

显示名称已经从「墨流」改为「全岛铁盒」。内部工程名、Bundle ID、App Group 与本机资料库路径保留兼容，不因改名丢失旧数据。

**源码已接入同步，但没有预配置任何人的开发者团队、签名证书或已注册的 CloudKit 容器。编译与本地自动化测试通过不代表已经完成两台真机的云端验收。**

## iCloud 使用

配置签名后，在设备上进入 **设置 → iCloud 同步 → 开启同步**，同一账号的其他设备也开启即可。可以查看待上传数量、最近完成时间，或点击“立即同步”。

数据使用你的 CloudKit **私有数据库**，不是 GitHub，也不是公共数据库。关闭同步不删除已有云端内容。切换 Apple 账号会暂停而不是自动迁移资料。操作系统可能延迟后台同步，重要内容请另做备份。

完整的配置、合并规则、生产环境部署和双设备验收清单见 [docs/ICLOUD.md](docs/ICLOUD.md)。

## 数据与隐私

- 默认只保存在应用沙盒 `Documents/Inkflow/index.json`；写入成功后才更新 UI。损坏文件不会被空资料库覆盖。
- 开启 iCloud 后，收集的文字和相关标记会传输到 Apple CloudKit；没有开发者自建服务端、广告或分析 SDK。
- JSON 导出是明文文件，请妥善保管。导出不包含 iCloud 账号绑定、设备 ID 或同步游标；导入不会覆盖当前账号绑定。
- 分享扩展写入 App Group 的独立收件文件，主应用确认落盘后才清理收件箱。
- 单条文本最多 5 MB，备份导入最多 50 MB；无自动过期。超大历史库仍受 JSON 全量本地读写性能限制，云端传输则按记录增量执行。
- iOS 不允许第三方 App 在后台持续收集其他 App 的所有复制，也不能恢复安装前的系统剪贴板历史。只保存实际收集到的纯文本／链接。

## 构建与测试

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodebuild -project Inkflow.xcodeproj -scheme Inkflow \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build-device CODE_SIGNING_ALLOWED=NO build
```

最低 iOS / iPadOS 17。当前本地验证环境为 Xcode 26.1.1、iOS SDK / 模拟器 26.1；尚未完成 Xcode 27 / iOS 27 的编译和真机验证。具体证据及未验证项见 [验证记录](docs/VALIDATION.md)。

工程可直接打开；增加源文件后可运行 `node scripts/generate-project.mjs` 重新生成，无需 XcodeGen、CocoaPods 或 npm 安装。生成器会覆盖工程设置，个人 Team / Bundle ID 等修改应同步到脚本，或不要重新生成工程。

`--demo` 启动参数使用独立临时示例资料库，并禁止 iCloud 上传。图标由 `scripts/make-icon.swift` 绘制。公开仓库只包含源码、测试和示例截图，不包含用户资料库或签名材料。

## 目录

```text
Inkflow/App/          原生界面、ClipStore、CloudKit 同步控制器
Inkflow/Core/         模型、动作、持久化、备份、可测试的同步合并逻辑
ShareExtension/       系统分享入口
Tests/                核心与多设备合并回归测试
scripts/              工程、图标与验证脚本
docs/                 配置、验证与示例截图
```

## 参考

- [Taio App Store 页面](https://apps.apple.com/cn/app/id1527036273)
- [Apple CloudKit 官方示例](https://github.com/apple/sample-cloudkit-sync-engine)
- [剪贴板隐私与系统粘贴控件](https://developer.apple.com/videos/play/wwdc2022/10096/)
