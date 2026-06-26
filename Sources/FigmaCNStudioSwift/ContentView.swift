import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: ServiceController
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 360)

            Divider()
                .overlay(theme.divider)

            LogView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
        .preferredColorScheme(controller.state.darkModeEnabled ? .dark : .light)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var controller: ServiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderView()

            StatusPanel()

            ActionGrid()

            SettingsPanel()

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var controller: ServiceController
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(theme.logoBackground)
                    Circle()
                        .fill(theme.logoAccent)
                        .frame(width: 28, height: 28)
                    Text("F")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(theme.logoBackground)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FigmaCN Studio")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text("Swift 原生版")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Text(controller.state.lastAction)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
        }
    }
}

private struct StatusPanel: View {
    @EnvironmentObject private var controller: ServiceController

    var body: some View {
        VStack(spacing: 10) {
            StatusRow(title: "服务", value: controller.state.running ? "运行中" : "未启动", ok: controller.state.running)
            StatusRow(title: "系统代理", value: controller.state.systemProxyApplied ? "已接管" : "未接管", ok: controller.state.systemProxyApplied)
            StatusRow(title: "mitmproxy", value: controller.state.mitmReady ? "可用" : "未安装", ok: controller.state.mitmReady)
            StatusRow(title: "证书", value: controller.state.certTrusted ? "已生成" : "未检测到", ok: controller.state.certTrusted)
            StatusRow(title: "中文包", value: controller.state.langVersion, ok: controller.state.langReady)
            StatusRow(title: "上游代理", value: controller.state.activeUpstream.isEmpty ? "直连" : controller.state.activeUpstream, ok: true)
        }
        .panelStyle()
    }
}

private struct StatusRow: View {
    @EnvironmentObject private var controller: ServiceController
    let title: String
    let value: String
    let ok: Bool
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ok ? theme.success : theme.danger)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct ActionGrid: View {
    @EnvironmentObject private var controller: ServiceController
    @State private var showingRestartConfirmation = false
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PrimaryButton(
                    title: controller.state.running ? "停止汉化" : "开启汉化",
                    systemImage: controller.state.running ? "stop.fill" : "play.fill",
                    tint: controller.state.running ? theme.danger : theme.primaryButton
                ) {
                    if controller.state.running {
                        controller.run(.stop)
                    } else {
                        showingRestartConfirmation = true
                    }
                }

                SecondaryButton(title: "刷新", systemImage: "arrow.clockwise") {
                    controller.run(.refresh)
                }
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "修复网络", systemImage: "wrench.and.screwdriver.fill") {
                    controller.run(.repair)
                }
                SecondaryButton(title: "清缓存", systemImage: "trash.fill") {
                    controller.run(.cache)
                }
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "安装证书", systemImage: "checkmark.shield.fill") {
                    controller.run(.cert)
                }
                SecondaryButton(title: "下载汉化包", systemImage: "arrow.down.circle.fill") {
                    controller.run(.downloadLang)
                }
            }
        }
        .alert("重启 Figma 并开启汉化？", isPresented: $showingRestartConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重启并开启") {
                controller.run(.start)
            }
        } message: {
            Text("将退出当前 Figma、清理资源缓存，并通过本地汉化代理重新启动。请先确认文件已同步。")
        }
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject private var controller: ServiceController
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Toggle("替换 Figma 中文包", isOn: Binding(
                get: { controller.state.localizationEnabled },
                set: {
                    controller.state.localizationEnabled = $0
                    controller.saveConfig()
                }
            ))
            .disabled(controller.state.running)

            Toggle("暗色模式", isOn: Binding(
                get: { controller.state.darkModeEnabled },
                set: {
                    controller.state.darkModeEnabled = $0
                    controller.saveConfig()
                }
            ))

            HStack {
                Text("监听端口")
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                TextField("8080", value: Binding(
                    get: { controller.state.port },
                    set: {
                        controller.state.port = $0
                        controller.saveConfig()
                    }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
                .disabled(controller.state.running)
            }

            Text("运行时链路：Figma → 本 App → 当前上游代理或直连网络")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct LogView: View {
    @EnvironmentObject private var controller: ServiceController
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("运行日志")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(controller.logs.count) 条")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(controller.logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.logText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(14)
                }
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: controller.logs.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(24)
    }
}

private struct PrimaryButton: View {
    @EnvironmentObject private var controller: ServiceController
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryButtonText)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SecondaryButton: View {
    @EnvironmentObject private var controller: ServiceController
    let title: String
    let systemImage: String
    let action: () -> Void
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryText)
        .background(theme.buttonSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PanelModifier: ViewModifier {
    @EnvironmentObject private var controller: ServiceController
    private var theme: AppTheme { AppTheme(dark: controller.state.darkModeEnabled) }

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }
}

private struct AppTheme {
    let dark: Bool

    var background: Color {
        dark ? Color(red: 0.09, green: 0.10, blue: 0.10) : Color(red: 0.96, green: 0.95, blue: 0.92)
    }

    var panel: Color {
        dark ? Color(red: 0.15, green: 0.16, blue: 0.15).opacity(0.92) : Color.white.opacity(0.72)
    }

    var buttonSurface: Color {
        dark ? Color(red: 0.20, green: 0.21, blue: 0.20) : Color.white.opacity(0.82)
    }

    var border: Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var divider: Color {
        dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    var primaryText: Color {
        dark ? Color(red: 0.94, green: 0.93, blue: 0.89) : Color(red: 0.10, green: 0.10, blue: 0.09)
    }

    var secondaryText: Color {
        dark ? Color(red: 0.66, green: 0.67, blue: 0.63) : Color(red: 0.42, green: 0.40, blue: 0.36)
    }

    var logText: Color {
        dark ? Color(red: 0.82, green: 0.84, blue: 0.78) : Color(red: 0.18, green: 0.17, blue: 0.15)
    }

    var primaryButton: Color {
        dark ? Color(red: 0.86, green: 0.84, blue: 0.75) : Color.black
    }

    var primaryButtonText: Color {
        dark ? Color(red: 0.08, green: 0.09, blue: 0.08) : Color.white
    }

    var logoBackground: Color {
        dark ? Color(red: 0.88, green: 0.86, blue: 0.78) : Color.black
    }

    var logoAccent: Color {
        dark ? Color(red: 0.14, green: 0.15, blue: 0.14) : Color(red: 0.96, green: 0.94, blue: 0.88)
    }

    var success: Color {
        Color(red: 0.14, green: 0.57, blue: 0.36)
    }

    var danger: Color {
        Color(red: 0.76, green: 0.29, blue: 0.24)
    }
}
