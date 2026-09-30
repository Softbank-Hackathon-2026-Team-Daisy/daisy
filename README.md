# Team Daisy — One Action, Infinite Clouds

**AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템**
SoftBank Hackathon 2026 in Korea 예선 (Term1)

배포 환경만 선택하면 AI가 환경별 인프라 코드(Terraform)를 생성·검증해서, 같은 애플리케이션을 온프레미스와 퍼블릭 클라우드에 동시에 배포해요.

```
main merge → GitHub Actions 이미지 빌드(커밋 해시 태그)
→ 환경 선택 (온프레미스 · AWS · GCP)
→ AI가 deploy.yaml로 환경별 Terraform 생성
→ validate · plan · 위험 설정 검사 (실패 시 AI 수정, 최대 3회)
→ plan 승인 → 환경별 병렬 apply
```

## 폴더

| 폴더 | 내용 | 담당 |
|---|---|---|
| `web/` | 웹 대시보드 (React + Vite) | 김도영 |
| `ios/` | Swift 앱 (승인 · 진행 상태 · 알림) | 박승준 |
| `server/` | 배포 서비스 API · AI · 검증 | 하은현, 김승환 |
| `infra/modules/` | 환경별 기준 Terraform 모듈 | 황지환(온프레미스), 임채준(GCP · AWS) |
| `docs/` | 아키텍처 그림, ADR 사본 | 전원 |

배포 대상 샘플 앱은 별도 레포(`sample-monolith`, `sample-msa`)에 있고, 이슈·PR 템플릿은 조직 공통 `.github` 레포에 있어요.

## 시작하기

- 작업 규칙: [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- AI 에이전트 공통 규칙: [`AGENTS.md`](./AGENTS.md) (영어 원문, 한국어 번역은 도입 PR 코멘트)
- 설계 문서 · 회의록 · ADR: 팀 Notion

## 팀

김도영(팀장 · Web) · 박승준(Swift 앱) · 하은현(BE) · 김승환(BE · AI) · 황지환(Infra · 온프레미스) · 임채준(Infra · 클라우드)
