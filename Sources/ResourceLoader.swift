import Foundation

/// 资源定位：优先 App 包内，其次可执行文件旁的 Resources，最后开发期的仓库 Resources。
/// Lawlearn 里这个方法住在 Database 中，独立版没有数据库层，单独放一份。
func findResource(name: String, ext: String) -> URL? {
    let fm = FileManager.default

    if let url = Bundle.main.url(forResource: name, withExtension: ext) {
        return url
    }

    let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let beside = exeDir.appendingPathComponent("Resources/\(name).\(ext)")
    if fm.fileExists(atPath: beside.path) { return beside }

    // #file = <repo>/Sources/ResourceLoader.swift → 上两级即仓库根，再进 Resources
    let dev = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/\(name).\(ext)")
    if fm.fileExists(atPath: dev.path) { return dev }

    return nil
}
