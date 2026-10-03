import { useState } from 'react'
import Button, { type ButtonVariant } from '../../components/Button.tsx'
import Checkbox from '../../components/Checkbox.tsx'
import EnvSelectCard from '../../components/EnvSelectCard.tsx'
import EnvTag from '../../components/EnvTag.tsx'
import type { EnvType } from '../../components/env.ts'
import Input from '../../components/Input.tsx'
import Logo from '../../components/Logo.tsx'
import MockBadge from '../../components/MockBadge.tsx'
import StatusBadge, { type StatusTone } from '../../components/StatusBadge.tsx'
import ThemeToggle from './ThemeToggle.tsx'
import './dev.css'

// 개발용 확인 페이지 (/dev/components) — Figma 「02 Core」와 눈으로 비교해요. 데모 화면이 아니에요.

const VARIANTS: ButtonVariant[] = ['primary', 'secondary', 'outline', 'ghost', 'destructive']
const TONES: StatusTone[] = ['queued', 'running', 'success', 'failed', 'warning', 'rolledback']
const ENVS: EnvType[] = ['onprem', 'aws', 'gcp', 'azure']

function ComponentsPage() {
  const [checked, setChecked] = useState(true)
  const [aws, setAws] = useState(false)
  const [gcp, setGcp] = useState(true)

  return (
    <main className="dev-page">
      <header className="dev-header">
        <h1 className="t-h1">Daisy DS · Core</h1>
        <ThemeToggle />
      </header>

      <section>
        <p className="t-overline t-muted">Button · Default / Disabled</p>
        <div className="dev-inline">
          {VARIANTS.map((v) => (
            <Button key={v} variant={v}>배포하기</Button>
          ))}
        </div>
        <div className="dev-inline">
          {VARIANTS.map((v) => (
            <Button key={v} variant={v} disabled>배포하기</Button>
          ))}
        </div>
        <div className="dev-inline">
          <Button variant="primary" size="lg">승인하고 배포</Button>
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Status Badge</p>
        <div className="dev-inline">
          {TONES.map((t) => (
            <StatusBadge key={t} tone={t} />
          ))}
          <StatusBadge tone="warning">일부 성공</StatusBadge>
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Env Tag</p>
        <div className="dev-inline">
          {ENVS.map((e) => (
            <EnvTag key={e} env={e} />
          ))}
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Input · Default / Error / Disabled (클릭하면 Focus)</p>
        <div className="dev-inline dev-inputs">
          <Input placeholder="https://github.com/team-daisy/sample-app" />
          <Input invalid defaultValue="https://github.com/team-daisy/sample-app" />
          <Input disabled defaultValue="https://github.com/team-daisy/sample-app" />
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Checkbox</p>
        <div className="dev-inline">
          <Checkbox checked={checked} onChange={(e) => setChecked(e.target.checked)}>체크</Checkbox>
          <Checkbox defaultChecked={false}>해제</Checkbox>
          <Checkbox disabled>비활성</Checkbox>
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Env Select Card · Off / On</p>
        <div className="dev-inline dev-cards">
          <EnvSelectCard
            env="aws"
            title="ECS Fargate · ap-northeast-2"
            description="컨테이너 서버리스 · 예상 월 ₩18,000"
            recommended
            selected={aws}
            onChange={setAws}
          />
          <EnvSelectCard
            env="gcp"
            title="Cloud Run · asia-northeast1"
            description="검증된 스크립트 재사용 · AI 호출 0회"
            selected={gcp}
            onChange={setGcp}
          />
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Logo · Mark / Lockup</p>
        <div className="dev-inline">
          <Logo type="mark" size={24} />
          <Logo type="mark" />
          <Logo type="mark" size={64} />
          <Logo type="lockup" />
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">MOCK 배지 (웹 전용)</p>
        <div className="dev-inline">
          <MockBadge />
        </div>
      </section>
    </main>
  )
}

export default ComponentsPage
