import Foundation

/// Aether Philo 预设数据加载器。
///
/// 全部预设文本（系统提示词、检测词库、三角色专属池、通用池）都放在
/// `Resources/aether_presets.json`，运行期读取后注入 Aether 页面的
/// `window.__AETHER_PRESETS`。这样：
///   - 数据与代码分离，JSON 可读、可 diff、可逐条校对，避免硬编码进二进制；
///   - 改文案只需替换 App `Contents/Resources/aether_presets.json`（开发期也会
///     自动从 `Sources/Lawlearn/Resources/` 命中），无需改动 Swift 代码；
///   - 前端按「三状态 + 双池 + 场景对齐」从 JSON 取词（见 SermoWindow 内 scenePool）。
enum AetherPhiloData {
    /// 注入 `<script>` 的 JS：`window.__AETHER_PRESETS = { ... };`
    static var js: String {
        guard let url = findResource(name: "aether_presets", ext: "json"),
              let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("AetherPhiloData: 未能加载 aether_presets.json（请确认已放入 App Contents/Resources 或 Sources/Lawlearn/Resources）")
            // 兜底：空的预设结构，避免页面因引用 undefined 而崩溃。
            return "window.__AETHER_PRESETS = { avatarMap:{ male:\"cecil\", female:\"aetheria\", ghost:\"nox\" }, characters:{}, common:{ profanity:[], comfort:[], greeting:[] }, detection:{ crashWords:[], profaneWords:[], whitelist:[], identityTriggers:[] } };"
        }
        return "window.__AETHER_PRESETS = \(json);"
    }
}
