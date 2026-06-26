# FigmaCN AI 技术文档

这份文档面向 AI 代理、代码维护者和后续接手开发的人。

目标不是介绍怎么使用产品，而是让阅读者快速理解：

- 这个产品解决什么问题
- 它依赖哪些技术
- 运行链路是怎样的
- 关键模块在哪里
- 构建、打包和扩展时应该改哪些位置

如果你只想看产品说明和使用方法，请先看仓库根目录的 [`README.md`](./README.md)。

## 1. 产品定义

FigmaCN 是一个 macOS 原生桌面工具，用来把 Figma Desktop 的界面语言替换为中文。

它不修改 Figma 安装目录，不注入 Figma 二进制，不依赖浏览器插件。它采用本地代理方式，在 Figma 请求官方英文语言包时返回本地中文语言包。

## 2. 技术栈

这套产品的技术栈是固定分层的：

- `Swift 6`
- `SwiftUI`
- `Swift Package Manager`
- `mitmproxy / mitmdump`
- `Python 3`
- macOS 系统命令：`networksetup`、`scutil`、`security`
- Bash 打包脚本

分工如下：

- `SwiftUI`：UI、状态展示、交互按钮、日志展示
- `Swift`：服务编排、配置持久化、系统代理管理、证书安装、缓存清理
- `mitmdump`：HTTPS 代理和请求拦截执行引擎
- `Python Runtime`：语言包命中规则、替换响应、记录运行日志

不要把 `mitmproxy` 当成可选依赖。当前产品架构就是围绕它构建的。

## 3. 运行模型

核心数据流：

```text
Figma
  -> 系统 PAC 自动代理
  -> 本地 mitmdump
  -> Runtime/injector.py
  -> Runtime/lang/ 中匹配的本地中文包
  -> 返回给 Figma
```

PAC 只把 `figma.com` 和 `*.figma.com` 路由到本地 mitmdump。非 Figma 域名不会走本地 `8080`：

- 如果启动前检测到用户已有系统代理，例如 Surge 的 `127.0.0.1:6152`，PAC 会把非 Figma 流量继续交给这个上游代理。
- 如果没有检测到上游代理，PAC 才会让非 Figma 流量 `DIRECT`。

这样可以避免 GitHub、VS Code、浏览器等非 Figma 流量被本 App 错误接管，同时不破坏用户原本依赖 Surge / Clash 的网络路径。

如果用户原本已经启用了系统代理，例如 Surge、Clash 或其他代理软件，则运行链路会变成：

```text
Figma
  -> FigmaCN 本地 mitmdump
  -> 原有系统代理（作为 upstream）
  -> 目标网络
```

这个上游代理转发逻辑很关键。产品不能直接覆盖掉用户已有代理，否则会破坏用户网络环境。

## 4. 仓库结构

```text
figmaCN/
  README.md
  TECHNICAL.md
  Package.swift
  Runtime/
    injector.py
    start_proxy.sh
    validate_lang.py
    lang/
      manifest.json
      en/
        en_latest.json
        auth_latest.en.json
        prototype_app_beta_latest.en.json
      zh/
        zh.json
        auth-zh.json
        prototype_app_beta-zh.json
  Scripts/
    package_app.sh
  Sources/FigmaCNStudioSwift/
    FigmaCNStudioSwiftApp.swift
    ContentView.swift
    ServiceController.swift
    SystemProxyManager.swift
    Shell.swift
    Paths.swift
    Models.swift
```

## 5. 关键模块说明

### `Sources/FigmaCNStudioSwift/FigmaCNStudioSwiftApp.swift`

应用入口。负责创建 `ServiceController` 并注入到 SwiftUI 环境中，同时在退出前触发清理逻辑。

### `Sources/FigmaCNStudioSwift/ContentView.swift`

UI 主界面。当前 UI 由几块组成：

- 头部信息
- 状态面板
- 操作按钮区
- 设置区
- 日志区

UI 很薄，业务逻辑基本都委托给 `ServiceController`。

### `Sources/FigmaCNStudioSwift/Models.swift`

定义运行时数据结构：

- `ServiceAction`
- `AppConfig`
- `ServiceState`
- `CurrentSystemProxy`
- `SystemProxyBackup`

如果后续新增设置项或状态字段，通常先改这里。

### `Sources/FigmaCNStudioSwift/Paths.swift`

路径解析中心。

这个文件负责识别两种运行方式：

1. 源码目录运行
2. `.app` 打包后运行

关键点：

- 如果检测到 `Contents/Resources/Runtime`，说明当前运行在打包后的 App 内
- 否则向上查找 `Runtime/injector.py`

因此，`Runtime` 目录不是普通文档目录，而是运行时资源目录。

### `Sources/FigmaCNStudioSwift/ServiceController.swift`

这是产品的核心编排器。

它负责：

- 刷新环境状态
- 启动/停止 `mitmdump`
- 检查语言包是否可用
- 检查 `mitmdump` 是否可用
- 自动选择可用端口
- 注入上游代理模式
- 设置和恢复系统代理
- 安装证书
- 清理 Figma 缓存
- 维护日志输出

如果要理解“产品怎么运行”，优先读这个文件。

### `Sources/FigmaCNStudioSwift/SystemProxyManager.swift`

专门处理 macOS 系统代理。

职责包括：

- 读取当前系统代理
- 备份各网络服务当前代理状态，包括 HTTP、HTTPS、SOCKS 和 PAC
- 生成 PAC 文件，并只把 Figma 域名切到本地端口
- 启用 FigmaCN PAC 时关闭系统 HTTP、HTTPS、SOCKS 开关，避免 Figma / Electron 绕过 PAC
- 恢复原代理配置，恢复成功后删除旧备份，避免后续误用过期快照
- 修复异常退出后的残留代理

设计原则是“恢复原状优先”，而不是“粗暴关掉所有代理”。

### `Sources/FigmaCNStudioSwift/Shell.swift`

Shell 命令执行器，封装普通命令和需要管理员权限的命令。系统代理修改和证书安装都依赖这里。

## 6. Runtime 目录的角色

`Runtime/` 是运行时资源目录，不是源码附属文档目录。

内容包括：

- `injector.py`：mitmproxy addon，负责拦截和替换语言包
- `start_proxy.sh`：命令行启动代理脚本
- `validate_lang.py`：校验 `lang/zh/zh.json` 的结构是否合理
- `lang/manifest.json`：记录语言包来源、key 数量和合并统计
- `lang/zh/zh.json`：主 Figma app 中文包
- `lang/zh/auth-zh.json`：登录、账号、鉴权相关中文包
- `lang/zh/prototype_app_beta-zh.json`：原型预览相关中文包
- `lang/en/*_latest.en.json`：捕获到的英文源包，作为翻译和对齐依据

用户点击“下载汉化包”后，App 会从 GitHub raw 地址下载最新中文包到：

```text
~/Library/Application Support/FigmaCNStudioSwift/lang/
```

启动代理时优先读取这个缓存目录；如果缓存文件不存在，则回退到 `.app` 内置或源码目录中的 `Runtime/lang/zh/`。

运行时依赖点：

- `Paths.swift` 会解析 `Runtime/`
- `ServiceController.swift` 启动 `mitmdump` 时会把工作目录设为 `Runtime/`
- `Scripts/package_app.sh` 会把 `Runtime/` 拷贝进 `.app`

所以这个目录不能删，也不能随意改名。要改名，必须同步改：

- `Paths.swift`
- `ServiceController.swift`
- `Scripts/package_app.sh`

## 7. 启动链路

用户点击“开启汉化”后，大致流程如下：

1. 如果检测到上次异常退出留下的代理残留，先尝试修复。
2. 刷新当前运行状态。
3. 检查 `mitmdump` 是否可执行。
4. 检查语言包是否可用。
5. 选择可用监听端口。
6. 检测是否存在当前系统代理，并决定是否启用 upstream 模式。
7. 用 `mitmdump -s injector.py` 启动本地代理。
8. 等端口监听成功。
9. 备份当前系统代理设置。
10. 生成 PAC 文件，Figma 域名指向本地 mitmdump，非 Figma 域名指向原上游代理或直连。
11. 关闭系统 HTTP、HTTPS、SOCKS 代理开关，并启用系统自动代理配置。

如果第 8 步失败，产品不会继续修改系统代理。

PAC 生成结果示例：

```javascript
function FindProxyForURL(url, host) {
  var lowerHost = host.toLowerCase();
  if (lowerHost === "figma.com" || shExpMatch(lowerHost, "*.figma.com")) {
    return "PROXY 127.0.0.1:8080; DIRECT";
  }
  return "PROXY 127.0.0.1:6152; DIRECT";
}
```

上例表示 Figma 请求走 FigmaCN 的本地 MITM，其他请求继续走 Surge 的 HTTP 上游代理。

## 8. 语言包替换逻辑

语言包替换逻辑位于：

- [`Runtime/injector.py`](./Runtime/injector.py)

它的职责：

- 识别 Figma 语言包请求 URL
- 判断当前是否启用本地汉化
- 根据请求类型选择本地中文包
- 直接构造响应返回给 Figma
- 记录命中的语言包 URL 和运行日志

它不是通用抓包脚本，而是面向 Figma 语言包资源的专用 addon。

当前已支持的本地替换规则：

```text
figma_app...min.en.json(.br)          -> Runtime/lang/zh/zh.json
auth...min.en.json(.br)               -> Runtime/lang/zh/auth-zh.json
auth_iframe...min.en.json(.br)        -> Runtime/lang/zh/auth-zh.json
prototype_app...min.en.json(.br)      -> Runtime/lang/zh/prototype_app_beta-zh.json
prototype_app_beta...min.en.json(.br) -> Runtime/lang/zh/prototype_app_beta-zh.json
community...min.en.json(.br)          -> Runtime/lang/zh/community-zh.json
```

`community` 规则已经预留，但仓库当前还没有 `lang/zh/community-zh.json`。捕获到对应英文包并生成中文包后即可生效。

所有 Figma 英文语言包请求都会被捕获，匹配范围是：

```text
/webpack-artifacts/assets/*.en.json
/webpack-artifacts/assets/*.en.json.br
```

打包后的 App 会把捕获文件写到：

```text
~/Library/Application Support/FigmaCNStudioSwift/captured_language_urls.txt
```

源码命令行运行且未设置 `FigmaCN_CAPTURE_FILE` 时，回退到：

```text
Runtime/latest/captured_language_urls.txt
```

语言包合并策略：

1. 先以捕获到的英文源包作为完整 key 集。
2. 用已有中文主包中 key 相同的条目覆盖英文条目。
3. 找不到中文条目的 key 保留英文，保证 Figma 收到完整 JSON。
4. key 数、fallback 数和来源 URL 写入 `Runtime/lang/manifest.json`。

## 9. 配置与状态持久化

配置文件位置：

```text
~/Library/Application Support/FigmaCNStudioSwift/config.json
```

当前主要配置：

```json
{
  "localizationEnabled": true,
  "darkModeEnabled": false,
  "port": 8080,
  "listenHost": "127.0.0.1"
}
```

代理备份文件位置：

```text
~/Library/Application Support/FigmaCNStudioSwift/system-proxy-backup.json
```

这里保存的是“接管系统代理之前”的快照，用于停止时恢复或异常恢复。

快照会记录：

- `web`：HTTP 代理
- `secure`：HTTPS 代理
- `socks`：SOCKS 代理
- `auto` / `autoState`：PAC URL 和 PAC 开关状态

恢复成功后会删除这个备份文件。它不是长期配置文件，不应该被当成当前代理状态的来源。

语言包捕获文件位置：

```text
~/Library/Application Support/FigmaCNStudioSwift/captured_language_urls.txt
```

## 10. 构建方式

Swift 构建：

```bash
swift build -c release
```

Swift Package 很简单，没有外部 Swift 依赖，主目标只有一个可执行产物：

- `FigmaCNStudioSwift`

## 11. 打包方式

打包脚本：

- [`Scripts/package_app.sh`](./Scripts/package_app.sh)

打包流程：

1. 执行 `swift build -c release`
2. 创建 `.app` 目录结构
3. 拷贝二进制到 `Contents/MacOS`
4. 拷贝 `Runtime/injector.py`、校验脚本、启动脚本和完整 `Runtime/lang/` 目录
5. 寻找本机 `mitmproxy.app`
6. 把 `mitmproxy.app` 内置到 `Contents/Resources/mitmproxy`

当前脚本要求本机能找到可用的 `mitmproxy.app`。如果找不到，会直接失败。

## 12. 环境依赖与约束

构建和运行时要注意这些前提：

- 仅支持 macOS
- 需要可运行的 `mitmdump`
- 首次代理链路通常需要先生成并安装 mitmproxy 证书
- 修改系统代理需要管理员权限
- 运行时依赖 Figma 的语言包请求路径模式没有发生根本变化

## 13. AI 修改这个项目时的建议

如果你是 AI 代理，建议按这个顺序理解和修改：

1. 先读 `ContentView.swift` 理解用户看到的操作面
2. 再读 `ServiceController.swift` 理解真实业务链路
3. 再读 `SystemProxyManager.swift` 理解系统代理副作用
4. 最后读 `Runtime/injector.py` 理解语言包替换逻辑

不要直接做这些危险操作，除非用户明确要求：

- 改动 `Runtime/` 目录名
- 改动系统代理恢复逻辑
- 删除 mitmproxy 依赖
- 改写证书安装方式

这几类改动会直接影响产品是否还能启动和是否会污染用户网络环境。

## 14. 适合继续扩展的方向

当前架构比较适合继续做这些能力：

- 语言包更新和版本管理
- GitHub Pages 托管语言包并在 UI 中提供“更新语言包”
- 捕获更多独立语言包，例如 community
- 更细粒度的日志和诊断
- 正式签名、公证和分发
- 自动更新
- 更稳的异常恢复能力
- 更少管理员弹窗的 helper 方案

## 15. 当前不该轻易改的地方

这些地方耦合度很高：

- `Runtime/` 路径约定
- `mitmdump` 启动参数
- 系统代理备份与恢复逻辑
- 打包时内置 `mitmproxy.app` 的方式

如果必须改，应该把 `Paths.swift`、`ServiceController.swift`、`SystemProxyManager.swift` 和 `Scripts/package_app.sh` 一起检查。

## 16. 本地开发日志约定

根目录的 `开发日志.MD` 是本地维护日志，用来记录每次 AI 或人工对项目做过的实际改动、验证结果和注意事项。

这个文件已经加入 `.gitignore`，默认不上传 GitHub。后续每次修改项目时，都应该在该文件追加一条按时间排序的记录，便于本机继续追踪上下文。
