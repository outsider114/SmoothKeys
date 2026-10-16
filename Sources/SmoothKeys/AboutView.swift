import AppKit
import SwiftUI

// Use the property wrapper, not the newer SDK macro unavailable in some CLT installs.
typealias ViewState<Value> = SwiftUI.State<Value>

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var document = LicenseDocument.license

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SmoothKeys").font(.title2.bold())
                    Text("版本 \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭关于窗口")
            }

            Text("CC BY-NC 4.0 · 署名-非商业性使用")
                .font(.subheadline)
            Text("Copyright (c) 2026 SmoothKeys contributors.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("鼠标滚动核心改编自 Mos，作者为 Caldis 及其贡献者。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("GitHub 项目", destination: URL(string: "https://github.com/outsider114/SmoothKeys")!)
                Link("Mos", destination: URL(string: "https://github.com/Caldis/Mos")!)
                Link("CC BY-NC 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-nc/4.0/")!)
            }
            .font(.caption)

            Picker("许可文件", selection: $document) {
                ForEach(LicenseDocument.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                Text(document.contents)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .id(document)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .padding(20)
        .frame(width: 440, height: 500)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
}

enum LicenseDocument: String, CaseIterable, Identifiable {
    case license = "LICENSE"
    case thirdParty = "THIRD_PARTY_NOTICES.md"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .license: return "许可证"
        case .thirdParty: return "第三方声明"
        }
    }

    var contents: String {
        guard let resources = Bundle.main.resourceURL,
              let text = try? String(contentsOf: resources.appendingPathComponent(rawValue), encoding: .utf8) else {
            return "许可文件无法读取，请通过 GitHub 项目查看。"
        }
        return text
    }
}
