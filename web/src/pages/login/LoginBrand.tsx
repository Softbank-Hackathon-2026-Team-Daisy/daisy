import Logo from '../../components/Logo.tsx'
import { t } from '../../i18n/index.ts'

// 로그인 · 회원가입 왼쪽 브랜드 영역 (900px 아래에서는 숨겨요)
function LoginBrand() {
  return (
    <section className="login__brand">
      <Logo type="mark" size={176} />
      <div className="login__slogan">
        <p className="t-overline t-muted">One action, infinite clouds</p>
        <h2 className="t-h1">{t('환경만 고르면, 어디든 같은 상태로')}</h2>
        <p className="t-body-sm t-muted">{t('AI가 환경별 인프라 코드를 만들고 검증해서 온프레미스와 퍼블릭 클라우드에 동시에 배포해요.')}</p>
      </div>
    </section>
  )
}

export default LoginBrand
