import AppKit
import Foundation

/// 第三方云端大模型桥（原 DeepSeekBridge，3.6.0 起支持多服务商）：
/// 按 OpenAI 兼容的 /chat/completions 协议调用；服务商与模型名可从密钥自动识别，也可手动指定。
@MainActor
final class CloudModelBridge: ObservableObject {
    static let shared = CloudModelBridge()

    /// 历史键名沿用 deepseekApiKey，避免老用户填过的 Key 丢失
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "deepseekApiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "deepseekApiKey") }
    }

    /// 服务商 id，见 CloudProviderCatalog
    @Published var providerID: String = UserDefaults.standard.string(forKey: "cloudProviderID") ?? CloudProviderCatalog.fallback.id {
        didSet { UserDefaults.standard.set(providerID, forKey: "cloudProviderID") }
    }

    /// 模型名，留空则用该服务商的默认模型
    @Published var model: String = UserDefaults.standard.string(forKey: "cloudModelName") ?? "" {
        didSet { UserDefaults.standard.set(model, forKey: "cloudModelName") }
    }

    /// 识别结果的人话，显示在设置页
    @Published var detectionNote: String = ""
    @Published var detecting: Bool = false

    var provider: CloudProvider {
        CloudProviderCatalog.provider(id: providerID) ?? CloudProviderCatalog.fallback
    }

    var effectiveModel: String {
        let m = model.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? provider.defaultModel : m
    }

    var isConfigured: Bool {
        let k = apiKey.trimmingCharacters(in: .whitespaces)
        return k.count >= 20
    }

    private var onDelta: ((String) -> Void)?
    private var onDone: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    private init() {}

    // MARK: - 服务商识别

    /// 用当前 Key 判定服务商：强前缀直接判断，弱前缀走 /models 探测
    func detectProvider(apply: Bool = true) {
        guard isConfigured else {
            detectionNote = "先填写 Key 再自动识别"
            return
        }
        detecting = true
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        CloudProviderDetector.detect(key: key) { [weak self] result in
            guard let self else { return }
            self.detecting = false
            if let p = result.provider {
                if apply {
                    self.providerID = p.id
                    // 不强行改模型名：各家默认值不同，改错会直接调不通；只把可用模型提示出来
                }
                var note = result.summary
                if let hint = result.modelHint, !hint.isEmpty {
                    note += "，可用模型如 " + hint
                }
                note += "；当前使用 " + self.provider.name + " · " + self.effectiveModel
                self.detectionNote = note
            } else {
                self.detectionNote = result.summary
            }
        }
    }

    // MARK: - 调用

    func complete(_ prompt: String,
                  maxTokens: Int = 500,
                  onDelta: @escaping (String) -> Void,
                  onDone: @escaping (String) -> Void,
                  onError: @escaping (String) -> Void) {
        self.onDelta = onDelta
        self.onDone = onDone
        self.onError = onError

        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            onError("未配置 API Key，请在设置中填写")
            return
        }
        guard let url = provider.chatURL else {
            onError("服务商地址无效：\(provider.baseURL)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": effectiveModel,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let providerName = provider.name
        let modelName = effectiveModel
        // 用 async/await 的 data(for:) 代替 dataTask 回调：避免在非 Sendable 的后台闭包里捕获
        // 非 Sendable 的 MainActor 实例（self），否则会与主线程并发操作产生数据竞争并破坏 Swift 运行时。
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    self.onError?("无响应")
                    return
                }
                guard !data.isEmpty else {
                    self.onError?("空响应")
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    var hint = "\(providerName) 返回 HTTP \(http.statusCode)"
                    if http.statusCode == 401 { hint += "，Key 无效或不属于 \(providerName)" }
                    if http.statusCode == 404 { hint += "，模型 \(modelName) 可能不存在" }
                    self.onError?(hint + "：" + String(raw.prefix(160)))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    self.onDelta?(content)
                    self.onDone?(content)
                } else {
                    self.onError?("解析响应失败，可能是该服务商的返回格式不兼容")
                }
            } catch {
                self.onError?("网络错误：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 多轮 + System Prompt 调用（供 Aether Philo 模式使用）

    /// 与 complete 类似，但支持传入 system 提示词与多轮 messages（[role, content]），
    /// 并可附带 reasoning 字段（部分服务商支持深度推理，不支持的会忽略）。
    func completeChat(system: String,
                     messages: [[String: String]],
                     reasoning: String? = nil,
                     maxTokens: Int = 1200,
                     onDelta: @escaping (String) -> Void,
                     onDone: @escaping (String) -> Void,
                     onError: @escaping (String) -> Void) {
        self.onDelta = onDelta; self.onDone = onDone; self.onError = onError
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            onError("未配置 API Key，请在设置中填写")
            return
        }
        guard let url = provider.chatURL else {
            onError("服务商地址无效：\(provider.baseURL)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages where (m["role"] != nil && m["content"] != nil) {
            msgs.append(["role": m["role"]!, "content": m["content"]!])
        }
        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": msgs,
            "stream": false,
            "max_tokens": maxTokens,
        ]
        if let r = reasoning, !r.isEmpty { body["reasoning"] = r }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let providerName = provider.name
        let modelName = effectiveModel
        // 同 complete：用 async/await 的 data(for:) 避免后台 @Sendable 闭包捕获非 Sendable 的 self。
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    self.onError?("无响应")
                    return
                }
                guard !data.isEmpty else {
                    self.onError?("空响应")
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    var hint = "\(providerName) 返回 HTTP \(http.statusCode)"
                    if http.statusCode == 401 { hint += "，Key 无效或不属于 \(providerName)" }
                    if http.statusCode == 404 { hint += "，模型 \(modelName) 可能不存在" }
                    self.onError?(hint + "：" + String(raw.prefix(160)))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    self.onDelta?(content)
                    self.onDone?(content)
                } else {
                    self.onError?("解析响应失败，可能是该服务商的返回格式不兼容")
                }
            } catch {
                self.onError?("网络错误：\(error.localizedDescription)")
            }
        }
    }

    var isLoggedIn: Bool { isConfigured }
}
