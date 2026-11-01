import Foundation

/// 一家云端大模型服务商的接入参数。全部按 OpenAI 兼容的 /chat/completions 协议调用。
struct CloudProvider: Identifiable, Hashable {
    let id: String
    let name: String
    /// 不带结尾斜杠的基址，例如 https://api.deepseek.com/v1
    let baseURL: String
    let defaultModel: String
    /// 能唯一指向该厂商的密钥前缀（如 sk-ant-、gsk_），命中即可确定
    let strongPrefixes: [String]
    /// 只是「可能属于」的弱前缀，需要探测
    let weakPrefixes: [String]

    var modelsURL: URL? { URL(string: baseURL + "/models") }
    var chatURL: URL? { URL(string: baseURL + "/chat/completions") }
}

enum CloudProviderCatalog {
    /// 顺序即探测顺序：越常用越靠前
    static let all: [CloudProvider] = [
        CloudProvider(id: "deepseek", name: "DeepSeek",
                      baseURL: "https://api.deepseek.com/v1",
                      defaultModel: "deepseek-chat",
                      strongPrefixes: [], weakPrefixes: ["sk-"]),
        CloudProvider(id: "openai", name: "OpenAI",
                      baseURL: "https://api.openai.com/v1",
                      defaultModel: "gpt-4o-mini",
                      strongPrefixes: ["sk-proj-", "sk-svcacct-", "sk-admin-"],
                      weakPrefixes: ["sk-"]),
        CloudProvider(id: "moonshot", name: "Moonshot 月之暗面",
                      baseURL: "https://api.moonshot.cn/v1",
                      defaultModel: "moonshot-v1-8k",
                      strongPrefixes: [], weakPrefixes: ["sk-"]),
        CloudProvider(id: "siliconflow", name: "SiliconFlow 硅基流动",
                      baseURL: "https://api.siliconflow.cn/v1",
                      defaultModel: "Qwen/Qwen2.5-7B-Instruct",
                      strongPrefixes: [], weakPrefixes: ["sk-"]),
        CloudProvider(id: "dashscope", name: "阿里云百炼（通义）",
                      baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                      defaultModel: "qwen-plus",
                      strongPrefixes: [], weakPrefixes: ["sk-"]),
        CloudProvider(id: "zhipu", name: "智谱 GLM",
                      baseURL: "https://open.bigmodel.cn/api/paas/v4",
                      defaultModel: "glm-4-flash",
                      strongPrefixes: [], weakPrefixes: []),
        CloudProvider(id: "openrouter", name: "OpenRouter",
                      baseURL: "https://openrouter.ai/api/v1",
                      defaultModel: "deepseek/deepseek-chat",
                      strongPrefixes: ["sk-or-v1-"], weakPrefixes: ["sk-"]),
    ]

    static func provider(id: String) -> CloudProvider? {
        all.first { $0.id == id }
    }

    static var fallback: CloudProvider { all[0] }

    /// 只看前缀能确定的那一类（强前缀）
    static func guessByPrefix(_ key: String) -> CloudProvider? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        for p in all {
            if p.strongPrefixes.contains(where: { k.hasPrefix($0) }) { return p }
        }
        return nil
    }

    /// 弱前缀候选：形如 sk-… 的密钥可能是 DeepSeek/OpenAI/Moonshot 等，需要实探
    static func weakCandidates(_ key: String) -> [CloudProvider] {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return [] }
        if let strong = guessByPrefix(k) { return [strong] }
        return all.filter { p in p.weakPrefixes.contains { k.hasPrefix($0) } }
    }
}

/// 通过各家的 /models 接口判断这把 Key 到底属于谁。
/// GET /models 不计费、只返回模型列表，适合用来做归属探测。
enum CloudProviderDetector {
    struct Result {
        let provider: CloudProvider?
        /// 给界面显示的一句话，例如「识别为 DeepSeek」或「未能识别，按 DeepSeek 处理」
        let summary: String
        /// 服务端返回的模型名（能读到就用它做默认值）
        let modelHint: String?
    }

    static func detect(key rawKey: String, timeout: TimeInterval = 8,
                       completion: @escaping (Result) -> Void) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8 else {
            completion(Result(provider: nil, summary: "密钥太短，无法识别", modelHint: nil))
            return
        }

        // 1. 强前缀直接确定，不用发请求
        if let strong = CloudProviderCatalog.guessByPrefix(key) {
            completion(Result(provider: strong,
                              summary: "按密钥格式识别为 \(strong.name)",
                              modelHint: nil))
            return
        }

        // 2. 弱前缀：并发问各家的 /models，谁回 200 就是谁
        let candidates = CloudProviderCatalog.weakCandidates(key)
        guard !candidates.isEmpty else {
            completion(Result(provider: nil,
                              summary: "密钥格式不匹配任何已知服务商，可手动选择",
                              modelHint: nil))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var hit: (CloudProvider, String?)?

        for provider in candidates {
            guard let url = provider.modelsURL else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = timeout

            URLSession.shared.dataTask(with: request) { data, response, _ in
                defer { group.leave() }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
                var hint: String?
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    hint = list.compactMap { $0["id"] as? String }.first
                }
                lock.lock()
                if hit == nil { hit = (provider, hint) }
                lock.unlock()
            }.resume()

            // 已经有人命中就不用再等
            if hit != nil { break }
        }

        group.notify(queue: .main) {
            if let hit {
                completion(Result(provider: hit.0,
                                  summary: "探测确认：\(hit.0.name)",
                                  modelHint: hit.1))
            } else {
                completion(Result(provider: nil,
                                  summary: "未能确认服务商（可能欠费、被墙或不是 OpenAI 兼容接口），可手动选择",
                                  modelHint: nil))
            }
        }
    }
}
