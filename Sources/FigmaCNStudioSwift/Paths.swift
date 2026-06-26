import Foundation

enum AppPaths {
    static var repoRoot: URL {
        if let override = ProcessInfo.processInfo.environment["FigmaCN_REPO_ROOT"], !override.isEmpty {
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

    static var bundledLangDir: URL {
        runtimeDir.appendingPathComponent("lang")
    }

    static var cachedLangDir: URL {
        appSupportDir.appendingPathComponent("lang", isDirectory: true)
    }

    static var langFile: URL {
        activeLangFile("zh/zh.json")
    }

    static var authLangFile: URL {
        activeLangFile("zh/auth-zh.json")
    }

    static var prototypeLangFile: URL {
        activeLangFile("zh/prototype_app_beta-zh.json")
    }

    static var communityLangFile: URL {
        activeLangFile("zh/community-zh.json")
    }

    static func cachedLangFile(_ relativePath: String) -> URL {
        cachedLangDir.appendingPathComponent(relativePath)
    }

    static func bundledLangFile(_ relativePath: String) -> URL {
        bundledLangDir.appendingPathComponent(relativePath)
    }

    private static func activeLangFile(_ relativePath: String) -> URL {
        let cached = cachedLangFile(relativePath)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        return bundledLangFile(relativePath)
    }

    static var bundledMitmDump: URL {
        repoRoot.appendingPathComponent("mitmproxy/mitmproxy.app/Contents/MacOS/mitmdump")
    }

    static var certPath: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".mitmproxy/mitmproxy-ca-cert.cer")
    }

    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FigmaCNStudioSwift", isDirectory: true)
    }

    static var configPath: URL {
        appSupportDir.appendingPathComponent("config.json")
    }

    static var proxyBackupPath: URL {
        appSupportDir.appendingPathComponent("system-proxy-backup.json")
    }

    static var pacFile: URL {
        appSupportDir.appendingPathComponent("figmacn-proxy.pac")
    }

    static var captureFile: URL {
        appSupportDir.appendingPathComponent("captured_language_urls.txt")
    }
}
