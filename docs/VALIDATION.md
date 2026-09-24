# 验证记录

## 1.2.4：短文本卡片自适应高度（2026-09-24）

- 移除片段正文 106 pt 的固定最小高度，按实际排版高度展示，保留最多五行预览、原有圆角、留白和底部收藏／复制按钮。历史、置顶与收藏共用此布局。
- 用户已在 iPhone 15 Pro 确认短文本卡片效果；正式版本统一为 1.2.4（build 7），工程生成脚本与全部 targets 的版本号同步更新。
- 核心测试 31 项通过，品牌一致性检查通过，本地版真机签名构建及完整版 iOS 无签名构建通过。
- 1.2.4 已覆盖安装到 iPhone 13 Pro Max 与 iPhone 15 Pro，两个设备均确认版本为 1.2.4（build 7）且启动命令成功；未卸载应用或主动清空本地数据。

## Mac mini 真机续签（2026-09-24）

- 用户完成备份并在 Mac mini 的 Xcode 登录原 Apple 账号后，`InkflowLocal` 与 `InkflowLocalWidget` 自动签名构建通过。
- 同一 Bundle ID 的 1.2.3（build 6）已覆盖安装到 iPhone 13 Pro Max，设备启动命令成功；未卸载应用或主动清空资料库，资料内容未逐条核验。
- 新描述文件到期时间（北京时间）：主应用 2026-10-01 09:23:01，小组件 2026-10-01 09:23:03。

## Mac mini 迁移验证（2026-09-24）

- 环境：Apple Silicon arm64、macOS 27.0（26A428）、Xcode 27.0（27A266a）、Swift 6.4、iOS SDK 27.0、Node.js 26.10.0；Xcode 命令行工具路径正确。
- `swift test`：31 项通过；使用独立构建目录执行 `swift test --scratch-path artifacts/migration-check/swift-local -Xswiftc -DLOCAL_ONLY`：31 项通过。
- `node scripts/check-brand.mjs`：共享品牌图片及四个 App / Widget target 检查通过。
- 在全新 DerivedData 目录中，`Inkflow` 与 `InkflowLocal` 的 iOS 设备构建、`Inkflow` 的 Mac Catalyst 构建均通过，全部使用 `CODE_SIGNING_ALLOWED=NO`。这验证了当前源码在 Xcode 27 / iOS 27 SDK 下的编译，不代表真机运行验收。
- 工程、配置及脚本未发现写死的旧机器 `/Users/` 或 `/Volumes/` 路径；本机签名配置文件存在，但钥匙串报告 0 个有效代码签名身份。
- 未安装任何 iOS 模拟器运行时，因此本轮未执行模拟器启动或界面操作；未执行真机安装、iCloud 双设备同步及签名分发验证。
- 完整版设备与 Catalyst 构建出现 App Intents 元数据提取跳过警告（没有依赖 AppIntents.framework），不影响构建成功。
- 本轮日志及新构建产物位于 Git 忽略的 `artifacts/migration-check/`；保留原机器复制过来的构建目录，未清理用户数据或签名配置。

## 1.2.3：长按预览圆角（2026-09-18）

- 剪贴板卡片和文本动作卡片使用共用 `RoundedMenuCard`：背景、内描边、裁剪、交互区域与 `.contextMenuPreview` 使用同一个连续圆角形状；不再仅绘制圆角背景而保留矩形抬起预览。
- 本地版真机签名构建、模拟器构建、完整版 iOS 无签名构建通过；完整版与本地版核心测试各 31 项通过，品牌图标一致性检查通过。
- iPhone 13 Pro Max（iOS 18.7.8）覆盖更新至 1.2.3（build 6），启动成功、进程保持运行；未修改或清空用户资料库。
- 用户在真机长按记录并收起菜单后确认“已经圆润了”。模拟器额外验证普通点按仍能进入片段详情；完整长按动画以此次真机反馈为验收依据。
- 对应官方接口：[contextMenuPreview](https://developer.apple.com/documentation/swiftui/contentshapekinds/contextmenupreview)。

## 1.1：全岛铁盒与 iCloud（2026-09-17）

本轮沿用下述 Xcode 26.1.1 / iOS 26.1 环境。

- **24 项 Swift Testing 测试通过**：原 7 项 + 17 项同步测试。
  - 无 sync 字段的旧版资料库迁移，内容和标记不丢失。
  - 两设备分别置顶／收藏、取消收藏与无关修改合并。
  - 离线编辑与删除竞争、墓碑持久化、不复活。
  - 同一字段并发编辑确定性收敛、三设备合并顺序无关及幂等。
  - 设备时钟快一天，读取后再修改仍能收敛。
  - 旧上传确认不清掉较新的本机变更。
  - 账号绑定拒绝换账号上传，备份导入不能改变绑定。
  - 导出移除账号和游标等元数据，恢复已删除内容分配新 ID。
  - 动作修改／删除、默认动作固定 ID、旧编辑器保存后分配新 ID。
  - 关闭同步期间仍记录离线变更，队列与内容同次落盘。
  - 拒绝未知 schema 和无效远端记录，不改写本机内容。
- iOS Simulator、iOS arm64 设备架构、Mac Catalyst 的主应用与分享扩展均编译通过；设备／Catalyst 构建未做开发者签名。
- 模拟器实测：设置显示「全岛铁盒」；iCloud 默认关闭；开启前展示上传范围确认；无账号时显示登录提示和 5 项待上传，而不是崩溃或虚假成功；手动重试正常；关闭后保留本机资料库。
- 旧版模拟器中的 1 条示例内容在更新及首次同步索引迁移后仍保留。
- 截图：`screenshots/icloud-settings.png`（设置与新名称）、`screenshots/icloud-no-account.png`（真实未登录状态）。截图内容为测试示例，不含个人账号或用户文字。
- 公开源码排除编译产物、签名证书、私钥、用户资料库、个人 Xcode 状态；提供 GitHub Actions 的核心测试与无签名 iOS 构建。

**未验证／仍需用户配置：** 本机没有可用 Apple 开发者签名身份，也没有已注册到用户团队的 CloudKit 容器，因此没有执行真实 iCloud 上传、双设备下载、APNs 后台推送、账号切换、配额错误、生产 schema 或 TestFlight 实测。核心多设备测试是本地模型模拟，不是云端验收。完整步骤见 [ICLOUD.md](ICLOUD.md)。Xcode 27 / iOS 27 验证仍未完成。

## 1.0 历史验证

日期：2026-09-16。测试内容均为本项目生成的示例文字。

## 环境

- macOS 15.6.1，Xcode 26.1.1（17B100），Swift 6.2.1。
- iOS SDK 26.1；部署下限 17.0。
- iPhone 17 与 iPad Air 11-inch M3 模拟器，iOS 26.1。
- 同一套界面的 Mac Catalyst 运行实例。

## 通过的检查

- Swift Testing：7 项核心测试通过。
  - 置顶与收藏状态独立，保存／重读后保留。
  - 损坏资料库读取失败，不覆盖原始文件。
  - 中文、emoji、CRLF 换行的动作组合与字面替换。
  - URL 编码／解码往返及无效编码处理。
  - 备份内容去重、ID 冲突处理与收藏／置顶标记合并。
  - 安全 HTTP(S) 链接识别。
  - UTF-8 BOM、UTF-16 文本解码与错误编码拒绝。
- iOS 真机架构 arm64 的主程序与分享扩展构建通过（未签名，不能直接安装到 iPhone）。
- iOS 模拟器完整构建（含图标资源）与本地签名通过，已安装并启动 iPhone / iPad 实例。
- Mac Catalyst 主程序与分享扩展构建通过。
- 实际界面操作：手动保存中文与多行文本；收藏；置顶；去重预览；确认替换；恢复原文；收藏独立页面。
- iPhone：卡片、粘贴控件、玻璃导航、详情、收藏筛选正常显示。
- iPad：侧栏、历史卡片、置顶与粘贴控件正常显示。
- App Group 模拟器共享容器已建立。通过收件箱注入一条中文与 emoji 测试文本，重新启动主应用后已完整导入为“分享菜单”来源，确认保存后收件文件被移除。
- iPhone 系统分享面板中可以找到墨流；实际打开“收集到墨流”扩展后，原文完整显示，点击“收集”成功写入 App Group 收件箱。随后以正式模式启动主程序，37 字原文完整进入历史，来源为“分享菜单”，收件箱已清空，端到端流程通过。

## 真实截图

- `screenshots/iphone-library.png`：iPhone 首页，独立演示资料库。
- `screenshots/ipad-library.png`：iPad 首页，独立演示资料库。
- `screenshots/iphone-share-import.png`：系统分享扩展收集后，原文进入主应用历史。

## 仍需完成的发布验证

- Xcode 27 / iOS 27 SDK 编译、iOS 27 真机运行与分享权限验证。本机系统版本不能运行 Xcode 27，因此未宣称已完成最新系统认证。
- 使用自己的 Apple Developer Team 为主程序和分享扩展配置唯一 Bundle ID 与共享 App Group，完成真实签名。
- 如通过 TestFlight / App Store 分发，另需归档、审核资料与账号配置。

## 本机 Xcode 注意事项

本机最初仅激活 Command Line Tools，因此所有构建都显式设置了 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。Xcode 出现过“iOS 26.1 is not installed”与 actool 找不到运行时的问题。安装 Xcode 默认的 iOS 26.1 运行时补丁版本 **23B86** 后已解决，最终完整构建不需要排除任何资源：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Inkflow.xcodeproj -scheme Inkflow \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
```

另外，`scripts/check.sh` 通过明确的 iOS destination 验证设备构建，避免 Xcode 在没有合适 iOS destination 时自动选择 Mac Catalyst。图标源文件和生成器已经提供。
