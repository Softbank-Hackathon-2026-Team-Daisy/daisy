-- Executable SH-owned proposal; NOT a numbered Flyway migration.
-- Run in an explicitly selected empty schema after the five management-owner tables exist.
-- No schema creation, DROP, CASCADE deletion, external calls, or management-table alteration.
CREATE TABLE deployment (
  id varchar(64) PRIMARY KEY, project_id varchar(64) NOT NULL REFERENCES project(id), source_version_id varchar(64),
  requested_by varchar(64) NOT NULL REFERENCES account(id), kind varchar(32) NOT NULL DEFAULT 'normal',
  retry_of_deployment_id varchar(64), rollback_of_deployment_id varchar(64), rollback_trigger_deployment_id varchar(64),
  commit_sha varchar(64) NOT NULL, repository_snapshot jsonb NOT NULL, input_snapshot jsonb NOT NULL,
  request_hash varchar(128) NOT NULL, image_refs jsonb, resolved_input_hash varchar(128),
  status varchar(32) NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','awaiting_approval','succeeded','partially_succeeded','failed','cancelled')),
  last_event_seq bigint NOT NULL DEFAULT 0 CHECK(last_event_seq>=0), version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
  created_at timestamptz NOT NULL DEFAULT now(), started_at timestamptz, finished_at timestamptz,
  UNIQUE(id,project_id), FOREIGN KEY(source_version_id,project_id) REFERENCES source_version(id,project_id),
  FOREIGN KEY(retry_of_deployment_id,project_id) REFERENCES deployment(id,project_id),
  FOREIGN KEY(rollback_of_deployment_id,project_id) REFERENCES deployment(id,project_id),
  FOREIGN KEY(rollback_trigger_deployment_id,project_id) REFERENCES deployment(id,project_id),
  CHECK((kind='normal' AND retry_of_deployment_id IS NULL AND rollback_of_deployment_id IS NULL AND rollback_trigger_deployment_id IS NULL)
    OR (kind='retry' AND retry_of_deployment_id IS NOT NULL AND rollback_of_deployment_id IS NULL AND rollback_trigger_deployment_id IS NULL)
    OR (kind='rollback' AND retry_of_deployment_id IS NULL AND rollback_of_deployment_id IS NOT NULL)),
  CHECK(retry_of_deployment_id IS NULL OR retry_of_deployment_id<>id),
  CHECK(rollback_of_deployment_id IS NULL OR rollback_of_deployment_id<>id),
  CHECK(rollback_trigger_deployment_id IS NULL OR rollback_trigger_deployment_id<>id)
);
CREATE INDEX deployment_project_created_idx ON deployment(project_id,created_at DESC,id);
CREATE INDEX deployment_project_status_idx ON deployment(project_id,status,created_at DESC,id);
CREATE INDEX deployment_retry_idx ON deployment(retry_of_deployment_id);
CREATE INDEX deployment_rollback_idx ON deployment(rollback_of_deployment_id);

CREATE TABLE deployment_target (
  id varchar(64) PRIMARY KEY, deployment_id varchar(64) NOT NULL, project_id varchar(64) NOT NULL, target_id varchar(64) NOT NULL,
  target_snapshot jsonb NOT NULL, retry_of_deployment_target_id varchar(64), restored_from_deployment_target_id varchar(64),
  state_identity varchar(512) NOT NULL, input_hash varchar(128),
  status varchar(32) NOT NULL DEFAULT 'waiting' CHECK(status IN ('waiting','generating','validating','awaiting_approval','applying','verifying','succeeded','failed','cancelled')),
  attempt smallint NOT NULL DEFAULT 0 CHECK(attempt BETWEEN 0 AND 3), ai_reused boolean NOT NULL DEFAULT false,
  script_id varchar(64), current_plan_id varchar(64), current_execution_id varchar(64), last_source_sequence bigint CHECK(last_source_sequence>=0),
  result jsonb, error_summary text, cancel_requested_by varchar(64) REFERENCES account(id), cancel_requested_at timestamptz,
  started_at timestamptz, finished_at timestamptz, version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
  UNIQUE(deployment_id,target_id), UNIQUE(id,deployment_id), UNIQUE(id,target_id,project_id), UNIQUE(id,project_id), UNIQUE(deployment_id,state_identity),
  FOREIGN KEY(deployment_id,project_id) REFERENCES deployment(id,project_id), FOREIGN KEY(target_id,project_id) REFERENCES target(id,project_id),
  FOREIGN KEY(retry_of_deployment_target_id,target_id,project_id) REFERENCES deployment_target(id,target_id,project_id),
  FOREIGN KEY(restored_from_deployment_target_id,target_id,project_id) REFERENCES deployment_target(id,target_id,project_id),
  CHECK((cancel_requested_by IS NULL)=(cancel_requested_at IS NULL)),
  CHECK(retry_of_deployment_target_id IS NULL OR retry_of_deployment_target_id<>id),
  CHECK(restored_from_deployment_target_id IS NULL OR restored_from_deployment_target_id<>id),
  CHECK(retry_of_deployment_target_id IS NULL OR restored_from_deployment_target_id IS NULL)
);
CREATE INDEX deployment_target_finished_idx ON deployment_target(target_id,finished_at DESC);

CREATE TABLE jenkins_execution (
  id varchar(64) PRIMARY KEY, deployment_id varchar(64) NOT NULL REFERENCES deployment(id), request_id varchar(128) NOT NULL UNIQUE,
  operation varchar(32) NOT NULL CHECK(operation IN ('prepare','replan','apply','stop')), parent_execution_id varchar(64),
  instance_id varchar(128) NOT NULL, job_full_name varchar(512) NOT NULL, request_payload jsonb NOT NULL, request_hash varchar(128) NOT NULL,
  dispatch_status varchar(32) NOT NULL DEFAULT 'pending' CHECK(dispatch_status IN ('pending','dispatching','accepted','unknown','rejected')),
  run_status varchar(32) NOT NULL DEFAULT 'unknown' CHECK(run_status IN ('unknown','queued','running','succeeded','failed','cancelled')),
  dispatch_attempts integer NOT NULL DEFAULT 0 CHECK(dispatch_attempts>=0), dispatch_started_at timestamptz,
  queue_id bigint CHECK(queue_id>=0), build_number bigint CHECK(build_number>=0), run_url text, log_owner_execution_id varchar(64),
  log_cursor bigint NOT NULL DEFAULT 0 CHECK(log_cursor>=0), log_complete boolean NOT NULL DEFAULT false,
  next_check_at timestamptz, last_checked_at timestamptz, last_error text, created_at timestamptz NOT NULL DEFAULT now(), started_at timestamptz, finished_at timestamptz,
  UNIQUE(id,deployment_id), FOREIGN KEY(parent_execution_id,deployment_id) REFERENCES jenkins_execution(id,deployment_id),
  FOREIGN KEY(log_owner_execution_id,deployment_id) REFERENCES jenkins_execution(id,deployment_id),
  CHECK(parent_execution_id IS NULL OR parent_execution_id<>id)
);
CREATE INDEX jenkins_dispatch_check_idx ON jenkins_execution(dispatch_status,next_check_at);
CREATE INDEX jenkins_run_check_idx ON jenkins_execution(run_status,next_check_at);
CREATE INDEX jenkins_queue_idx ON jenkins_execution(instance_id,queue_id);
CREATE INDEX jenkins_run_idx ON jenkins_execution(instance_id,job_full_name,build_number);
CREATE INDEX jenkins_deployment_created_idx ON jenkins_execution(deployment_id,created_at);
CREATE UNIQUE INDEX jenkins_log_owner_idx ON jenkins_execution(instance_id,job_full_name,build_number)
  WHERE log_owner_execution_id=id AND build_number IS NOT NULL;

CREATE TABLE execution_target (
  execution_id varchar(64) NOT NULL, deployment_target_id varchar(64) NOT NULL, deployment_id varchar(64) NOT NULL,
  input_hash varchar(128), plan_id varchar(64), plan_digest varchar(128),
  status varchar(32) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','running','succeeded','failed','cancelled','stale')),
  last_source_sequence bigint CHECK(last_source_sequence>=0), started_at timestamptz, finished_at timestamptz,
  PRIMARY KEY(execution_id,deployment_target_id), UNIQUE(execution_id,deployment_target_id,deployment_id),
  FOREIGN KEY(execution_id,deployment_id) REFERENCES jenkins_execution(id,deployment_id),
  FOREIGN KEY(deployment_target_id,deployment_id) REFERENCES deployment_target(id,deployment_id),
  CHECK((plan_id IS NULL)=(plan_digest IS NULL))
);
CREATE INDEX execution_target_target_idx ON execution_target(deployment_target_id,execution_id);
CREATE INDEX execution_target_plan_idx ON execution_target(plan_id);

CREATE TABLE script (
  id varchar(64) PRIMARY KEY, project_id varchar(64) NOT NULL, target_id varchar(64) NOT NULL,
  version integer NOT NULL CHECK(version>=1), source varchar(512) NOT NULL, external_script_id varchar(255) NOT NULL,
  source_deployment_target_id varchar(64) NOT NULL, artifact_ref text NOT NULL, content_digest varchar(128) NOT NULL,
  compatibility_key varchar(255), metadata jsonb, validated_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
  artifact_expires_at timestamptz, unavailable_at timestamptz,
  UNIQUE(id,project_id,target_id), UNIQUE(project_id,target_id,version), UNIQUE(source,external_script_id),
  FOREIGN KEY(target_id,project_id) REFERENCES target(id,project_id),
  FOREIGN KEY(source_deployment_target_id,target_id,project_id) REFERENCES deployment_target(id,target_id,project_id)
);
CREATE INDEX script_target_validated_idx ON script(project_id,target_id,validated_at DESC);

CREATE TABLE plan_revision (
  id varchar(64) PRIMARY KEY, deployment_target_id varchar(64) NOT NULL, execution_id varchar(64) NOT NULL,
  project_id varchar(64) NOT NULL, target_id varchar(64) NOT NULL, revision integer NOT NULL CHECK(revision>=1),
  source varchar(512) NOT NULL, source_plan_id varchar(255) NOT NULL, input_hash varchar(128) NOT NULL, script_id varchar(64) NOT NULL,
  artifact_ref text NOT NULL, digest varchar(128) NOT NULL, summary jsonb NOT NULL, resources jsonb NOT NULL,
  state varchar(32) NOT NULL DEFAULT 'active' CHECK(state IN ('active','superseded','expired')),
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL, invalidated_at timestamptz, invalidation_reason varchar(255), artifact_expires_at timestamptz,
  UNIQUE(id,deployment_target_id), UNIQUE(deployment_target_id,revision), UNIQUE(source,source_plan_id),
  FOREIGN KEY(execution_id,deployment_target_id) REFERENCES execution_target(execution_id,deployment_target_id),
  FOREIGN KEY(deployment_target_id,target_id,project_id) REFERENCES deployment_target(id,target_id,project_id),
  FOREIGN KEY(script_id,project_id,target_id) REFERENCES script(id,project_id,target_id), CHECK(expires_at>created_at)
);
CREATE UNIQUE INDEX plan_active_idx ON plan_revision(deployment_target_id) WHERE state='active';
CREATE INDEX plan_target_created_idx ON plan_revision(deployment_target_id,created_at);
CREATE INDEX plan_expiry_idx ON plan_revision(state,expires_at);

CREATE TABLE approval (
  id varchar(64) PRIMARY KEY, plan_id varchar(64) NOT NULL UNIQUE, deployment_target_id varchar(64) NOT NULL,
  state varchar(32) NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','approved','rejected','superseded','expired')),
  decision varchar(32) CHECK(decision IN ('approved','rejected')), decided_by varchar(64) REFERENCES account(id), decided_at timestamptz,
  confirmation_text varchar(128), created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  invalidated_at timestamptz, invalidation_reason varchar(255),
  FOREIGN KEY(plan_id,deployment_target_id) REFERENCES plan_revision(id,deployment_target_id),
  CHECK((decision IS NULL)=(decided_by IS NULL) AND (decision IS NULL)=(decided_at IS NULL)),
  CHECK(state NOT IN ('approved','rejected') OR (decision IS NOT NULL AND state=decision)), CHECK(expires_at>created_at)
);
CREATE UNIQUE INDEX approval_pending_idx ON approval(deployment_target_id) WHERE state='pending';
CREATE INDEX approval_expiry_idx ON approval(state,expires_at);
CREATE INDEX approval_target_created_idx ON approval(deployment_target_id,created_at);

CREATE TABLE ai_usage (
  id varchar(64) PRIMARY KEY, execution_id varchar(64) NOT NULL, deployment_target_id varchar(64) NOT NULL,
  source varchar(512) NOT NULL, external_call_id varchar(255) NOT NULL, payload_hash varchar(128) NOT NULL,
  provider varchar(64) NOT NULL, model varchar(128) NOT NULL, step varchar(32) NOT NULL,
  attempt smallint NOT NULL CHECK(attempt BETWEEN 1 AND 3), status varchar(32) NOT NULL CHECK(status IN ('succeeded','failed','unknown')),
  input_tokens bigint CHECK(input_tokens>=0), output_tokens bigint CHECK(output_tokens>=0), usage_details jsonb,
  cost_usd numeric(20,10) CHECK(cost_usd>=0), cost_basis varchar(32) CHECK(cost_basis IN ('reported','estimated')),
  occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(), UNIQUE(source,external_call_id),
  FOREIGN KEY(execution_id,deployment_target_id) REFERENCES execution_target(execution_id,deployment_target_id), CHECK((cost_usd IS NULL)=(cost_basis IS NULL))
);
CREATE INDEX ai_usage_target_occurred_idx ON ai_usage(deployment_target_id,occurred_at,id);
CREATE INDEX ai_usage_execution_idx ON ai_usage(execution_id);

CREATE TABLE deployment_log (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, deployment_id varchar(64) NOT NULL REFERENCES deployment(id),
  execution_id varchar(64), deployment_target_id varchar(64), seq bigint NOT NULL CHECK(seq>=1),
  source varchar(512) NOT NULL, source_event_id varchar(255) NOT NULL, source_sequence bigint CHECK(source_sequence>=0), payload_hash varchar(128) NOT NULL,
  event_type varchar(64) NOT NULL, stage_occurrence_id varchar(255), step varchar(32) CHECK(step IN ('generate','validate','plan','risk_check','apply','health_check')),
  level varchar(16) NOT NULL DEFAULT 'info' CHECK(level IN ('debug','info','warn','error')), message text CHECK(octet_length(message)<=16384),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb, processing_result varchar(32) NOT NULL DEFAULT 'applied' CHECK(processing_result IN ('applied','ignored_stale')),
  source_stream varchar(512), source_offset bigint, source_end_offset bigint, occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,deployment_id), UNIQUE(deployment_id,seq), UNIQUE(source,source_event_id),
  FOREIGN KEY(execution_id,deployment_id) REFERENCES jenkins_execution(id,deployment_id),
  FOREIGN KEY(deployment_target_id,deployment_id) REFERENCES deployment_target(id,deployment_id),
  FOREIGN KEY(execution_id,deployment_target_id) REFERENCES execution_target(execution_id,deployment_target_id),
  CHECK((source_stream IS NULL AND source_offset IS NULL AND source_end_offset IS NULL)
    OR (source_stream IS NOT NULL AND source_offset IS NOT NULL AND source_end_offset IS NOT NULL AND source_offset>=0 AND source_end_offset>source_offset))
);
CREATE UNIQUE INDEX deployment_log_offset_idx ON deployment_log(source_stream,source_offset) WHERE source_stream IS NOT NULL;
CREATE INDEX deployment_log_target_seq_idx ON deployment_log(deployment_id,deployment_target_id,seq);
CREATE INDEX deployment_log_occurrence_idx ON deployment_log(execution_id,stage_occurrence_id);

CREATE TABLE project_event (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, project_id varchar(64) NOT NULL REFERENCES project(id),
  deployment_id varchar(64), source_version_id varchar(64), deployment_log_id bigint, seq bigint NOT NULL CHECK(seq>=1),
  source varchar(512) NOT NULL, source_event_id varchar(255) NOT NULL, payload_hash varchar(128) NOT NULL, event_type varchar(64) NOT NULL,
  payload jsonb NOT NULL, occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(project_id,seq), UNIQUE(project_id,source,source_event_id),
  FOREIGN KEY(deployment_id,project_id) REFERENCES deployment(id,project_id), FOREIGN KEY(source_version_id,project_id) REFERENCES source_version(id,project_id),
  FOREIGN KEY(deployment_log_id,deployment_id) REFERENCES deployment_log(id,deployment_id), CHECK(deployment_log_id IS NULL OR deployment_id IS NOT NULL)
);
CREATE UNIQUE INDEX project_event_projection_idx ON project_event(deployment_log_id) WHERE deployment_log_id IS NOT NULL;

CREATE TABLE idempotency (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, actor_id varchar(64) NOT NULL REFERENCES account(id), project_id varchar(64) NOT NULL REFERENCES project(id),
  operation varchar(64) NOT NULL, resource_key varchar(255) NOT NULL, request_key varchar(255) NOT NULL, request_hash varchar(128) NOT NULL,
  deployment_id varchar(64), response_status smallint NOT NULL CHECK(response_status BETWEEN 200 AND 599), response_body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(actor_id,project_id,operation,resource_key,request_key),
  FOREIGN KEY(deployment_id,project_id) REFERENCES deployment(id,project_id)
);
CREATE INDEX idempotency_deployment_idx ON idempotency(deployment_id);

CREATE TABLE target_lock (
  state_identity varchar(512) PRIMARY KEY, execution_id varchar(64) NOT NULL, deployment_target_id varchar(64) NOT NULL,
  acquired_at timestamptz NOT NULL DEFAULT now(), UNIQUE(execution_id,deployment_target_id),
  FOREIGN KEY(execution_id,deployment_target_id) REFERENCES execution_target(execution_id,deployment_target_id)
);

-- Close SH-owned cycles after every referenced table exists. Nullable pointers are set last by services.
ALTER TABLE deployment_target ADD CONSTRAINT deployment_target_script_fk
  FOREIGN KEY(script_id,project_id,target_id) REFERENCES script(id,project_id,target_id);
ALTER TABLE deployment_target ADD CONSTRAINT deployment_target_current_plan_fk
  FOREIGN KEY(current_plan_id,id) REFERENCES plan_revision(id,deployment_target_id);
ALTER TABLE deployment_target ADD CONSTRAINT deployment_target_current_execution_fk
  FOREIGN KEY(current_execution_id,id) REFERENCES execution_target(execution_id,deployment_target_id);
ALTER TABLE execution_target ADD CONSTRAINT execution_target_plan_fk
  FOREIGN KEY(plan_id,deployment_target_id) REFERENCES plan_revision(id,deployment_target_id);
