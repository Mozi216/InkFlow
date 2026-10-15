# InkFlow iOS 原生验证工程

目标是将 Windows InkFlow 的文字演出迁移到真正的灵动岛。当前为未经过 Xcode 编译及真机验收的原型，不是可上架成品。Windows 版本不依赖此目录。

## 代码

- `InkFlowCore`：歌词解析、时间轴、语言排版、运动参数、参考场景测试。时间单位统一为秒。
- `Shared`：原生文字、辉光、纸片和镜叙叠字；App 与 Widget 共用。
- `App/Sync`：系统音频采集、Shazam 指纹匹配、网易云歌词请求。
- `App/Playback`：同步时钟、歌曲切换、实时活动发布。
- `LiveActivity`：实际的 WidgetKit / ActivityKit 扩展。
- `scripts`：云端构建、签名检查、Windows 设备操作。

## 当前已做与未验证的区别

已写入雾光、纵书、散章、拼贴、镜叙及自动选择。运动参数取自当前 Windows 源码；72 组参考场景记录位置、旋转、缩放及填充，用 Swift 测试比较数值。它们不证明字体光栅化和岛内动画已经一致。

App 预览用 TimelineView 请求 60 Hz。灵动岛用真实 ActivityKit 更新、系统定时 ProgressView 遮罩与原生过渡；没有网页或假灵动岛。系统能否持续执行遮罩、是否合并更新、背景动画帧率都尚未实测。没有强制长期展开的实现。

目前只有网易云歌词 HTTP 接口在 Windows 上验证过。音频采集、Shazam 时码、跨 App 后台运行均待 iOS 实测。静音会冻结未确认的时钟，并等待下一次指纹匹配；不能可靠区分歌曲本身的完全静音与暂停，恢复可能有识别延迟。版本匹配不唯一时要求选择，不把第一条搜索结果当成正确歌曲。

目前的自动同步不是 Windows SMTC 的移植。系统采集必须由用户在系统选择器中开启；采集到的是所选来源的音频，不保证一定来自网易云。画面立即丢弃，不记录原始音频。仅将指纹交给 Shazam 服务，将歌曲名称交给网易云搜索。

## 无 Mac 的构建方式

仓库根目录的 `.github/workflows/ios.yml` 使用 GitHub 提供的 `xcode-27` runner。推送 `codex/ios-native` 分支中的 iOS 改动会运行编译，也可以在 Actions 中手动运行 **InkFlow iOS**；不会自动上传 App Store：

1. 执行 Swift 核心测试；不通过就停止。
2. 用 XcodeGen 生成 App 与 Widget 两个 target。
3. 编译模拟器版本和设备版本。
4. 输出日志及 `InkFlow-unsigned.ipa`。这个文件尚未签名，不能直接安装。

运行前检查账户可用额度；本工程没有创建云端账户，也没有触发任何收费任务。

生成可安装测试包时，工作流开启 `signed_ipa`，并在 GitHub Secrets 中配置：

- `IOS_CERTIFICATE_BASE64`：Apple Distribution 证书的 P12 内容（Base64）。
- `IOS_CERTIFICATE_PASSWORD`：P12 密码。
- `IOS_APP_PROFILE_BASE64`：App 的 ad-hoc 描述文件（Base64）。
- `IOS_WIDGET_PROFILE_BASE64`：扩展的 ad-hoc 描述文件（Base64）。

两个描述文件必须属于同一 Team，包含要测试的 iPhone；扩展 Bundle ID 为 App ID 加 `.lyrics`。脚本从描述文件读取 Bundle ID，避免修改后忘记同步扩展。证书只能放 Secrets，不提交仓库或粘贴到聊天。

Shazam 目录识别还要求在 Apple Developer 的 App ID / App Services 中启用 ShazamKit。未启用时可以检查编译和预览，不能将其称为自动跟歌通过。正式上架还需歌词来源授权、审核资料和分发签名，均未完成。

## 插手机后

先有匹配设备的签名包，再安装 Apple 设备驱动和 `pymobiledevice3`，在手机上信任此电脑。开发调试可能需要 Developer Mode 和开发者镜像，届时根据设备版本处理，不自动修改系统设置。

```powershell
.\ios\scripts\device.ps1 -Action Check
.\ios\scripts\device.ps1 -Action Install -Ipa .\InkFlow.ipa
.\ios\scripts\device.ps1 -Action Screenshot -Output .\artifacts\iphone-screen.png
```

以上设备命令尚未在这台电脑连接 iPhone 执行；仅插线不代表具备签名或完成调试。

## 真机验收顺序

1. 先测实际灵动岛：长音持续 8 秒、逐字遮罩、五种效果、换句、两行、暂停半字、最后一句。将 App 切入后台，在岛内录制实际效果。不能用 App 内预览替代。
2. 测同步：网易云至少三首中英日歌曲，外放/耳机、暂停、拖进度、切歌、切换其他 App，各记录音频与高亮误差；不能只对比 UI 计时数字。
3. 连续运行 20 分钟，记录更新次数、丢失音频、热状态和画面卡顿。低电量及锁屏另测；不承诺 Always-On 下高帧。
4. 测取消系统采集、断网、识别失败、歌词不存在、长歌词超过 4 KB、重复歌曲和现场版本。超过载荷限制当前会报告错误，超长句的岛内分段还需完善。
5. 完整效果、自动展开、自动同步有任何一项未通过，仍算未达成用户要求，不标记成品完成。

## 依据

- [iOS 27 ScreenCaptureKit 官方示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [ShazamKit 时码](https://developer.apple.com/documentation/shazamkit/shmatchedmediaitem/predictedcurrentmatchoffset)
- [ShazamKit App ID 设置](https://developer.apple.com/help/account/services/shazamkit)
- [WidgetKit 动画限制](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)
- [Live Activities 生命周期和容量](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Xcode 27 云端 runner](https://github.com/actions/runner-images/issues/14404)
- [GitHub 签名流程](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
