-- 기존 데이터와 V1 체크섬을 유지하고 Azure 환경만 추가해요.
ALTER TABLE target DROP CONSTRAINT ck_target_env;
ALTER TABLE target ADD CONSTRAINT ck_target_env
    CHECK (environment_type IN ('onprem', 'aws', 'gcp', 'azure'));
