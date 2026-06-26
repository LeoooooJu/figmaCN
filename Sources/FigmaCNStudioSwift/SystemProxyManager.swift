import Foundation

final class SystemProxyManager: @unchecked Sendable {
    func listNetworkServices() async throws -> [String] {
        let result = try await runCommand("/usr/sbin/networksetup", ["-listallnetworkservices"], timeout: 15)
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
    }

    func getNetworkSetup(_ flag: String, service: String) async -> String {
        do {
            return try await runCommand("/usr/sbin/networksetup", [flag, service], timeout: 10).stdout
        } catch {
            return ""
        }
    }

    func snapshotProxyService(_ service: String) async -> ProxySnapshot {
        let web = await getNetworkSetup("-getwebproxy", service: service)
        let secure = await getNetworkSetup("-getsecurewebproxy", service: service)
        let socks = await getNetworkSetup("-getsocksfirewallproxy", service: service)
        let auto = await getNetworkSetup("-getautoproxyurl", service: service)
        let autoState = await getNetworkSetup("-getautoproxystate", service: service)
        return ProxySnapshot(web: web, secure: secure, socks: socks, auto: auto, autoState: autoState)
    }

    func setSystemProxy(host: String, port: Int, fallbackUpstream: String) async throws {
        let services = try await listNetworkServices()
        var snapshot: [String: ProxySnapshot] = [:]
        for service in services {
            snapshot[service] = await snapshotProxyService(service)
        }

        try FileManager.default.createDirectory(at: AppPaths.appSupportDir, withIntermediateDirectories: true)
        let pacURL = try writePacFile(host: host, port: port, fallbackUpstream: fallbackUpstream)
        let backup = SystemProxyBackup(platform: "darwin", ts: Date().timeIntervalSince1970, data: snapshot)
        let data = try JSONEncoder().encode(backup)
        try data.write(to: AppPaths.proxyBackupPath, options: .atomic)

        var commands: [String] = []
        for service in services {
            let svc = "\"\(escapedShellDouble(service))\""
            commands.append("networksetup -setwebproxystate \(svc) off")
            commands.append("networksetup -setsecurewebproxystate \(svc) off")
            commands.append("networksetup -setsocksfirewallproxystate \(svc) off")
            commands.append("networksetup -setautoproxyurl \(svc) \"\(escapedShellDouble(pacURL.absoluteString))\"")
            commands.append("networksetup -setautoproxystate \(svc) on")
        }
        try await runAsAdminBatch(commands)
    }

    func restoreSystemProxy() async throws {
        let data = try Data(contentsOf: AppPaths.proxyBackupPath)
        let backup = try JSONDecoder().decode(SystemProxyBackup.self, from: data)
        let services = try await listNetworkServices()
        var commands: [String] = []

        for service in services {
            let svc = "\"\(escapedShellDouble(service))\""
            let snap = backup.data[service]
            let webOn = parseEnabled(snap?.web)
            let webHost = parseServer(snap?.web)
            let webPort = parsePort(snap?.web)
            let secureOn = parseEnabled(snap?.secure)
            let secureHost = parseServer(snap?.secure)
            let securePort = parsePort(snap?.secure)
            let socksOn = parseEnabled(snap?.socks)
            let socksHost = parseServer(snap?.socks)
            let socksPort = parsePort(snap?.socks)
            let autoOn = (snap?.autoState.range(of: "Yes", options: .caseInsensitive) != nil)
            let autoURL = parseAutoURL(snap?.auto)

            if webOn, !webHost.isEmpty, !webPort.isEmpty {
                commands.append("networksetup -setwebproxy \(svc) \(webHost) \(webPort)")
                commands.append("networksetup -setwebproxystate \(svc) on")
            } else {
                commands.append("networksetup -setwebproxystate \(svc) off")
            }

            if secureOn, !secureHost.isEmpty, !securePort.isEmpty {
                commands.append("networksetup -setsecurewebproxy \(svc) \(secureHost) \(securePort)")
                commands.append("networksetup -setsecurewebproxystate \(svc) on")
            } else {
                commands.append("networksetup -setsecurewebproxystate \(svc) off")
            }

            if socksOn, !socksHost.isEmpty, !socksPort.isEmpty {
                commands.append("networksetup -setsocksfirewallproxy \(svc) \(socksHost) \(socksPort)")
                commands.append("networksetup -setsocksfirewallproxystate \(svc) on")
            } else {
                commands.append("networksetup -setsocksfirewallproxystate \(svc) off")
            }

            if autoOn, !autoURL.isEmpty {
                commands.append("networksetup -setautoproxyurl \(svc) \"\(escapedShellDouble(autoURL))\"")
                commands.append("networksetup -setautoproxystate \(svc) on")
            } else {
                commands.append("networksetup -setautoproxystate \(svc) off")
            }
        }

        try await runAsAdminBatch(commands)
        try? FileManager.default.removeItem(at: AppPaths.proxyBackupPath)
    }

    func disableAppSystemProxy(host: String, port: Int) async throws -> Bool {
        let services = try await listNetworkServices()
        var commands: [String] = []

        for service in services {
            let snap = await snapshotProxyService(service)
            let svc = "\"\(escapedShellDouble(service))\""
            let autoOn = snap.autoState.range(of: "Yes", options: .caseInsensitive) != nil
            let autoURL = parseAutoURL(snap.auto)

            if parseEnabled(snap.web), parseServer(snap.web) == host, Int(parsePort(snap.web)) == port {
                commands.append("networksetup -setwebproxystate \(svc) off")
            }
            if parseEnabled(snap.secure), parseServer(snap.secure) == host, Int(parsePort(snap.secure)) == port {
                commands.append("networksetup -setsecurewebproxystate \(svc) off")
            }
            if autoOn, isAppPacURL(autoURL) {
                commands.append("networksetup -setautoproxystate \(svc) off")
            }
        }

        guard !commands.isEmpty else { return false }
        try await runAsAdminBatch(commands)
        return true
    }

    func repairNetwork(host: String, port: Int) async throws -> String {
        if FileManager.default.fileExists(atPath: AppPaths.proxyBackupPath.path) {
            try await restoreSystemProxy()
            return "已恢复上次备份的系统代理设置"
        }

        let disabled = try await disableAppSystemProxy(host: host, port: port)
        if disabled {
            return "未找到备份，已关闭残留的 \(host):\(port) 系统代理"
        }
        return "未找到需要修复的 App 代理残留"
    }

    func currentSystemProxy() async -> CurrentSystemProxy {
        do {
            let result = try await runCommand("/usr/sbin/scutil", ["--proxy"], timeout: 10)
            var kv: [String: String] = [:]
            for line in result.stdout.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count == 2 {
                    kv[parts[0]] = parts[1]
                }
            }

            return CurrentSystemProxy(
                ok: true,
                http: ProxyEntry(enabled: kv["HTTPEnable"] == "1", host: kv["HTTPProxy"] ?? "", port: Int(kv["HTTPPort"] ?? "")),
                https: ProxyEntry(enabled: kv["HTTPSEnable"] == "1", host: kv["HTTPSProxy"] ?? "", port: Int(kv["HTTPSPort"] ?? "")),
                socks: ProxyEntry(enabled: kv["SOCKSEnable"] == "1", host: kv["SOCKSProxy"] ?? "", port: Int(kv["SOCKSPort"] ?? "")),
                pac: PacEntry(enabled: kv["ProxyAutoConfigEnable"] == "1", url: kv["ProxyAutoConfigURLString"] ?? "")
            )
        } catch {
            return CurrentSystemProxy(ok: false, http: nil, https: nil, socks: nil, pac: nil)
        }
    }

    func isSystemProxyPointingTo(host: String, port: Int) async -> Bool {
        let current = await currentSystemProxy()
        guard current.ok else { return false }
        let httpHit = current.http?.enabled == true && current.http?.host == host && current.http?.port == port
        let httpsHit = current.https?.enabled == true && current.https?.host == host && current.https?.port == port
        let pacHit = current.pac?.enabled == true && isAppPacURL(current.pac?.url ?? "")
        return httpHit || httpsHit || pacHit
    }

    func detectUpstreamProxy(listenHost: String, listenPort: Int) async -> String {
        let current = await currentSystemProxy()
        guard current.ok else { return "" }

        if let upstream = proxyEntryToUpstream(current.https, listenPort: listenPort, scheme: "http"), !upstream.isEmpty {
            return upstream
        }
        if let upstream = proxyEntryToUpstream(current.http, listenPort: listenPort, scheme: "http"), !upstream.isEmpty {
            return upstream
        }
        if let upstream = proxyEntryToUpstream(current.socks, listenPort: listenPort, scheme: "socks5"), !upstream.isEmpty {
            return upstream
        }
        return ""
    }

    private func proxyEntryToUpstream(_ entry: ProxyEntry?, listenPort: Int, scheme: String) -> String? {
        guard let entry, entry.enabled, !entry.host.isEmpty, let port = entry.port else { return nil }
        if isLoopbackHost(entry.host), port == listenPort { return nil }
        let host = entry.host.contains(":") && !entry.host.hasPrefix("[") ? "[\(entry.host)]" : entry.host
        return "\(scheme)://\(host):\(port)"
    }

    private func isLoopbackHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func writePacFile(host: String, port: Int, fallbackUpstream: String) throws -> URL {
        let proxyHost = host == "0.0.0.0" || host.isEmpty ? "127.0.0.1" : host
        let figmaProxy = "PROXY \(proxyHost):\(port); DIRECT"
        let fallbackProxy = pacProxyReturnValue(for: fallbackUpstream)
        let pac = """
        // Generated by FigmaCN. Figma traffic uses the local MITM proxy.
        function FindProxyForURL(url, host) {
          var lowerHost = host.toLowerCase();
          if (lowerHost === "figma.com" || shExpMatch(lowerHost, "*.figma.com")) {
            return "\(figmaProxy)";
          }
          return "\(fallbackProxy)";
        }
        """
        try pac.write(to: AppPaths.pacFile, atomically: true, encoding: .utf8)
        return AppPaths.pacFile
    }

    private func pacProxyReturnValue(for upstream: String) -> String {
        guard let url = URL(string: upstream), let host = url.host, let port = url.port else {
            return "DIRECT"
        }

        let pacHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        switch url.scheme?.lowercased() {
        case "socks", "socks5":
            return "SOCKS \(pacHost):\(port); DIRECT"
        case "http", "https":
            return "PROXY \(pacHost):\(port); DIRECT"
        default:
            return "DIRECT"
        }
    }

    private func isAppPacURL(_ url: String) -> Bool {
        url == AppPaths.pacFile.absoluteString || url == AppPaths.pacFile.path
    }
}

private func parseEnabled(_ text: String?) -> Bool {
    text?.range(of: #"Enabled:\s+Yes"#, options: [.regularExpression, .caseInsensitive]) != nil
}

private func parseServer(_ text: String?) -> String {
    parseFirstMatch(text, pattern: #"Server:\s+(.+)"#)
}

private func parsePort(_ text: String?) -> String {
    parseFirstMatch(text, pattern: #"Port:\s+(\d+)"#)
}

private func parseAutoURL(_ text: String?) -> String {
    parseFirstMatch(text, pattern: #"URL:\s+(.+)"#)
}

private func parseFirstMatch(_ text: String?, pattern: String) -> String {
    guard let text else { return "" }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return "" }
    guard let swiftRange = Range(match.range(at: 1), in: text) else { return "" }
    return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}
