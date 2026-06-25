import Foundation
import Network
import Darwin

@MainActor
final class ServiceController: ObservableObject {
    @Published var state = ServiceState()
    @Published var logs: [String] = []

    private let proxyManager = SystemProxyManager()
    private var proxyProcess: Process?
    private var expectedProxyExit = false
    private var cleanupInProgress = false

    init() {
        loadConfig()
    }

    func loadConfig() {
        do {
            guard FileManager.default.fileExists(atPath: AppPaths.configPath.path) else { return }
            let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: AppPaths.configPath))
            state.localizationEnabled = config.localizationEnabled
            state.darkModeEnabled = config.darkModeEnabled
            state.port = config.port
            state.listenHost = config.listenHost
        } catch {
            appendLog("配置加载失败：\(error.localizedDescription)")
        }
    }

    func saveConfig() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.appSupportDir, withIntermediateDirectories: true)
            let config = AppConfig(
                localizationEnabled: state.localizationEnabled,
                darkModeEnabled: state.darkModeEnabled,
                port: state.port,
                listenHost: state.listenHost
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: AppPaths.configPath, options: .atomic)
        } catch {
            appendLog("配置保存失败：\(error.localizedDescription)")
        }
    }

    func run(_ action: ServiceAction) {
        Task {
            do {
                switch action {
                case .start:
                    try await startProxy()
                case .stop:
                    try await stopProxy()
                case .refresh:
                    try await refreshStatus()
                    setLastAction("状态已刷新")
                case .repair:
                    let message = try await proxyManager.repairNetwork(host: state.listenHost, port: state.port)
                    state.systemProxyApplied = false
                    setLastAction(message)
                case .cache:
                    let message = try clearFigmaCache()
                    setLastAction(message)
                case .cert:
                    let message = try await installCertificate()
                    state.certTrusted = true
                    setLastAction(message)
                }
            } catch {
                setLastAction(error.localizedDescription)
                appendLog("错误：\(error.localizedDescription)")
            }
        }
    }

    func refreshStatus() async throws {
        state.mitmReady = mitmDumpExecutable() != nil
        state.certTrusted = FileManager.default.fileExists(atPath: AppPaths.certPath.path)
        state.systemProxyReady = true
        state.running = proxyProcess != nil
        state.systemProxyApplied = await proxyManager.isSystemProxyPointingTo(host: state.listenHost, port: state.port)

        let lang = validateLang()
        state.langReady = lang.ok
        state.langVersion = lang.keys > 0 ? "\(lang.keys.formatted()) 个键" : (lang.ok ? "已校验" : "无效")
        if !lang.ok, !lang.message.isEmpty {
            appendLog(lang.message)
        }
    }

    func recoverStaleSystemProxy() async {
        guard proxyProcess == nil else { return }
        let stale = await proxyManager.isSystemProxyPointingTo(host: state.listenHost, port: state.port)
        guard stale else { return }
        guard FileManager.default.fileExists(atPath: AppPaths.proxyBackupPath.path) else {
            appendLog("检测到系统代理仍指向 \(state.listenHost):\(state.port)，但没有备份文件，已跳过自动恢复")
            return
        }

        do {
            appendLog("检测到上次异常退出后的系统代理残留，正在恢复")
            let message = try await proxyManager.repairNetwork(host: state.listenHost, port: state.port)
            state.systemProxyApplied = false
            setLastAction(message)
        } catch {
            appendLog("网络自修复失败：\(error.localizedDescription)")
        }
    }

    func startProxy() async throws {
        if proxyProcess != nil {
            setLastAction("代理已经在运行")
            return
        }

        await recoverStaleSystemProxy()
        try await refreshStatus()

        guard let mitmDump = mitmDumpExecutable() else { throw AppError.message("未找到内置或系统 mitmdump。") }
        guard !state.localizationEnabled || state.langReady else { throw AppError.message("语言包无效。") }

        let host = state.listenHost.isEmpty ? "127.0.0.1" : state.listenHost
        let preferredPort = state.port
        let port = await availablePort(preferred: preferredPort, host: host)
        guard let port else {
            throw AppError.message("没有找到可用的本地通道，请稍后重试或重启电脑。")
        }
        if port != preferredPort {
            state.port = port
            saveConfig()
            appendLog("原通道被占用，已自动切换到可用通道：\(port)")
        }

        var args = [
            "--listen-host", host,
            "-p", String(port),
            "--set", "keepserving=true",
            "--set", "flow_detail=0",
            "--set", "termlog_verbosity=info",
            "--set", "allow_hosts=^(.+\\.)?figma\\.com(:443)?$",
            "-s", "injector.py"
        ]

        let upstream = await proxyManager.detectUpstreamProxy(listenHost: host, listenPort: port)
        if upstream.isEmpty {
            state.activeUpstream = ""
            appendLog("未检测到可用上游代理，将直连网络")
        } else {
            args.insert(contentsOf: ["--mode", "upstream:\(upstream)"], at: 0)
            state.activeUpstream = upstream
            appendLog("已检测到现有系统代理，将作为上游：\(upstream)")
        }

        let process = Process()
        process.executableURL = mitmDump
        process.arguments = args
        process.currentDirectoryURL = AppPaths.runtimeDir

        var env = ProcessInfo.processInfo.environment
        env["FIGCN_ENABLE_LOCALIZATION"] = state.localizationEnabled ? "1" : "0"
        env["FIGCN_LANG_FILE"] = AppPaths.langFile.path
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        attachLogReader(stdoutPipe)
        attachLogReader(stderrPipe)

        expectedProxyExit = false
        appendLog("正在启动 mitmdump：\(host):\(port)")
        appendLog("使用 mitmdump：\(mitmDump.path)")
        try process.run()
        proxyProcess = process
        state.running = true

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                await self?.handleProxyExit(code: proc.terminationStatus)
            }
        }

        let ready = await waitForPortListening(host: host, port: port, timeout: 8)
        guard ready else {
            expectedProxyExit = true
            process.terminate()
            proxyProcess = nil
            state.running = false
            throw AppError.message("mitmdump 未能在 \(port) 端口就绪，系统代理未修改。")
        }

        appendLog("正在把系统代理指向本地 MITM 端点")
        do {
            try await proxyManager.setSystemProxy(host: host, port: port)
            state.systemProxyApplied = true
            setLastAction("代理已启动")
        } catch {
            state.systemProxyApplied = false
            appendLog("系统代理设置失败，但本地代理已启动：\(error.localizedDescription)")
            appendLog("请手动把 HTTP/HTTPS 代理设置为 \(host):\(port)")
            setLastAction("代理已启动，系统代理未自动应用")
        }
    }

    func stopProxy() async throws {
        if proxyProcess == nil {
            state.running = false
            if state.systemProxyApplied {
                let message = try await proxyManager.repairNetwork(host: state.listenHost, port: state.port)
                appendLog(message)
            }
            state.systemProxyApplied = false
            state.activeUpstream = ""
            setLastAction("代理未运行")
            return
        }

        let child = proxyProcess
        proxyProcess = nil
        expectedProxyExit = true
        child?.terminate()

        if state.systemProxyApplied {
            let message = try await proxyManager.repairNetwork(host: state.listenHost, port: state.port)
            appendLog(message)
        }

        state.running = false
        state.systemProxyApplied = false
        state.activeUpstream = ""
        setLastAction("已请求停止代理")
    }

    func cleanupBeforeQuit() async {
        if cleanupInProgress { return }
        cleanupInProgress = true
        do {
            try await stopProxy()
        } catch {
            appendLog("退出前清理失败：\(error.localizedDescription)")
        }
        cleanupInProgress = false
    }

    private func handleProxyExit(code: Int32) async {
        appendLog("mitmdump 已退出 code=\(code)")
        proxyProcess = nil
        let shouldRestore = state.systemProxyApplied && !expectedProxyExit
        expectedProxyExit = false

        if shouldRestore {
            do {
                appendLog("检测到代理异常退出，正在恢复系统代理")
                let message = try await proxyManager.repairNetwork(host: state.listenHost, port: state.port)
                appendLog(message)
            } catch {
                appendLog("系统代理自动恢复失败：\(error.localizedDescription)")
            }
        }

        state.running = false
        state.systemProxyApplied = false
        state.activeUpstream = ""
        state.lastAction = "代理已停止"
    }

    private func attachLogReader(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                for line in text.split(whereSeparator: \.isNewline) {
                    self?.appendLog(String(line))
                }
            }
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func setLastAction(_ message: String) {
        state.lastAction = message
        appendLog(message)
    }

    private func validateLang() -> (ok: Bool, keys: Int, message: String) {
        do {
            let data = try Data(contentsOf: AppPaths.langFile)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dict = object as? [String: Any] else {
                return (false, 0, "语言包根节点必须是 JSON 对象")
            }
            let bad = dict.prefix(5).filter { _, value in
                guard let item = value as? [String: Any] else { return true }
                return !(item["string"] is String)
            }
            if !bad.isEmpty {
                return (true, dict.count, "校验通过，但有 \(bad.count) 个可疑条目")
            }
            return (dict.count > 0, dict.count, "校验通过：\(dict.count) 个键")
        } catch {
            return (false, 0, "语言包校验失败：\(error.localizedDescription)")
        }
    }

    private func mitmDumpExecutable() -> URL? {
        if FileManager.default.isExecutableFile(atPath: AppPaths.bundledMitmDump.path) {
            return AppPaths.bundledMitmDump
        }
        if let path = findExecutableInPath("mitmdump") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func findExecutableInPath(_ name: String) -> String? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathValue.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func clearFigmaCache() throws -> String {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Figma/DesktopProfile")
        guard FileManager.default.fileExists(atPath: base.path) else {
            return "未找到 Figma DesktopProfile 目录。"
        }

        let profiles = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])
        var cleared = 0
        for profile in profiles {
            let values = try profile.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let cache = profile.appendingPathComponent("Cache")
            guard FileManager.default.fileExists(atPath: cache.path) else { continue }
            try FileManager.default.removeItem(at: cache)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            cleared += 1
        }
        return cleared > 0 ? "已清理 \(cleared) 个缓存目录。" : "未找到可清理的缓存目录。"
    }

    private func installCertificate() async throws -> String {
        let target = AppPaths.certPath
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw AppError.message("证书尚不存在：\(target.path)。请先启动一次代理，让 mitmproxy 生成证书。")
        }

        let loginKeychain = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Keychains/login.keychain-db")
        let keychainArg = FileManager.default.fileExists(atPath: loginKeychain.path) ? loginKeychain.path : "login.keychain"

        do {
            _ = try await runCommand("/usr/bin/security", [
                "add-trusted-cert",
                "-d",
                "-r",
                "trustRoot",
                "-k",
                keychainArg,
                target.path
            ], timeout: 120)
            return "证书已安装到登录钥匙串"
        } catch {
            let command = "security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"\(escapedShellDouble(target.path))\""
            let script = "do shell script \"\(escapedAppleScript(command))\" with administrator privileges"
            _ = try await runCommand("/usr/bin/osascript", ["-e", script], timeout: 120)
            return "证书已安装到系统钥匙串"
        }
    }

    private func isPortAvailable(host: String, port: Int) async -> Bool {
        await Task.detached(priority: .utility) {
            Self.canBind(host: host, port: port)
        }.value
    }

    nonisolated private static func canBind(host: String, port: Int) -> Bool {
        guard port > 0 && port <= 65535 else { return false }

        if host == "::1" {
            let fd = socket(AF_INET6, SOCK_STREAM, 0)
            guard fd >= 0 else { return false }
            defer { close(fd) }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = UInt16(port).bigEndian
            addr.sin6_addr = in6addr_loopback

            return withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                }
            }
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian

        let bindHost = host.isEmpty || host == "localhost" ? "127.0.0.1" : host
        let parsed = inet_pton(AF_INET, bindHost, &addr.sin_addr)
        guard parsed == 1 else { return false }

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func availablePort(preferred: Int, host: String) async -> Int? {
        var candidates: [Int] = []
        if preferred > 0 {
            candidates.append(preferred)
        }
        candidates += [18080, 18081, 18082, 18083, 18084, 18085, 19080, 19081, 19082]

        var seen = Set<Int>()
        for port in candidates where seen.insert(port).inserted {
            if await isPortAvailable(host: host, port: port) {
                return port
            }
        }

        for port in 20000...20100 {
            if await isPortAvailable(host: host, port: port) {
                return port
            }
        }
        return nil
    }

    private func waitForPortListening(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await canConnect(host: host, port: port) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    private func canConnect(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let completion = BoolCompletion(continuation: continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    completion.finish(true)
                case .failed:
                    connection.cancel()
                    completion.finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                connection.cancel()
                completion.finish(false)
            }
        }
    }
}

private final class BoolCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Bool, Never>

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Bool) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        continuation.resume(returning: value)
    }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}
