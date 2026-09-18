# 免费账号安装到自己的 iPhone

使用 **InkflowLocal** scheme，不需要购买 Apple Developer Program，也不需要上架。

## 两个版本

| Scheme | 用途 | 能力 |
| --- | --- | --- |
| `InkflowLocal` | 免费 Personal Team 自用 | 历史、置顶、收藏、搜索、文本动作、备份、桌面小组件；不连接 CloudKit、不包含分享扩展 |
| `Inkflow` | 有开发者会员时使用 | 另含 iCloud、推送和 App Group 分享扩展 |

本地版的 Bundle ID 是 `com.wssxzzzz.quandaotiehe.local`，与完整版独立，避免覆盖另一个版本的数据。切换版本可通过导出／导入备份迁移。

## 首次安装

1. 在 Mac 上安装 Xcode，打开 **Xcode → Settings → Apple Accounts → Add Apple Account**，登录自己的普通 Apple 账号。密码及验证码只在苹果登录窗口输入。
2. 用数据线连接 iPhone，解锁并确认“信任此电脑”。
3. 在 iPhone 打开 **设置 → 隐私与安全 → 开发者模式**，按系统提示重启，并在重启后确认启用。若找不到选项，先让 Xcode 识别已连接的手机，再回到设置检查。
4. 打开 `Inkflow.xcodeproj`，选择 **InkflowLocal** scheme；运行目标选择自己的 iPhone，不要选模拟器或 `Inkflow` scheme。
5. 为 **InkflowLocal** 和 **InkflowLocalWidget** 两个 target 使用同一个 **Personal Team**。推荐复制 `Config/Signing.local.example.xcconfig` 为 `Config/Signing.local.xcconfig`，填写自己的 `QDTH_LOCAL_DEVELOPMENT_TEAM`，自动签名即可读取它；该文件被 Git 忽略，不会公开。也可在 Xcode 的 Signing & Capabilities 直接选择 Team，但不要把由此写入工程的个人 Team ID 提交到公开仓库。两者必须使用同一个本地 App Group；当前为 `group.com.wssxzzzz.quandaotiehe.local`。换账号自建时若标识已被占用，请同时修改两个 entitlements 和 `WidgetStorage.groupID` 的本地分支，并使用自己的 Bundle ID。
6. 点运行（⌘R）。Xcode 会为这个 App 创建个人开发签名并安装。
7. 如果手机提示“不受信任的开发者”，进入 **设置 → 通用 → VPN 与设备管理**，找到自己的开发者账号并按提示信任，再打开「全岛铁盒」。

本地版只使用 App Groups 在 App 和小组件之间共享少量摘要，不启用 iCloud 或 Push Notifications。构建时的 `LOCAL_ONLY` 条件会排除实际 CloudKit 实现，设置页也不显示云同步开关。Apple 当前能力表列出免费账号支持 App Groups；仍需由 Xcode 为两个 target 正确签名。

## 添加主屏幕小组件

更新后先打开一次「全岛铁盒」，再长按主屏幕空白处 → 编辑 → 添加小组件，搜索「全岛铁盒」，选择「常用文字」的小、中或大尺寸。

- 小号显示一条常用文字，中号最多两条，大号最多四条；置顶优先，同类按收集时间倒序。
- 点文字进入对应片段，再点「复制内容」。中、大号还提供收集文字、历史和收藏入口。
- 小组件不会在后台读取系统剪贴板；收集入口打开 App 的系统粘贴控件，需要用户点按确认。
- 只共享最多六条、每条最多 180 个字符的置顶／收藏摘要，不共享完整资料库或普通历史。快照保存在本机 App Group，原资料库仍保存在原 App 沙盒；覆盖安装不会迁移或清空它。
- 设置 → 主屏幕小组件可隐藏文字；隐藏时会把共享快照替换为空内容。WidgetKit 控制最终刷新时间，可能不是立即更新，敏感内容应确认桌面已隐藏，或移除小组件。
- 小组件库中的示例只用于系统预览，添加到桌面后读取真实快照。若列表暂未出现，请先打开 App、退出主屏幕编辑再重试。

官方说明：[支持的能力](https://developer.apple.com/help/account/reference/supported-capabilities-ios)、[创建小组件](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)。

## 7 天后续签

免费 Personal Team 的 provisioning profile 7 天后到期。届时用同一个 Apple 账号、同一个 Team 和 Bundle ID，再用 Xcode 运行一次，覆盖安装即可。

**不要先删除手机上的 App。** 删除 App 可能一并删除本地资料库。建议在 App 的设置页定期导出明文 JSON 备份，并妥善保管。首次安装为空资料库，不会上传或注入示例内容。

## 无账号编译检查

下面的命令只验证编译，不产生可直接安装到手机的签名包：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test -Xswiftc -DLOCAL_ONLY
xcodebuild -project Inkflow.xcodeproj -scheme InkflowLocal \
  -destination 'generic/platform=iOS' -derivedDataPath build-local \
  CODE_SIGNING_ALLOWED=NO build
```

免费签名和开发者模式要求见 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 与 [启用开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
