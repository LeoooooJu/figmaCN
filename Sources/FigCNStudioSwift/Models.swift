import Foundation

enum ServiceAction: String {
    case start
    case stop
    case refresh
    case repair
    case cache
    case cert
}

struct AppConfig: Codable {
    var localizationEnabled: Bool = true
    var darkModeEnabled: Bool = false
    var port: Int = 8080
    var listenHost: String = "127.0.0.1"
}

struct ServiceState: Equatable {
    var running = false
    var localizationEnabled = true
    var darkModeEnabled = false
    var port = 8080
    var listenHost = "127.0.0.1"
    var certTrusted = false
    var langReady = false
    var mitmReady = false
    var systemProxyReady = true
    var systemProxyApplied = false
    var activeUpstream = ""
    var langVersion = "未检查"
    var lastAction = "就绪"
}

struct ProxyEntry: Codable {
    var enabled: Bool
    var host: String
    var port: Int?
}

struct PacEntry: Codable {
    var enabled: Bool
    var url: String
}

struct CurrentSystemProxy {
    var ok: Bool
    var http: ProxyEntry?
    var https: ProxyEntry?
    var socks: ProxyEntry?
    var pac: PacEntry?
}

struct ProxySnapshot: Codable {
    var web: String
    var secure: String
    var auto: String
    var autoState: String
}

struct SystemProxyBackup: Codable {
    var platform: String
    var ts: TimeInterval
    var data: [String: ProxySnapshot]
}

struct LangEntry: Decodable {
    let string: String?
}
