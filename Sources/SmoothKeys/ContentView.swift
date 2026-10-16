import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: Binding {
                appState.selectedTab
            } set: { tab in
                appState.selectedTab = tab
            }) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            ScrollView {
                Group {
                    switch appState.selectedTab {
                    case .mouse:
                        MouseSettingsView(appState: appState)
                    case .input:
                        InputMethodSettingsView(appState: appState)
                    case .keyboard:
                        KeyboardSettingsView(appState: appState)
                    case .system:
                        SystemSettingsView(appState: appState)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("SmoothKeys")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                appState.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出")
        }
        .padding(14)
    }

    private var statusText: String {
        if appState.accessibilityTrusted && appState.inputMonitoringTrusted {
            return "权限已允许"
        }
        return "需要权限"
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case mouse
    case input
    case keyboard
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "鼠标"
        case .input: return "输入法"
        case .keyboard: return "键盘"
        case .system: return "系统"
        }
    }

    var symbol: String {
        switch self {
        case .mouse: return "computermouse"
        case .input: return "textformat"
        case .keyboard: return "keyboard"
        case .system: return "gearshape"
        }
    }
}

private struct MouseSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "外接鼠标滚动", subtitle: "只处理非连续滚轮事件，内置触控板保持系统原样。")

            Toggle("启用鼠标增强", isOn: binding(\.mouse.enabled))
            Toggle("平滑滚动", isOn: binding(\.mouse.smoothScroll))
            Toggle("垂直滚轮翻转", isOn: binding(\.mouse.reverseVertical))
            Toggle("水平滚轮翻转", isOn: binding(\.mouse.reverseHorizontal))

            VStack(alignment: .leading, spacing: 8) {
                Text("滚动速度")
                    .font(.subheadline)
                Slider(value: binding(\.mouse.speed), in: 0.4...2.2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("平滑惯性")
                    .font(.subheadline)
                Slider(value: binding(\.mouse.smoothness), in: 0.55...0.88)
            }

            HStack(spacing: 8) {
                StatusDot(ok: appState.mouseDiagnostics.transformedEvents > 0 && !appState.mouseConflictDetected)
                Text(mouseStatus)
                    .font(.subheadline)
                    .foregroundStyle(appState.mouseConflictDetected ? .red : .secondary)
            }

            PermissionNotice(appState: appState, reason: "鼠标平滑和翻转需要辅助功能权限。")

            HStack(spacing: 4) {
                Text("滚动核心改编自")
                Link("Mos", destination: URL(string: "https://github.com/Caldis/Mos")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var mouseStatus: String {
        if appState.mouseConflictDetected {
            return "Mos 正在运行，鼠标增强已暂停"
        }
        let diagnostics = appState.mouseDiagnostics
        if diagnostics.receivedEvents == 0 {
            return "等待外接鼠标滚轮输入"
        }
        if diagnostics.mouseEvents == 0 {
            return "最近检测到的是触控板输入"
        }
        if diagnostics.transformedEvents == 0 {
            return "已检测到滚轮，但尚未完成处理"
        }
        return "外接鼠标滚轮已处理 \(diagnostics.transformedEvents) 次"
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            appState.settings[keyPath: keyPath]
        } set: { value in
            appState.settings[keyPath: keyPath] = value
        }
    }
}

private struct InputMethodSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "输入法锁定", subtitle: "选择固定默认输入法后，应用会在后台自动切回该输入法。")

            Toggle("启用输入法锁定", isOn: binding(\.inputMethod.lockEnabled))

            Picker("固定输入法", selection: selectedSourceBinding) {
                Text("未选择").tag("")
                ForEach(appState.inputSources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .pickerStyle(.menu)

            Button {
                appState.refreshInputSources()
            } label: {
                Label("刷新输入法列表", systemImage: "arrow.clockwise")
            }
        }
    }

    private var selectedSourceBinding: Binding<String> {
        Binding {
            appState.settings.inputMethod.selectedSourceID ?? ""
        } set: { value in
            appState.settings.inputMethod.selectedSourceID = value.isEmpty ? nil : value
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            appState.settings[keyPath: keyPath]
        } set: { value in
            appState.settings[keyPath: keyPath] = value
        }
    }
}

private struct KeyboardSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "外接键盘映射", subtitle: "Ctrl -> Command，Alt -> Option，Windows -> Control。映射写入选中键盘的 HID 属性，不影响内置键盘。")

            Toggle("启用键盘映射", isOn: binding(\.keyboard.enabled))

            HStack(spacing: 8) {
                StatusDot(ok: !appState.mappedKeyboardIDs.isEmpty)
                Text(appState.keyboardMappingStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if appState.keyboards.isEmpty {
                EmptyState(text: "没有检测到键盘设备")
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.keyboards) { device in
                        KeyboardDeviceRow(
                            device: device,
                            selected: appState.settings.keyboard.selectedDeviceIDs.contains(device.id),
                            mapped: appState.mappedKeyboardIDs.contains(device.id),
                            toggle: {
                                toggleDevice(device)
                            }
                        )
                    }
                }
            }

            PermissionNotice(appState: appState, reason: "部分键盘需要在隐私设置中允许输入监控或辅助功能后才能完整枚举。")
        }
    }

    private func toggleDevice(_ device: KeyboardDevice) {
        guard device.isExternal else { return }
        if appState.settings.keyboard.selectedDeviceIDs.contains(device.id) {
            appState.settings.keyboard.selectedDeviceIDs.remove(device.id)
        } else {
            appState.settings.keyboard.selectedDeviceIDs.insert(device.id)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            appState.settings[keyPath: keyPath]
        } set: { value in
            appState.settings[keyPath: keyPath] = value
        }
    }
}

private struct SystemSettingsView: View {
    @ObservedObject var appState: AppState
    @ViewState private var showingAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "后台与权限", subtitle: "打开配置窗口时显示在 Dock，关闭窗口后切换成后台菜单栏模式。")

            Toggle("登录时自动启动", isOn: Binding {
                appState.launchAtLoginEnabled
            } set: { enabled in
                appState.toggleLaunchAtLogin(enabled)
            })

            HStack {
                StatusDot(ok: appState.accessibilityTrusted)
                Text(appState.accessibilityTrusted ? "辅助功能已允许" : "辅助功能未允许")
                Spacer()
                Button("打开") {
                    appState.requestAccessibility()
                }
            }

            HStack {
                StatusDot(ok: appState.inputMonitoringTrusted)
                Text(appState.inputMonitoringTrusted ? "输入监控已允许" : "输入监控未允许")
                Spacer()
                Button("打开") {
                    appState.openInputMonitoringSettings()
                }
            }

            HStack {
                StatusDot(ok: appState.eventTapRunning)
                Text(appState.eventTapRunning ? "鼠标事件监听运行中" : "鼠标事件监听未运行")
                Spacer()
                Button("刷新") {
                    appState.refreshSystemState()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当前应用路径")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.appLocation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingAbout = true
            } label: {
                Label("关于与许可", systemImage: "info.circle")
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }

            if !appState.accessibilityTrusted || !appState.inputMonitoringTrusted {
                Text("如果系统设置里已允许但这里仍显示未允许，通常是因为授权给了另一个位置的旧版 SmoothKeys。请把当前这个 app 放到 /Applications 后，删除隐私列表里的旧 SmoothKeys，再重新添加当前版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct KeyboardDeviceRow: View {
    let device: KeyboardDevice
    let selected: Bool
    let mapped: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(device.isExternal ? (selected ? .blue : .secondary) : .gray)
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(device.name)
                            .foregroundStyle(device.isExternal ? .primary : .secondary)
                        if !device.isExternal {
                            Text("内置")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text(device.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if mapped {
                    Text("已生效")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(.quaternary.opacity(selected ? 0.7 : 0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!device.isExternal)
    }
}

private struct PermissionNotice: View {
    @ObservedObject var appState: AppState
    let reason: String

    var body: some View {
        if !appState.accessibilityTrusted || !appState.inputMonitoringTrusted {
            VStack(alignment: .leading, spacing: 8) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if !appState.accessibilityTrusted {
                        Button {
                            appState.requestAccessibility()
                        } label: {
                            Label("辅助功能", systemImage: "lock.open")
                        }
                    }
                    if !appState.inputMonitoringTrusted {
                        Button {
                            appState.openInputMonitoringSettings()
                        } label: {
                            Label("输入监控", systemImage: "hand.raised")
                        }
                    }
                }
            }
            .padding(10)
            .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
    }
}
