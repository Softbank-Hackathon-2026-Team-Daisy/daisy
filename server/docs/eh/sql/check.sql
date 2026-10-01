-- V1__init.sql (17개 테이블) 제약 검사
--   bash sql/verify.sh
--
-- 검사 항목 (먼저 정한 것)
--   T1  다른 프로젝트의 source_version 으로 배포            막혀야 함
--   T2  다른 프로젝트의 target 을 배포에 붙이기             막혀야 함
--   T3  자기 자신을 되돌리는 배포                           막혀야 함
--   T4  kind='normal' 인데 lineage 가 채워짐                막혀야 함
--   T5  kind='rollback' 인데 rollback_of 가 없음            막혀야 함
--   T6  한 배포에 같은 state_identity 대상 두 개            막혀야 함
--   T7  한 배포에 같은 target 두 번                         막혀야 함
--   T8  attempt = 4                                         막혀야 함
--   T9  취소 요청자만 있고 시각이 없음                      막혀야 함
--   T10 살아 있는 plan 두 개 (state=active)                 막혀야 함
--   T11 살아 있는 승인 두 개 (state=pending)                막혀야 함
--   T12 state=approved 인데 decision=rejected               막혀야 함
--   T13 만료 승인을 expired 로 내린 뒤 새 승인              통과해야 함
--   T14 같은 state_identity 동시 락 2건 → 1건만             막혀야 함
--   T15 deployment_log.seq = 0                              막혀야 함
--   T16 같은 멱등 scope + key 두 번                         막혀야 함
--   T17 FK 걸린 컬럼에 인덱스 없는 곳                       목록만 출력

\set ON_ERROR_STOP off
\pset pager off

SELECT count(*) AS tables FROM information_schema.tables WHERE table_schema='public';

-- ── 씨앗
INSERT INTO account (id,username,password_hash,display_name,role,created_at,updated_at)
VALUES ('acc_1','demo','h','데모','owner',now(),now()),
       ('acc_2','viewer','h','뷰어','viewer',now(),now());

INSERT INTO project (id,name,repository_id,repository_url,default_branch,manifest_path,created_by,created_at,updated_at)
VALUES ('prj_1','mono','org/mono','https://github.com/org/mono','main','deploy.yaml','acc_1',now(),now()),
       ('prj_2','other','org/other','https://github.com/org/other','main','deploy.yaml','acc_1',now(),now());

INSERT INTO target (id,project_id,name,environment_type,state_identity,config,connection_state,created_at,updated_at)
VALUES ('tgt_aws','prj_1','aws-tokyo','aws','prj_1/tgt_aws/terraform.tfstate','{}'::jsonb,'ok',now(),now()),
       ('tgt_gcp','prj_1','gcp-asia','gcp','prj_1/tgt_gcp/terraform.tfstate','{}'::jsonb,'ok',now(),now()),
       ('tgt_dup','prj_1','aws-dup','aws','prj_1/tgt_aws/terraform.tfstate','{}'::jsonb,'ok',now(),now()),
       ('tgt_p2','prj_2','aws-other','aws','prj_2/tgt_p2/terraform.tfstate','{}'::jsonb,'ok',now(),now());

INSERT INTO source_version (id,project_id,source,external_build_id,commit_sha,status,received_at)
VALUES ('src_1','prj_1','jenkins/daisy-build','101',repeat('a',40),'succeeded',now()),
       ('src_p2','prj_2','jenkins/daisy-build','102',repeat('c',40),'succeeded',now());

INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,commit_sha,
                        repository_snapshot,input_snapshot,request_hash,status,created_at)
VALUES ('dep_1','prj_1','src_1','acc_1','normal',repeat('a',40),'{}'::jsonb,'{}'::jsonb,'h1','queued',now());

INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity,status)
VALUES ('dt_1','dep_1','prj_1','tgt_aws','{}'::jsonb,'prj_1/tgt_aws/terraform.tfstate','waiting');

\echo ''
\echo '--- T1 다른 프로젝트의 source_version 으로 배포 → 막혀야 함'
INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,commit_sha,
                        repository_snapshot,input_snapshot,request_hash,status,created_at)
VALUES ('dep_x1','prj_1','src_p2','acc_1','normal',repeat('c',40),'{}'::jsonb,'{}'::jsonb,'h2','queued',now());

\echo '--- T2 다른 프로젝트의 target 을 배포에 붙이기 → 막혀야 함'
INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity,status)
VALUES ('dt_x2','dep_1','prj_1','tgt_p2','{}'::jsonb,'prj_2/tgt_p2/terraform.tfstate','waiting');

\echo '--- T3 자기 자신을 되돌리는 배포 → 막혀야 함'
INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,rollback_of_deployment_id,
                        commit_sha,repository_snapshot,input_snapshot,request_hash,status,created_at)
VALUES ('dep_x3','prj_1','src_1','acc_1','rollback','dep_x3',repeat('a',40),'{}'::jsonb,'{}'::jsonb,'h3','queued',now());

\echo '--- T4 kind=normal 인데 lineage 가 채워짐 → 막혀야 함'
INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,retry_of_deployment_id,
                        commit_sha,repository_snapshot,input_snapshot,request_hash,status,created_at)
VALUES ('dep_x4','prj_1','src_1','acc_1','normal','dep_1',repeat('a',40),'{}'::jsonb,'{}'::jsonb,'h4','queued',now());

\echo '--- T5 kind=rollback 인데 rollback_of 가 없음 → 막혀야 함'
INSERT INTO deployment (id,project_id,source_version_id,requested_by,kind,
                        commit_sha,repository_snapshot,input_snapshot,request_hash,status,created_at)
VALUES ('dep_x5','prj_1','src_1','acc_1','rollback',repeat('a',40),'{}'::jsonb,'{}'::jsonb,'h5','queued',now());

\echo '--- T6 한 배포에 같은 state_identity 대상 두 개 → 막혀야 함'
INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity,status)
VALUES ('dt_x6','dep_1','prj_1','tgt_dup','{}'::jsonb,'prj_1/tgt_aws/terraform.tfstate','waiting');

\echo '--- T7 한 배포에 같은 target 두 번 → 막혀야 함'
INSERT INTO deployment_target (id,deployment_id,project_id,target_id,target_snapshot,state_identity,status)
VALUES ('dt_x7','dep_1','prj_1','tgt_aws','{}'::jsonb,'prj_1/tgt_aws/x','waiting');

\echo '--- T8 attempt = 4 → 막혀야 함'
UPDATE deployment_target SET attempt = 4 WHERE id='dt_1';

\echo '--- T9 취소 요청자만 있고 시각이 없음 → 막혀야 함'
UPDATE deployment_target SET cancel_requested_by='acc_1' WHERE id='dt_1';

-- ── plan·승인 준비
INSERT INTO jenkins_execution (id,deployment_id,request_id,operation,instance_id,job_full_name,
                               request_payload,request_hash,dispatch_status,run_status,created_at)
VALUES ('je_1','dep_1','req-1','prepare','jk1','daisy/prepare','{}'::jsonb,'h','accepted','running',now());
INSERT INTO execution_target (execution_id,deployment_target_id,deployment_id,status)
VALUES ('je_1','dt_1','dep_1','running');
INSERT INTO script (id,project_id,target_id,version,source,external_script_id,source_deployment_target_id,
                    artifact_ref,content_digest,validated_at,received_at)
VALUES ('scr_1','prj_1','tgt_aws',1,'jenkins','s1','dt_1','s3://x','sha256:1',now(),now());
INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                           source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                           state,created_at,expires_at)
VALUES ('pl_1','dt_1','je_1','prj_1','tgt_aws',1,'jenkins','p1','ih','scr_1','s3://p','sha256:p',
        '{}'::jsonb,'[]'::jsonb,'active',now(),now()+interval '1 hour');

\echo '--- T10 살아 있는 plan 두 개 → 막혀야 함'
INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                           source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                           state,created_at,expires_at)
VALUES ('pl_2','dt_1','je_1','prj_1','tgt_aws',2,'jenkins','p2','ih','scr_1','s3://p','sha256:p',
        '{}'::jsonb,'[]'::jsonb,'active',now(),now()+interval '1 hour');

INSERT INTO approval (id,plan_id,deployment_target_id,state,created_at,expires_at)
VALUES ('apv_1','pl_1','dt_1','pending',now(),now()+interval '1 hour');

\echo '--- T11 살아 있는 승인 두 개 → 막혀야 함'
INSERT INTO plan_revision (id,deployment_target_id,execution_id,project_id,target_id,revision,source,
                           source_plan_id,input_hash,script_id,artifact_ref,digest,summary,resources,
                           state,created_at,expires_at)
VALUES ('pl_3','dt_1','je_1','prj_1','tgt_aws',3,'jenkins','p3','ih','scr_1','s3://p','sha256:p',
        '{}'::jsonb,'[]'::jsonb,'superseded',now(),now()+interval '1 hour');
INSERT INTO approval (id,plan_id,deployment_target_id,state,created_at,expires_at)
VALUES ('apv_2','pl_3','dt_1','pending',now(),now()+interval '1 hour');

\echo '--- T12 state=approved 인데 decision=rejected → 막혀야 함'
UPDATE approval SET state='approved', decision='rejected', decided_by='acc_1', decided_at=now()
WHERE id='apv_1';

\echo '--- T13 만료 승인을 expired 로 내린 뒤 새 승인 → 통과해야 함'
UPDATE approval SET state='expired' WHERE id='apv_1';
INSERT INTO approval (id,plan_id,deployment_target_id,state,created_at,expires_at)
VALUES ('apv_3','pl_3','dt_1','pending',now(),now()+interval '1 hour');
SELECT count(*) AS t13_new_approval FROM approval WHERE id='apv_3';

\echo '--- T14 같은 state_identity 동시 락 2건 → 1건만'
INSERT INTO target_lock (state_identity,execution_id,deployment_target_id,acquired_at)
VALUES ('prj_1/tgt_aws/terraform.tfstate','je_1','dt_1',now());
INSERT INTO target_lock (state_identity,execution_id,deployment_target_id,acquired_at)
VALUES ('prj_1/tgt_aws/terraform.tfstate','je_1','dt_1',now());

\echo '--- T15 deployment_log.seq = 0 → 막혀야 함'
INSERT INTO deployment_log (deployment_id,seq,source,source_event_id,payload_hash,event_type,
                            occurred_at,received_at)
VALUES ('dep_1',0,'jenkins','e0','h','log',now(),now());

\echo '--- T16 같은 멱등 scope + key 두 번 → 막혀야 함'
INSERT INTO idempotency (actor_id,project_id,operation,resource_key,request_key,request_hash,
                         response_status,response_body,created_at)
VALUES ('acc_1','prj_1','create','prj_1','key-1','h',201,'{}'::jsonb,now());
INSERT INTO idempotency (actor_id,project_id,operation,resource_key,request_key,request_hash,
                         response_status,response_body,created_at)
VALUES ('acc_1','prj_1','create','prj_1','key-1','h',201,'{}'::jsonb,now());

\echo '--- T17 FK 걸린 컬럼에 인덱스 없는 곳 (삭제·조인이 느려지는 자리)'
SELECT c.conname, c.conrelid::regclass AS tbl
FROM pg_constraint c
WHERE c.contype='f' AND NOT EXISTS (
  SELECT 1 FROM pg_index i WHERE i.indrelid=c.conrelid
    AND (c.conkey::int[] <@ i.indkey::int[]) AND i.indkey[0]=c.conkey[1]
) ORDER BY 2,1;
