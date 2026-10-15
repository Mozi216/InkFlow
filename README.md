# InkFlow

iOS 原生歌词效果验证工程。App 和实时活动扩展共用 SwiftUI 文字排版、辉光和逐字填充，目标是在网易云播放时同步歌词。

当前不是经过真机验收的成品。持续展开灵动岛、跨 App 同步和岛内动画流畅度仍需验证；App 内效果预览不能代替灵动岛实测。

- [工程说明与验证清单](ios/README.md)
- [云端构建](../../actions)

`ios/` 是独立的原生工程。`frontend/src/features/lyrics/` 仅保留 Windows 运动参数的对照源码，用来重新生成 Swift 测试数据，不参与 iOS 运行。

未签名 IPA 可用于检查构建结果，不能直接安装到 iPhone。真机安装还需要设备对应的 Apple 签名。
