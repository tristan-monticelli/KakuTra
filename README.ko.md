# KakuTra

macOS 메뉴 막대에서 실행되는 커서 번역 앱입니다. Vision OCR로 일본어, 중국어, 한국어를 인식하고 Apple Translation으로 영어로 번역합니다.

## 사용 방법

설정한 단축키를 누릅니다.

- **1회**: 커서 아래 단어를 추적해 번역합니다.
- **2회**: 커서가 있는 화면의 OCR 텍스트를 번역해 겹쳐 표시합니다. 일본어, 중국어, 한국어를 지원하며 Esc로 중지합니다.

한 번에 하나의 모드만 활성화됩니다. Direct 버전은 한 번 눌렀을 때 커서 근처에 기존 텍스트 선택 영역이 있으면 Accessibility로 읽어 문장으로 번역할 수 있습니다. 사용할 수 있는 선택 영역이 없거나 App Store 버전에서는 단어 OCR을 사용합니다. 두 번 누르기는 두 버전 모두 화면 OCR을 사용합니다.

## 기능과 데이터

- Apple 번역 기능과 시스템 음성을 사용합니다.
- 오프라인 사전은 `~/Library/Application Support/KakuTra/Dictionaries`에 있는 SQLite 파일을 읽습니다.
- 화면에 표시된 결과에서 AnkiConnect를 통해 카드를 직접 추가할 수 있습니다. 조회 기록은 저장하지 않습니다.
- 앱 표시 언어는 번역 언어와 별도로 설정할 수 있습니다.
- 화면 기록 권한이 필요합니다. Direct 버전의 Accessibility 권한은 선택 사항이며, 허용되지 않으면 OCR을 사용합니다.

## 빌드 및 테스트

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

MIT License
