import SwiftUI

/// W-00 로그인 · W-00b 로그인 실패.
/// 넓으면 왼쪽 브랜드 패널 + 오른쪽 폼, 좁으면 폼만 (브랜드 문구는 위에 작게).
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: Problem?
    @FocusState private var passwordFocused: Bool

    enum Problem: Equatable {
        case wrongCredentials, network, other(String)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= RootView.sidebarBreakpoint {
                HStack(spacing: 0) {
                    brand.frame(maxWidth: .infinity, maxHeight: .infinity).background(SidebarBackground())
                    ScrollView { form.frame(maxWidth: 400).padding(32) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentSurface()
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        brandText.padding(.top, 24)
                        form
                    }
                    .padding(20)
                }
                .contentSurface()
            }
        }
    }

    // MARK: 브랜드 패널

    private var brand: some View {
        VStack(spacing: 24) {
            InfraBlock(animated: false).frame(width: 172, height: 196)
            brandText
        }
        .padding(40)
    }

    private var brandText: some View {
        VStack(spacing: 8) {
            Text("ONE ACTION, INFINITE CLOUDS")
                .font(.caption.monospaced().weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            Text("환경만 고르면, 어디든 같은 상태로").font(.title2.weight(.semibold))
            Text("AI가 환경별 인프라 코드를 만들고 검증해서 온프레미스와 퍼블릭 클라우드에 동시에 배포해요.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: 폼

    private var form: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(.appLogo).resizable().frame(width: 32, height: 32).clipShape(.rect(cornerRadius: 8))
                Text("daisy").font(.system(size: 22, weight: .semibold, design: .monospaced))
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                Text("로그인").font(.title2.weight(.semibold))
                Text("팀 계정으로 로그인해요.").foregroundStyle(.secondary)
            }

            alert

            // 앱에만 있는 칸: 웹은 주소가 정해져 있지만 앱은 연결할 서버를 골라요.
            field("서버 주소") {
                TextField("https://api.example.com", text: $app.serverURLString).urlInput()
            }
            if !app.serverURLString.isEmpty && app.serverURL == nil {
                Text("https://로 시작하는 주소를 넣어 주세요.").font(.caption).foregroundStyle(.red)
            }
            field("아이디") {
                TextField("아이디", text: $username).textContentType(.username).plainInput()
                    .onSubmit { passwordFocused = true }
            }
            field("비밀번호", error: problem == .wrongCredentials) {
                SecureField("비밀번호", text: $password).textContentType(.password)
                    .focused($passwordFocused)
                    .onSubmit { Task { await signIn() } }
            }

            Button {
                Task { await signIn() }
            } label: {
                if working { ProgressView().controlSize(.small) } else { Text("로그인") }
            }
            .buttonStyle(.glassCapsule(prominent: true, fullWidth: true, height: 38))
            .disabled(working || username.isEmpty || password.isEmpty || app.serverURL == nil)

            HStack {
                VStack { Divider() }
                Text("또는").font(.caption).foregroundStyle(.secondary)
                VStack { Divider() }
            }

            Button {
                Task { await signInAsDemo() }
            } label: {
                Text("데모 계정으로 둘러보기 (읽기 전용)")
            }
            .buttonStyle(.glassCapsule(fullWidth: true, height: 38))
            .disabled(working || app.serverURL == nil)

            Text("SoftBank Hackathon 2026 · Team Daisy")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var alert: some View {
        switch problem {
        case .wrongCredentials:
            InlineAlert(.danger, "로그인하지 못했어요", "아이디 또는 비밀번호가 맞지 않아요. 다시 확인해 주세요.")
        case .network:
            InlineAlert(.danger, "로그인하지 못했어요", "서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
        case .other(let message):
            InlineAlert(.danger, "로그인하지 못했어요", message)
        case nil:
            if app.sessionExpired {
                InlineAlert(.info, "다시 로그인해 주세요.")
            }
        }
    }

    private func field(_ label: String, error: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            content()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(error ? AnyShapeStyle(.red) : AnyShapeStyle(.separator), lineWidth: error ? 1 : 0.5))
        }
    }

    // MARK: 동작

    private func signIn() async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await app.signIn(username: username, password: password)
        } catch {
            show(error)
            // W-00b NOTE: 아이디는 그대로 두고 비밀번호만 비워요.
            password = ""
        }
    }

    private func signInAsDemo() async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await app.signInAsDemo()
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        switch error as? APIError {
        case .server(401, _, _, _): problem = .wrongCredentials
        case .transport: problem = .network
        default: problem = .other(error.localizedDescription)
        }
    }
}
