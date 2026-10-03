-- 회원가입(POST /auth/signup)이 대소문자만 다른 아이디를 막도록 소문자 기준 UNIQUE 를 둬요.
-- V3 는 비워 둔 번호라 쓰지 않아요. 기존 uq_account_username(대소문자 구분)은 그대로 둬요.
CREATE UNIQUE INDEX ux_account_username_lower ON account (lower(username));
