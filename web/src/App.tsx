import { Route, Routes } from 'react-router'
import ComponentsPage from './pages/dev/ComponentsPage.tsx'
import PrimitivesPage from './pages/dev/PrimitivesPage.tsx'
import TokensPage from './pages/dev/TokensPage.tsx'

// 화면 경로(W-00 ~ W-14, L-01 ~ L-03)와 사이드바 레이아웃은 Step 5에서 채워요
function App() {
  return (
    <Routes>
      <Route path="/dev/tokens" element={<TokensPage />} />
      <Route path="/dev/components" element={<ComponentsPage />} />
      <Route path="/dev/primitives" element={<PrimitivesPage />} />
      <Route path="*" element={<p>Daisy</p>} />
    </Routes>
  )
}

export default App
