import { useState, type FormEvent } from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { ApiError, USE_MOCK } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import Icon from '../../components/Icon.tsx'
import InfraBlock from '../../components/InfraBlock.tsx'
import LanguageSelect from '../../components/LanguageSelect.tsx'
import Input from '../../components/Input.tsx'
import Logo from '../../components/Logo.tsx'
import MockBadge from '../../components/MockBadge.tsx'
import { t } from '../../i18n/index.ts'
import MacAppDialog from '../app-download/MacAppDialog.tsx'
import './LoginPage.css'

// W-00 로그인 · W-00b 실패. Bearer 토큰 하나(R-01 · R-02), GitHub 로그인은 넣지 않아요
type Failure = { kind: 'auth' | 'network' | 'other'; message: string } | null

function LoginPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const { signIn } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [failure, setFailure] = useState<Failure>(null)
  const [pending, setPending] = useState(false)
  const [macAppOpen, setMacAppOpen] = useState(false)
  const expired = params.get('expired') === '1' && !failure

  // 로그인 후 첫 화면 — 원래 가려던 화면, 없으면 첫 프로젝트(FirstProject)
  const goNext = () => navigate(params.get('next') ?? '/', { replace: true })

  const run = async (login: () => ReturnType<typeof api.login>) => {
    setPending(true)
    setFailure(null)
    try {
      signIn(await login())
      goNext()
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        setFailure({ kind: 'auth', message: t('아이디 또는 비밀번호가 맞지 않아요. 다시 확인해 주세요.') })
        setPassword('')
      } else if (e instanceof ApiError && e.code === 'NETWORK') {
        setFailure({ kind: 'network', message: t('서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.') })
      } else {
        setFailure({ kind: 'other', message: e instanceof Error ? e.message : t('로그인하지 못했어요.') })
      }
    } finally {
      setPending(false)
    }
  }

  const onSubmit = (e: FormEvent) => {
    e.preventDefault()
    void run(() => api.login(username, password))
  }

  return (
    <div className="login">
      <section className="login__brand">
        <InfraBlock stack={3} />
        <div className="login__slogan">
          <p className="t-overline t-muted">One action, infinite clouds</p>
          <h2 className="t-h1">{t('환경만 고르면, 어디든 같은 상태로')}</h2>
          <p className="t-body-sm t-muted">{t('AI가 환경별 인프라 코드를 만들고 검증해서 온프레미스와 퍼블릭 클라우드에 동시에 배포해요.')}</p>
        </div>
      </section>

      <section className="login__form-area">
        {/* 로그인 전에도 언어를 바꿀 수 있게 (#75) */}
        <div className="login__lang">
          <LanguageSelect />
        </div>
        <form className="login__form" onSubmit={onSubmit} noValidate>
          <Logo type="lockup" color="ink" />
          <div className="login__heading">
            <h1 className="t-h1">{t('로그인')}</h1>
            <p className="t-muted">{t('팀 계정으로 로그인해요.')}</p>
          </div>

          {failure && (
            <Alert type="danger" title={failure.kind === 'network' ? t('서버에 연결하지 못했어요') : t('로그인하지 못했어요')}>
              {failure.message}
            </Alert>
          )}
          {expired && <Alert type="info" title={t('다시 로그인해 주세요')}>{t('로그인이 만료됐어요.')}</Alert>}

          <div className="login__fields">
            <label className="login__field">
              <span className="t-label">{t('아이디')}</span>
              <Input
                name="username"
                autoComplete="username"
                placeholder="doyoung@teamdaisy.dev"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
              />
            </label>
            <label className="login__field">
              <span className="t-label">{t('비밀번호')}</span>
              <Input
                name="password"
                type="password"
                autoComplete="current-password"
                value={password}
                invalid={failure?.kind === 'auth'}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </label>
          </div>

          <Button type="submit" variant="secondary" className="login__full" disabled={pending || !username || !password}>
            {pending ? t('로그인하는 중…') : t('로그인')}
          </Button>

          <div className="login__or">
            <span />
            <span className="t-mono-sm t-muted">{t('또는')}</span>
            <span />
          </div>

          <Button variant="outline" className="login__full" disabled={pending} onClick={() => void run(api.loginDemo)}>
            {t('데모 계정으로 둘러보기 (읽기 전용)')}
          </Button>

          <p className="login__mac t-body-sm">
            <Icon name="download" size={16} />
            <span className="t-muted">{t('승인 알림은 Mac 앱으로 받아요 ·')}</span>
            <button type="button" className="login__link" onClick={() => setMacAppOpen(true)}>
              {t('Mac 앱 다운로드')}
            </button>
          </p>

          <p className="t-mono-sm t-muted">SoftBank Hackathon 2026 · Team Daisy</p>

          {USE_MOCK && (
            <p className="login__mock t-body-sm t-muted">
              <MockBadge note={t('서버 인증(R-02)이 열리기 전 목업 로그인이에요')} />
              {/* 비밀번호만 코드 모양으로 — 번역문을 {pw} 자리에서 나눠요 */}
              {t('비밀번호 {pw}로 로그인해요').split('{pw}')[0]}
              <code>daisy</code>
              {t('비밀번호 {pw}로 로그인해요').split('{pw}')[1]}
            </p>
          )}
        </form>
      </section>

      <MacAppDialog open={macAppOpen} onClose={() => setMacAppOpen(false)} />
    </div>
  )
}

export default LoginPage
