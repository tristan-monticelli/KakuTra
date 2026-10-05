import Combine
import Foundation
import Translation

@available(macOS 15.0, *)
@MainActor
final class LanguagePackManager: ObservableObject {
    @Published var languageStatuses: [String: LanguageAvailability.Status] = [:]

    private let availability = LanguageAvailability()
    /// 检查特定语言对的可用性
    func checkLanguagePair(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailability.Status {
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let status = await availability.status(from: source, to: target)
        languageStatuses["\(sourceLanguage)->\(targetLanguage)"] = status
        return status
    }

    /// 快速检查单个语言对（不显示 loading 状态）
    func checkLanguagePairQuiet(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailability.Status {
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let status = await availability.status(from: source, to: target)
        languageStatuses["\(sourceLanguage)->\(targetLanguage)"] = status
        return status
    }

}

        // 方式2: 使用 AppleScript 打开并尝试点击 Translation Languages 按钮
        let script = """
        tell application "System Settings"
            activate
            delay 0.5
            reveal pane id "com.apple.Localization-Settings.extension"
        end tell

        tell application "System Events"
            tell process "System Settings"
                try
                    delay 0.5
                    -- 尝试点击 "Translation Languages..." 按钮
                    click button "Translation Languages…" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                on error
                    -- 如果找不到按钮，至少已经打开了 Language & Region 面板
                end try
            end tell
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                return
            }
        }

        // 方式3: 降级到只打开 Language & Region
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
