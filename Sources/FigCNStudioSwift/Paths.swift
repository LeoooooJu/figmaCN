import Foundation

enum AppPaths {
    static var repoRoot: URL {
        if let override = ProcessInfo.processInfo.environment["FIGCN_REPO_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let bundleURL = Bundle.main.bundleURL
        let bundledRuntime = bundleURL.appendingPathComponent("Contents/Resources/Runtime")
        if FileManager.default.fileExists(atPath: bundledRuntime.path) {
            return bundleURL.appendingPathComponent("Contents/Resources")
        }

        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Runtime/injector.py").path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static var runtimeDir: URL {
        repoRoot.appendingPathComponent("Runtime")
    }

    static var langFile: URL {
        runtimeDir.appendingPathComponent("lang/zh.json")
    }

    static var bundledMitmDump: URL {
        repoRoot.appendingPathComponent("mitmproxy/mitmproxy.app/Contents/MacOS/mitmdump")
    }

    static var certPath: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".mitmproxy/mitmproxy-ca-cert.cer")
    }

    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FigCNStudioSwift", isDirectory: true)
    }

    static var configPath: URL {
        appSupportDir.appendingPathComponent("config.json")
    }

    static var proxyBackupPath: URL {
        appSupportDir.appendingPathComponent("system-proxy-backup.json")
    }
}
