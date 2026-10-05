import Foundation
import Security

enum LegacyProviderDataCleanup {
    static func removeStoredCredentials(defaults: UserDefaults) {
        // SettingsStore is also constructed with isolated UserDefaults suites in tests.
        // Only the app's standard preferences may trigger this one-time Keychain migration.
        guard defaults === UserDefaults.standard,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !defaults.bool(forKey: AppSettingKey.legacyProviderCredentialCleanupCompleted) else {
            return
        }

        let llmProviders = ["openai", "anthropic", "gemini", "deepseek", "zhipu", "ollama", "omlx"]
        for provider in llmProviders {
            delete(service: "com.tristanmonticelli.KakuTra.llm", account: provider)
        }
        delete(service: "com.tristanmonticelli.KakuTra.image-translation", account: "baidu")
        defaults.set(true, forKey: AppSettingKey.legacyProviderCredentialCleanupCompleted)
    }

    private static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
