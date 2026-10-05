# KakuTra

macOS メニューバーで動作するカーソル翻訳アプリです。Vision OCR で日本語・中国語・韓国語を認識し、Apple の Translation framework で英語に翻訳します。

## 使い方

設定したホットキーを押します。

- **1 回**：カーソル下の単語を追跡して翻訳します。
- **2 回**：カーソルがある画面の OCR テキストを翻訳して重ねて表示します。日本語・中国語・韓国語が対象です。Esc で停止します。

同時に有効になるモードは 1 つです。Direct 版では 1 回押したとき、カーソル付近に既存のテキスト選択があれば Accessibility で読み取って文として翻訳できます。選択を利用できない場合と App Store 版では単語 OCR を使います。2 回押しは両版とも画面 OCR を使います。

## 機能とデータ

- Apple の翻訳機能とシステム音声を使用します。
- オフライン辞書は `~/Library/Application Support/KakuTra/Dictionaries` に置いた SQLite ファイルを読み込みます。
- 表示中の結果から、AnkiConnect 経由でカードを手動追加できます。検索履歴は保存しません。
- アプリの表示言語は翻訳言語とは独立して設定できます。
- 画面収録の許可が必要です。Direct 版の Accessibility 許可は任意で、許可がない場合は OCR に切り替わります。

## ビルドとテスト

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

MIT License
