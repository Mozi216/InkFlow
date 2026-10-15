# iOS 26 歌词推送连接

这个目录替换了 pre6 / pre7 中失败的「广播扩展直接枚举主 App 实时活动」路径。它是待真机验收的实现，不是已连通的服务。现有免费签名安装包没有完成这条链路所需的权限；服务也尚未部署。

## 数据怎么走

1. 主 App 创建带 `.token` 的实时活动，取得 ActivityKit 推送令牌。
2. 主 App 向 HTTPS 服务注册。服务通过 APNs 发回会话标记，主 App 必须在 `contentUpdates` 中收到它，才允许继续。
3. 主 App 将短期上传凭据和样式写入 App Group。连接配置保存在本机 Keychain，APNs 私钥只留在服务端。
4. 用户在系统面板确认采集。ReplayKit 扩展读取会话，丢弃画面及麦克风数据，识别系统音乐并取得网易云歌词。
5. 扩展把当前歌词和时间轴发给服务，服务通过 APNs 更新实时活动。扩展不再调用 `Activity.activities` 或 `Activity.update`，也不要求已挂起的主 App 定时醒来。

只在换句、短语切换、校时、暂停或样式变化时发布，并有 15 秒心跳。填充使用歌词时间轴，不能靠每字发一条通知。服务器使用优先级 5；这能避免把所有消息作为高优先级消耗预算，但不能保证低延迟。推送限流、断网和系统渲染节奏仍需真机验收，这个改动没有解决 pre7 的卡顿问题。

## 准备条件

- 支持 Push Notifications 的 Apple Developer 签名。主 App 的 `aps-environment` 与服务环境必须一致。
- App 与广播扩展都授权同一个 `group.<主 App Bundle ID>` App Group；Widget 无需读共享凭据。
- 主 App、Widget、广播扩展的描述文件。开启实际识别所用 App ID 的 ShazamKit 服务。
- APNs ES256 `.p8` 私钥、Key ID、Team ID，以及可由手机访问的 HTTPS 服务。

不要把这些密钥写入源代码、IPA、Actions 日志或聊天。仓库的签名工作流从已有 Secrets 读取三个描述文件，检查共享组和推送权限，再设置 `Relay.entitlements`。普通 unsigned 构建不声明这些权限，可以用于预览编译；免费重签它不会自动得到推送能力。

## 服务运行

Node.js 22 或更新版本，无第三方依赖。运行前由部署环境提供：

| 环境变量 | 内容 |
| --- | --- |
| `INKFLOW_SETUP_KEY` | 为此自用服务随机生成的至少 32 字符连接密钥 |
| `APNS_BUNDLE_ID` | 实际签名后的主 App Bundle ID |
| `APNS_TEAM_ID` | 开发者 Team ID |
| `APNS_KEY_ID` | APNs 密钥 ID |
| `APNS_KEY_FILE` | 服务端 `.p8` 文件路径 |
| `APNS_ENVIRONMENT` | `sandbox` 或 `production` |
| `PORT` | 可选，本机端口，默认 8787 |

```sh
node --test ios/relay/server.test.mjs
node ios/relay/server.mjs
```

服务仅监听 `127.0.0.1`，前面需要 HTTPS 反向代理，并应关闭请求体及 Authorization 日志。不会自行创建外网隧道或公开端口。当前设计面向单人私有部署，尚未提供 App Store 公共服务所需的用户登录、账户隔离和持久化运维。

在自己的设备上创建 JSON 配置文件，通过 App 的「导入推送连接配置」选择它。字段为 `server`（HTTPS 根地址）和 `accessKey`（上述连接密钥）。不要将真实配置提交到仓库。导入后可删除原始配置文件，App 已将其保存在 Keychain。

## 生命周期和错误

- 会话凭据是服务端生成的随机值，最多存活六小时；服务只在内存中保存会话，重启后需要重新准备连接。
- 后续上传只能使用该会话凭据；注册密钥不能代替其他会话凭据。
- 推送令牌轮换后，主 App 更新服务端的目标。无效或注销的令牌会使会话失效。
- 每个会话顺序提交，拒绝旧序号；同一秒的更新等待下一秒，不伪造未来时间戳。客户端只保留最新待发送状态。
- APNs 外层日期用 Unix 秒，`content-state` 保留 Swift 默认 Codable 日期格式。超过 4 KB 时先移除封面，仍超限则报错，不截断歌词。
- 主 App 停止时删除共享会话并通知服务，广播扩展也会检查失效。扩展结束时发送 `end`；被系统强制结束或断网时，最后状态在 45 秒后变为过期，而不是假装继续同步。
- APNs 接受推送不代表已经显示；连接前的回传检查失败时，不显示系统采集按钮。

## 仍需真实凭据后的验收

先验证回传标记，再测试网易云音频能否采集及 Shazam 能否匹配。之后检查切歌、拖动、暂停、耳机、锁屏和至少 20 分钟后台运行，记录推送延迟及实际屏幕响应。当前本地测试使用替身 APNs 发送器，只验证协议、鉴权、顺序与失败处理，不能证明 Apple 已收到消息或手机已显示歌词。

依据：[ActivityKit 推送更新](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)、[App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[ShazamKit 服务配置](https://developer.apple.com/help/account/services/shazamkit)。
