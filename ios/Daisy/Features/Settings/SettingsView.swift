import SwiftUI

/// 6 설정: 서버 주소, 로그인 · 로그아웃.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                TextField("https://api.example.com", text: $app.serverURLString)
                    .urlInput()
            } header: {
                Text("서버 주소")
            } footer: {
                if !app.serverURLString.isEmpty && app.serverURL == nil {
                    Text("https://로 시작하는 주소를 넣어 주세요.").foregroundStyle(.red)
                }
            }

            Section("계정") {
                if app.isSignedIn {
                    LabeledContent("권한", value: app.isViewer ? "읽기 전용" : "승인 가능")
                    Button("로그아웃", role: .destructive) { app.signOut() }
                } else {
                    TextField("아이디", text: $username)
                        .textContentType(.username)
                        .plainInput()
                    SecureField("비밀번호", text: $password)
                        .textContentType(.password)
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSigningIn { ProgressView() } else { Text("로그인") }
                    }
                    .disabled(isSigningIn || username.isEmpty || password.isEmpty || app.serverURL == nil)
                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                    }
                }
            }

            Section {
                LabeledContent("버전", value: Bundle.main.versionText)
            }
        }
        .navigationTitle("설정")
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await app.signIn(username: username, password: password)
            password = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
