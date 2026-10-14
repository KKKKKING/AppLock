import SwiftUI
import UIKit

private let ownerID = "com.king.AppLockManager"
private let dylibName = "AppLock.dylib"
private let pinName = "AppLock.pin"
private let ownerName = "AppLock.owner"

private struct LockTarget: Identifiable {
    let id: String
    let name: String
    let teamID: String
    let bundleURL: URL
    let icon: UIImage?
    let isInjected: Bool
}

private struct ManagerMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private enum Operation: Equatable { case inject, remove }

private enum ManagerError: LocalizedError {
    case foreignDylib(String)
    case inconsistentInjection(String)

    var errorDescription: String? {
        switch self {
        case let .foreignDylib(app):
            return "“\(app)”中存在同名 dylib，但没有 AppLock 所有权标记。为避免误删其他插件，已跳过。"
        case let .inconsistentInjection(app):
            return "“\(app)”中的 AppLock 文件与加载命令不一致，请重新安装该 App 后再操作。"
        }
    }
}

private final class LockManagerModel: ObservableObject {
    @Published var targets: [LockTarget] = []
    @Published var selectedIDs = Set<String>()
    @Published var isWorking = false
    @Published var progressText = ""
    @Published var message: ManagerMessage?

    init() { reload() }

    func reload() {
        let managerID = Bundle.main.bundleIdentifier
        let proxies = LSApplicationWorkspace.default().allApplications() ?? []
        targets = proxies.compactMap { proxy -> LockTarget? in
            guard let identifier = proxy.applicationIdentifier(), identifier != managerID,
                  let name = proxy.localizedName(), let type = proxy.applicationType(),
                  let bundleURL = proxy.bundleURL(),
                  bundleURL.path.contains("/var/containers/Bundle/Application/") else { return nil }

            let isUser = type == "User"
            if isUser && identifier.hasPrefix("com.apple.") { return nil }
            if isUser && !InjectorV3.main.checkIsEligibleAppBundle(bundleURL) { return nil }

            let injected = FileManager.default.fileExists(atPath: dylibURL(bundleURL).path) && ownsInjection(bundleURL)
            return LockTarget(
                id: identifier,
                name: name,
                teamID: proxy.teamID() ?? "0000000000",
                bundleURL: bundleURL,
                icon: UIImage._applicationIconImage(forBundleIdentifier: identifier, format: 0, scale: 3.0),
                isInjected: injected
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedIDs.formIntersection(Set(targets.map(\.id)))
    }

    func toggle(_ target: LockTarget) {
        if selectedIDs.contains(target.id) { selectedIDs.remove(target.id) }
        else { selectedIDs.insert(target.id) }
    }

    func selectAll(_ visible: [LockTarget]) {
        let ids = Set(visible.map(\.id))
        if ids.isSubset(of: selectedIDs) { selectedIDs.subtract(ids) }
        else { selectedIDs.formUnion(ids) }
    }

    func injectSelected(pin: String) {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            message = ManagerMessage(title: "尚未设置 PIN", detail: "请先在设置中保存 6 位数字 PIN。")
            return
        }
        perform(.inject, pin: pin)
    }

    func removeSelected() { perform(.remove, pin: nil) }

    private func perform(_ operation: Operation, pin: String?) {
        let selected = targets.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else {
            message = ManagerMessage(title: "未选择 App", detail: "请先勾选至少一个 App。")
            return
        }
        guard let source = Bundle.main.url(forResource: "AppLock", withExtension: "dylib") else {
            message = ManagerMessage(title: "安装包不完整", detail: "安装包中缺少 AppLock.dylib。")
            return
        }

        isWorking = true
        progressText = "准备处理 \(selected.count) 个 App…"
        let total = selected.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var successCount = 0
            var failures: [String] = []
            for (index, target) in selected.enumerated() {
                DispatchQueue.main.async { self.progressText = "\(index + 1)/\(total)  \(target.name)" }
                let result: Result<Void, Error> = Result {
                    let injector = try InjectorV3(target.bundleURL)
                    injector.appID = target.id
                    injector.teamID = target.teamID
                    if operation == .inject { try self.inject(source, pin: pin!, into: target, using: injector) }
                    else { try self.remove(from: target, using: injector) }
                }
                switch result {
                case .success: successCount += 1
                case let .failure(error): failures.append("\(target.name)：\(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.isWorking = false
                self.progressText = ""
                self.reload()
                let action = operation == .inject ? "注入" : "移除"
                let detail = failures.isEmpty
                    ? "已成功为 \(successCount) 个 App 完成\(action)。"
                    : "成功 \(successCount) 个，失败 \(failures.count) 个。\n\n" + failures.joined(separator: "\n")
                self.message = ManagerMessage(title: "批量\(action)完成", detail: detail)
            }
        }
    }

    private func inject(_ source: URL, pin: String, into target: LockTarget, using injector: InjectorV3) throws {
        let installed = dylibURL(target.bundleURL)
        if FileManager.default.fileExists(atPath: installed.path) {
            guard ownsInjection(target.bundleURL) else { throw ManagerError.foreignDylib(target.name) }
            if let asset = injector.injectedAssetURLsInBundle(target.bundleURL).first(where: { $0.lastPathComponent == dylibName }) {
                try injector.eject([asset], shouldDesist: true)
            } else {
                try injector.cmdRemove(installed)
            }
            try? injector.cmdRemove(sidecarURL(target.bundleURL, pinName))
            try? injector.cmdRemove(sidecarURL(target.bundleURL, ownerName))
        }

        try injector.inject([source], shouldPersist: false)
        do {
            try installSidecar(pin, named: pinName, into: target.bundleURL, using: injector)
            try installSidecar(ownerID, named: ownerName, into: target.bundleURL, using: injector)
        } catch {
            if let asset = injector.injectedAssetURLsInBundle(target.bundleURL).first(where: { $0.lastPathComponent == dylibName }) {
                try? injector.eject([asset], shouldDesist: true)
            }
            throw error
        }
    }

    private func remove(from target: LockTarget, using injector: InjectorV3) throws {
        let installed = dylibURL(target.bundleURL)
        guard FileManager.default.fileExists(atPath: installed.path) else {
            if ownsInjection(target.bundleURL) {
                try? injector.cmdRemove(sidecarURL(target.bundleURL, pinName))
                try? injector.cmdRemove(sidecarURL(target.bundleURL, ownerName))
            }
            return
        }
        guard ownsInjection(target.bundleURL) else { throw ManagerError.foreignDylib(target.name) }
        guard let asset = injector.injectedAssetURLsInBundle(target.bundleURL).first(where: { $0.lastPathComponent == dylibName })
        else { throw ManagerError.inconsistentInjection(target.name) }
        try injector.eject([asset], shouldDesist: true)
        try? injector.cmdRemove(sidecarURL(target.bundleURL, pinName))
        try? injector.cmdRemove(sidecarURL(target.bundleURL, ownerName))
    }

    private func installSidecar(_ value: String, named name: String, into bundleURL: URL, using injector: InjectorV3) throws {
        let temporary = injector.temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(value.utf8).write(to: temporary, options: .atomic)
        let destination = sidecarURL(bundleURL, name)
        try injector.cmdCopy(from: temporary, to: destination, overwrite: true)
        try injector.cmdChangeOwnerToInstalld(destination)
    }

    private func frameworksURL(_ bundle: URL) -> URL { bundle.appendingPathComponent("Frameworks", isDirectory: true) }
    private func dylibURL(_ bundle: URL) -> URL { frameworksURL(bundle).appendingPathComponent(dylibName) }
    private func sidecarURL(_ bundle: URL, _ name: String) -> URL { frameworksURL(bundle).appendingPathComponent(name) }
    private func ownsInjection(_ bundle: URL) -> Bool {
        guard let owner = try? String(contentsOf: sidecarURL(bundle, ownerName), encoding: .utf8) else { return false }
        return owner.trimmingCharacters(in: .whitespacesAndNewlines) == ownerID
    }
}

private struct TargetListView: View {
    @StateObject private var model = LockManagerModel()
    @State private var query = ""
    let pin: String

    private var visible: [LockTarget] {
        query.isEmpty ? model.targets : model.targets.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("名称或者标识符", text: $query).disableAutocorrection(true).autocapitalization(.none)
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(Color(.secondarySystemBackground)).cornerRadius(13).padding(.horizontal)

                if model.targets.isEmpty {
                    Spacer(); ProgressView("正在读取可注入 App…"); Spacer()
                } else {
                    List(visible) { target in
                        Button { model.toggle(target) } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let icon = target.icon { Image(uiImage: icon).resizable() }
                                    else { Image(systemName: "app.fill").resizable().foregroundColor(.secondary) }
                                }
                                .scaledToFit().frame(width: 48, height: 48).cornerRadius(11)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(target.name).font(.headline).foregroundColor(.primary)
                                        if target.isInjected {
                                            Text("已注入").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3)
                                                .foregroundColor(.green).background(Color.green.opacity(0.12)).clipShape(Capsule())
                                        }
                                    }
                                    Text(target.id).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: model.selectedIDs.contains(target.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundColor(model.selectedIDs.contains(target.id) ? .accentColor : .secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.listStyle(.plain)
                }

                if model.isWorking {
                    HStack { ProgressView(); Text(model.progressText).font(.footnote).foregroundColor(.secondary) }
                }
                HStack(spacing: 12) {
                    Button { model.injectSelected(pin: pin) } label: {
                        Label("批量注入", systemImage: "lock.fill").frame(maxWidth: .infinity).frame(height: 44)
                            .foregroundColor(.white).background(Color.accentColor).cornerRadius(10)
                    }.buttonStyle(.plain)
                    Button(action: model.removeSelected) {
                        Label("批量移除", systemImage: "trash").frame(maxWidth: .infinity).frame(height: 44)
                            .foregroundColor(.red).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red))
                    }.buttonStyle(.plain)
                }.padding(.horizontal).padding(.bottom, 8).disabled(model.isWorking)
            }
            .navigationTitle("AppLock")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("刷新", action: model.reload).disabled(model.isWorking) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(model.selectedIDs.count == visible.count && !visible.isEmpty ? "取消全选" : "全选") { model.selectAll(visible) }
                }
            }
            .alert(item: $model.message) { value in
                Alert(title: Text(value.title), message: Text(value.detail), dismissButton: .default(Text("好")))
            }
        }.navigationViewStyle(.stack)
    }
}

private struct AppLockSettingsView: View {
    @Binding var pin: String
    @State private var newPIN = ""
    @State private var confirmation = ""
    @State private var message: ManagerMessage?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("动态密码"), footer: Text("修改 PIN 后，请重新勾选并批量注入以更新目标 App。")) {
                    HStack { Text("当前状态"); Spacer(); Text(pin.isEmpty ? "未设置" : "已设置").foregroundColor(pin.isEmpty ? .secondary : .green) }
                    SecureField("输入 6 位数字 PIN", text: $newPIN).keyboardType(.numberPad)
                        .onChange(of: newPIN) { newPIN = digits($0) }
                    SecureField("再次输入 PIN", text: $confirmation).keyboardType(.numberPad)
                        .onChange(of: confirmation) { confirmation = digits($0) }
                    Button("保存新 PIN") {
                        guard newPIN.count == 6 else { message = ManagerMessage(title: "无法保存", detail: "PIN 必须是 6 位数字。"); return }
                        guard newPIN == confirmation else { message = ManagerMessage(title: "无法保存", detail: "两次输入的 PIN 不一致。"); return }
                        pin = newPIN; newPIN = ""; confirmation = ""
                        message = ManagerMessage(title: "已保存", detail: "下次打开 AppLock 时将要求输入新 PIN。")
                    }
                }
                if !pin.isEmpty {
                    Section(footer: Text("清除后，管理 App 本身不再要求密码；已注入 App 不受影响。")) {
                        Button("清除管理密码") { pin = ""; newPIN = ""; confirmation = "" }.foregroundColor(.red)
                    }
                }
                Section(header: Text("安全边界")) {
                    Text("移除操作仅在 AppLock.owner 所有权标记匹配时执行，不会删除其他注入器或插件的 dylib。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .alert(item: $message) { Alert(title: Text($0.title), message: Text($0.detail), dismissButton: .default(Text("好"))) }
        }.navigationViewStyle(.stack)
    }

    private func digits(_ value: String) -> String { String(value.filter(\.isNumber).prefix(6)) }
}

private struct ManagerTabs: View {
    @Binding var pin: String
    var body: some View {
        TabView {
            TargetListView(pin: pin).tabItem { Label("应用", systemImage: "checklist") }
            AppLockSettingsView(pin: $pin).tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

private struct ManagerUnlockView: View {
    let requiredPIN: String
    let onUnlock: () -> Void
    @State private var enteredPIN = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill").font(.system(size: 62)).foregroundColor(.accentColor)
            Text("AppLock").font(.largeTitle.bold())
            Text("请输入管理密码").foregroundColor(.secondary)
            SecureField("6 位 PIN", text: $enteredPIN).keyboardType(.numberPad).multilineTextAlignment(.center)
                .font(.title2.monospacedDigit()).padding().background(Color(.secondarySystemBackground)).cornerRadius(13)
                .onChange(of: enteredPIN) { enteredPIN = String($0.filter(\.isNumber).prefix(6)) }
            Button("解锁") {
                if enteredPIN == requiredPIN { enteredPIN = ""; onUnlock() }
                else { enteredPIN = ""; failed = true }
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .foregroundColor(.white).background(Color.accentColor).cornerRadius(12)
        }
        .padding(32)
        .alert(isPresented: $failed) {
            Alert(title: Text("PIN码验证失败"), message: Text("PIN码错误，禁止使用。"), dismissButton: .default(Text("重新输入")))
        }
    }
}

@main
struct TrollFoolsApp: SwiftUI.App {
    @AppStorage("managerPIN") private var managerPIN = ""
    @State private var unlocked = false
    @Environment(\.scenePhase) private var scenePhase

    init() { try? FileManager.default.removeItem(at: InjectorV3.temporaryRoot) }

    var body: some Scene {
        WindowGroup {
            Group {
                if managerPIN.isEmpty || unlocked { ManagerTabs(pin: $managerPIN) }
                else { ManagerUnlockView(requiredPIN: managerPIN) { unlocked = true } }
            }
            .onAppear { unlocked = managerPIN.isEmpty }
            .onChange(of: scenePhase) { if $0 != .active && !managerPIN.isEmpty { unlocked = false } }
            .onChange(of: managerPIN) { if $0.isEmpty { unlocked = true } }
        }
    }
}
