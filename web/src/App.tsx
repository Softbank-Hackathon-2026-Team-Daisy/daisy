import { Navigate, Route, Routes } from 'react-router'
import { MOCK_PROJECTS } from './mocks/workspace.ts'
import AppLayout from './pages/AppLayout.tsx'
import ComponentsPage from './pages/dev/ComponentsPage.tsx'
import PrimitivesPage from './pages/dev/PrimitivesPage.tsx'
import TokensPage from './pages/dev/TokensPage.tsx'
import Placeholder from './pages/Placeholder.tsx'
import { paths } from './paths.ts'

// 화면 경로 (SPEC.md §2, 경로 함수는 paths.ts). 각 Placeholder는 화면을 만들면서 실제 페이지로 바꿔요
function App() {
  return (
    <Routes>
      <Route path="/login" element={<Placeholder id="W-00 · W-00b" title="로그인" />} />

      <Route element={<AppLayout />}>
        <Route path="/connect" element={<Placeholder id="W-02 · STEP 1" title="애플리케이션 연결" />} />
        <Route path="/projects/:projectId">
          <Route index element={<Placeholder id="W-01" title="개요" />} />
          <Route path="deploy/build" element={<Placeholder id="W-03 · STEP 2" title="이미지 빌드" note="전환 로딩 L-01(W-02 → W-03)은 이 화면으로 들어올 때 띄워요." />} />
          <Route path="deploy/targets" element={<Placeholder id="W-04 · STEP 3" title="배포할 환경 선택" />} />
          <Route
            path="deployments/current"
            element={<Placeholder id="배포" title="진행 중인 배포" note="진행 중인 배포의 현재 단계(W-05 ~ W-08)로 보내요. 서버 API A-03이 열리면 연결해요." />}
          />
          <Route path="deployments/:deploymentId">
            <Route path="generate" element={<Placeholder id="W-05 · W-05b · STEP 4" title="인프라 코드 생성 · 검증" note="전환 로딩 L-02(W-04 → W-05)는 이 화면으로 들어올 때 띄워요." />} />
            <Route path="approve" element={<Placeholder id="W-06 · STEP 5" title="변경 사항 확인 후 승인" />} />
            <Route path="progress" element={<Placeholder id="W-07 · STEP 5" title="배포 중" note="전환 로딩 L-03(W-06 → W-07)은 이 화면으로 들어올 때 띄워요." />} />
            <Route path="result" element={<Placeholder id="W-08 · STEP 6" title="배포 결과" />} />
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
