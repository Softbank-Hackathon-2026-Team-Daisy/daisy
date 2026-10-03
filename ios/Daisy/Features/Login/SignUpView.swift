import SwiftUI

/// 회원가입 (10/3 팀 합의 `POST /auth/signup`). 로그인 화면 "회원가입"에서 시트로 열려요 (iPhone · Mac 같아요).
/// 가입하면 로그인과 똑같이 토큰을 저장해서 바로 앱에 들어가요. 실서버 전용이라 예시 데이터 모드에는 없어요.
struct SignUpView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var form = SignUpForm()
    @State private var working = false
    @State private var failure: SignUpFailure?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case username, displayName, password, confirmation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let failure { InlineAlert(.danger, failure.title, failure.message) }

                AuthField("아이디", hint: form.usernameHint, error: form.showsUsernameError || failure == .usernameTaken) {
                    TextField("아이디", text: $form.username).textContentType(.username).plainInput()
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .displayName }
                }
                AuthField("표시 이름 (선택)", hint: form.displayNameHint, error: form.showsDisplayNameError) {
                    TextField("표시 이름", text: $form.displayName).textContentType(.name)
                        .focused($focus, equals: .displayName)
                        .onSubmit { focus = .password }
                }
                AuthField("비밀번호", hint: form.passwordHint, error: form.showsPasswordError) {
                    SecureField("비밀번호", text: $form.password).textContentType(.newPassword)
                        .focused($focus, equals: .password)
                        .onSubmit { focus = .confirmation }
                }
                AuthField("비밀번호 확인", hint: form.confirmationHint, error: form.showsConfirmationError) {
                    SecureField("비밀번호 확인", text: $form.confirmation).textContentType(.newPassword)
                        .focused($focus, equals: .confirmation)
                        .onSubmit { Task { await submit() } }
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(working ? "가입하는 중…" : "가입하기")
                }
                .buttonStyle(.glassCapsule(prominent: true, fullWidth: true, height: 38))
                .disabled(working || !form.isValid || app.serverURL == nil)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentSurface()
        #if os(macOS)
        .frame(width: 420)
        .frame(minHeight: 560)
        #endif
        .interactiveDismissDisabled(working)
        .onChange(of: form) { failure = nil }
        .onAppear { focus = .username }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("회원가입").font(.title2.weight(.semibold))
                Text("새 계정을 만들어요. 가입하면 바로 로그인돼요.").foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                .buttonStyle(GlassCircleButtonStyle(diameter: 28))
                .keyboardShortcut(.cancelAction)
                .disabled(working)
        }
    }

    private func submit() async {
        guard !working, form.isValid else { return }
        working = true
        defer { working = false }
        do {
            try await app.signUp(username: form.username, password: form.password, displayName: form.displayName)
            dismiss()
        } catch {
            failure = SignUpFailure(error)
            if failure == .usernameTaken { focus = .username }
        }
    }
}

// MARK: - 입력 규칙

/// 회원가입 칸과 서버 규칙 (`POST /auth/signup` 계약): 아이디는 공백을 빼고 소문자로 바꾼 뒤 `^[a-z0-9][a-z0-9._-]{2,31}$`,
/// 비밀번호 8자 이상 · UTF-8 72바이트까지(서버 BCrypt 제한: 영문 72자 · 한글 24자) · 공백만은 안 돼요, 표시 이름은 선택 · 64자까지, 확인은 비밀번호와 같아야 해요.
/// 빨간 표시는 그 칸을 쓰기 시작한 뒤에만 보여요.
struct SignUpForm: Equatable {
    var username = ""
    var displayName = ""
    var password = ""
    var confirmation = ""

    static let passwordMinimum = 8
    /// 서버 BCrypt가 받는 최대 길이 (UTF-8 바이트). 넘으면 서버가 400 `password`예요
    static let passwordMaximumBytes = 72
    static let displayNameMaximum = 64

    /// 서버로 보내는 아이디 (공백 빼고 소문자)
    var normalizedUsername: String { SignupRequest.normalized(username) }

    var usernameValid: Bool { normalizedUsername.wholeMatch(of: #/[a-z0-9][a-z0-9._\-]{2,31}/#) != nil }
    var displayNameValid: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).count <= Self.displayNameMaximum
    }
    var passwordValid: Bool {
        password.count >= Self.passwordMinimum && !passwordTooLong
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var passwordTooLong: Bool { password.utf8.count > Self.passwordMaximumBytes }
    var confirmationMatches: Bool { !confirmation.isEmpty && confirmation == password }

    var isValid: Bool { usernameValid && displayNameValid && passwordValid && confirmationMatches }

    var showsUsernameError: Bool { !username.isEmpty && !usernameValid }
    var showsDisplayNameError: Bool { !displayNameValid }
    var showsPasswordError: Bool { !password.isEmpty && !passwordValid }
    var showsConfirmationError: Bool { !confirmation.isEmpty && !confirmationMatches }

    var usernameHint: String { .app("영문 소문자 · 숫자 · . _ -로 3~32자예요. 첫 글자는 영문이나 숫자예요.") }
    var displayNameHint: String {
        displayNameValid ? .app("비워 두면 아이디로 보여요.") : .app("표시 이름은 64자까지 쓸 수 있어요.")
    }
    var passwordHint: String {
        passwordTooLong ? .app("비밀번호가 너무 길어요. 영문 72자, 한글 24자까지 쓸 수 있어요.") : .app("8자 이상으로 정해 주세요.")
    }
    var confirmationHint: String? { showsConfirmationError ? .app("비밀번호가 서로 달라요.") : nil }
}

// MARK: - 실패 문구

/// 가입 실패를 사람이 읽을 문구로. 서버 오류 봉투(`APIClient`가 읽은 `error.code`)로 나눠요
enum SignUpFailure: Equatable {
    /// 409 `USERNAME_TAKEN` (대소문자 무시하고 같은 아이디)
    case usernameTaken
    /// 429 `RATE_LIMITED` (같은 IP에서 10분에 5번 넘게)
    case rateLimited
    /// 400 `VALIDATION_FAILED`
    case invalidInput
    /// 403 `FORBIDDEN` (서버가 가입을 꺼 둠). 가입 API가 아직 없는 서버(401 · 404)도 같은 안내예요
    case closed
    /// 서버에 닿지 못함
    case network
    case other(String)

    init(_ error: Error) {
        switch error as? APIError {
        case .server(_, "USERNAME_TAKEN", _, _), .server(409, _, _, _): self = .usernameTaken
        case .server(_, "RATE_LIMITED", _, _), .server(429, _, _, _): self = .rateLimited
        case .server(_, "VALIDATION_FAILED", _, _), .server(400, _, _, _): self = .invalidInput
        case .server(403, _, _, _), .server(401, _, _, _), .server(404, _, _, _): self = .closed
        case .transport: self = .network
        default: self = .other(error.localizedDescription)
        }
    }

    var title: String {
        self == .network ? .app("서버에 연결하지 못했어요") : .app("가입하지 못했어요")
    }

    var message: String {
        switch self {
        case .usernameTaken: .app("이미 사용 중인 아이디예요. 다른 아이디를 골라 주세요.")
        case .rateLimited: .app("가입 요청이 너무 많아요. 몇 분 뒤에 다시 시도해 주세요.")
        case .invalidInput: .app("아이디 · 비밀번호 · 표시 이름 형식을 확인해 주세요.")
        case .closed: .app("지금은 회원가입을 받지 않아요. 팀에 계정을 요청해 주세요.")
        case .network: .app("서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
        case .other(let message): message
        }
    }
}

// MARK: - 입력칸

/// 로그인 · 회원가입이 같이 쓰는 입력칸: 위에 이름, 채운 둥근 칸, 아래 작은 안내 (오류면 빨간 테두리 · 빨간 안내)
struct AuthField<Content: View>: View {
    let label: LocalizedStringKey
    var hint: String?
    var error = false
    @ViewBuilder let content: Content

    init(_ label: LocalizedStringKey, hint: String? = nil, error: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.error = error
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(error ? AnyShapeStyle(.red) : AnyShapeStyle(.separator), lineWidth: error ? 1 : 0.5))
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
