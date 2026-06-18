import SwiftUI

/// 开发者日志页面 —— 展示 / 过滤 / 导出 AppSession 运行时日志。
///
/// 入口：设置 → 守护设置 → 开发者日志
///
/// 数据源：`LogStore.shared`（环形 buffer，最近 1000 条）+ `Documents/dev.log`（完整文件）
public struct DevLogScreen: View {
    @ObservedObject private var store = LogStore.shared
    @State private var searchQuery: String = ""
    @State private var levelFilter: LevelFilter = .all
    @State private var shareSheetItem: ShareItem?
    @State private var showClearConfirm: Bool = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient
            VStack(spacing: 0) {
                settingsCard
                searchBar
                levelChips
                logCount
                logList
            }
            bottomToolbar
        }
        .navigationTitle("开发者日志")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .confirmationDialog("清空所有日志？",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("清空内存 + 文件", role: .destructive) {
                store.clearBuffer()
                store.clearFile()
            }
            Button("只清内存", role: .destructive) {
                store.clearBuffer()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("内存日志会立即清空，文件 dev.log 将一并删除。此操作不可撤销。")
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.35),
                         Color.clear,
                         Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Settings card (3 toggles)

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("日志输出")
            VStack(spacing: 0) {
                toggleRow(
                    icon: "terminal.fill",
                    tint: Theme.primary,
                    title: "Xcode Console",
                    subtitle: "同步输出到 Mac 控制台",
                    isOn: $store.isConsoleLoggingEnabled
                )
                divider
                toggleRow(
                    icon: "doc.text.fill",
                    tint: Theme.violet,
                    title: "写入文件",
                    subtitle: store.logFileURL?.lastPathComponent ?? "dev.log",
                    isOn: $store.isFileLoggingEnabled
                )
                divider
                toggleRow(
                    icon: "ladybug.fill",
                    tint: Theme.success,
                    title: "Debug 级别",
                    subtitle: "调试时打开，默认关闭",
                    isOn: $store.isDebugEnabled
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var divider: some View {
        Divider().padding(.leading, 52)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private func toggleRow(icon: String, tint: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.fontSm, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            BrandToggle(isOn: isOn)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textMuted)
            TextField("搜索模块 / 消息…", text: $searchQuery)
                .font(.system(size: Theme.fontSm))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Level chips

    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LevelFilter.allCases) { filter in
                    Button {
                        levelFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(levelFilter == filter ? Theme.primary : Theme.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(levelFilter == filter ? Theme.primarySoft : Theme.surface)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        levelFilter == filter ? Theme.primary : Theme.border,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
    }

    // MARK: - Count

    private var logCount: some View {
        HStack {
            Text("\(filteredEntries.count) / \(store.entries.count) 条")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSubtle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Log list

    private var filteredEntries: [LogEntry] {
        store.entries.filter { entry in
            if levelFilter != .all && entry.level != levelFilter.toLogLevel { return false }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let hay = (entry.module + " " + entry.message).lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    emptyView
                        .padding(.top, 60)
                } else {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .background(
                                Theme.surface
                                    .opacity(0.001) // hit-test
                            )
                        Divider()
                            .background(Theme.border)
                            .padding(.leading, 16)
                    }
                }
                // 底部留白给 toolbar
                Color.clear.frame(height: 80)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(Theme.textSubtle)
            Text("没有匹配的日志")
                .font(.system(size: Theme.fontSm, weight: .medium))
                .foregroundColor(Theme.textMuted)
            Text("切换过滤条件或搜索其他关键字")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSubtle)
        }
    }

    // MARK: - Bottom toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            toolbarButton(icon: "doc.on.doc", title: "复制", variant: .normal) {
                copyAllToClipboard()
            }
            toolbarButton(icon: "square.and.arrow.up", title: "分享文件", variant: .primary) {
                shareLogFile()
            }
            toolbarButton(icon: "trash", title: "清空", variant: .danger) {
                showClearConfirm = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private enum ToolbarVariant { case normal, primary, danger }

    private func toolbarButton(icon: String, title: String, variant: ToolbarVariant, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(toolbarColor(variant))
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(toolbarBg(variant))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(toolbarBorder(variant), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolbarColor(_ v: ToolbarVariant) -> Color {
        switch v {
        case .normal:  return Theme.text
        case .primary: return Theme.primary
        case .danger:  return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    private func toolbarBg(_ v: ToolbarVariant) -> Color {
        switch v {
        case .normal:  return Theme.surface
        case .primary: return Theme.primarySoft
        case .danger:  return Color(red: 1.00, green: 0.95, blue: 0.95)
        }
    }

    private func toolbarBorder(_ v: ToolbarVariant) -> Color {
        switch v {
        case .normal:  return Theme.border
        case .primary: return Theme.primary.opacity(0.3)
        case .danger:  return Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.3)
        }
    }

    // MARK: - Actions

    private func copyAllToClipboard() {
        let text = filteredEntries.reversed().map(\.fullLine).joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    private func shareLogFile() {
        guard let url = store.logFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        shareSheetItem = ShareItem(url: url)
    }

    // MARK: - Nested types

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all, info, warn, error, debug
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:   return "全部"
            case .info:  return "INFO"
            case .warn:  return "WARN"
            case .error: return "ERROR"
            case .debug: return "DEBUG"
            }
        }
        var toLogLevel: LogLevel? {
            switch self {
            case .all:   return nil
            case .info:  return .info
            case .warn:  return .warn
            case .error: return .error
            case .debug: return .debug
            }
        }
    }
}

// MARK: - Single log row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左侧色条
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(levelColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                // 头部：时间 / 级别 / 模块
                HStack(spacing: 6) {
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textSubtle)
                    Text(entry.level.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(levelFgColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(levelBgColor)
                        )
                    Text(entry.module)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // 消息
                Text(entry.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 12)
        }
        .padding(.leading, 13)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: entry.timestamp)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return Theme.textSubtle
        case .info:  return Theme.primary
        case .warn:  return Color(red: 0.94, green: 0.65, blue: 0.13)
        case .error: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
    private var levelFgColor: Color {
        switch entry.level {
        case .debug: return Theme.textMuted
        case .info:  return Theme.primary
        case .warn:  return Color(red: 0.94, green: 0.65, blue: 0.13)
        case .error: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
    private var levelBgColor: Color {
        switch entry.level {
        case .debug: return Theme.textSubtle.opacity(0.18)
        case .info:  return Theme.primarySoft
        case .warn:  return Color(red: 0.99, green: 0.95, blue: 0.78)
        case .error: return Color(red: 1.00, green: 0.91, blue: 0.91)
        }
    }
}

// MARK: - Share helpers

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}