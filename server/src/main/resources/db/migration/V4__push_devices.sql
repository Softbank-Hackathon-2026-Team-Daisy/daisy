-- APNs 푸시 기기 토큰과 발송 커서예요 (ios/SPEC.md §6-5 P-01·P-02, server/docs/push.md).
-- V3 는 서버 담당자의 진행 중 PR 몫이라 비워 둬요. 이 V4 는 V3 가 먼저 머지·배포된 뒤에 머지해요.

-- ────────────────────────────────── 기기 토큰
-- 토큰 하나는 한 계정에만 묶여요. 같은 토큰을 다시 등록하면 그 계정으로 옮겨요(upsert).
-- APNs 가 거절한 토큰은 지우지 않고 disabled_at·last_error 를 남겨요. 다시 등록하면 살아나요.
CREATE TABLE push_device (
  apns_token  varchar(200) NOT NULL,
  account_id  varchar(64)  NOT NULL,
  platform    varchar(16)  NOT NULL,
  apns_env    varchar(16)  NOT NULL,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  disabled_at timestamptz,
  last_error  varchar(64),
  CONSTRAINT pk_push_device PRIMARY KEY (apns_token),
  CONSTRAINT fk_push_device_account FOREIGN KEY (account_id) REFERENCES account (id),
  CONSTRAINT ck_push_device_token CHECK (apns_token ~ '^[0-9a-f]{32,200}$'),
  CONSTRAINT ck_push_device_platform CHECK (platform IN ('ios','macos')),
  CONSTRAINT ck_push_device_env CHECK (apns_env IN ('production','sandbox'))
);
CREATE INDEX ix_push_device_account ON push_device (account_id) WHERE disabled_at IS NULL;

-- ────────────────────────────────── 발송 커서
-- deployment_log.id 를 어디까지 처리했는지 적어요. 여러 인스턴스가 같은 이벤트를 두 번 보내지 않게
-- 이 행을 SELECT ... FOR UPDATE 로 잡고 읽어요. 행이 없으면 첫 실행 때 현재 최대 id 로 만들어요.
CREATE TABLE push_cursor (
  name       varchar(64) NOT NULL,
  last_id    bigint      NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_push_cursor PRIMARY KEY (name),
  CONSTRAINT ck_push_cursor_last CHECK (last_id >= 0)
);
