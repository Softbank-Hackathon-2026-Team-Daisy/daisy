-- TEST ONLY: EH-owned management tables. Not an authentication policy or production migration.
CREATE TABLE account (
  id varchar(64) PRIMARY KEY, username varchar(128) NOT NULL UNIQUE,
  password_hash text NOT NULL, display_name varchar(128) NOT NULL, role varchar(32) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), disabled_at timestamptz
);
CREATE TABLE project (
  id varchar(64) PRIMARY KEY, name varchar(128) NOT NULL, repository_id varchar(255) NOT NULL,
  repository_url text NOT NULL, default_branch varchar(255) NOT NULL,
  manifest_path varchar(512) NOT NULL DEFAULT 'deploy.yaml', repository_credential_ref text,
  created_by varchar(64) NOT NULL REFERENCES account(id), last_event_seq bigint NOT NULL DEFAULT 0 CHECK(last_event_seq>=0),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), archived_at timestamptz
);
CREATE INDEX project_created_idx ON project(created_at,id);
CREATE TABLE project_member (
  project_id varchar(64) NOT NULL REFERENCES project(id), account_id varchar(64) NOT NULL REFERENCES account(id),
  granted_by varchar(64) NOT NULL REFERENCES account(id), granted_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz,
  PRIMARY KEY(project_id,account_id)
);
CREATE INDEX project_member_account_idx ON project_member(account_id,project_id);
CREATE TABLE target (
  id varchar(64) PRIMARY KEY, project_id varchar(64) NOT NULL REFERENCES project(id), name varchar(128) NOT NULL,
  environment_type varchar(32) NOT NULL CHECK(environment_type IN ('onprem','aws','gcp','azure')),
  state_identity varchar(512) NOT NULL, config jsonb NOT NULL,
  config_revision bigint NOT NULL DEFAULT 1 CHECK(config_revision>=1), credential_ref text, credential_version varchar(255),
  connection_state varchar(32) NOT NULL DEFAULT 'unknown' CHECK(connection_state IN ('unknown','connected','disconnected')),
  connection_checked_at timestamptz, current_deployment_target_id varchar(64), observed_state jsonb, observed_at timestamptz,
  reuse_assessment jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), archived_at timestamptz,
  UNIQUE(id,project_id)
);
CREATE INDEX target_project_active_idx ON target(project_id,archived_at,id);
CREATE INDEX target_state_idx ON target(state_identity);
CREATE TABLE source_version (
  id varchar(64) PRIMARY KEY, project_id varchar(64) NOT NULL REFERENCES project(id), source varchar(255) NOT NULL,
  external_build_id varchar(255) NOT NULL, commit_sha varchar(64) NOT NULL, branch varchar(255),
  status varchar(32) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','running','succeeded','failed')),
  image_refs jsonb, manifest_snapshot jsonb, manifest_ref text, manifest_digest varchar(128), manifest_schema_version varchar(64),
  run_url text, started_at timestamptz, finished_at timestamptz, error_summary text, received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,project_id), UNIQUE(source,external_build_id),
  CHECK(status<>'succeeded' OR (image_refs IS NOT NULL AND jsonb_typeof(image_refs)='object' AND image_refs<>'{}'::jsonb))
);
CREATE INDEX source_project_received_idx ON source_version(project_id,received_at DESC,id);
CREATE INDEX source_project_commit_idx ON source_version(project_id,commit_sha);
