-- V1__init.sql (17개 테이블) 제약 검사 — 자동 판정
--   bash server/docs/eh/sql/verify.sh
--
-- 각 검사는 "막혀야 함(t_blocked)" 또는 "통과해야 함(t_ok)" 으로 선언한다.
-- 예상과 다르면 FAIL 로 기록하고, 마지막에 FAIL 이 하나라도 있으면 예외를 던져
-- psql 이 0 이 아닌 코드로 끝난다. 사람이 로그를 눈으로 훑지 않아도 된다.
--
-- 검사 항목 (먼저 정한 것)
--   T1  다른 프로젝트의 source_version 으로 배포            막혀야 함
--   T2  다른 프로젝트의 target 을 배포에 붙이기             막혀야 함
--   T3  자기 자신을 되돌리는 배포                           막혀야 함
--   T4  kind='normal' 인데 lineage 가 채워짐                막혀야 함
--   T5  kind='rollback' 인데 rollback_of 가 없음            막혀야 함
--   T6  한 배포에 같은 state_identity 대상 두 개            막혀야 함
--   T7  한 배포에 같은 target 두 번                         막혀야 함
--   T8  deployment_target.attempt = 4                       막혀야 함
--   T9  취소 요청자만 있고 시각이 없음                      막혀야 함
--   T10 살아 있는 plan 두 개 (state=active)                 막혀야 함
--   T11 살아 있는 승인 두 개 (state=pending)                막혀야 함
--   T12 state=approved 인데 decision=rejected               막혀야 함
--   T13 만료 승인을 expired 로 내린 뒤 새 승인              통과해야 함
--   T14 같은 state_identity 락 2건                          막혀야 함
--   T15 deployment_log.seq = 0                              막혀야 함
--   T16 같은 멱등 scope + key 두 번                         막혀야 함
--   T18 state=approved 인데 결정 3종이 모두 NULL            막혀야 함  ← 승환 발견 (PR #32)
--   T19 ai_usage.attempt = 0                                막혀야 함
--   T20 ai_usage.attempt = 4                                막혀야 함
--   T21 ai_usage.cost_usd 가 음수                           막혀야 함
--   T22 cost_usd 만 있고 cost_basis 가 없음                 막혀야 함
--   T23 execution_target.plan_id 만 있고 plan_digest 없음   막혀야 함
--   T24 account.role 이 목록 밖                             막혀야 함
--   T25 target.environment_type 이 목록 밖                  막혀야 함
--   T26 source_version.status 가 목록 밖                    막혀야 함
--   T27 plan_revision.state = 'invalidated' (설계 3값 밖)   막혀야 함
--   T28 설계가 지정한 DB 기본값이 실제로 붙어 있는지        통과해야 함
--   T17 FK 걸린 컬럼에 인덱스 없는 곳                       참고 목록 (판정 안 함)

\set ON_ERROR_STOP on
\pset pager off

-- ────────────────────────────────── 판정 장치

CREATE TEMP TABLE t_result (
  seq    serial PRIMARY KEY,
  label  text,
  expect text,
  status text,
  detail text
);

-- 막혀야 하는 문장. 예외가 나면 PASS, 통과하면 FAIL.
CREATE FUNCTION t_blocked(p_label text, p_stmt text) RETURNS void AS $fn$
BEGIN
  BEGIN
    EXECUTE p_stmt;
  EXCEPTION WHEN others THEN
    INSERT INTO t_result (label, expect, status, detail)
    VALUES (p_label, '막힘', 'PASS', SQLSTATE || ' ' || split_part(SQLERRM, chr(10), 1));
    RETURN;
  END;
  INSERT INTO t_result (label, expect, status, detail)
  VALUES (p_label, '막힘', 'FAIL', '막혀야 하는데 통과했다');
END $fn$ LANGUAGE plpgsql;

-- 통과해야 하는 문장. 예외가 나면 FAIL.
CREATE FUNCTION t_ok(p_label text, p_stmt text) RETURNS void AS $fn$
BEGIN
  EXECUTE p_stmt;
  INSERT INTO t_result (label, expect, status, detail)
  VALUES (p_label, '통과', 'PASS', '');
EXCEPTION WHEN others THEN
  INSERT INTO t_result (label, expect, status, detail)
  VALUES (p_label, '통과', 'FAIL', SQLSTATE || ' ' || split_part(SQLERRM, chr(10), 1));
END $fn$ LANGUAGE plpgsql;

-- ────────────────────────────────── 씨앗
-- 씨앗이 CHECK 를 어기면 여기서 바로 멈춘다 (ON_ERROR_STOP on).

INSERT INTO account (id,username,password_hash,display_name,role)
VALUES ('acc_1','demo','h','데모','owner'),
       ('acc_2','viewer','h','뷰어','viewer');

INSERT INTO project (id,name,repository_id,repository_url,default_branch,created_by)
VALUES ('prj_1','mono','org/mono','https://github.com/org/mono','main','acc_1'),
       ('prj_2','other','org/other','https://github.com/org/other','main','acc_1');

INSERT INTO target (id,project_id,name,environment_type,state_identity,config,connection_state)
VALUES ('tgt_aws','prj_1','aws-tokyo','aws','prj_1/tgt_aws/terraform.tfstate','{}'::jsonb,'connected'),
       ('tgt_gcp','prj_1','gcp-asia','gcp','prj_1/tgt_gcp/terraform.tfstate','{}'::jsonb,'connected'),
       ('tgt_dup','prj_1','aws-dup','aws','prj_1/tgt_aws/terraform.tfstate','{}'::jsonb,'connected'),
       ('tgt_p2','prj_2','aws-other','aws','prj_2/tgt_p2/terraform.tfstate','{}'::jsonb,'unknown');

INSERT INTO source_version (id,project_id,source,external_build_id,commit_sha,status)
VALUES ('src_1','prj_1','jenkins/daisy-build','101',repeat('a',40),'succeeded'),
       ('src_p2','prj_2','jenkins/daisy-build','102',repeat('c',40),'succeeded');

INSERT INTO deployment (id,project_id,source_version_id,requested_by,commit_sha,
                        repository_snapshot,input_snapshot,request_hash)
VALUES ('dep_1','prj_1','src_1','acc_1',repeat('a',40),'{}'::jsonb,'{}'::jsonb,'h1');

INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity)
VALUES ('dt_1','dep_1','prj_1','tgt_aws','{}'::jsonb,'prj_1/tgt_aws/terraform.tfstate');

INSERT INTO jenkins_execution (id,deployment_id,request_id,operation,instance_id,job_full_name,
                               request_payload,request_hash,dispatch_status,run_status)
VALUES ('je_1','dep_1','req-1','prepare','jk1','daisy/prepare','{}'::jsonb,'h','accepted','running');

INSERT INTO execution_target (execution_id,deployment_target_id,deployment_id,status)
VALUES ('je_1','dt_1','dep_1','running');

INSERT INTO script (id,project_id,target_id,version,source,external_script_id,
                    source_deployment_target_id,artifact_ref,content_digest,validated_at)
VALUES ('scr_1','prj_1','tgt_aws',1,'jenkins','s1','dt_1','s3://x','sha256:1',now());

INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                           source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                           expires_at)
VALUES ('pl_1','dt_1','je_1','prj_1','tgt_aws',1,'jenkins','p1','ih','scr_1','s3://p','sha256:p',
        '{}'::jsonb,'[]'::jsonb,now()+interval '1 hour');

-- ────────────────────────────────── 프로젝트 경계 · lineage

SELECT t_blocked('T1  다른 프로젝트의 source_version 으로 배포', $$
  INSERT INTO deployment (id,project_id,source_version_id,requested_by,commit_sha,
                          repository_snapshot,input_snapshot,request_hash)
  VALUES ('dep_x1','prj_1','src_p2','acc_1',repeat('c',40),'{}'::jsonb,'{}'::jsonb,'h2') $$);

SELECT t_blocked('T2  다른 프로젝트의 target 을 배포에 붙이기', $$
  INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity)
  VALUES ('dt_x2','dep_1','prj_1','tgt_p2','{}'::jsonb,'prj_2/tgt_p2/terraform.tfstate') $$);

SELECT t_blocked('T3  자기 자신을 되돌리는 배포', $$
  INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,rollback_of_deployment_id,
                          commit_sha,repository_snapshot,input_snapshot,request_hash)
  VALUES ('dep_x3','prj_1','src_1','acc_1','rollback','dep_x3',repeat('a',40),
          '{}'::jsonb,'{}'::jsonb,'h3') $$);

SELECT t_blocked('T4  kind=normal 인데 lineage 가 채워짐', $$
  INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,retry_of_deployment_id,
                          commit_sha,repository_snapshot,input_snapshot,request_hash)
  VALUES ('dep_x4','prj_1','src_1','acc_1','normal','dep_1',repeat('a',40),
          '{}'::jsonb,'{}'::jsonb,'h4') $$);

SELECT t_blocked('T5  kind=rollback 인데 rollback_of 가 없음', $$
  INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,
                          commit_sha,repository_snapshot,input_snapshot,request_hash)
  VALUES ('dep_x5','prj_1','src_1','acc_1','rollback',repeat('a',40),
          '{}'::jsonb,'{}'::jsonb,'h5') $$);

-- ────────────────────────────────── 대상 중복 · 범위

SELECT t_blocked('T6  한 배포에 같은 state_identity 대상 두 개', $$
  INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity)
  VALUES ('dt_x6','dep_1','prj_1','tgt_dup','{}'::jsonb,'prj_1/tgt_aws/terraform.tfstate') $$);

SELECT t_blocked('T7  한 배포에 같은 target 두 번', $$
  INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity)
  VALUES ('dt_x7','dep_1','prj_1','tgt_aws','{}'::jsonb,'prj_1/tgt_aws/x') $$);

SELECT t_blocked('T8  deployment_target.attempt = 4',
  $$ UPDATE deployment_target SET attempt = 4 WHERE id='dt_1' $$);

SELECT t_blocked('T9  취소 요청자만 있고 시각이 없음',
  $$ UPDATE deployment_target SET cancel_requested_by='acc_1' WHERE id='dt_1' $$);

-- ────────────────────────────────── 살아 있는 것은 하나

SELECT t_blocked('T10 살아 있는 plan 두 개', $$
  INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                             source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                             expires_at)
  VALUES ('pl_2','dt_1','je_1','prj_1','tgt_aws',2,'jenkins','p2','ih','scr_1','s3://p','sha256:p',
          '{}'::jsonb,'[]'::jsonb,now()+interval '1 hour') $$);

INSERT INTO approval (id,plan_id,deployment_target_id,expires_at)
VALUES ('apv_1','pl_1','dt_1',now()+interval '1 hour');

INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                           source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                           state,expires_at)
VALUES ('pl_3','dt_1','je_1','prj_1','tgt_aws',3,'jenkins','p3','ih','scr_1','s3://p','sha256:p',
        '{}'::jsonb,'[]'::jsonb,'superseded',now()+interval '1 hour');

SELECT t_blocked('T11 살아 있는 승인 두 개', $$
  INSERT INTO approval (id,plan_id,deployment_target_id,expires_at)
  VALUES ('apv_2','pl_3','dt_1',now()+interval '1 hour') $$);

-- ────────────────────────────────── 승인 상태와 결정

SELECT t_blocked('T12 state=approved 인데 decision=rejected', $$
  UPDATE approval SET state='approved', decision='rejected', decided_by='acc_1', decided_at=now()
  WHERE id='apv_1' $$);

-- 승환이 PR #32 에서 찾은 구멍.
-- 예전 CHECK 는 (state NOT IN (...) OR decision = state) 였고, decision 이 NULL 이면
-- (NULL = 'approved') 가 NULL 이 되어 CHECK 전체가 NULL → PostgreSQL 은 통과시킨다.
SELECT t_blocked('T18 state=approved 인데 결정 3종이 모두 NULL',
  $$ UPDATE approval SET state='approved' WHERE id='apv_1' $$);

SELECT t_ok('T13 만료 승인을 expired 로 내린 뒤 새 승인', $$
  UPDATE approval SET state='expired' WHERE id='apv_1';
  INSERT INTO approval (id,plan_id,deployment_target_id,expires_at)
  VALUES ('apv_3','pl_3','dt_1',now()+interval '1 hour') $$);

-- ────────────────────────────────── 락 · 로그 · 멱등

INSERT INTO target_lock (state_identity,execution_id,deployment_target_id)
VALUES ('prj_1/tgt_aws/terraform.tfstate','je_1','dt_1');

SELECT t_blocked('T14 같은 state_identity 락 2건', $$
  INSERT INTO target_lock (state_identity,execution_id,deployment_target_id)
  VALUES ('prj_1/tgt_aws/terraform.tfstate','je_1','dt_1') $$);

SELECT t_blocked('T15 deployment_log.seq = 0', $$
  INSERT INTO deployment_log (deployment_id,seq,source,source_event_id,payload_hash,event_type,
                              occurred_at)
  VALUES ('dep_1',0,'jenkins','e0','h','log',now()) $$);

INSERT INTO idempotency (actor_id,project_id,operation,resource_key,request_key,request_hash,
                         response_status,response_body)
VALUES ('acc_1','prj_1','create','prj_1','key-1','h',201,'{}'::jsonb);

SELECT t_blocked('T16 같은 멱등 scope + key 두 번', $$
  INSERT INTO idempotency (actor_id,project_id,operation,resource_key,request_key,request_hash,
                           response_status,response_body)
  VALUES ('acc_1','prj_1','create','prj_1','key-1','h',201,'{}'::jsonb) $$);

-- ────────────────────────────────── AI 사용량 (PR #32 에서 추가)
-- attempt 는 개별 API 호출 횟수가 아니라 생성·수정 회차(1~3)다 — 승환 확인

INSERT INTO ai_usage (id,execution_id,deployment_target_id,source,external_call_id,payload_hash,
                      provider,model,step,attempt,status,occurred_at)
VALUES ('ai_1','je_1','dt_1','infra/plan_with_ai','call-1','h','anthropic','claude-opus-5-5',
        'generate',1,'succeeded',now());

SELECT t_blocked('T19 ai_usage.attempt = 0', $$
  INSERT INTO ai_usage (id,execution_id,deployment_target_id,source,external_call_id,payload_hash,
                        provider,model,step,attempt,status,occurred_at)
  VALUES ('ai_x0','je_1','dt_1','infra/plan_with_ai','call-x0','h','anthropic','claude-opus-5-5',
          'generate',0,'succeeded',now()) $$);

SELECT t_blocked('T20 ai_usage.attempt = 4', $$
  INSERT INTO ai_usage (id,execution_id,deployment_target_id,source,external_call_id,payload_hash,
                        provider,model,step,attempt,status,occurred_at)
  VALUES ('ai_x4','je_1','dt_1','infra/plan_with_ai','call-x4','h','anthropic','claude-opus-5-5',
          'generate',4,'succeeded',now()) $$);

SELECT t_blocked('T21 ai_usage.cost_usd 가 음수',
  $$ UPDATE ai_usage SET cost_usd = -1, cost_basis = 'fixed' WHERE id='ai_1' $$);

SELECT t_blocked('T22 cost_usd 만 있고 cost_basis 가 없음',
  $$ UPDATE ai_usage SET cost_usd = 0.5 WHERE id='ai_1' $$);

-- ────────────────────────────────── 동반 존재 · 상태 목록 (PR #32 에서 추가)

SELECT t_blocked('T23 execution_target.plan_id 만 있고 plan_digest 없음',
  $$ UPDATE execution_target SET plan_id='pl_1'
     WHERE execution_id='je_1' AND deployment_target_id='dt_1' $$);

SELECT t_blocked('T24 account.role 이 목록 밖',
  $$ UPDATE account SET role='superuser' WHERE id='acc_1' $$);

SELECT t_blocked('T25 target.environment_type 이 목록 밖',
  $$ UPDATE target SET environment_type='azure' WHERE id='tgt_aws' $$);

SELECT t_blocked('T26 source_version.status 가 목록 밖',
  $$ UPDATE source_version SET status='cancelled' WHERE id='src_1' $$);

SELECT t_blocked('T27 plan_revision.state = invalidated (설계 3값 밖)',
  $$ UPDATE plan_revision SET state='invalidated' WHERE id='pl_3' $$);

-- ────────────────────────────────── 설계가 지정한 기본값

SELECT t_ok('T28 설계 기본값 14개가 실제로 붙어 있다', $$
  DO $inner$
  DECLARE missing text;
  BEGIN
    SELECT string_agg(x.t || '.' || x.c, ', ') INTO missing
    FROM (VALUES
      ('project','manifest_path'), ('target','connection_state'),
      ('source_version','status'),
      ('deployment','kind'), ('deployment','status'),
      ('deployment_target','status'),
      ('jenkins_execution','dispatch_status'), ('jenkins_execution','run_status'),
      ('execution_target','status'),
      ('plan_revision','state'), ('approval','state'),
      ('deployment_log','level'), ('deployment_log','payload'),
      ('deployment_log','processing_result')
    ) AS x(t,c)
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns ic
      WHERE ic.table_schema='public' AND ic.table_name=x.t
        AND ic.column_name=x.c AND ic.column_default IS NOT NULL);
    IF missing IS NOT NULL THEN
      RAISE EXCEPTION '기본값 없음: %', missing;
    END IF;
  END $inner$;
$$);

-- ────────────────────────────────── 결과

\echo ''
\echo '=== 검사 결과'
SELECT label, expect, status, detail FROM t_result ORDER BY seq;

\echo ''
\echo '=== 참고: FK 걸린 컬럼에 인덱스가 없는 곳 (삭제·조인이 느려지는 자리, 판정 안 함)'
SELECT c.conname, c.conrelid::regclass AS tbl
FROM pg_constraint c
WHERE c.contype='f' AND NOT EXISTS (
  SELECT 1 FROM pg_index i WHERE i.indrelid=c.conrelid
    AND (c.conkey::int[] <@ i.indkey::int[]) AND i.indkey[0]=c.conkey[1]
) ORDER BY 2,1;

\echo ''
DO $$
DECLARE
  n_fail int;
  n_all  int;
  names  text;
BEGIN
  SELECT count(*) FILTER (WHERE status='FAIL'), count(*) INTO n_fail, n_all FROM t_result;
  IF n_fail > 0 THEN
    SELECT string_agg(label, ', ') INTO names FROM t_result WHERE status='FAIL';
    RAISE EXCEPTION '검사 %/% 실패: %', n_fail, n_all, names;
  END IF;
  RAISE NOTICE '검사 %건 전부 예상대로', n_all;
END $$;
