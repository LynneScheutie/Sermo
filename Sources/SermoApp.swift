import AppKit

/// Sermo 独立版入口。
///
/// 只做一件事：起一个常规 App，建菜单，开 Aether 窗口。
/// 菜单里必须带「编辑」，否则网页里的输入框无法响应 ⌘C / ⌘V——AppKit 的
/// 剪贴板快捷键是挂在菜单项上的，没有菜单项就没有快捷键。
@main
struct SermoApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        SermoWindowController.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 菜单

    private func buildMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let about = NSMenuItem(title: "关于 Sermo", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Sermo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Sermo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单（剪贴板快捷键的宿主）
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 窗口菜单
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - 动作

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string:
            "QuotOS Aether 独立版。\n把想说的话放进来，其余交给它。")
        credits.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 0, length: credits.length))

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Sermo",
            .applicationVersion: "1.0.0",
            .version: "1.0.0",
            .credits: credits,
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        SermoWindowController.shared.openSettings()
    }
}
