# InkFlow iOS 原生验证工程

## 构建 12：预览与灵动岛共用画面

移除原来的两套绘制路径：App 的 60 Hz TimelineView 与岛内 `anchored` 静态字位不再并存；不再为岛内单独取消位移、缩放、模糊或改写透明度，也不再给岛内运动额外提前 1.25 秒。完整文字运动保留，由共享的 `StageFrame` 根据发布的歌词位置采样，再由 SwiftUI 插值。逐字填充使用同一系统计时遮罩，暂停时使用同一字宽加权进度。

App 和 Widget 直接调用 `IslandLyricView`：统一 320×136 内容区域、字体、辉光、下一句和换句过渡。预览增加展开/收起选择，收起与最小态也使用同一组件；选句不再依赖各个视图被绘制时的系统时间。系统提供的外围岛形与刷新调度仍由 iOS 控制，不能用 App 截图替代真机验收。

演示只有一份 20 秒时间轴。「在灵动岛显示」发送当前预览状态，不切换为另一套歌词、不把时间减半、不重置播放位置。发送前的容量处理也返回同一份状态给 App 预览，避免封面降级后两边内容不同。新增完整运动、等待分页、跨序列化场景和减少动态效果的回归测试；截图检查覆盖六种模式的中英日歌词。

本轮检测到一台 iOS 27.0 手机连接，但读取 App 信息时系统拒绝配对信任，尚未在该设备上安装或验证构建 12。

## 构建 11：识曲计算与等待状态修复

构建 10 已在 iPhone 15 Pro / iOS 26.6.1 上读到真实音频、匹配到歌曲并驱动灵动岛显示歌词。日志显示每轮指纹计算为 10.52、11.00、11.21 秒，请求分别约 0.75、0.66、0.46 秒；主要瓶颈在无 JIT 的 JavaScriptCore。未匹配期间状态一直保留“等待网易云播放”，这是错误提示。用户仍报告长时间等待与显示停顿，不能把一次显示成功当作同步和流畅度验收通过。

构建 11 用 WABT 转换的 C 代码原生计算，移除 App 与扩展的 JavaScriptCore 依赖。Windows 原生验证同一音频约 23 毫秒，输出与 WASM 完全一致；手机速度待测。新增独立原生测试，包括重复计算、静音及无效输入。确认服务可匹配 6/9 秒窗口后，改为 6 秒起步、失败逐步延长至 12 秒；过滤超过歌曲时长的无效位置。已收到声音时分别显示采样、匹配、未命中状态，不再误称等待播放。

频繁校时的微小误差会重建系统填充计时区间；现忽略 180 毫秒内的识别抖动，真实跳转仍校正。新增计时回归测试和播放状态日志。计算耗时、计时器重建、WidgetKit 显示调度是不同环节，尚未证明它们解释了所有停顿。

另外修正了音频恢复后仍等待识曲的逻辑：旧版遇到静音或缺失回调会冻结时钟，声音恢复却只能靠下一轮匹配重新启动，额外等待一个采样与识别周期。现在有已识别歌曲时，声音恢复即继续已有时钟，再由匹配结果校准；重复音频回调不改变计时起点，歌曲结尾也不会被重新启动。真实暂停、曲内静音和换歌仍不能只凭音量完全区分，不能把临时继续计时描述成已得到网易云的播放状态。

此次排查期间 USB 设备连接中断，后续修改尚未安装实测。不能宣称已经实现完全自动监听网易云、免系统采集确认或持续高帧灵动岛。当前 Apple 接口只允许当前 App 发布自己的 Now Playing 信息；快捷指令 App 打开触发能调起入口，但不会授予另一个 App 的音频访问。

已核查的无采集方案：Apple 的 Shazam 应用能够识别耳机里的音乐，快捷指令也能调用识曲；但尚未找到能交给 InkFlow 的连续播放进度、暂停和切歌事件，不能据此实现自动同步。网易云公开社区接口的 `relay_play_state_submit` 是上报状态，`listentogether_status` 属于一起听会话，均不是普通手机播放的全局查询入口。未添加假自动开关，也未把最近听歌记录当成实时进度。依据：[Now Playing](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)、[耳机识曲](https://support.apple.com/guide/shazam/dev57c8c9468/web)、[快捷指令识曲](https://support.apple.com/guide/shazam/deve5143aaf5/web)、[iOS 系统采集](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)。

## 构建 10：直接使用网易云音频指纹

构建 9 在这台免费签名的 iPhone 上实际处理了约 629 秒音频，后台主 App 持续收到共享组状态；ShazamKit 请求全部因 HTTP 401 失败。音频通道与跨进程通道有效，但没有成功识曲。后续调试器暂停广播扩展约 80 秒，触发连接超时；这次中止不能当作自然后台寿命的测量结果。

构建 10 改为本机计算网易云指纹，直接向网易云官方服务请求歌曲编号和采样位置，再拉取对应编号的歌词。没有 ShazamKit 授权、付费开发者账号或自建推送服务器依赖。每次采样 12 秒，正在识别时继续接收音频，间隔至少 4 秒；响应使用采样起点校时，暂停或音频断开后作废旧请求。初次识别和换歌存在采样等待，不能声称即时同步。

电脑实测：多个公共试听片段返回正确曲目，片段移动 3 秒，返回位置也相应变化；合成噪声无匹配。静音触发上游提取器内存中止的问题已增加前置保护；转换后的静态算法通过连续窗口一致性检查。上述结果不是手机端的端到端验收。云端编译、iPhone JavaScriptCore 性能、实际网易云歌曲的命中率与灵动岛持续更新仍需验证。

算法资源与来源见 `Vendor/NetEaseFingerprint/README.md`。仍须用户确认系统采集；本机后台任务每次最多 30 分钟且可能被 iOS 结束。联网用于网易云识曲与歌词，耳机音频来自系统采集而非麦克风。不能宣称 App Store 上架条件已满足。

## 构建 9：不经过推送服务的本机连接

当前用户要求免费签名、无需自建服务器，并且必须支持耳机。构建 9 将 iOS 26 的连接改为 ReplayKit 系统音频 → 音乐识别与歌词查询 → App Group 原子快照和 Darwin 通知 → 主 App 更新实时活动。扩展不再访问 ActivityKit，主 App 不再请求 APNs 令牌。画面和麦克风数据直接丢弃，不保存录音。

用户点连接后申请 `BGContinuedProcessingTask`，本次最多处理 30 分钟音频。进度来自实际处理的 PCM 样本数，系统可随时终止任务；手机会显示相应的后台任务界面。这里不是无限后台保活，也不能省略用户对系统采集的确认。歌曲识别和网易云歌词查询仍需互联网。

iLoader 为重签后的主 App 和扩展分配同一 App Group。代码读取各自签名描述文件中实际授予的组名，而非假定未签名工程的固定名称。此前将免费安装一概视为缺少共享组的判断不准确。共享权限、系统音频输入、Shazam 匹配和持续后台更新必须分别真机验证；本节尚不代表这些环节已经通过。

依据：[Apple 长任务文档](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)、[Apple DTS 对用户主动开始的持续处理会话的解释](https://developer.apple.com/forums/thread/840384)、[iLoader 签名实现](https://github.com/nab138/isideload/blob/main/isideload/src/sideload/sideloader.rs)。旧 APNs 服务代码保留作历史候选，不是当前连接的前置要求。

[构建 9 验证](https://github.com/Mozi216/InkFlow/actions/runs/38819928698) 对应 `9e083fd`：24 项核心测试、10 项旧服务协议测试、6 项签名检查、设备编译和 IPA 结构检查通过。未运行模拟器；旧服务测试不代表本机连接通过。`release/InkFlow-iOS-26-preview9-unsigned.ipa` 的 SHA256 为 `ddd57ea2a6809b4e09967fde4c5a6af0aa9c2a39e7e573fefca08407cbf4d702`。已经 iLoader 免费签名覆盖安装，USB 确认构建 9；iPhone 15 Pro / iOS 26.6.1 启动诊断确认 `sharedGroup: true`。这仅证实主 App 能访问已签名的共享容器，耳机音频、跨进程交换和实际歌词同步仍待播放实测。

## 构建 8：重做 iOS 26 音频扩展连接

用户确认 pre7 的显示验收仍未通过，优先修复「系统音频扩展未能访问歌词实时活动」。旧方案在三次真机日志中均返回零个活动，在识别开始前退出；本次删除广播扩展直接调用 ActivityKit 的路径，改为共享会话 + 私有 HTTPS 服务 + APNs 更新。

主 App 必须先取得推送令牌、注册服务，并真正收到 APNs 回传标记，才显示系统采集按钮。扩展只负责音频识别和歌词上传，服务处理签名、顺序、令牌轮换和结束消息。断网、失效、缺少权限都明确停止，不再提示用户反复重试原来的无效连接。连接条件、部署方法、数据范围和未通过项见 [推送连接说明](relay/README.md)。

**尚未在真实 APNs 和手机上连通。** 目前只有免费签名，没有这条路径需要的推送权限、共享组描述文件及已配置的 APNs 服务。普通 unsigned 构建用于检查代码及预览；不能靠重新安装它补出权限。显示卡顿、网易云匹配与后台时序仍未验收。这里没有声称实现了自动监听网易云启动、免系统确认或 App Store 成品。

[构建 8 最终验证](https://github.com/Mozi216/InkFlow/actions/runs/38817786638) 对应 `b4e9800`：24 项 Swift 核心测试、10 项服务协议测试、6 项签名检查、设备编译和 IPA 结构检查通过。服务测试使用替身 APNs，未连接 Apple；此次未运行模拟器截图，也未覆盖安装手机。包为 `release/InkFlow-iOS-26-preview8-unsigned.ipa`，SHA256 `dda137fc8a3706a1b9711c1e4c197b96e1eac4685bbeb1c5261d65d9d9c2bfdc`。初版构建 `38817260727` 通过；中间构建 `38817569784` 在后续修正后取消，以最终记录为准。

## 构建 7：同侧短语与固定位置

pre6 已通过 23 项核心测试、两个平台编译和模拟器截图，但用户真机验收仍失败：换句会停顿一两秒、收起态被拆成左右两半、展开歌词整体漂移。诊断中换句提交耗时为 6–34 ms，不能把提交成功当成屏幕及时渲染。

构建 7 将完整短语放在同一侧的 96 pt 区域居中，另一侧只保留 20 pt 封面；不再将一句分到摄像头两边。最小态仍为两行短语。展开态固定每个词的位置，去掉整个舞台的漂移、旋转和缩放；字形自身的摆动与背景叠字保留。显示姿态按渲染时的实际播放时间计算，避免重复显示过期姿态。增加稳定字位与持续填充测试。网易云连接的已知失败见下节。

[构建 7 验证](https://github.com/Mozi216/InkFlow/actions/runs/38815165108) 对应 `3d95431`：24 项核心测试、设备编译和 IPA 结构检查通过，本次未运行模拟器。包 `release/InkFlow-iOS-26-preview7-unsigned.ipa` 已经 iLoader 签名覆盖安装，USB 确认版本为 7 并成功启动。用户随后明确反馈「都没好」，因此显示验收失败，不能宣称流畅度或布局通过。

## 构建 6：收起态、持续运动与连接入口

构建 5 的用户实测未通过：收起态会把末句剩余单字当作一页，展开动画仍偶发卡顿，ReplayKit 入口不可见或无法点击；尚未完成网易云音频同步验证。

构建 6 改为摄像头两侧等宽、按实际字体测量排词，保留英文完整单词，并合并孤立尾字。预览结束时较短的最后一句完整保留。系统选择极小态时使用两行短语布局；单词很短时在普通收起态留出封面位置。不能由 App 强制生成主副两个岛。

镜叙加入跨越左右两侧的缓慢非线性摆动；散章、拼贴、纵书和雾光保留不同运动幅度。沿用 Windows 的基础字位和填充测试，新增 iOS 持续运动测试。装饰运动提前给出下一段目标并延长原生插值，逐字填充仍使用实际时钟。这是待验收的平滑度改进，不能据此宣称 60 fps。

用户另确认 pre5 在控制中心没有 InkFlow。广播扩展的 `RPBroadcastProcessMode` 原先错误地位于 `NSExtensionAttributes` 内，现移至 `NSExtension` 直接子项，并检查最终 IPA。pre6 已在 iPhone 15 Pro / iOS 26.6.1 安装、启动；用户确认系统面板出现 InkFlow，日志也确认 `SampleHandler` 已运行。ReplayKit 按钮以实际 52×52 尺寸创建，使用白底黑色系统控件；扩展缺失时明确报错。

**pre6 的网易云连接验收失败。** 2026-10-16 06:02–06:03 的三次真机启动中，广播扩展的 `Activity<LyricActivity>.activities` 均返回空数组，随后按代码结束广播。用户看到的“系统音频扩展未能访问歌词实时活动”与日志一致。该路径错误地假设广播扩展可以直接驱动主 App 的活动，不能继续把它当成可用的 iOS 26 后台同步方案，也不要要求用户重复安装或连接。此次失败发生在音频识别之前，尚未验证 Shazam 权限和网易云音频输入。

新增「准备网易云歌词」App Intent 与 `inkflow://connect` 入口，可用于快捷指令的网易云打开自动化。连接有效时 Intent 不唤起 App；未连接时进入前台确认入口，仍需用户确认采集。Intent 入口不能解决上述跨进程失败；尚未在手机验收。没有实现静默启动网易云采集，也没有声称等同 Apple Music 的系统播放接口。

后续连接方案必须先验证运行边界，再扩展功能：[ActivityKit 文档](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) 描述的更新来源是主 App 或 APNs。iOS 27 的 [ScreenCaptureKit 全屏采集](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios) 可在主 App 内运行，但当前连接的手机实际是 iOS 26.6.1，不能验证该路径。iOS 26 若采用服务器推送，还需 APNs 签名、服务端和更新频率验收；App Group 共享文件本身不会让已挂起的主 App 持续运行。两个方向都不是当前已完成的功能，也不能保证零确认或持续高帧动画。


目标是将 Windows InkFlow 的文字演出迁移到真正的灵动岛。当前原型已安装到 iPhone 15 Pro，并确认 App 原生渲染、真实灵动岛的紧凑与展开布局可显示。**构建 3 的 20 秒后台演示能换句，但用户反馈卡顿和文字闪动；网易云持续同步尚未通过测试，不是可上架成品。** Windows 版本不依赖此目录。

## 构建 4 的改动与验证范围

- 填充计时的日期只在暂停、跳转或校时后重建；移除逐字刷新上的整层动画和高对比度滤镜。文字运动、换句和填充分开处理。
- 实时活动只保留一个正在提交的更新，期间的新状态合并为最新一份。进度不再逐字向系统发送，通常每秒更新一次姿态，句子与短语边界及时更新。
- 收起态显示短语填充与切换，右侧显示歌曲封面；系统进入最小态时显示短歌词。两个独立岛的分配由 iOS 决定，不创建重复活动强占位置。
- iOS 26 增加 ReplayKit 扩展：用户先在 InkFlow 准备连接，再确认系统音频采集。扩展丢弃画面与麦克风数据，只将音乐音频用于 Shazam 指纹识别，再请求网易云歌词和封面。无录音文件、无 App Groups 或账户密码共享。
- ReplayKit 扩展能否访问主 App 创建的 Activity、个人签名下的 Shazam 识别，以及网易云能否提供可采集的音频，**尚待真机验证**。没有假装已实现零操作监听网易云启动。连接退出、系统采集结束、授权失败都可能中断同步。

构建 3 的真机截图已记录英文、日文、中文换句，用户也确认能换句。静态采样不能证明帧率；平滑度验收失败。

[构建 4 验证记录](https://github.com/Mozi216/InkFlow/actions/runs/38805452373)（`30deec7`）：17 项核心测试及模拟器、设备编译全部通过。为排查长时间编译提交过取消请求，取消发生在编译完成后的截图阶段，所以整条工作流显示 cancelled，只有一张雾光截图；不能称为完整工作流通过。包内 App、Widget、ReplayKit 扩展均为构建 4 / iOS 26.0。截图发现遮罩放在阴影外侧会截断辉光，因此构建 4 未交付安装。

构建 5 恢复先填充、后叠加辉光的顺序。核心源码与通过 17 项测试的版本一致；[设备编译](https://github.com/Mozi216/InkFlow/actions/runs/38808722564)已通过，代码为 `c922197`，使用手动 `device_only` 路径，明确不重跑核心测试和模拟器截图。包 `release/InkFlow-iOS-26-preview5-unsigned.ipa` 已验证三个组件均为构建 5 / iOS 26.0，待个人签名安装。新填充、收起态和网易云连接仍需真机验收，不能把编译通过称为流畅度或后台同步通过。

[云端验证记录](https://github.com/Mozi216/InkFlow/actions/runs/38789097264)：代码提交 `1c15515`，10 项 Swift 测试通过，其中包含 72 组 Windows 运动参考场景。iPhone 18 Pro 模拟器的六种原生预览已截图检查，并修复缩放后的整体位置偏移。编译和截图通过不代表灵动岛持续动画和网易云同步已通过实测。

## 代码

- `InkFlowCore`：歌词解析、时间轴、语言排版、运动参数、参考场景测试。时间单位统一为秒。
- `Shared`：原生文字、辉光、纸片和镜叙叠字；App 与 Widget 共用。
- `App/Sync`：系统音频采集、Shazam 指纹匹配、网易云歌词请求。
- `App/Playback`：同步时钟、歌曲切换、实时活动发布。
- `LiveActivity`：实际的 WidgetKit / ActivityKit 扩展。
- `scripts`：云端构建、签名检查、Windows 设备操作。

## 当前已做与未验证的区别

已写入雾光、纵书、散章、拼贴、镜叙及自动选择。运动参数取自当前 Windows 源码；72 组参考场景记录位置、旋转、缩放及填充，用 Swift 测试比较数值。它们不证明字体光栅化和岛内动画已经一致。

App 预览用 TimelineView 请求 60 Hz。灵动岛用真实 ActivityKit 更新、系统定时 ProgressView 遮罩与原生过渡；没有网页或假灵动岛。2026-10-16 真机测试确认岛内布局可显示，但回到主屏幕后歌词停留在预览句。当前预览依赖 App 的任务循环；它没有后台执行来源，不能据此提供连续换句。系统定时遮罩也不会自动选择下一句。没有强制长期展开的实现，尚未测得岛内帧率。

构建 2 修正预览的测试流程：一个按钮从零开始并清理旧活动；预览首尾使用不同句子；40 秒结束后停止计时并显示结束状态；再次点播放从零重播。Widget 会处理 `isStale`，不再无限展示过期歌词。诊断记录增加前后台切换及提交更新的时刻，提交成功不等同于系统实际渲染。这些修正**没有解决后台执行问题**，也没有通过新一轮真机验收。

构建 3 增加单独的 **20 秒灵动岛演示**：点击后从头播放五句样例，同时申请 UIKit 短时后台任务。正常结束、暂停、退出演示或系统提前收回执行时间时释放任务，不续期、不循环保活。它用于验证真实灵动岛中的短时换句、逐字填充与过渡，不是网易云的长期后台同步方案。系统仍可拒绝或提前终止任务；构建 3 已在手机上验证短时换句，平滑度未通过。

[构建 3 的云端验证](https://github.com/Mozi216/InkFlow/actions/runs/38800375770) 对应代码 `f6e955a`：12 项核心测试、模拟器及设备编译通过，生成六种原生预览截图。已检查 IPA 内 App 与扩展的构建版本均为 `3`、最低系统均为 `26.0`。本机测试文件为 `release/InkFlow-iOS-26-preview3-unsigned.ipa`，已由用户签名覆盖安装；短时换句另有真机采样和用户确认，不能据此认定流畅度通过。

网易云歌词 HTTP 接口已在 Windows 上验证。音频采集、Shazam 时码、跨 App 后台运行均待 iPhone 实测；模拟器不提供系统音频采集模块，只用于检查原生界面。静音会冻结未确认的时钟，并等待下一次指纹匹配；不能可靠区分歌曲本身的完全静音与暂停，恢复可能有识别延迟。版本匹配不唯一时要求选择，不把第一条搜索结果当成正确歌曲。

目前的自动同步不是 Windows SMTC 的移植。系统采集必须由用户在系统选择器中开启；采集到的是所选来源的音频，不保证一定来自网易云。画面立即丢弃，不记录原始音频。仅将指纹交给 Shazam 服务，将歌曲名称交给网易云搜索。

App 和实时活动的最低系统版本为 iOS 26，ScreenCaptureKit 音频采集要求 iOS 27；构建 4 为 iOS 26 增加了 ReplayKit 连接路径，尚待真机验证。不能把预览测试算成网易云同步通过。iOS 27 采集类单独做了可用性检查，避免低版本在启动时调用新接口。

[iOS 26 兼容构建](https://github.com/Mozi216/InkFlow/actions/runs/38792294203) 已通过 10 项核心测试、模拟器与设备编译、六种预览截图。实际检查 IPA：两个 bundle 的 `MinimumOSVersion` 均为 `26.0`，ScreenCaptureKit 为弱链接。设备测试包是 `release/InkFlow-iOS-26-unsigned.ipa`，仍需签名。

## 无 Mac 的构建方式

仓库根目录的 `.github/workflows/ios.yml` 使用 GitHub 提供的 `xcode-27` runner。推送 `codex/ios-native` 分支中的 iOS 改动会运行编译，也可以在 Actions 中手动运行 **InkFlow iOS**；不会自动上传 App Store：

1. 执行 Swift 核心测试；不通过就停止。
2. 用 XcodeGen 生成 App 与 Widget 两个 target。
3. 编译模拟器版本和设备版本。
4. 输出日志及 `InkFlow-unsigned.ipa`。这个文件尚未签名，不能直接安装。

生成可安装测试包时，工作流开启 `signed_ipa`，并在 GitHub Secrets 中配置：

- `IOS_CERTIFICATE_BASE64`：Apple Distribution 证书的 P12 内容（Base64）。
- `IOS_CERTIFICATE_PASSWORD`：P12 密码。
- `IOS_APP_PROFILE_BASE64`：App 的 ad-hoc 描述文件（Base64）。
- `IOS_WIDGET_PROFILE_BASE64`：扩展的 ad-hoc 描述文件（Base64）。
- `IOS_BROADCAST_PROFILE_BASE64`：音频采集扩展的 ad-hoc 描述文件（Base64）。

三个描述文件必须属于同一 Team，包含要测试的 iPhone；扩展 Bundle ID 分别为 App ID 加 `.lyrics` 和 `.broadcast`。脚本从描述文件读取 Bundle ID，避免修改后忘记同步扩展。证书只能放 Secrets，不提交仓库或粘贴到聊天。

Shazam 目录识别还要求在 Apple Developer 的 App ID / App Services 中启用 ShazamKit。未启用时可以检查编译和预览，不能将其称为自动跟歌通过。正式上架还需歌词来源授权、审核资料和分发签名，均未完成。

## 插手机后

安装 Apple 设备驱动和 `pymobiledevice3`，在手机上信任此电脑，即可先做连接检查。安装 App 则需要匹配设备的签名包。开发调试还需要 Developer Mode 和开发者镜像；由用户在手机设置中开启并确认重启。

2026-10-16 已在 Windows 上实际连接 iPhone 15 Pro（`iPhone16,1`），设备返回 iOS **26.6.1 / 23G83**，并确认安装网易云音乐 9.6.09。USB 配对、开发者模式、开发调试镜像及 DVT 查询均已验证。用户通过 iloader 为构建 1 签名并安装，已打开 App；通过 USB 截图确认了 App 与真实灵动岛布局。后台动态测试失败，且该系统不能运行本工程的 iOS 27 音频采集实现。设备标识、签名资料和手机主屏截图只保存在本机被忽略的目录，不随源码上传。

```powershell
.\ios\scripts\device.ps1 -Action Check
.\ios\scripts\device.ps1 -Action Install -Ipa .\InkFlow.ipa
.\ios\scripts\device.ps1 -Action Screenshot -Output .\artifacts\iphone-screen.png
```

`Check` 已在这台 iPhone 执行；脚本会优先使用项目内 `tools/ios-device` 的工具。`Install` 仍拒绝未带描述文件的包；`Screenshot` 需要已准备好的开发调试连接。仅插线不代表具备签名或完成调试。

没有付费会员时，可尝试用自己的免费 Apple 账户通过 AltServer 为测试包签名。登录和双重认证由用户在本机窗口操作，不把密码或证书放到仓库。此方式是否保留所需服务权限必须实测；不能据此承诺 ShazamKit 识别或 App Store 发布已经可用。

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
- [UIKit 短时后台任务与到期处理](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
- [Xcode 27 云端 runner](https://github.com/actions/runner-images/issues/14404)
- [GitHub 签名流程](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
