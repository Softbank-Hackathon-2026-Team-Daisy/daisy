# CLAUDE.md — infra/ (환경별 기준 Terraform 모듈)

> 담당: 황지환(온프레미스), 임채준(GCP · AWS) · 상태: **빈 틀 (D1 안에 담당 파트가 채워요)**
> 루트 `CLAUDE.md`의 공통 규칙을 먼저 따르고, 이 파일에는 **이 폴더에만 해당하는 규칙**만 적어요.

## 이 폴더가 하는 일
- modules/onprem: Docker 기준 모듈, 터널 외부 공개 (N-04)
- modules/gcp: Cloud Run 기준 모듈 (N-03)
- modules/aws: ECS · ALB · RDS 기준 모듈 (N-06)
- 환경별 state 분리·잠금 (N-07)
- 기준 모듈 = AI 생성의 정답 예시이자 N-02 실패 시 대안

## 기술 스택
- (예: 언어, 프레임워크, 주요 라이브러리 — 왜 골랐는지 한 줄)

## 폴더 구조
```
(작성)
```

## 컨벤션
- 이름 규칙:
- 파일 배치:
- 에러 처리:
- 테스트:

## 다른 파트와의 약속
- 모듈 입력 변수는 deploy.yaml 필드와 1:1로 맞춰요 (server 파트와 합의)
- 리전: AWS ap-northeast-2, GCP asia-northeast3 [미정]

## 실행 방법
```bash
(작성)
```

## AI 에이전트에게
- (이 폴더에서 AI가 꼭 지켜야 할 것, 하지 말아야 할 것)
