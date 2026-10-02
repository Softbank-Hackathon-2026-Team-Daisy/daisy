import { Route, Routes } from 'react-router'
import AppLayout from './pages/AppLayout.tsx'
import FirstProject from './pages/FirstProject.tsx'
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
import { useLang } from './i18n/index.ts'

// 화면 경로 (SPEC.md §2, 경로 함수는 paths.ts)
function App() {
  // 언어를 바꾸면 화면 전체를 새 언어로 다시 그려요. 로그인(AuthProvider)은 바깥이라 그대로 남아요 (#75)
  const lang = useLang()
  return (
    <Routes key={lang}>
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

      {/* 프로젝트를 정하지 않은 주소는 프로젝트 목록(A-01)의 첫 프로젝트로 */}
      <Route element={<AppLayout />}>
        <Route path="*" element={<FirstProject />} />
      </Route>
    </Routes>
  )
}

export default App
