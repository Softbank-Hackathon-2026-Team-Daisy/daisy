# 10월 1일 V1 Flyway 마이그레이션

## 작업 범위

- `database-design.md` 의 17개 테이블과 `domain` 패키지 엔티티에 맞는 초기 마이그레이션 `V1__init.sql` 을 추가했어요.
- 설계 문서의 FK·CHECK·부분 UNIQUE·인덱스를 DB 제약으로 구현했어요. 엔티티의 JPA 매핑이 DB 무결성을 대신하지 않아서예요. **다만 설계가 적은 제약 중 아직 안 넣은 것이 있어요. 「인계와 제한」에 전부 적었어요.**
- 규모는 17개 테이블, FK 47개(인라인 42 · 순환 해소용 `ALTER` 5), 부분 UNIQUE 5개, 그 밖의 인덱스 30개예요.
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
- **설계 문서에 있는데 V1 에 안 넣은 제약이 있어요.** 자체 대조에서 찾았고, 숨기지 않고 적어요. 넣는 게 맞다고 보시면 V2 로 올리거나 이 PR 에서 고칠게요.

  | 설계 | V1 상태 |
  |---|---|
  | `account.role` CHECK (`database-design.md:236`) | **없어요.** 설계가 "은현이 확정한 역할 목록에 맞춘다" 로 유보해 둔 항목이라 비워 뒀는데, 지금 코드는 `owner`·`viewer` 를 쓰고 있어요. 값을 확정하고 CHECK 를 넣는 게 맞다고 봐요 |
  | `ai_usage.attempt BETWEEN 1 AND 3` | 없어요. `deployment_target.attempt` 에는 `ck_dt_attempt` 로 넣었는데 여기만 빠졌어요 |
  | `ai_usage` 의 `cost_usd`·`cost_basis` 동반 NULL/존재 | 없어요 |
  | `execution_target` 의 `plan_id`·`plan_digest` 동반 NULL/존재 | 없어요 |
  | `target.environment_type`·`connection_state`, `source_version.status` CHECK | 없어요. 다른 상태 컬럼에는 CHECK 를 걸어서 기준이 일관되지 않아요 |
  | `now()` 기본값 (`created_at` 류 12곳), `project.manifest_path='deploy.yaml'`, 상태 문자열 기본값 | 없어요. 엔티티가 항상 값을 채워서 런타임 영향은 없지만 설계와는 달라요 |
  | `script` 의 `(project_id, target_id, validated_at DESC)` 인덱스 | 대신 `version DESC` 로 넣었는데, 바로 위 `uq_script_version` 과 컬럼이 같아 중복이에요 |

- **설계에 없는 값을 하나 더 넣었어요.** `plan_revision.state` CHECK 에 `invalidated` 를 추가했어요 (설계는 `active/superseded/expired` 3개). `invalidated_at`·`invalidation_reason` 컬럼과 짝을 맞추려고 넣었는데, 설계에 없는 값이라 확인 부탁드려요.
- **중복 인덱스가 4개 있어요.** `ix_dl_replay`·`ix_pe_replay` 는 같은 컬럼의 UNIQUE 와 겹치고, `ix_dt_by_dep` 는 `uq_dt_natural` 의 선두 컬럼으로 충족돼요. 설계 §4 의 "중복 인덱스 금지" 와 어긋나요. 지우는 게 맞다고 보시면 고칠게요.
- **DB 제약만 확인했어요.** 실제 배포 흐름·동시성·Jenkins 연동·SSE 재생은 이번 검증 범위가 아니에요.
- `source_version` 은 `(project_id, commit_sha)` 가 UNIQUE 가 아니에요. 같은 커밋 재빌드를 새 행으로 보존하는 설계 5.5 를 그대로 따랐어요. 웹·앱이 커밋을 키로 쓰고 있어서 소비자 계약 확인이 필요하다고 PR #19 에 적어 뒀어요.
- 원격 push 와 PR 은 하지 않았어요.

## 검증 결과

- **빈 PostgreSQL 17 에 PR #19 브랜치를 실제로 띄워서 확인했어요.** 엔티티와 컬럼이 어긋나면 여기서 기동이 실패해요.

  ```
  Flyway     Migrating schema "public" to version "1 - init"
             Successfully applied 1 migration (execution time 00:00.390s)
  Hibernate  ddl-auto=validate 통과 (검증 오류 없음)
  Started DaisyServerApplication in 21.972 seconds
  ```

- 제약 검사 17가지를 돌렸어요. `bash server/docs/eh/sql/verify.sh` 로 재현할 수 있어요. **`verify.sh` 는 Flyway 를 쓰지 않고 `psql` 로 DDL 을 직접 올려요.** 위 기동 로그는 `./gradlew bootRun` 으로 따로 확인한 것이라 `verify.sh` 로는 재현되지 않아요.
  정확히는 **위반이 막히는지 보는 검사 15가지 + 정상 통과 확인 1가지(T13) + 목록 출력 1가지(T17)** 예요.

  | | 검사 | 결과 |
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
  | T14 | 같은 `state_identity` 동시 락 2건 | 1건만 |
  | T15·T16 | `seq=0` · 같은 멱등 scope·키 두 번 | 막힘 |
  | T17 | FK 인덱스 누락 스캔 | 목록 36개 출력 |

- 테이블 17개가 생성되는 것과 Flyway 버전이 `v1` 인 것을 확인했어요.
- **검사 항목을 먼저 적고 그대로 돌렸어요.** 항목에 없는 실패 모드는 확인하지 않은 거예요.
