import { Navigate, Route, Routes } from 'react-router'
import { MOCK_PROJECTS } from './mocks/workspace.ts'
import AppLayout from './pages/AppLayout.tsx'
import BuildPage from './pages/image-build/BuildPage.tsx'
import AiUsagePage from './pages/ai-usage/AiUsagePage.tsx'
import ApprovePage from './pages/approve/ApprovePage.tsx'
import ConnectPage from './pages/connect/ConnectPage.tsx'
import CurrentDeployment from './pages/deploy/CurrentDeployment.tsx'
import ProgressPage from './pages/deploy/ProgressPage.tsx'
import EnvironmentsPage from './pages/environments/EnvironmentsPage.tsx'
import GeneratePage from './pages/generate/GeneratePage.tsx'
import HistoryPage from './pages/history/HistoryPage.tsx'
import LoginPage from './pages/login/LoginPage.tsx'
import OverviewPage from './pages/overview/OverviewPage.tsx'
import ResultPage from './pages/result/ResultPage.tsx'
import ScriptsPage from './pages/scripts/ScriptsPage.tsx'
import SettingsPage from './pages/settings/SettingsPage.tsx'
import TargetsPage from './pages/targets/TargetsPage.tsx'
import ComponentsPage from './pages/dev/ComponentsPage.tsx'
import PrimitivesPage from './pages/dev/PrimitivesPage.tsx'
import TokensPage from './pages/dev/TokensPage.tsx'
import { paths } from './paths.ts'

// 화면 경로 (SPEC.md §2, 경로 함수는 paths.ts)
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
          <Route path="deployments/current" element={<CurrentDeployment />} />
          <Route path="deployments/:deploymentId">
            <Route path="generate" element={<GeneratePage />} />
            <Route path="approve" element={<ApprovePage />} />
            <Route path="progress" element={<ProgressPage />} />
            <Route path="result" element={<ResultPage />} />
          </Route>
          <Route path="history" element={<HistoryPage />} />
          <Route path="environments" element={<EnvironmentsPage />} />
          <Route path="scripts" element={<ScriptsPage />} />
          <Route path="ai-usage" element={<AiUsagePage />} />
          <Route path="settings" element={<SettingsPage />} />
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
