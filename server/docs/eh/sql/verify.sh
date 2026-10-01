#!/bin/sh
# V1__init.sql (PR #19 ERD 17개 테이블) 을 빈 Postgres 17 에 올리고 제약이 실제로 막는지 확인한다.
#
#   bash sql/verify.sh
#
# 검사 항목은 sql/check.sql 머리말에 있다 (T1~T17).
# "막혀야 함" 항목에 ERROR 가 보이면 정상이다.
set -e

NOCONV="MSYS_NO_PATHCONV=1"
DIR=$(cd "$(dirname "$0")" && pwd)
DDL="$DIR/../../../src/main/resources/db/migration"
DDLW="$DDL"
command -v cygpath >/dev/null 2>&1 && DIR=$(cygpath -w "$DIR") && DDLW=$(cygpath -w "$DDL")
NAME=daisy-ddl-verify

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "Postgres 17 기동..."
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=x -e POSTGRES_DB=daisy postgres:17-alpine >/dev/null

i=0
while [ $i -lt 40 ]; do
  docker exec "$NAME" pg_isready -U postgres -q 2>/dev/null && break
  sleep 1; i=$((i + 1))
done
[ $i -lt 40 ] || { echo "Postgres 기동 실패"; exit 1; }
echo "  준비됨 (${i}s)"

env $NOCONV docker cp "$DDLW\V1__init.sql" "$NAME:/tmp/V1__init.sql"
env $NOCONV docker cp "$DIR\check.sql"    "$NAME:/tmp/check.sql"

echo
echo "=== 1) DDL 적용"
env $NOCONV docker exec "$NAME" psql -U postgres -d daisy -v ON_ERROR_STOP=1 -q -f /tmp/V1__init.sql
echo "  OK"

echo
echo "=== 2) 제약 검사 T1~T17"
env $NOCONV docker exec "$NAME" psql -U postgres -d daisy -q -f /tmp/check.sql 2>&1

echo
echo "=== 끝. '막혀야 함' 항목에 ERROR 가 보이면 정상이다."
