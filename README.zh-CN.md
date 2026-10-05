# KakuTra

KakuTra 是一款运行在 macOS 菜单栏中的光标翻译应用。它使用 Vision OCR 识别日语、中文和韩语，再通过 Apple Translation 翻译成英语。

## 使用方式

按下设置好的快捷键：

- **按 1 次**：跟踪并翻译光标下的单词。
- **按 2 次**：翻译光标所在屏幕上识别出的日语、中文和韩语文字，并覆盖显示；按 Esc 停止。

同一时间只运行一种模式。Direct 版本单击时可以先通过 Accessibility 读取光标附近现成的文本选区并翻译句子；没有可用选区时，以及 App Store 版本中，使用单词 OCR。双击在两个版本中都使用屏幕 OCR。

## 功能与数据

- 使用 Apple 翻译功能和系统语音。
- 离线词典读取 `~/Library/Application Support/KakuTra/Dictionaries` 中的 SQLite 文件。
- 可以从已显示的结果通过 AnkiConnect 手动添加卡片。应用不保存查询历史。
- 界面语言可以独立于翻译语言设置。
- OCR 需要“屏幕录制”权限。Direct 版本的 Accessibility 权限是可选的；未授权时会退回 OCR。

## 构建与测试

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

MIT License
