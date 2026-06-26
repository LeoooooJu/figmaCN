# Runtime：Figma 中文语言包本地代理

这是核心验证版：不做桌面 UI，不自动修改系统代理，只验证语言包替换逻辑。

工作方式：

1. 本机启动 `mitmdump` 代理。
2. Figma 请求英文语言包时，`injector.py` 拦截请求。
3. 代理按请求类型返回 `lang/` 下对应的本地中文包。
4. Figma 收到中文语言包后显示中文。

## 文件说明

```text
Runtime/
├── README.md
├── injector.py          # 中文语言包注入脚本
├── start_proxy.sh       # 启动代理
├── validate_lang.py     # 检查中文包是否可用
└── lang/
    ├── manifest.json
    ├── zh.json
    ├── auth-zh.json
    └── prototype_app_beta-zh.json
```

## 1. 校验中文包

```bash
cd Runtime
python3 validate_lang.py
python3 validate_lang.py lang/auth-zh.json
python3 validate_lang.py lang/prototype_app_beta-zh.json
```

看到 `OK` 和 key 数量即可。

## 2. 启动本地代理

```bash
cd Runtime
chmod +x start_proxy.sh
./start_proxy.sh
```

默认监听：

```text
127.0.0.1:8080
```

如果 8080 被占用，可以换端口：

```bash
PORT=18080 ./start_proxy.sh
```

## 3. 安装并信任 mitmproxy 证书

第一次启动代理后，mitmproxy 会生成证书：

```text
~/.mitmproxy/mitmproxy-ca-cert.cer
```

macOS 可以打开证书文件：

```bash
open ~/.mitmproxy/mitmproxy-ca-cert.cer
```

导入后在“钥匙串访问”里把该证书设置为“始终信任”。

## 4. 临时设置系统代理

macOS 图形界面路径：

```text
系统设置 → 网络 → 当前网络 → 详细信息 → 代理
```

打开：

```text
网页代理 HTTP
安全网页代理 HTTPS
```

两项都填：

```text
服务器：127.0.0.1
端口：8080
```

如果你用的是 `PORT=18080`，这里端口也要填 `18080`。

## 5. 让 Figma 重新加载语言包

设置代理和证书后，重启 Figma。

如果还是英文，清理 Figma 缓存后再打开：

```bash
rm -rf ~/Library/Application\ Support/Figma/DesktopProfile/*/Cache
```

## 6. 验证语言包是否命中

代理终端里出现类似日志，说明已替换成功：

```text
[Runtime] 已替换 Figma main 语言包: https://www.figma.com/webpack-artifacts/assets/...
[Runtime] 已替换 Figma auth 语言包: https://www.figma.com/webpack-artifacts/assets/...
[Runtime] 已替换 Figma prototype 语言包: https://www.figma.com/webpack-artifacts/assets/...
```

捕获到但还没有规则或中文包的语言包会标记为 `other`：

```text
[Runtime] 捕获 Figma 英文语言包 URL (other): https://www.figma.com/webpack-artifacts/assets/...
```

桌面 App 启动时，捕获文件会写到：

```text
~/Library/Application Support/FigmaCNStudioSwift/captured_language_urls.txt
```

直接运行 `start_proxy.sh` 时，默认写到：

```text
Runtime/latest/captured_language_urls.txt
```

如果没有出现这条日志，通常是：

- 系统代理没设置成功。
- 证书没有被信任。
- Figma 用了缓存，没有重新请求语言包。
- Figma 资源文件名变化，当前正则没有匹配到。
- 捕获到了 `other`，但还没有生成对应中文包。

## 7. 恢复系统代理

测试结束后，回到系统网络设置，把 HTTP 和 HTTPS 代理关闭。

如果使用命令行代理窗口，按 `Ctrl+C` 停止 `mitmdump`。
