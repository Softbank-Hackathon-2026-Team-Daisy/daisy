import { Route, Routes } from 'react-router'
import TokensPage from './pages/dev/TokensPage.tsx'

// 화면 경로(W-00 ~ W-14, L-01 ~ L-03)와 사이드바 레이아웃은 Step 5에서 채워요
function App() {
  return (
    <Routes>
      <Route path="/dev/tokens" element={<TokensPage />} />
      <Route path="*" element={<p>Daisy</p>} />
    </Routes>
  )
}

export default App
