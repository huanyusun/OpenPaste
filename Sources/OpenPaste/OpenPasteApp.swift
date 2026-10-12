import SwiftUI

@main
struct OpenPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 无窗口场景：Paste 式常驻工具，一切交互通过悬浮面板/菜单栏/快捷键完成
        Settings {
            SettingsView()
        }
    }
}
