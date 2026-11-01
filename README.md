# Sermo

QuotOS Aether 的独立 macOS 客户端。把 Aether 界面单独拿出来，配上自己的设置面板——打开就能用，不用先进主程序。

纯 Swift + WebKit，无第三方依赖，产物 2.9 MB。

## 它是什么

Aether 原本是 Lawlearn 里的一个小窗，API 入口挂在主程序的设置页里。独立出来后没有主程序了，所以把入口补回页面本身：顶部栏末尾多一个「⚙ 设置」，里面填服务商与 API Key，存本机，重启后还在。

- **只有 Aether**：没有法条检索、没有主程序框架，窗口里就是那一个界面
- **七家服务商**：DeepSeek、OpenAI、Moonshot、硅基流动、阿里通义、智谱、OpenRouter
- **本地存储**：对话历史与图鉴靠 `localStorage` 留存，与原先一致
- **外链走系统浏览器**，页面本身是本地加载，不联网也能打开

## 目录

| 路径 | 说明 |
| --- | --- |
| `Sources/SermoApp.swift` | 应用入口、菜单（关于 / 设置 / 编辑 / 窗口） |
| `Sources/SermoWindow.swift` | 主窗口控制器，负责加载页面、桥接 JS 与 Swift |
| `Sources/SermoHTML.swift` | Aether 页面本体，一个 2 MB 的字符串字面量 |
| `Sources/SettingsPanel.swift` | 注入到页面里的设置面板（按钮 + 弹窗 + 事件绑定） |
| `Sources/CloudModelBridge.swift` | 各家 API 的统一调用层，读写 UserDefaults |
| `Sources/CloudProviders.swift` | 服务商目录与默认模型 |
| `Sources/AetherPhiloData.swift` | 页面用的预设数据 |
| `Sources/ResourceLoader.swift` | 资源查找（Bundle → 可执行文件旁 → 源码树） |
| `Resources/aether_presets.json` | 随包携带的预设数据 |
| `tools/package.sh` | 编译 → 组装 → 自检 → 签名 → 安装，一条命令 |
| `tools/make_icon.swift` | 图标绘制源码（Core Graphics） |
| `tools/icon-source.svg` | 图标的矢量设计原稿 |

## 构建

需要 Xcode 命令行工具（Swift 6）。没有其他依赖：

```bash
./tools/package.sh              # 产出 dist/Sermo.app
./tools/package.sh --install    # 另外覆盖安装到 /Applications
```

单独跑起来调试：

```bash
./tools/package.sh && open dist/Sermo.app
```

换图标改 `tools/make_icon.swift` 里的绘制代码（本机没有 SVG 光栅化工具，所以图标是用 Core Graphics 画出来的，`icon-source.svg` 只是设计原稿），然后：

```bash
swift tools/make_icon.swift && iconutil -c icns tools/AppIcon.iconset -o Resources/AppIcon.icns
```

## 几个实现上的选择

**页面本体一行没改。** `SermoHTML.swift` 是从 Lawlearn 的 `SermoWindow.swift` 里整块提取出来的字符串字面量，内容与原文件逐字节一致。改 2 MB 的单行字面量风险太高，任何一处笔误都会让整页白屏。

**设置面板用注入实现。** 运行期往 `.top` 追加按钮、往 `body` 追加弹窗，而不是改 HTML 源文件。好处是页面与逻辑解耦——以后页面更新了，注入代码不用跟着改。JS 与 Swift 之间走 `WKScriptMessageHandler`：

```
JS  → Swift   window.webkit.messageHandlers.aetherBridge.postMessage({type:"settings", action:"get"|"save", ...})
Swift → JS    window.__sermoPrefs({key, providerID, model, providers:[...]})
```

**存储沿用原键名**（`deepseekApiKey` / `cloudProviderID` / `cloudModelName`）。这样从 Lawlearn 那边带过来的配置习惯不用变，判断「是否已配置」的条件也一致：密钥长度 ≥ 20。

**窗口定位不用 `NSScreen.main`。** 它的定义是「有键盘焦点的窗口所在屏幕」，启动瞬间还没有 key window 时会退回鼠标所在屏幕——多显示器下会把窗口开到副屏，看起来像没启动。改用 `NSScreen.screens.first`（顺序固定，第 0 个是带菜单栏的主显示器），另加一道兜底：窗口与所有屏幕都不相交时搬回主屏。

## 安装包

正式安装包在 [Sermo-download](https://github.com/LynneScheutie/Sermo-download) 发布，本仓库不含二进制。

## 版权

© Eisice
