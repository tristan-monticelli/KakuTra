# KakuTra 文档

KakuTra 是 macOS 菜单栏翻译应用。它使用 Vision OCR 在本机识别日语、中文和韩语，并通过 Apple Translation 翻译成英语。

## 当前操作流程

- 单击快捷键：跟踪并翻译光标下的单词。
- 双击快捷键：翻译光标所在屏幕上识别出的日语、中文和韩语文字并覆盖显示；按 Esc 停止。
- 同一时间只运行一种模式。

Direct 版本单击时可以读取光标附近现成的 Accessibility 文本选区并翻译句子；没有可用选区时回退到 OCR 单词流程。App Store 版本直接使用 OCR。双击屏幕翻译在两个版本中都使用 OCR。屏幕录制权限用于两种模式的 OCR；Accessibility 权限对 Direct 版本是可选的，App Store 版本不使用该功能。除非用户明确决定变更，否则保持这套路由不变。

## 服务与数据

- 翻译：Apple Translation，目标语言固定为英语。
- 语音：Apple 系统语音。
- 词典：应用从 `~/Library/Application Support/KakuTra/Dictionaries` 读取日语、中文和韩语 SQLite 数据库。
- Anki：用户可从已显示结果通过 AnkiConnect 主动添加卡片。
- 不自动保存查询历史。更新启动时会删除已弃用的 SwiftData 数据库。
- 界面语言与翻译语言独立设置。

## 构建和测试

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

项目包含 App Store 和 Direct 两种发行配置。修改工程设置时请保留各自的 entitlement 和发行能力。
