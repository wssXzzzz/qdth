# iCloud 配置与同步说明

全岛铁盒 1.1 使用 `CKSyncEngine` + **CloudKit 私有数据库**，同步同一 Apple 账号下的设备。无需自建服务器，但源码中写入容器名称不等于已经在 Apple 注册了该容器。

## 先准备

- 有效的 **Apple Developer Program** 会员资格及相应团队权限；免费 Personal Team 不能完成这套 CloudKit 能力配置。
- Xcode 和两台测试设备（例如 iPhone + iPad，或 iPhone + Mac Catalyst），登录同一个 iCloud 账号。
- 开启设备的 iCloud 权限。系统限制、低电量、网络及配额会影响自动同步。

没有开发者配置时，可以在模拟器运行本地功能；不要把无账号模拟器的编译通过当作跨设备同步通过。

## 1. 签名与容器

打开 `Inkflow.xcodeproj`，两个 target（`Inkflow`、`InkflowShare`）在 **Signing & Capabilities** 中选择同一 Team。

默认标识如下；如果它们尚未被注册且属于你的团队，可以沿用，否则替换成你拥有的唯一标识：

| 用途 | 默认值 | 修改位置 |
| --- | --- | --- |
| 主应用 Bundle ID | `com.qdth.inkflow` | Xcode 主 target / `scripts/generate-project.mjs` |
| 分享扩展 Bundle ID | `com.qdth.inkflow.share` | Xcode 扩展 target / 生成脚本 |
| 本机共享 App Group | `group.com.qdth.inkflow` | 两份 entitlements、`ClipStore.swift`、`ShareViewController.swift` |
| iCloud 容器 | `iCloud.com.qdth.inkflow` | 主应用 entitlements、`CloudSyncController.containerID` |

主应用添加/确认以下能力：

1. **iCloud → CloudKit**：创建并勾选上述容器。
2. **Push Notifications**：用于 CloudKit 变更通知。
3. **Background Modes → Remote notifications**：源码 Info.plist 已包含此项。
4. **App Groups**：与分享扩展相同的 group。

分享扩展只需要 App Group，不直接访问 CloudKit。它收集的文字由主应用下次启动时导入，再进入同步队列。所有设备版本必须使用同一个 CloudKit 容器。

> 保留原 Bundle ID 和 App Group 能让旧版升级继续访问原数据。修改 Bundle ID 相当于安装另一个 App，请先导出旧版备份。应用显示名称已经改成「全岛铁盒」，内部工程和目录名保留 Inkflow 以保持兼容。

## 2. 在开发环境测试

1. 用配置好 Team 的 Xcode 分别安装到两台设备。
2. 打开 **设置 → iCloud 同步**，阅读并确认上传提示。
3. 点 **立即同步**，确认没有权限、容器或账号错误。
4. 首次写入会建立自定义 zone `QuanDaoTieHe` 和记录类型 `VaultItem`。
5. 在另一台设备开启同步并点“立即同步”，确认文字、置顶、收藏和文本动作一致。

每条 CloudKit 记录只有以下自定义字段：

| 字段 | CloudKit 类型 | 内容 |
| --- | --- | --- |
| `payload` | Asset | UTF-8 JSON：文字/动作、字段版本或不含文字的删除标记 |
| `revision` | String | 单次上传标识，用于避免旧上传确认覆盖新编辑 |
| `schemaVersion` | Int64 | 当前为 1 |

使用 Asset 是为了支持超过 CloudKit 普通字段大小限制的文本。应用不做公共数据库查询，因此不需要业务查询索引。

## 3. TestFlight / App Store 前

开发环境和生产环境是两套数据，不能拿 Xcode 的开发版与 TestFlight 版直接验证同步。

1. 在 [CloudKit Console](https://icloud.developer.apple.com/) 选中自己的容器。
2. 检查 Development 中 `VaultItem` 的三个字段类型。
3. 将 schema **部署到 Production**；这不会把测试记录复制到生产数据库。
4. 使用正确的分发签名归档。检查归档后的 iCloud 容器、CloudKit 环境和 APNs entitlement；不要手工把开发 provisioning profile 用于发布。
5. 两台设备都安装同一环境的版本后，重新执行下面的验收清单。

本项目没有替你注册容器、选择 Team、部署 schema、创建签名证书或发布 TestFlight。

## 同步规则

- **默认关闭**；开启后同步已有和以后收集的片段、置顶、收藏、编辑及动作。外观、前台剪贴板开关只保留在本机。
- 本机继续使用原子写入的 `Documents/Inkflow/index.json`；新增的 `sync` 字段与内容在同一事务中保存。云端按记录增量传输，不上传整份资料库。
- 本地旧资料库无损读取；首次开启时建立同步索引。未修改的内置动作转成固定 ID，避免每台设备多一套动作。
- 每个字段有混合逻辑时钟。**置顶与收藏分别合并**；文字和上一版原文作为一组；动作整体作为一组。同一字段同时修改时按时钟与设备 ID 确定胜者，不保证保留双方所有编辑历史。重要内容仍建议定期备份。
- 删除采用 **delete-wins 墓碑**：同一记录 ID 一经删除，离线旧副本不能让它复活。墓碑不包含原文字，不自动过期。重新收集或从备份恢复会使用新 ID。
- 同一条记录在设备间不会重复；两个设备在尚未同步时分别收集相同文字可能有不同 ID，保留为独立片段，避免误删合法的相同内容。
- 上传确认会比对送出版本；上传途中发生的新编辑继续留在队列。落盘失败、未知数据格式或无效记录会暂停同步，不接受后续游标。
- 首次开启时资料库绑定当前 iCloud 账号。退出或换账号后暂停，保留本机内容；**不会将原账号资料自动上传给另一个账号**。恢复同步请切回原账号；本版没有“迁移到新账号”的入口。
- 用户在 iCloud 中移除资料库后，不自动重建并传回旧内容；设置页需要明确确认“重新上传本机资料库”。
- 关闭同步保留本机与云端内容，之后本机编辑仍记入队列，重新开启时合并。关闭开关不代表删除云端数据。
- 导出备份只包含可移植内容，不含账号 ID、设备 ID、CloudKit 游标和传输元数据。旧备份可导入，导入不会覆盖当前账号绑定。
- 自动同步由系统调度，可能延迟；前台激活会主动同步，也提供“立即同步”。iCloud 同步不能绕过 iOS 后台读取剪贴板的限制。

## 真机验收清单（需开发者配置后执行）

- [ ] A 新建片段，B 自动/手动同步后出现，重启后仍存在。
- [ ] A 置顶、B 收藏，同步后两者都保留；再取消收藏，不被置顶动作恢复。
- [ ] A 删除，B 离线修改该片段后联网，删除不会复活。
- [ ] A/B 同时编辑同一段文字，多次同步后结果收敛。
- [ ] 上传进行中继续编辑，最新修改最终出现在另一台设备。
- [ ] 自定义动作新增、修改、删除一致，内置动作不重复。
- [ ] 断网后收集、杀掉 App、重开并联网，队列恢复并上传。
- [ ] 退出 iCloud / 换账号，暂停且不串号；切回原账号恢复。
- [ ] 关闭同步，不再传输新变更；重新开启正常合并。
- [ ] 分享扩展收集后打开主应用，另一台设备随后收到。
- [ ] 大文本、中文、emoji、iCloud 配额不足和权限受限时状态准确。
- [ ] 云端删除 zone 后不会自动重传，确认后可重新建立。
- [ ] 两台生产环境/TestFlight 设备重复完成以上核心场景。

## 苹果资料

- [CKSyncEngine 官方示例与开发者会员要求](https://github.com/apple/sample-cloudkit-sync-engine)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [CKSyncEngineDelegate：事件串行处理](https://developer.apple.com/documentation/cloudkit/cksyncenginedelegate-1q7g8)
- [Sync to iCloud with CKSyncEngine（WWDC23）](https://developer.apple.com/videos/play/wwdc2023/10188/)
