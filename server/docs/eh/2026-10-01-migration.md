# 10월 1일 V1 Flyway 마이그레이션

## 작업 범위

- `database-design.md` 의 17개 테이블과 `domain` 패키지 엔티티에 맞는 초기 마이그레이션 `V1__init.sql` 을 추가했어요.
- 설계 문서의 FK·CHECK·부분 UNIQUE·인덱스·기본값을 DB 에 구현했어요. 엔티티의 JPA 매핑이 DB 무결성을 대신하지 않아서예요.
- 규모는 17개 테이블, FK 47개(인라인 42 · 순환 해소용 `ALTER` 5), CHECK 51개, 부분 UNIQUE 5개, 그 밖의 인덱스 28개예요.
- PR #32 리뷰(승환)를 반영했어요. 반영 내용은 아래 「PR #32 리뷰 반영」에 있어요.
- 테이블·컬럼 정의는 승환이 작성한 설계와 엔티티를 기준으로 했어요. 컬럼을 새로 만들거나 이름을 바꾸지 않았어요.
- 업무 API·시드 데이터·운영 스크립트는 넣지 않았어요.
- 구현은 Claude Opus 5 로 했고, 검증 명령과 결과는 아래에 그대로 적었어요.

## 설계 이유

- **복합 FK 로 프로젝트 소속을 DB 가 직접 봐요.** `(source_version_id, project_id) → source_version(id, project_id)` 처럼 둘을 함께 참조해요. 단일 FK 로는 다른 프로젝트의 소스·대상이 섞여도 막지 못해요. 이 서비스에서 그건 남의 환경에 `terraform apply` 를 거는 일이라 애플리케이션 검증만으로 두지 않았어요.
- **순환 FK 는 테이블을 먼저 만들고 파일 끝에서 `ALTER` 로 붙여요.** `target ↔ deployment_target`, `deployment_target ↔ script`·`plan_revision`·`execution_target`, `execution_target ↔ plan_revision` **다섯 건**이에요. 설계 §7 의 저장 순서를 따랐어요.
- **삭제 CASCADE 를 두지 않았어요.** 설계 §4 대로 `RESTRICT` 기본이고 보관은 `archived_at`·`disabled_at` 으로 해요. 배포 이력을 지우는 경로를 DB 가 열어 주지 않는 쪽이 맞다고 봤어요.
- **enum 은 `varchar` + CHECK 예요.** PostgreSQL enum 타입은 값을 추가할 때 마이그레이션이 필요해서 설계 §4 대로 피했어요.
- **부분 UNIQUE 로 "살아 있는 것은 하나" 를 강제해요.** 대상별 `state=active` plan 하나, `state=pending` 승인 하나, run 당 log owner 하나예요. 애플리케이션 경합으로는 이 불변 조건을 지키기 어려워요.
- **시간 조건은 인덱스에 넣지 않았어요.** `expires_at > now()` 같은 조건은 PostgreSQL 이 인덱스 조건으로 받지 않아요(`functions in index predicate must be marked IMMUTABLE`). 만료된 `pending` 승인을 `expired` 로 내리는 일은 서비스가 해야 해요.

## 인계와 제한

- **만료된 승인을 상태 전환하지 않으면 다음 승인이 막혀요.** 부분 UNIQUE 가 `state='pending'` 조건이라, 새 승인을 만들 때 같은 트랜잭션에서 기존 만료 건을 내려야 해요. 실행 서비스 쪽에서 챙겨 주세요.
- **FK 걸린 컬럼 중 인덱스가 없는 곳이 36개예요.** 검사 T17 에 목록이 있어요. 예선 데이터 규모에서는 문제가 아니라고 보고 넣지 않았어요. 삭제·조인이 느려지면 그때 추가하면 돼요.
- **값 목록이 열려 있는 컬럼에는 CHECK 를 걸지 않았어요.** 설계가 "등" 으로 적은 `ai_usage.step`·`idempotency.operation`·`invalidation_reason` 이에요. `ai_usage.cost_basis`(reported/estimated)도 설계의 CHECK 목록(`database-design.md:543`)에 없어서 값 CHECK 는 넣지 않고, `cost_usd` 와 함께 있는지만 봐요.
- **`destroy` 는 넣지 않았어요.** 전체 삭제 지원 범위가 정해지면 배포 종류와 lineage 규칙을 함께 추가하기로 했어요 (PR #32).
- **DB 제약만 확인했어요.** 실제 배포 흐름·동시성·Jenkins 연동·SSE 재생은 이번 검증 범위가 아니에요.
- `source_version` 은 `(project_id, commit_sha)` 가 UNIQUE 가 아니에요. 같은 커밋 재빌드를 새 행으로 보존하는 설계 5.5 를 그대로 따랐어요. 웹·앱이 커밋을 키로 쓰고 있어서 소비자 계약 확인이 필요하다고 PR #19 에 적어 뒀어요.
## PR #32 리뷰 반영

공용 DB 에 이 V1 이 적용된 적이 없어서 V2 를 만들지 않고 V1 을 고쳤어요.

| 리뷰 | 반영 |
|---|---|
| ① `ai_usage` 범위·비용 | `ck_ai_attempt`(1~3, 생성·수정 회차), `ck_ai_cost_sign`(`cost_usd ≥ 0`), `ck_ai_cost_pair`(`cost_usd`·`cost_basis` 함께 NULL/존재) |
| ① `execution_target` plan 짝 | `ck_et_plan_pair`(`plan_id`·`plan_digest` 함께 NULL/존재) |
| ② 결정 정보 없는 승인 | `ck_approval_state_decision` 을 `decision IS NOT NULL AND decision = state` 로 고쳤어요. `decided_by`·`decided_at` 은 기존 `ck_approval_decision_triple` 이 `decision` 과 함께 묶어요. 검사 T18 로 막히는 것을 확인했어요 |
| ③ 검증 스크립트 | 검사마다 예상(막힘/통과)과 실제를 비교해 하나라도 다르면 exit 1 이에요. 경로는 POSIX 로 쓰고 윈도우에서만 `cygpath` 로 바꿔요. 컨테이너 이름에 PID 를 붙이고, 스크립트가 만든 컨테이너만 지워요 |
| ④ 중복 인덱스 | `ix_dt_by_dep`(`uq_dt_natural` 선두 컬럼과 같음)·`ix_dl_replay`(`uq_dl_seq` 와 같음)·`ix_pe_replay`(`uq_pe_seq` 와 같음) 3개를 지웠어요 |
| ④ 스크립트 재사용 인덱스 | `ix_script_reuse` 를 `(project_id, target_id, validated_at DESC)` 로 바꿨어요 |
| ④ 기본값 | 설계 표에 기본값이 적힌 컬럼 전부(`now()`, `deploy.yaml`, 상태 문자열)에 DB 기본값을 붙였어요 |
| ④ 상태 CHECK | `ck_target_env`(onprem/aws/gcp), `ck_target_conn`(unknown/connected/disconnected), `ck_sv_status`(pending/running/succeeded/failed) |
| ④ 역할 | `ck_account_role`(owner/viewer). 인증 브랜치의 데모 계정이 쓰는 두 값이에요 |
| `invalidated` | `ck_plan_state` 를 설계의 세 값(active/superseded/expired)으로 되돌렸어요. 무효화는 `invalidated_at`·`invalidation_reason` 으로 남겨요 |

리뷰 밖에서 하나 더 고쳤어요. 설계 문서와 DB 를 스크립트로 대조하다 `ai_usage` 인덱스가 설계(`database-design.md:543`)와 다른 것을 찾았어요. `(deployment_target_id, occurred_at)` 하나뿐이던 것을 설계대로 `(deployment_target_id, occurred_at, id)` 와 `(execution_id)` 두 개로 맞췄어요.

## 검증 결과

- **빈 PostgreSQL 17 에 이 브랜치를 jar 로 실제로 띄워서 확인했어요.** 엔티티와 컬럼이 어긋나면 여기서 기동이 실패해요.

  ```
  Flyway     Migrating schema "public" to version "1 - init"
             Successfully applied 1 migration
  Hibernate  ddl-auto=validate 통과 (검증 오류 없음)
  Started DaisyServerApplication in 9.047 seconds
  ```

- **설계 문서와 DB 를 스크립트로 대조했어요.** Flyway 로 올린 DB 의 카탈로그를 `database-design.md` 의 표와 비교했어요.
  - 기본값: 설계 표에 기본값이 적힌 컬럼 전부 일치
  - 값 목록: 설계가 닫힌 목록으로 적은 상태 컬럼 14개 전부 CHECK 와 일치
  - 인덱스·UNIQUE: 위의 `ai_usage` 를 고친 뒤 전부 일치. 설계의 `deployment_target INDEX(deployment_id)` 만 `uq_dt_natural` 로 대신해요 (중복 인덱스 제거)
- 제약 검사 27건을 자동 판정으로 돌렸어요. `bash server/docs/eh/sql/verify.sh` 로 재현할 수 있고, 하나라도 예상과 다르면 exit 1 이에요. **`verify.sh` 는 Flyway 를 쓰지 않고 `psql` 로 DDL 을 직접 올려요.** 위 기동 확인은 `verify.sh` 로는 재현되지 않아요.
- **판정 장치 자체도 시험했어요.** `ck_approval_state_decision` 을 예전(뚫린) 형태로 되돌리면 T18 이 FAIL 하고 exit 1 이 나는 것을 확인한 뒤 원래대로 돌렸어요.

  | | 검사 | 예상 |
  |---|---|---|
  | T1·T2 | 다른 프로젝트의 `source_version`·`target` 을 배포에 붙이기 | 막힘 |
  | T3 | 자기 자신을 되돌리는 배포 | 막힘 |
  | T4·T5 | `kind` 와 lineage 조합 불일치 | 막힘 |
  | T6 | 한 배포에 같은 `state_identity` 대상 두 개 | 막힘 |
  | T7 | 한 배포에 같은 대상 두 번 | 막힘 |
  | T8·T9 | `attempt=4` · 취소 요청자만 있고 시각 없음 | 막힘 |
  | T10·T11 | 살아 있는 plan·승인 두 개 | 막힘 |
  | T12 | `state=approved` 인데 `decision=rejected` | 막힘 |
  | T13 | 만료 승인을 `expired` 로 내린 뒤 새 승인 | 통과 |
  | T14 | 같은 `state_identity` 락 2건 | 막힘 |
  | T15·T16 | `seq=0` · 같은 멱등 scope·키 두 번 | 막힘 |
  | T18 | `state=approved` 인데 결정 3종이 모두 NULL (리뷰 ②) | 막힘 |
  | T19·T20 | `ai_usage.attempt` 0 · 4 | 막힘 |
  | T21·T22 | `cost_usd` 음수 · `cost_basis` 없이 `cost_usd` 만 | 막힘 |
  | T23 | `plan_id` 만 있고 `plan_digest` 없음 | 막힘 |
  | T24~T26 | `role`·`environment_type`·`source_version.status` 가 목록 밖 | 막힘 |
  | T27 | `plan_revision.state = 'invalidated'` | 막힘 |
  | T28 | 설계 기본값 14개가 실제로 붙어 있음 | 통과 |
  | T17 | FK 걸린 컬럼 중 인덱스 없는 곳 (판정 안 함) | 목록 36개 출력 |

- 테이블 17개가 생성되는 것과 Flyway 버전이 `v1` 인 것을 확인했어요.
- **검사 항목을 먼저 적고 그대로 돌렸어요.** 항목에 없는 실패 모드는 확인하지 않은 거예요.
