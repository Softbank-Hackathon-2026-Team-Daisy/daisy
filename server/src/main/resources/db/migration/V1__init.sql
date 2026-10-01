-- V1__init.sql — PR #19 ERD(17개 테이블) 기준 초기 스키마
--
-- 기준: server/docs/database-design.md + domain 패키지 JPA 엔티티
-- 목표: ddl-auto=validate 를 통과하면서, 설계 문서의 FK·CHECK·부분 UNIQUE·인덱스를 DB 에 구현한다.
--
-- 규칙 (설계 §4)
--   ID            varchar(64). 로그·멱등 내부 PK 만 bigint identity
--   시간           timestamptz
--   digest        varchar(128), commit_sha varchar(64)
--   JSON          jsonb
--   enum          varchar + CHECK (PostgreSQL enum 타입 안 씀)
--   삭제           CASCADE 없음. RESTRICT/NO ACTION 기본. 보관은 archived_at/disabled_at
--   순환 FK        테이블을 먼저 만들고 파일 끝에서 ALTER 로 붙인다

-- ────────────────────────────────── 1. 계정·프로젝트

CREATE TABLE account (
  id            varchar(64)  NOT NULL,
  username      varchar(128) NOT NULL,
  password_hash text         NOT NULL,
  display_name  varchar(128) NOT NULL,
  role          varchar(32)  NOT NULL,
  created_at    timestamptz  NOT NULL,
  updated_at    timestamptz  NOT NULL,
  disabled_at   timestamptz,
  CONSTRAINT pk_account PRIMARY KEY (id),
  CONSTRAINT uq_account_username UNIQUE (username)
);

CREATE TABLE project (
  id                        varchar(64)  NOT NULL,
  name                      varchar(128) NOT NULL,
  repository_id             varchar(255) NOT NULL,
  repository_url            text         NOT NULL,
  default_branch            varchar(255) NOT NULL,
  manifest_path             varchar(512) NOT NULL,
  repository_credential_ref text,
  created_by                varchar(64)  NOT NULL,
  last_event_seq            bigint       NOT NULL DEFAULT 0,
  created_at                timestamptz  NOT NULL,
  updated_at                timestamptz  NOT NULL,
  archived_at               timestamptz,
  CONSTRAINT pk_project PRIMARY KEY (id),
  CONSTRAINT fk_project_created_by FOREIGN KEY (created_by) REFERENCES account (id),
  CONSTRAINT ck_project_seq CHECK (last_event_seq >= 0)
);
CREATE INDEX ix_project_list ON project (created_at, id);

CREATE TABLE project_member (
  project_id varchar(64) NOT NULL,
  account_id varchar(64) NOT NULL,
  granted_by varchar(64) NOT NULL,
  granted_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT pk_project_member PRIMARY KEY (project_id, account_id),
  CONSTRAINT fk_pm_project    FOREIGN KEY (project_id) REFERENCES project (id),
  CONSTRAINT fk_pm_account    FOREIGN KEY (account_id) REFERENCES account (id),
  CONSTRAINT fk_pm_granted_by FOREIGN KEY (granted_by) REFERENCES account (id)
);
CREATE INDEX ix_pm_account ON project_member (account_id, project_id);

-- ────────────────────────────────── 2. 대상·입력

CREATE TABLE target (
  id                           varchar(64)  NOT NULL,
  project_id                   varchar(64)  NOT NULL,
  name                         varchar(128) NOT NULL,
  environment_type             varchar(32)  NOT NULL,
  state_identity               varchar(512) NOT NULL,
  config                       jsonb        NOT NULL,
  config_revision              bigint       NOT NULL DEFAULT 1,
  credential_ref               text,
  credential_version           varchar(255),
  connection_state             varchar(32)  NOT NULL,
  connection_checked_at        timestamptz,
  current_deployment_target_id varchar(64),            -- FK 는 파일 끝 (순환)
  observed_state               jsonb,
  observed_at                  timestamptz,
  reuse_assessment             jsonb,
  created_at                   timestamptz  NOT NULL,
  updated_at                   timestamptz  NOT NULL,
  archived_at                  timestamptz,
  CONSTRAINT pk_target PRIMARY KEY (id),
  CONSTRAINT uq_target_project UNIQUE (id, project_id),
  CONSTRAINT fk_target_project FOREIGN KEY (project_id) REFERENCES project (id),
  CONSTRAINT ck_target_config_revision CHECK (config_revision >= 1)
);
CREATE INDEX ix_target_list  ON target (project_id, archived_at, id);
CREATE INDEX ix_target_state ON target (state_identity);

CREATE TABLE source_version (
  id                      varchar(64)  NOT NULL,
  project_id              varchar(64)  NOT NULL,
  source                  varchar(255) NOT NULL,
  external_build_id       varchar(255) NOT NULL,
  commit_sha              varchar(64)  NOT NULL,
  branch                  varchar(255),
  status                  varchar(32)  NOT NULL,
  image_refs              jsonb,
  manifest_snapshot       jsonb,
  manifest_ref            text,
  manifest_digest         varchar(128),
  manifest_schema_version varchar(64),
  run_url                 text,
  started_at              timestamptz,
  finished_at             timestamptz,
  error_summary           text,
  received_at             timestamptz  NOT NULL,
  CONSTRAINT pk_source_version PRIMARY KEY (id),
  CONSTRAINT uq_sv_project  UNIQUE (id, project_id),
  CONSTRAINT uq_sv_external UNIQUE (source, external_build_id),
  CONSTRAINT fk_sv_project  FOREIGN KEY (project_id) REFERENCES project (id)
);
-- (project_id, commit_sha) 는 일부러 UNIQUE 가 아니다. 동일 커밋 재빌드를 새 행으로 보존한다 (설계 5.5)
CREATE INDEX ix_sv_recent ON source_version (project_id, received_at DESC, id);
CREATE INDEX ix_sv_commit ON source_version (project_id, commit_sha);

-- ────────────────────────────────── 3. 배포

CREATE TABLE deployment (
  id                             varchar(64)  NOT NULL,
  project_id                     varchar(64)  NOT NULL,
  source_version_id              varchar(64),
  requested_by                   varchar(64)  NOT NULL,
  kind                           varchar(32)  NOT NULL,
  retry_of_deployment_id         varchar(64),
  rollback_of_deployment_id      varchar(64),
  rollback_trigger_deployment_id varchar(64),
  commit_sha                     varchar(64)  NOT NULL,
  repository_snapshot            jsonb        NOT NULL,
  input_snapshot                 jsonb        NOT NULL,
  request_hash                   varchar(128) NOT NULL,
  image_refs                     jsonb,
  resolved_input_hash            varchar(128),
  status                         varchar(32)  NOT NULL,
  last_event_seq                 bigint       NOT NULL DEFAULT 0,
  version                        bigint       NOT NULL DEFAULT 0,
  created_at                     timestamptz  NOT NULL,
  started_at                     timestamptz,
  finished_at                    timestamptz,
  CONSTRAINT pk_deployment PRIMARY KEY (id),
  CONSTRAINT uq_deployment_project UNIQUE (id, project_id),
  CONSTRAINT fk_dep_project     FOREIGN KEY (project_id)   REFERENCES project (id),
  CONSTRAINT fk_dep_requested_by FOREIGN KEY (requested_by) REFERENCES account (id),
  -- 소스는 반드시 같은 프로젝트의 것
  CONSTRAINT fk_dep_source FOREIGN KEY (source_version_id, project_id)
    REFERENCES source_version (id, project_id),
  -- lineage 세 개도 같은 프로젝트의 배포만
  CONSTRAINT fk_dep_retry_of FOREIGN KEY (retry_of_deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT fk_dep_rollback_of FOREIGN KEY (rollback_of_deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT fk_dep_rollback_trigger FOREIGN KEY (rollback_trigger_deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT ck_dep_status CHECK (status IN
    ('queued','running','awaiting_approval','succeeded','partially_succeeded','failed','cancelled')),
  CONSTRAINT ck_dep_kind CHECK (kind IN ('normal','retry','rollback')),
  -- kind 별 lineage 조합 (설계 5.6)
  CONSTRAINT ck_dep_lineage CHECK (
    (kind = 'normal'
      AND retry_of_deployment_id IS NULL
      AND rollback_of_deployment_id IS NULL
      AND rollback_trigger_deployment_id IS NULL)
    OR (kind = 'retry'
      AND retry_of_deployment_id IS NOT NULL
      AND rollback_of_deployment_id IS NULL
      AND rollback_trigger_deployment_id IS NULL)
    OR (kind = 'rollback'
      AND rollback_of_deployment_id IS NOT NULL
      AND retry_of_deployment_id IS NULL)
  ),
  CONSTRAINT ck_dep_self_retry    CHECK (retry_of_deployment_id         IS NULL OR retry_of_deployment_id         <> id),
  CONSTRAINT ck_dep_self_rollback CHECK (rollback_of_deployment_id      IS NULL OR rollback_of_deployment_id      <> id),
  CONSTRAINT ck_dep_self_trigger  CHECK (rollback_trigger_deployment_id IS NULL OR rollback_trigger_deployment_id <> id),
  CONSTRAINT ck_dep_counters CHECK (last_event_seq >= 0 AND version >= 0)
);
CREATE INDEX ix_dep_list     ON deployment (project_id, created_at DESC, id);
CREATE INDEX ix_dep_status   ON deployment (project_id, status, created_at DESC, id);
CREATE INDEX ix_dep_retry    ON deployment (retry_of_deployment_id);
CREATE INDEX ix_dep_rollback ON deployment (rollback_of_deployment_id);

CREATE TABLE deployment_target (
  id                                 varchar(64)  NOT NULL,
  deployment_id                      varchar(64)  NOT NULL,
  project_id                         varchar(64)  NOT NULL,
  target_id                          varchar(64)  NOT NULL,
  target_snapshot                    jsonb        NOT NULL,
  retry_of_deployment_target_id      varchar(64),
  restored_from_deployment_target_id varchar(64),
  state_identity                     varchar(512) NOT NULL,
  input_hash                         varchar(128),
  status                             varchar(32)  NOT NULL,
  attempt                            smallint     NOT NULL DEFAULT 0,
  ai_reused                          boolean      NOT NULL DEFAULT false,
  script_id                          varchar(64),            -- FK 는 파일 끝 (순환)
  current_plan_id                    varchar(64),            -- FK 는 파일 끝 (순환)
  current_execution_id               varchar(64),            -- FK 는 파일 끝 (순환)
  last_source_sequence               bigint,
  result                             jsonb,
  error_summary                      text,
  cancel_requested_by                varchar(64),
  cancel_requested_at                timestamptz,
  started_at                         timestamptz,
  finished_at                        timestamptz,
  version                            bigint       NOT NULL DEFAULT 0,
  CONSTRAINT pk_deployment_target PRIMARY KEY (id),
  CONSTRAINT uq_dt_natural   UNIQUE (deployment_id, target_id),
  CONSTRAINT uq_dt_in_dep    UNIQUE (id, deployment_id),
  CONSTRAINT uq_dt_in_target UNIQUE (id, target_id, project_id),
  CONSTRAINT uq_dt_in_proj   UNIQUE (id, project_id),
  -- 한 배포에 같은 state 를 쓰는 대상을 중복 선택하지 못하게 한다 (설계 5.7)
  CONSTRAINT uq_dt_state     UNIQUE (deployment_id, state_identity),
  -- 배포와 환경이 같은 프로젝트인지 DB 가 직접 본다
  CONSTRAINT fk_dt_deployment FOREIGN KEY (deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT fk_dt_target FOREIGN KEY (target_id, project_id)
    REFERENCES target (id, project_id),
  CONSTRAINT fk_dt_cancel_by FOREIGN KEY (cancel_requested_by) REFERENCES account (id),
  CONSTRAINT fk_dt_retry_of FOREIGN KEY (retry_of_deployment_target_id, target_id, project_id)
    REFERENCES deployment_target (id, target_id, project_id),
  CONSTRAINT fk_dt_restored_from FOREIGN KEY (restored_from_deployment_target_id, target_id, project_id)
    REFERENCES deployment_target (id, target_id, project_id),
  CONSTRAINT ck_dt_status CHECK (status IN
    ('waiting','generating','validating','awaiting_approval','applying','verifying','succeeded','failed','cancelled')),
  CONSTRAINT ck_dt_attempt CHECK (attempt BETWEEN 0 AND 3),
  CONSTRAINT ck_dt_version CHECK (version >= 0),
  CONSTRAINT ck_dt_cancel_pair CHECK (
    (cancel_requested_by IS NULL AND cancel_requested_at IS NULL)
    OR (cancel_requested_by IS NOT NULL AND cancel_requested_at IS NOT NULL)),
  CONSTRAINT ck_dt_self_retry    CHECK (retry_of_deployment_target_id      IS NULL OR retry_of_deployment_target_id      <> id),
  CONSTRAINT ck_dt_self_restored CHECK (restored_from_deployment_target_id IS NULL OR restored_from_deployment_target_id <> id),
  -- 두 lineage 동시 지정 금지 (설계 5.7)
  CONSTRAINT ck_dt_lineage_exclusive CHECK (
    retry_of_deployment_target_id IS NULL OR restored_from_deployment_target_id IS NULL)
);
CREATE INDEX ix_dt_by_dep    ON deployment_target (deployment_id);
CREATE INDEX ix_dt_by_target ON deployment_target (target_id, finished_at DESC);

-- ────────────────────────────────── 4. Jenkins 명령

CREATE TABLE jenkins_execution (
  id                     varchar(64)  NOT NULL,
  deployment_id          varchar(64)  NOT NULL,
  request_id             varchar(128) NOT NULL,
  operation              varchar(32)  NOT NULL,
  parent_execution_id    varchar(64),
  instance_id            varchar(128) NOT NULL,
  job_full_name          varchar(512) NOT NULL,
  request_payload        jsonb        NOT NULL,
  request_hash           varchar(128) NOT NULL,
  dispatch_status        varchar(32)  NOT NULL,
  run_status             varchar(32)  NOT NULL,
  dispatch_attempts      integer      NOT NULL DEFAULT 0,
  dispatch_started_at    timestamptz,
  queue_id               bigint,
  build_number           bigint,
  run_url                text,
  log_owner_execution_id varchar(64),
  log_cursor             bigint       NOT NULL DEFAULT 0,
  log_complete           boolean      NOT NULL DEFAULT false,
  next_check_at          timestamptz,
  last_checked_at        timestamptz,
  last_error             text,
  created_at             timestamptz  NOT NULL,
  started_at             timestamptz,
  finished_at            timestamptz,
  CONSTRAINT pk_jenkins_execution PRIMARY KEY (id),
  CONSTRAINT uq_je_request UNIQUE (request_id),
  CONSTRAINT uq_je_in_dep  UNIQUE (id, deployment_id),
  CONSTRAINT fk_je_deployment FOREIGN KEY (deployment_id) REFERENCES deployment (id),
  CONSTRAINT fk_je_parent FOREIGN KEY (parent_execution_id, deployment_id)
    REFERENCES jenkins_execution (id, deployment_id),
  CONSTRAINT fk_je_log_owner FOREIGN KEY (log_owner_execution_id, deployment_id)
    REFERENCES jenkins_execution (id, deployment_id),
  CONSTRAINT ck_je_operation CHECK (operation IN ('prepare','replan','apply','stop')),
  CONSTRAINT ck_je_dispatch CHECK (dispatch_status IN ('pending','dispatching','accepted','unknown','rejected')),
  CONSTRAINT ck_je_run CHECK (run_status IN ('unknown','queued','running','succeeded','failed','cancelled')),
  CONSTRAINT ck_je_counters CHECK (dispatch_attempts >= 0 AND log_cursor >= 0),
  CONSTRAINT ck_je_queue CHECK (queue_id IS NULL OR queue_id >= 0),
  CONSTRAINT ck_je_build CHECK (build_number IS NULL OR build_number >= 0),
  -- parent 는 자기 자신을 못 가리킨다. log owner 는 자기 자신도 허용 (설계 5.8)
  CONSTRAINT ck_je_self_parent CHECK (parent_execution_id IS NULL OR parent_execution_id <> id)
);
-- run 키는 UNIQUE 가 아니다. 같은 run 을 여러 명령이 가리킬 수 있다.
-- 다만 한 run 의 log owner 는 하나뿐이어야 한다 (설계 5.8)
CREATE UNIQUE INDEX uq_je_log_owner_per_run ON jenkins_execution (instance_id, job_full_name, build_number)
  WHERE log_owner_execution_id = id AND build_number IS NOT NULL;
CREATE INDEX ix_je_dispatch ON jenkins_execution (dispatch_status, next_check_at);
CREATE INDEX ix_je_run      ON jenkins_execution (run_status, next_check_at);
CREATE INDEX ix_je_queue    ON jenkins_execution (instance_id, queue_id);
CREATE INDEX ix_je_build    ON jenkins_execution (instance_id, job_full_name, build_number);
CREATE INDEX ix_je_by_dep   ON jenkins_execution (deployment_id, created_at);

CREATE TABLE execution_target (
  execution_id         varchar(64)  NOT NULL,
  deployment_target_id varchar(64)  NOT NULL,
  deployment_id        varchar(64)  NOT NULL,
  input_hash           varchar(128),
  plan_id              varchar(64),            -- FK 는 파일 끝 (순환)
  plan_digest          varchar(128),
  status               varchar(32)  NOT NULL,
  last_source_sequence bigint,
  started_at           timestamptz,
  finished_at          timestamptz,
  CONSTRAINT pk_execution_target PRIMARY KEY (execution_id, deployment_target_id),
  CONSTRAINT uq_et_in_dep UNIQUE (execution_id, deployment_target_id, deployment_id),
  CONSTRAINT fk_et_execution FOREIGN KEY (execution_id, deployment_id)
    REFERENCES jenkins_execution (id, deployment_id),
  CONSTRAINT fk_et_target FOREIGN KEY (deployment_target_id, deployment_id)
    REFERENCES deployment_target (id, deployment_id),
  CONSTRAINT ck_et_status CHECK (status IN ('pending','running','succeeded','failed','cancelled','stale'))
);
CREATE INDEX ix_et_by_target ON execution_target (deployment_target_id, execution_id);
CREATE INDEX ix_et_by_plan   ON execution_target (plan_id);

-- ────────────────────────────────── 5. 산출물

CREATE TABLE script (
  id                          varchar(64)  NOT NULL,
  project_id                  varchar(64)  NOT NULL,
  target_id                   varchar(64)  NOT NULL,
  version                     integer      NOT NULL,
  source                      varchar(512) NOT NULL,
  external_script_id          varchar(255) NOT NULL,
  source_deployment_target_id varchar(64)  NOT NULL,
  artifact_ref                text         NOT NULL,
  content_digest              varchar(128) NOT NULL,
  compatibility_key           varchar(255),
  metadata                    jsonb,
  validated_at                timestamptz  NOT NULL,
  received_at                 timestamptz  NOT NULL,
  artifact_expires_at         timestamptz,
  unavailable_at              timestamptz,
  CONSTRAINT pk_script PRIMARY KEY (id),
  CONSTRAINT uq_script_in_target UNIQUE (id, project_id, target_id),
  CONSTRAINT uq_script_version   UNIQUE (project_id, target_id, version),
  CONSTRAINT uq_script_external  UNIQUE (source, external_script_id),
  CONSTRAINT fk_script_target FOREIGN KEY (target_id, project_id)
    REFERENCES target (id, project_id),
  CONSTRAINT fk_script_source_dt FOREIGN KEY (source_deployment_target_id, target_id, project_id)
    REFERENCES deployment_target (id, target_id, project_id),
  CONSTRAINT ck_script_version CHECK (version >= 1)
);
CREATE INDEX ix_script_reuse ON script (project_id, target_id, version DESC);

CREATE TABLE plan_revision (
  id                   varchar(64)  NOT NULL,
  deployment_target_id varchar(64)  NOT NULL,
  execution_id         varchar(64)  NOT NULL,
  project_id           varchar(64)  NOT NULL,
  target_id            varchar(64)  NOT NULL,
  revision             integer      NOT NULL,
  source               varchar(512) NOT NULL,
  source_plan_id       varchar(255) NOT NULL,
  input_hash           varchar(128) NOT NULL,
  script_id            varchar(64)  NOT NULL,
  artifact_ref         text         NOT NULL,
  digest               varchar(128) NOT NULL,
  summary              jsonb        NOT NULL,
  resources            jsonb        NOT NULL,
  state                varchar(32)  NOT NULL,
  created_at           timestamptz  NOT NULL,
  expires_at           timestamptz  NOT NULL,
  invalidated_at       timestamptz,
  invalidation_reason  varchar(255),
  artifact_expires_at  timestamptz,
  CONSTRAINT pk_plan_revision PRIMARY KEY (id),
  CONSTRAINT uq_plan_in_dt    UNIQUE (id, deployment_target_id),
  CONSTRAINT uq_plan_revision UNIQUE (deployment_target_id, revision),
  CONSTRAINT uq_plan_external UNIQUE (source, source_plan_id),
  CONSTRAINT fk_plan_execution FOREIGN KEY (execution_id, deployment_target_id)
    REFERENCES execution_target (execution_id, deployment_target_id),
  CONSTRAINT fk_plan_dt FOREIGN KEY (deployment_target_id, target_id, project_id)
    REFERENCES deployment_target (id, target_id, project_id),
  CONSTRAINT fk_plan_script FOREIGN KEY (script_id, project_id, target_id)
    REFERENCES script (id, project_id, target_id),
  CONSTRAINT ck_plan_revision_no CHECK (revision >= 1),
  CONSTRAINT ck_plan_expiry CHECK (expires_at > created_at),
  CONSTRAINT ck_plan_state CHECK (state IN ('active','superseded','expired','invalidated'))
);
-- 한 대상에 살아 있는 plan 은 하나뿐
CREATE UNIQUE INDEX uq_plan_active ON plan_revision (deployment_target_id) WHERE state = 'active';
CREATE INDEX ix_plan_by_dt   ON plan_revision (deployment_target_id, created_at);
CREATE INDEX ix_plan_expiry  ON plan_revision (state, expires_at);

CREATE TABLE approval (
  id                   varchar(64)  NOT NULL,
  plan_id              varchar(64)  NOT NULL,
  deployment_target_id varchar(64)  NOT NULL,
  state                varchar(32)  NOT NULL DEFAULT 'pending',
  decision             varchar(32),
  decided_by           varchar(64),
  decided_at           timestamptz,
  confirmation_text    varchar(128),
  created_at           timestamptz  NOT NULL,
  expires_at           timestamptz  NOT NULL,
  invalidated_at       timestamptz,
  invalidation_reason  varchar(255),
  CONSTRAINT pk_approval PRIMARY KEY (id),
  CONSTRAINT uq_approval_plan UNIQUE (plan_id),
  CONSTRAINT fk_approval_plan FOREIGN KEY (plan_id, deployment_target_id)
    REFERENCES plan_revision (id, deployment_target_id),
  CONSTRAINT fk_approval_decided_by FOREIGN KEY (decided_by) REFERENCES account (id),
  CONSTRAINT ck_approval_state CHECK (state IN ('pending','approved','rejected','superseded','expired')),
  CONSTRAINT ck_approval_decision CHECK (decision IS NULL OR decision IN ('approved','rejected')),
  -- 결정 3종은 모두 NULL 이거나 모두 존재
  CONSTRAINT ck_approval_decision_triple CHECK (
    (decision IS NULL     AND decided_by IS NULL     AND decided_at IS NULL)
    OR (decision IS NOT NULL AND decided_by IS NOT NULL AND decided_at IS NOT NULL)),
  -- state 가 approved/rejected 면 decision 과 일치해야 한다
  CONSTRAINT ck_approval_state_decision CHECK (
    state NOT IN ('approved','rejected') OR decision = state),
  CONSTRAINT ck_approval_expiry CHECK (expires_at > created_at)
);
-- 한 대상에 살아 있는 승인은 하나뿐
CREATE UNIQUE INDEX uq_approval_pending ON approval (deployment_target_id) WHERE state = 'pending';
CREATE INDEX ix_approval_expiry ON approval (state, expires_at);
CREATE INDEX ix_approval_by_dt  ON approval (deployment_target_id, created_at);

CREATE TABLE ai_usage (
  id                   varchar(64)    NOT NULL,
  execution_id         varchar(64)    NOT NULL,
  deployment_target_id varchar(64)    NOT NULL,
  source               varchar(512)   NOT NULL,
  external_call_id     varchar(255)   NOT NULL,
  payload_hash         varchar(128)   NOT NULL,
  provider             varchar(64)    NOT NULL,
  model                varchar(128)   NOT NULL,
  step                 varchar(32)    NOT NULL,
  attempt              smallint       NOT NULL,
  status               varchar(32)    NOT NULL,
  input_tokens         bigint,
  output_tokens        bigint,
  usage_details        jsonb,
  cost_usd             numeric(20,10),
  cost_basis           varchar(32),
  occurred_at          timestamptz    NOT NULL,
  received_at          timestamptz    NOT NULL,
  CONSTRAINT pk_ai_usage PRIMARY KEY (id),
  CONSTRAINT uq_ai_external UNIQUE (source, external_call_id),
  CONSTRAINT fk_ai_execution_target FOREIGN KEY (execution_id, deployment_target_id)
    REFERENCES execution_target (execution_id, deployment_target_id),
  -- LLM 호출 결과다. Terraform 검증 결과가 아니다 (설계 5.13)
  CONSTRAINT ck_ai_status CHECK (status IN ('succeeded','failed','unknown')),
  CONSTRAINT ck_ai_tokens CHECK (
    (input_tokens  IS NULL OR input_tokens  >= 0)
    AND (output_tokens IS NULL OR output_tokens >= 0))
);
CREATE INDEX ix_ai_by_dt ON ai_usage (deployment_target_id, occurred_at);

-- ────────────────────────────────── 6. 이벤트·멱등·락

CREATE TABLE deployment_log (
  id                   bigint       GENERATED BY DEFAULT AS IDENTITY,
  deployment_id        varchar(64)  NOT NULL,
  execution_id         varchar(64),
  deployment_target_id varchar(64),
  seq                  bigint       NOT NULL,
  source               varchar(512) NOT NULL,
  source_event_id      varchar(255) NOT NULL,
  source_sequence      bigint,
  payload_hash         varchar(128) NOT NULL,
  event_type           varchar(64)  NOT NULL,
  stage_occurrence_id  varchar(255),
  step                 varchar(32),
  level                varchar(16)  NOT NULL DEFAULT 'info',
  message              text,
  payload              jsonb        NOT NULL DEFAULT '{}'::jsonb,
  processing_result    varchar(32)  NOT NULL DEFAULT 'applied',
  source_stream        varchar(512),
  source_offset        bigint,
  source_end_offset    bigint,
  occurred_at          timestamptz  NOT NULL,
  received_at          timestamptz  NOT NULL,
  CONSTRAINT pk_deployment_log PRIMARY KEY (id),
  CONSTRAINT uq_dl_in_dep   UNIQUE (id, deployment_id),
  CONSTRAINT uq_dl_seq      UNIQUE (deployment_id, seq),
  CONSTRAINT uq_dl_external UNIQUE (source, source_event_id),
  CONSTRAINT fk_dl_deployment FOREIGN KEY (deployment_id) REFERENCES deployment (id),
  CONSTRAINT fk_dl_execution FOREIGN KEY (execution_id, deployment_id)
    REFERENCES jenkins_execution (id, deployment_id),
  CONSTRAINT fk_dl_target FOREIGN KEY (deployment_target_id, deployment_id)
    REFERENCES deployment_target (id, deployment_id),
  -- 둘 다 있으면 execution_target 소속까지 검사한다 (MATCH SIMPLE 이라 하나가 NULL 이면 통과)
  CONSTRAINT fk_dl_execution_target FOREIGN KEY (execution_id, deployment_target_id)
    REFERENCES execution_target (execution_id, deployment_target_id),
  CONSTRAINT ck_dl_seq CHECK (seq >= 1),
  CONSTRAINT ck_dl_level CHECK (level IN ('debug','info','warn','error')),
  CONSTRAINT ck_dl_processing CHECK (processing_result IN ('applied','ignored_stale')),
  CONSTRAINT ck_dl_step CHECK (step IS NULL OR step IN
    ('generate','validate','plan','risk_check','apply','health_check')),
  -- offset 3개는 함께 NULL 이거나 함께 존재. 0 <= offset < end_offset
  CONSTRAINT ck_dl_offsets CHECK (
    (source_stream IS NULL AND source_offset IS NULL AND source_end_offset IS NULL)
    OR (source_stream IS NOT NULL AND source_offset IS NOT NULL AND source_end_offset IS NOT NULL
        AND source_offset >= 0 AND source_offset < source_end_offset))
);
CREATE UNIQUE INDEX uq_dl_stream_offset ON deployment_log (source_stream, source_offset)
  WHERE source_stream IS NOT NULL;
CREATE INDEX ix_dl_replay    ON deployment_log (deployment_id, seq);
CREATE INDEX ix_dl_by_target ON deployment_log (deployment_id, deployment_target_id, seq);
CREATE INDEX ix_dl_stage     ON deployment_log (execution_id, stage_occurrence_id);

CREATE TABLE project_event (
  id                bigint       GENERATED BY DEFAULT AS IDENTITY,
  project_id        varchar(64)  NOT NULL,
  deployment_id     varchar(64),
  source_version_id varchar(64),
  deployment_log_id bigint,
  seq               bigint       NOT NULL,
  source            varchar(512) NOT NULL,
  source_event_id   varchar(255) NOT NULL,
  payload_hash      varchar(128) NOT NULL,
  event_type        varchar(64)  NOT NULL,
  payload           jsonb        NOT NULL,
  occurred_at       timestamptz  NOT NULL,
  received_at       timestamptz  NOT NULL,
  CONSTRAINT pk_project_event PRIMARY KEY (id),
  CONSTRAINT uq_pe_seq      UNIQUE (project_id, seq),
  CONSTRAINT uq_pe_external UNIQUE (project_id, source, source_event_id),
  CONSTRAINT fk_pe_project FOREIGN KEY (project_id) REFERENCES project (id),
  CONSTRAINT fk_pe_deployment FOREIGN KEY (deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT fk_pe_source_version FOREIGN KEY (source_version_id, project_id)
    REFERENCES source_version (id, project_id),
  CONSTRAINT fk_pe_log FOREIGN KEY (deployment_log_id, deployment_id)
    REFERENCES deployment_log (id, deployment_id),
  CONSTRAINT ck_pe_seq CHECK (seq >= 1),
  CONSTRAINT ck_pe_log_needs_dep CHECK (deployment_log_id IS NULL OR deployment_id IS NOT NULL)
);
-- 배포 사건의 프로젝트 투영은 원본 하나당 한 번만
CREATE UNIQUE INDEX uq_pe_log_projection ON project_event (deployment_log_id)
  WHERE deployment_log_id IS NOT NULL;
CREATE INDEX ix_pe_replay ON project_event (project_id, seq);

CREATE TABLE idempotency (
  id              bigint       GENERATED BY DEFAULT AS IDENTITY,
  actor_id        varchar(64)  NOT NULL,
  project_id      varchar(64)  NOT NULL,
  operation       varchar(64)  NOT NULL,
  resource_key    varchar(255) NOT NULL,
  request_key     varchar(255) NOT NULL,
  request_hash    varchar(128) NOT NULL,
  deployment_id   varchar(64),
  response_status smallint     NOT NULL,
  response_body   jsonb        NOT NULL,
  created_at      timestamptz  NOT NULL,
  CONSTRAINT pk_idempotency PRIMARY KEY (id),
  CONSTRAINT uq_idem_scope UNIQUE (actor_id, project_id, operation, resource_key, request_key),
  CONSTRAINT fk_idem_actor   FOREIGN KEY (actor_id)   REFERENCES account (id),
  CONSTRAINT fk_idem_project FOREIGN KEY (project_id) REFERENCES project (id),
  CONSTRAINT fk_idem_deployment FOREIGN KEY (deployment_id, project_id)
    REFERENCES deployment (id, project_id),
  CONSTRAINT ck_idem_status CHECK (response_status BETWEEN 200 AND 599)
);
CREATE INDEX ix_idem_by_dep ON idempotency (deployment_id);

CREATE TABLE target_lock (
  state_identity       varchar(512) NOT NULL,
  execution_id         varchar(64)  NOT NULL,
  deployment_target_id varchar(64)  NOT NULL,
  acquired_at          timestamptz  NOT NULL,
  CONSTRAINT pk_target_lock PRIMARY KEY (state_identity),
  CONSTRAINT uq_tl_owner UNIQUE (execution_id, deployment_target_id),
  CONSTRAINT fk_tl_execution_target FOREIGN KEY (execution_id, deployment_target_id)
    REFERENCES execution_target (execution_id, deployment_target_id)
);

-- ────────────────────────────────── 7. 순환 FK (설계 §7 저장 순서대로 마지막에 연결)

ALTER TABLE target
  ADD CONSTRAINT fk_target_current_dt FOREIGN KEY (current_deployment_target_id, id, project_id)
    REFERENCES deployment_target (id, target_id, project_id);

ALTER TABLE deployment_target
  ADD CONSTRAINT fk_dt_script FOREIGN KEY (script_id, project_id, target_id)
    REFERENCES script (id, project_id, target_id);

ALTER TABLE deployment_target
  ADD CONSTRAINT fk_dt_current_plan FOREIGN KEY (current_plan_id, id)
    REFERENCES plan_revision (id, deployment_target_id);

ALTER TABLE deployment_target
  ADD CONSTRAINT fk_dt_current_execution FOREIGN KEY (current_execution_id, id)
    REFERENCES execution_target (execution_id, deployment_target_id);

ALTER TABLE execution_target
  ADD CONSTRAINT fk_et_plan FOREIGN KEY (plan_id, deployment_target_id)
    REFERENCES plan_revision (id, deployment_target_id);
