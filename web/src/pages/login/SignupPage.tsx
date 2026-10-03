import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { ApiError, USE_MOCK } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import Input from '../../components/Input.tsx'
import LanguageSelect from '../../components/LanguageSelect.tsx'
import Logo from '../../components/Logo.tsx'
import MockBadge from '../../components/MockBadge.tsx'
import { t } from '../../i18n/index.ts'
import LoginBrand from './LoginBrand.tsx'
import './LoginPage.css'

// 회원가입 (R-02b POST /auth/signup, #111 · #114). 규칙 · 오류 문구는 앱 SignUpView와 같아요
// 성공하면 201 본문이 /auth/token과 같아서 로그인과 똑같이 signIn → 바로 들어가요
const USERNAME_RULE = /^[a-z0-9][a-z0-9._-]{2,31}$/

type Field = 'username' | 'displayName' | 'password' | 'confirm'
type Values = Record<Field, string>

// 서버와 같은 규칙 — 아이디는 앞뒤 공백을 빼고 소문자로 봐요 (서버도 그렇게 저장해요)
function check(v: Values): Partial<Record<Field, string>> {
  const errors: Partial<Record<Field, string>> = {}
  const username = v.username.trim().toLowerCase()
  if (!USERNAME_RULE.test(username)) errors.username = t('영문 소문자 · 숫자로 시작하고, 영문 소문자 · 숫자 · . _ - 로 3~32자예요.')
  if (v.displayName.trim().length > 64) errors.displayName = t('표시 이름은 64자까지 쓸 수 있어요.')
  if (v.password.length < 8 || !v.password.trim()) errors.password = t('비밀번호는 8자 이상이에요.')
  else if (v.password.length > 200) errors.password = t('비밀번호는 200자까지 쓸 수 있어요.')
  if (v.confirm !== v.password) errors.confirm = t('비밀번호가 서로 달라요.')
  return errors
}

function failureMessage(e: unknown): { network: boolean; message: string; taken?: boolean } {
  if (e instanceof ApiError) {
    if (e.code === 'NETWORK') return { network: true, message: t('서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.') }
    if (e.code === 'USERNAME_TAKEN' || e.status === 409)
      return { network: false, taken: true, message: t('이미 사용 중인 아이디예요. 다른 아이디를 골라 주세요.') }
    if (e.code === 'RATE_LIMITED' || e.status === 429) return { network: false, message: t('가입 요청이 너무 많아요. 몇 분 뒤에 다시 시도해 주세요.') }
    if (e.code === 'VALIDATION_FAILED' || e.status === 400) return { network: false, message: t('아이디 · 비밀번호 · 표시 이름 형식을 확인해 주세요.') }
    // 403 = 가입 꺼짐, 401 · 404 = 가입 API가 없는 서버 (앱과 같은 안내)
    if ([401, 403, 404].includes(e.status)) return { network: false, message: t('지금은 회원가입을 받지 않아요. 팀에 계정을 요청해 주세요.') }
  }
  return { network: false, message: e instanceof Error ? e.message : t('가입하지 못했어요') }
}

function SignupPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const { signIn } = useAuth()
  const [values, setValues] = useState<Values>({ username: '', displayName: '', password: '', confirm: '' })
  // 입력을 마친 칸(blur)과 제출 뒤에만 빨갛게 — 치는 도중에는 안내만 보여요
  const [touched, setTouched] = useState<Partial<Record<Field, boolean>>>({})
  const [submitted, setSubmitted] = useState(false)
  const [failure, setFailure] = useState<ReturnType<typeof failureMessage> | null>(null)
  const [pending, setPending] = useState(false)

  const errors = check(values)
  const shown = (f: Field) => (submitted || touched[f] ? errors[f] : undefined)
  const next = params.get('next')
  const loginHref = next ? `/login?next=${encodeURIComponent(next)}` : '/login'

  const set = (f: Field) => (e: { target: { value: string } }) => {
    setValues((v) => ({ ...v, [f]: e.target.value }))
    if (f === 'username' && failure?.taken) setFailure(null)
  }
  const blur = (f: Field) => () => setTouched((x) => ({ ...x, [f]: true }))

  const onSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setSubmitted(true)
    if (Object.keys(errors).length > 0) return
    setPending(true)
    setFailure(null)
    try {
      signIn(await api.signup(values.username.trim().toLowerCase(), values.password, values.displayName.trim() || undefined))
      navigate(next ?? '/', { replace: true })
    } catch (err) {
      setFailure(failureMessage(err))
    } finally {
      setPending(false)
    }
  }

  const hint = (f: Field, text: string) => {
    const error = shown(f) ?? (f === 'username' && failure?.taken ? t('이미 사용 중인 아이디예요.') : undefined)
    return (
      <span id={`signup-${f}-hint`} className={`t-body-sm ${error ? 'login__hint--error' : 't-muted'}`}>
        {error ?? text}
      </span>
    )
  }

  return (
    <div className="login">
      <LoginBrand />

      <section className="login__form-area">
        <div className="login__lang">
          <LanguageSelect />
        </div>
        <form className="login__form" onSubmit={(e) => void onSubmit(e)} noValidate>
          <Logo type="lockup" color="ink" />
          <div className="login__heading">
            <h1 className="t-h1">{t('회원가입')}</h1>
            <p className="t-muted">{t('새 계정을 만들어요. 가입하면 바로 로그인돼요.')}</p>
          </div>

          {failure && !failure.taken && (
            <Alert type="danger" title={failure.network ? t('서버에 연결하지 못했어요') : t('가입하지 못했어요')}>
              {failure.message}
            </Alert>
          )}

          <div className="login__fields">
            <label className="login__field">
              <span className="t-label">{t('아이디')}</span>
              <Input
                name="username"
                autoComplete="username"
                autoCapitalize="none"
                spellCheck={false}
                value={values.username}
                onChange={set('username')}
                onBlur={blur('username')}
                invalid={!!shown('username') || !!failure?.taken}
                aria-describedby="signup-username-hint"
                required
              />
              {hint('username', t('영문 소문자 · 숫자로 시작하고, 영문 소문자 · 숫자 · . _ - 로 3~32자예요.'))}
            </label>
            <label className="login__field">
              <span className="t-label">{t('표시 이름 (선택)')}</span>
              <Input
                name="display_name"
                autoComplete="nickname"
                value={values.displayName}
                onChange={set('displayName')}
                onBlur={blur('displayName')}
                invalid={!!shown('displayName')}
                aria-describedby="signup-displayName-hint"
              />
              {hint('displayName', t('비워 두면 아이디로 보여요.'))}
            </label>
            <label className="login__field">
              <span className="t-label">{t('비밀번호')}</span>
              <Input
                name="password"
                type="password"
                autoComplete="new-password"
                value={values.password}
                onChange={set('password')}
                onBlur={blur('password')}
                invalid={!!shown('password')}
                aria-describedby="signup-password-hint"
                required
              />
              {hint('password', t('비밀번호는 8자 이상이에요.'))}
            </label>
            <label className="login__field">
              <span className="t-label">{t('비밀번호 확인')}</span>
              <Input
                name="password_confirm"
                type="password"
                autoComplete="new-password"
                value={values.confirm}
                onChange={set('confirm')}
                onBlur={blur('confirm')}
                invalid={!!shown('confirm')}
                aria-describedby="signup-confirm-hint"
                required
              />
              {shown('confirm') && hint('confirm', '')}
            </label>
          </div>

          <Button type="submit" variant="secondary" className="login__full" disabled={pending}>
            {pending ? t('가입하는 중…') : t('가입하기')}
          </Button>

          <p className="login__switch t-body-sm">
            <span className="t-muted">{t('이미 계정이 있나요?')}</span>
            <Link to={loginHref} className="login__link">
              {t('로그인')}
            </Link>
          </p>

          {USE_MOCK && (
            <p className="login__mock t-body-sm t-muted">
              <MockBadge note={t('목업 회원가입이에요. 서버에 계정이 만들어지지 않아요')} />
            </p>
          )}
        </form>
      </section>
    </div>
  )
}

export default SignupPage
