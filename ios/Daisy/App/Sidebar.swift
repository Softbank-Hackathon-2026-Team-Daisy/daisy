import SwiftUI

/// 넓은 화면의 길잡이. 구성과 문구는 웹 사이드바, 재질 · 행 · 움직임은 AfterPlan 사이드바를 따라요.
/// 위→아래: 로고 · 프로젝트 전환 · 새 배포 · PROJECT 메뉴 · ENVIRONMENTS · (여백) · AI 사용량 · 설정 · 연결 상태 · 사용자
struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @Namespace private var tint
    @State private var hovered: AppTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    logo
                    projectSwitcher
                    Button {
                        router.open(.newDeployment)
                    } label: {
                        Label("새 배포", systemImage: "plus")
                    }
                    .buttonStyle(.glassCapsule(fullWidth: true))
                    .disabled(app.isViewer || workspace.project == nil)
                    .help(app.isViewer ? "읽기 전용 계정이라 배포할 수 없어요" : "새 배포")

                    VStack(alignment: .leading, spacing: 2) {
                        overline("PROJECT")
                        ForEach(AppTab.projectMenu) { row($0) }
                    }
                    environments
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppTab.bottomMenu) { row($0) }
                Divider().padding(.vertical, 6)
                ConnectionIndicator(state: workspace.connection) {
                    Task { await workspace.refresh(using: app) }
                }
                .padding(.horizontal, 10)
                user
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        // 선 없음: 재질이 바뀌는 곳이 본문과의 경계예요.
        .background(SidebarBackground())
    }

    private var logo: some View {
        HStack(spacing: 10) {
            Image(.appLogo)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .clipShape(.rect(cornerRadius: 7))
                .accessibilityHidden(true)
            // 워드마크는 서비스 이름 "unibloom" 소문자 (10/1 이름 변경, 웹 Logo와 같아요)
            Text("unibloom").font(.system(size: 17, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    /// 웹 프로젝트 전환: 이름 · "main · a1b2c3d" · ⌄. 메뉴 끝에 "새 프로젝트 연결".
    private var projectSwitcher: some View {
        Menu {
            Section("PROJECTS") {
                ForEach(workspace.projects) { project in
                    Button {
                        app.selectedProjectID = project.id
                        Task { await workspace.refresh(using: app) }
                    } label: {
                        if project.id == app.selectedProjectID {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            }
            Divider()
            Button {
                router.open(.connectProject)
            } label: {
                Label("새 프로젝트 연결", systemImage: "plus")
            }
            .disabled(app.isViewer)
        } label: {
            HStack(spacing: 10) {
                Text(initials(workspace.project?.name))
                    .font(.caption.monospaced().weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(.fill.secondary, in: .rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.project?.name ?? "프로젝트 없음").font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(projectDetail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .contentShape(.rect)
            .glassSurface(in: .rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var projectDetail: String {
        let branch = workspace.project?.branch ?? "main"
        let commit = workspace.statuses.compactMap { $0.current?.commit }.first.map { String($0.prefix(7)) }
        return [branch, commit].compactMap { $0 }.joined(separator: " · ")
    }

    private func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "—" }
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters.joined()
    }

    private func overline(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced().weight(.semibold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func row(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        return HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 16))
                .frame(width: 22)
            Text(tab.title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
            Spacer(minLength: 0)
            if tab == .deployments, !workspace.awaitingApproval.isEmpty {
                Text("\(workspace.awaitingApproval.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .background(.fill.secondary, in: .capsule)
                    .accessibilityLabel("승인 대기 \(workspace.awaitingApproval.count)건")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.fill.tertiary)
                    .matchedGeometryEffect(id: "tint", in: tint)
            } else if hovered == tab {
                RoundedRectangle(cornerRadius: 8).fill(.fill.quinary)
            }
        }
        .contentShape(.rect)
        .onTapGesture { select(tab) }
        // 탭 제스처는 VoiceOver에 누르기 동작을 주지 않아서 따로 달아요.
        .accessibilityAction { select(tab) }
        .onHover { inside in hovered = inside ? tab : (hovered == tab ? nil : hovered) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(tab.title)
    }

    private func select(_ tab: AppTab) {
        withAnimation(spring) {
            if router.tab == tab { router.popToRoot() } else { router.tab = tab }
        }
    }

    /// 웹 ENVIRONMENTS: 환경 이름과 상태 (정상 · 이상)
    @ViewBuilder
    private var environments: some View {
        if !workspace.environments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                overline("ENVIRONMENTS")
                ForEach(workspace.environments) { environment in
                    HStack(spacing: 8) {
                        Image(systemName: environment.type.systemImage).font(.caption).frame(width: 22)
                        Text(environment.type == .unknown ? environment.name : environment.type.displayName)
                            .font(.subheadline)
                        Spacer(minLength: 4)
                        Circle().fill(color(environment.health)).frame(width: 6, height: 6)
                        Text(text(environment.health)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func text(_ health: Health) -> String {
        switch health {
        case .healthy: "정상"
        case .unhealthy: "이상"
        case .unknown: "확인 전"
        }
    }

    private func color(_ health: Health) -> Color {
        switch health {
        case .healthy: .green
        case .unhealthy: .red
        case .unknown: .gray
        }
    }

    /// 웹 사용자 줄: 아바타 · 이름 · 역할
    private var user: some View {
        HStack(spacing: 10) {
            Avatar(name: app.username)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.username ?? "로그인됨").font(.subheadline.weight(.medium)).lineLimit(1)
                Text(app.isSampleMode ? "예시 데이터 · 읽기 전용" : app.isViewer ? "읽기 전용" : "팀 계정").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}
