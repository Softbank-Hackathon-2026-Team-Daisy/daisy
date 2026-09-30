import { Navigate, Route, Routes } from 'react-router'
import { MOCK_PROJECTS } from './mocks/workspace.ts'
import AppLayout from './pages/AppLayout.tsx'
import BuildPage from './pages/build/BuildPage.tsx'
import ApprovePage from './pages/approve/ApprovePage.tsx'
import ConnectPage from './pages/connect/ConnectPage.tsx'
import ProgressPage from './pages/deploy/ProgressPage.tsx'
import GeneratePage from './pages/generate/GeneratePage.tsx'
import LoginPage from './pages/login/LoginPage.tsx'
import OverviewPage from './pages/overview/OverviewPage.tsx'
import ResultPage from './pages/result/ResultPage.tsx'
import TargetsPage from './pages/targets/TargetsPage.tsx'
import ComponentsPage from './pages/dev/ComponentsPage.tsx'
import PrimitivesPage from './pages/dev/PrimitivesPage.tsx'
import TokensPage from './pages/dev/TokensPage.tsx'
import Placeholder from './pages/Placeholder.tsx'
import { paths } from './paths.ts'

// 화면 경로 (SPEC.md §2, 경로 함수는 paths.ts). 각 Placeholder는 화면을 만들면서 실제 페이지로 바꿔요
function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route element={<AppLayout />}>
        <Route path="/connect" element={<ConnectPage />} />
        <Route path="/projects/:projectId">
          <Route index element={<OverviewPage />} />
          <Route path="deploy/build" element={<BuildPage />} />
          <Route path="deploy/targets" element={<TargetsPage />} />
          <Route
            path="deployments/current"
            element={<Placeholder id="배포" title="진행 중인 배포" note="진행 중인 배포의 현재 단계(W-05 ~ W-08)로 보내요. 서버 API A-03이 열리면 연결해요." />}
          />
          <Route path="deployments/:deploymentId">
            <Route path="generate" element={<GeneratePage />} />
            <Route path="approve" element={<ApprovePage />} />
            <Route path="progress" element={<ProgressPage />} />
            <Route path="result" element={<ResultPage />} />
          </Route>
          <Route path="history" element={<Placeholder id="W-09" title="배포 이력 · 롤백" />} />
          <Route path="environments" element={<Placeholder id="W-10" title="환경" />} />
          <Route path="scripts" element={<Placeholder id="W-11" title="스크립트" />} />
          <Route path="ai-usage" element={<Placeholder id="W-12" title="AI 사용량" />} />
          <Route path="settings" element={<Placeholder id="W-13" title="설정" />} />
        </Route>
      </Route>

      {/* 개발용 확인 페이지 */}
      <Route path="/dev/tokens" element={<TokensPage />} />
      <Route path="/dev/components" element={<ComponentsPage />} />
      <Route path="/dev/primitives" element={<PrimitivesPage />} />

      {/* MOCK: 로그인 · 프로젝트 목록(A-01) 연결 전까지 첫 목업 프로젝트로 보내요 */}
      <Route path="*" element={<Navigate to={paths.overview(MOCK_PROJECTS[0].id)} replace />} />
    </Routes>
  )
}

export default App
