#!/bin/sh
# V1__init.sql (ERD 17개 테이블) 을 빈 Postgres 17 에 올리고 제약이 실제로 막는지 확인한다.
#
#   bash server/docs/eh/sql/verify.sh
#
# 판정은 check.sql 이 한다. 예상과 다른 검사가 하나라도 있으면 psql 이 0 이 아닌 코드로
# 끝나고 이 스크립트도 실패한다. 사람이 로그를 눈으로 훑지 않아도 된다.
#   종료 코드 0  = 전부 예상대로
#   종료 코드 1  = 기동·적용 실패, 또는 검사 중 예상과 다른 것이 있음
#
# macOS · Linux · Windows(Git Bash) 에서 같이 돈다. Docker 만 있으면 된다.
# 컨테이너 이름에 PID 를 붙이고 이 스크립트가 만든 것만 지운다. 기존 컨테이너는 건드리지 않는다.
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
DDL="$DIR/../../../src/main/resources/db/migration/V1__init.sql"
CHECK="$DIR/check.sql"

[ -f "$DDL" ]   || { echo "마이그레이션을 찾을 수 없다: $DDL"; exit 1; }
[ -f "$CHECK" ] || { echo "검사 파일을 찾을 수 없다: $CHECK"; exit 1; }

command -v docker >/dev/null 2>&1 || { echo "docker 가 없다"; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker 데몬이 안 떠 있다"; exit 1; }

NAME="daisy-ddl-verify-$$"
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "컨테이너 이름이 이미 쓰이고 있다: $NAME"
  echo "기존 컨테이너를 지우지 않는다. 잠시 뒤 다시 실행해 달라."
  exit 1
fi

CREATED=0
cleanup() {
  # 이 스크립트가 만든 컨테이너만 지운다.
  [ "$CREATED" = "1" ] && docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# 윈도우에서는 docker cp 의 "보내는 쪽" 경로만 윈도우 형식이어야 한다.
# 받는 쪽(컨테이너 안 경로)은 POSIX 그대로 두고 MSYS_NO_PATHCONV 로 변환을 막는다.
to_host_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

echo "Postgres 17 기동 ($NAME)..."
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=verify-only -e POSTGRES_DB=daisy \
  postgres:17-alpine >/dev/null
CREATED=1

i=0
while [ "$i" -lt 60 ]; do
  if docker exec "$NAME" pg_isready -U postgres -q 2>/dev/null; then break; fi
  sleep 1
  i=$((i + 1))
done
[ "$i" -lt 60 ] || { echo "Postgres 기동 실패"; exit 1; }
echo "  준비됨 (${i}s)"

MSYS_NO_PATHCONV=1 docker cp "$(to_host_path "$DDL")"   "$NAME:/tmp/V1__init.sql" >/dev/null
MSYS_NO_PATHCONV=1 docker cp "$(to_host_path "$CHECK")" "$NAME:/tmp/check.sql"    >/dev/null

echo
echo "=== 1) DDL 적용"
MSYS_NO_PATHCONV=1 docker exec "$NAME" \
  psql -U postgres -d daisy -v ON_ERROR_STOP=1 -q -f /tmp/V1__init.sql
TABLES=$(MSYS_NO_PATHCONV=1 docker exec "$NAME" psql -U postgres -d daisy -tAc \
  "select count(*) from information_schema.tables where table_schema='public'")
echo "  적용됨. 테이블 $TABLES 개"
if [ "$TABLES" != "17" ]; then
  echo "  테이블이 17개가 아니다"
  exit 1
fi

echo
echo "=== 2) 제약 검사 (판정은 check.sql 이 한다)"
if MSYS_NO_PATHCONV=1 docker exec "$NAME" \
     psql -U postgres -d daisy -v ON_ERROR_STOP=1 -q -f /tmp/check.sql; then
  echo
  echo "=== 전부 예상대로"
  exit 0
else
  echo
  echo "=== 예상과 다른 검사가 있다. 위의 FAIL 행을 봐 달라."
  exit 1
fi
