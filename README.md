# 全岛铁盒

给零散的文字，一个安静的家。

当前版本：**1.2.4（build 7）**。短文本卡片高度随内容自适应，详见 [版本更新记录](CHANGELOG.md)。

受 Taio 使用体验启发的独立原生 iPhone / iPad 剪贴板应用，支持 Mac Catalyst。聚焦历史浏览、置顶、收藏、文本处理及可选的 iCloud 同步。SwiftUI / UIKit / CloudKit，无第三方运行时依赖。

[设置页截图](docs/screenshots/icloud-settings.png) · [iCloud 状态示例](docs/screenshots/icloud-no-account.png)

## 功能

- 剪贴板历史、全文搜索、文字／链接筛选；手动收集时按内容去重。
- 独立置顶与收藏；复制、编辑、分享、删除确认、恢复上一版原文。
- 主屏幕小组件：小／中／大尺寸展示置顶与收藏摘要，点击进入片段；提供收集、历史、收藏入口，并支持隐藏桌面文字。
- 系统分享扩展，从其他 App 分享文字或链接到「全岛铁盒」。
- 可选前台自动收集，默认关闭；不声称能后台记录所有复制操作。
- 文本动作：清理空白、去空行、行去重、排序、大小写、引用、待办、URL 编解码、字面查找替换。
- 自定义动作和步骤排序；运行后先预览，再确认替换或另存。
- JSON 备份／合并导入，UTF-8 / UTF-16 文本导入。
- **iCloud 同步**：同一 Apple 账号的历史、置顶、收藏与动作增量同步，支持离线队列、删除标记、字段级冲突合并、状态显示和手动重试。默认关闭。
- 深浅色主题、iPhone 底部导航、iPad 自适应侧栏。

## 运行

**没有付费开发者会员、只想装到自己的手机：选择 `InkflowLocal` scheme，按 [免费自用安装说明](docs/LOCAL_INSTALL.md) 操作。** 本地版不会初始化 CloudKit，不包含分享扩展；免费签名需要每 7 天续签。下面的 `Inkflow` 是保留云同步的完整版。

1. 打开 `Inkflow.xcodeproj`，选择 `Inkflow` scheme。
2. 选择已安装运行时的 iPhone / iPad 模拟器，按 ⌘R，即可查看本地功能。
3. 安装真机时，为 App 和其扩展 targets 的 **Signing & Capabilities** 选择同一个开发者 Team，并配置应用标识与 App Group。完整版为 Inkflow / InkflowShare / InkflowWidget，本地版为 InkflowLocal / InkflowLocalWidget。
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
- 小组件只读取本机 App Group 的有限摘要：最多六条置顶／收藏，每条最多 180 字符；不读取完整资料库、普通历史或剪贴板。可在设置关闭内容展示，系统刷新可能延迟。
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

最低 iOS / iPadOS 17。已在 Mac mini 的 Xcode 27.0 / iOS SDK 27.0 下通过核心测试、完整版与本地版 iOS 无签名构建及 Mac Catalyst 无签名构建；iOS 27 模拟器与真机运行尚未验证。此前界面验证使用 iOS 26.1 模拟器。具体证据及未验证项见 [验证记录](docs/VALIDATION.md)。

工程可直接打开；增加源文件后可运行 `node scripts/generate-project.mjs` 重新生成，无需 XcodeGen、CocoaPods 或 npm 安装。个人 Team 放在 Git 忽略的 `Config/Signing.local.xcconfig` 中，可复制同目录的 `Signing.local.example.xcconfig` 并填写自己的 Team ID；App 和对应小组件自动使用同一个 Team。公开工程只引用变量，不包含任何人的 Team ID；重新生成不会改动本机签名配置，但会覆盖工程里的其他手工构建设置。切勿提交证书或用户数据。

`--demo` 启动参数使用独立临时示例资料库，并禁止 iCloud 上传。桌面、设置页、侧栏和小组件统一使用设置页原有的圆润引号造型，图片字节一致；品牌颜色不随 App 深浅色主题反转。iOS 主屏幕的圆角、着色等仍由系统控制。

更新图标时运行下列命令，避免出现两套图形；`check-brand.mjs` 同时检查四个 App／Widget target 都包含共享图标：

```sh
swift scripts/make-icon.swift \
  Inkflow/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  BrandAssets.xcassets/BrandMark.imageset/BrandMark.png
node scripts/check-brand.mjs
```

公开仓库只包含源码、测试和示例截图，不包含用户资料库或签名材料。

## 目录

```text
Inkflow/App/          原生界面、ClipStore、CloudKit 同步控制器
Inkflow/Core/         模型、动作、持久化、备份、可测试的同步合并逻辑
ShareExtension/       系统分享入口
WidgetExtension/      主屏幕小组件（完整版与本地版独立签名）
Tests/                核心与多设备合并回归测试
scripts/              工程、图标与验证脚本
docs/                 配置、验证与示例截图
```

## 参考

- [Taio App Store 页面](https://apps.apple.com/cn/app/id1527036273)
- [Apple CloudKit 官方示例](https://github.com/apple/sample-cloudkit-sync-engine)
- [剪贴板隐私与系统粘贴控件](https://developer.apple.com/videos/play/wwdc2022/10096/)
