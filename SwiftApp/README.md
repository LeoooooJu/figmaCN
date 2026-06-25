# FigCN Studio Swift 技术文档

本文档说明当前 Swift 原生版 App 的实现方式、运行链路、打包方式、系统代理逻辑和常见问题。当前版本只保留 Figma 中文语言包替换能力。

## 1. 项目目标

App 不修改 Figma 客户端文件，而是在 Figma 请求官方英文语言包时，通过本地代理返回中文语言包。

核心链路：

```text
Figma 请求英文语言包
        ↓
系统代理把请求交给本 App 启动的本地 mitmproxy
        ↓
mitmproxy 运行 Runtime/injector.py
        ↓
命中 Figma 语言包 URL
        ↓
返回本地 Runtime/lang/zh.json
        ↓
Figma 界面显示中文
```

## 2. 目录结构

```text
SwiftApp/
  Package.swift
  Sources/FigCNStudioSwift/
    FigCNStudioSwiftApp.swift
    ContentView.swift
    ServiceController.swift
    SystemProxyManager.swift
    Shell.swift
    Paths.swift
    Models.swift
  Scripts/
    package_app.sh
  release/
    FigCN Studio Swift.app

Runtime/
  injector.py
  start_proxy.sh
  validate_lang.py
  lang/zh.json
```

主要文件职责：

| 文件 | 作用 |
| --- | --- |
| `FigCNStudioSwiftApp.swift` | SwiftUI App 入口，处理窗口和退出前清理 |
| `ContentView.swift` | 主界面，包含状态、操作按钮、设置、日志、暗色模式 |
| `ServiceController.swift` | 服务总控，负责启动/停止 mitmdump、校验语言包、清缓存、安装证书 |
| `SystemProxyManager.swift` | macOS 系统代理读取、备份、设置、恢复、修复 |
| `Shell.swift` | 执行命令、管理员权限 AppleScript 封装 |
| `Paths.swift` | 统一管理 Runtime、证书、配置、内置 mitmproxy 路径 |
| `Models.swift` | 状态、配置、代理快照等数据结构 |
| `package_app.sh` | 构建 `.app`，复制 Runtime 资源并内置 mitmproxy |

## 3. 技术方案

当前方案分三层：

```text
SwiftUI App
  负责界面、按钮、状态、日志、配置保存

mitmproxy / mitmdump
  负责 HTTPS 中间人代理、证书、请求拦截、响应替换

Python addon
  Runtime/injector.py 负责识别 Figma 语言包请求并返回 zh.json
```

没有用 Swift 直接重写 HTTPS MITM，是因为证书签发、TLS、HTTP/2、压缩、连接复用等能力都已有成熟实现。第一版使用 mitmproxy 更稳。

## 4. 启动流程

用户点击“开启汉化”后，`ServiceController.startProxy()` 执行：

1. 检查服务是否已经运行。
2. 检查上次异常退出留下的系统代理残留。
3. 校验运行环境：
   - 是否找到内置或系统 `mitmdump`
   - `Runtime/lang/zh.json` 是否有效
4. 选择本地监听端口。
5. 检测当前系统代理。如果用户已开 Surge、Clash 或其他 VPN，则作为上游代理。
6. 启动内置 `mitmdump`，加载 `Runtime/injector.py`。
7. 等待本地端口真正开始监听。
8. 备份当前系统代理设置。
9. 把系统 HTTP/HTTPS 代理指向本 App 的本地端口。

没有 VPN 时：

```text
Figma → 127.0.0.1:端口 → mitmdump → Figma 官方服务器
```

有 Surge/Clash/VPN 时：

```text
Figma → 127.0.0.1:端口 → mitmdump → 原来的系统代理 → 网络
```

关键规则：必须先读取当前系统代理，再把系统代理改成 App 本地端口。否则会把 App 自己误认为上游代理。

## 5. 端口逻辑

默认监听端口是 `8080`。端口可以理解成 App 在本机开的临时入口。

App 会自动换端口：

1. 优先尝试用户设置里的端口。
2. 如果被占用，自动尝试：

```text
18080, 18081, 18082, 18083, 18084, 18085,
19080, 19081, 19082,
20000-20100
```

3. 找到可用端口后自动保存配置，并继续启动。

端口可用性检测使用底层 `socket + bind`，避免误判。

## 6. 系统代理逻辑

系统代理由 `SystemProxyManager.swift` 管理。

启动时：

1. 使用 `scutil --proxy` 读取当前系统代理。
2. 如果当前代理不是 App 自己的端口，则作为上游代理。
3. 使用 `networksetup -listallnetworkservices` 获取所有网络服务。
4. 读取每个服务的 HTTP、HTTPS、PAC 设置。
5. 写入备份文件：

```text
~/Library/Application Support/FigCNStudioSwift/system-proxy-backup.json
```

6. 通过管理员权限执行 `networksetup`，把 HTTP/HTTPS 代理指向本地 mitmdump。

停止时：

1. 停止 mitmdump。
2. 如果存在备份文件，则恢复之前的系统代理。
3. 清空 App 内部状态。

修复网络时：

1. 优先读取备份文件并恢复。
2. 如果没有备份，只关闭仍然指向 App 本地端口的 HTTP/HTTPS 代理。
3. 不会关闭用户自己的 Surge、Clash 或其他代理。

## 7. 异常退出保护

App 做了三层保护：

1. 正常退出时，先调用 `cleanupBeforeQuit()`。
2. 如果 mitmdump 异常退出，App 会尝试自动恢复系统代理。
3. 下次启动 App 时，如果检测到系统代理仍指向 App 本地端口，会尝试恢复备份。

限制：

- 如果 App 被强制杀掉，清理逻辑可能来不及执行。
- 用户重新打开 App 后，点击“修复网络”即可恢复。
- 更强保护需要 privileged helper 或独立守护进程。

## 8. 内置 mitmproxy

打包脚本会把本机安装的 `mitmproxy.app` 复制到 App 内部：

```text
FigCN Studio Swift.app/
  Contents/Resources/mitmproxy/mitmproxy.app
```

App 启动服务时优先使用：

```text
Contents/Resources/mitmproxy/mitmproxy.app/Contents/MacOS/mitmdump
```

如果内置文件不存在，则回退查找系统 PATH 里的 `mitmdump`。

完整包大小约 `93M`，主要来自内置 mitmproxy。

## 9. 证书逻辑

mitmproxy 第一次启动后会生成证书：

```text
~/.mitmproxy/mitmproxy-ca-cert.cer
```

App 的“安装证书”按钮会：

1. 检查证书文件是否存在。
2. 优先尝试安装到登录钥匙串。
3. 如果失败，再通过管理员权限安装到系统钥匙串。

证书没有安装或没有信任时，Figma 的 HTTPS 请求可能失败，汉化无法生效。

## 10. 语言包拦截

核心逻辑在：

```text
Runtime/injector.py
```

它匹配 Figma 主语言包请求：

```text
/webpack-artifacts/assets/figma_app...min.en.json
/webpack-artifacts/assets/figma_app...min.en.json.br
```

命中后返回：

```text
Runtime/lang/zh.json
```

同时会记录捕获到的语言包 URL：

```text
Runtime/latest/captured_language_urls.txt
```

## 11. 暗色模式

暗色模式只影响 App 自身 UI，不影响 Figma 汉化。

配置字段：

```swift
darkModeEnabled: Bool
```

保存位置：

```text
~/Library/Application Support/FigCNStudioSwift/config.json
```

界面使用 `preferredColorScheme` 切换浅色/暗色，并通过 `AppTheme` 集中管理颜色。

## 12. 配置文件

配置文件路径：

```text
~/Library/Application Support/FigCNStudioSwift/config.json
```

当前保存字段：

```json
{
  "localizationEnabled": true,
  "darkModeEnabled": false,
  "port": 8080,
  "listenHost": "127.0.0.1"
}
```

代理备份路径：

```text
~/Library/Application Support/FigCNStudioSwift/system-proxy-backup.json
```

## 13. 构建和打包

开发构建：

```bash
cd /Users/judy/Documents/Codex/figma汉化/SwiftApp
swift build -c release
```

打包 `.app`：

```bash
cd /Users/judy/Documents/Codex/figma汉化
SwiftApp/Scripts/package_app.sh
```

当前产物：

```text
/Users/judy/Documents/Codex/figma汉化/SwiftApp/release/FigCN Studio Swift.app
```

## 14. 普通用户使用流程

推荐流程：

1. 打开 App。
2. 第一次点击“开启汉化”，让 mitmproxy 生成证书。
3. 点击“安装证书”并按系统提示授权。
4. 再点击“开启汉化”。
5. 重启 Figma 或清理 Figma 缓存后打开 Figma。

如果同时使用 Surge、Clash 或其他 VPN：

1. 先打开 VPN 软件。
2. 再打开本 App。
3. 点击“开启汉化”。

App 会自动把原来的 VPN 代理作为上游。

## 15. 常见问题

### 为什么每次开启/停止都可能要输入密码？

因为 App 需要修改 macOS 系统代理，底层使用 `networksetup`。修改系统网络配置需要管理员权限。

### “修复网络”做什么？

它会恢复 App 启动前备份的系统代理设置。如果备份不存在，只关闭指向本 App 本地端口的残留代理。

### 汉化不生效怎么办？

按顺序检查：

1. App 是否显示服务运行中。
2. 是否安装并信任 mitmproxy 证书。
3. 是否清理 Figma 缓存。
4. 是否重启 Figma。
5. 日志里是否出现“已替换 Figma 语言包”。

## 16. 当前限制

1. 只支持 macOS。
2. 依赖 mitmproxy 实现 HTTPS MITM。
3. 修改系统代理仍需要管理员密码。
4. 强制杀进程时，无法保证退出前清理一定执行。
5. 语言包仍使用现有 `zh.json`，还没有完整自翻译工作流。
6. App 未做正式签名、公证和自动更新。

## 17. 后续优化建议

1. 增加正式签名和公证。
2. 增加 privileged helper，减少重复输入管理员密码。
3. 增加完整自翻译语言包工作流。
4. 精简内置 mitmproxy，降低包体积。
5. 增加自动更新机制。
6. 增加崩溃后独立网络恢复工具或守护进程。
