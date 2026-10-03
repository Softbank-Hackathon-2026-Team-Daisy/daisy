// unibloom-platform2-cd: Docker Hub 이미지(커밋 태그)로 개발 서버(172.16.1.5)의 웹 · 백엔드를 교체해요 (infra/SPEC.md §18)
// - Jenkins Job unibloom-platform2-cd의 Pipeline script와 같은 내용이에요. 보통 platform-ci가 IMAGE_TAG를 넣어 시작해요
// - SSH는 Credentials unibloom-prod-ssh(user)예요. Terraform 온프레미스 배포 키(onprem_deploy)와 다른 키라 서로 겹치지 않아요
// - 수동 배포와 같은 파일(/home/user/compose/docker-compose.yml)의 image: 줄만 태그로 바꿔요 (수동 재빌드 명령과 같은 방식)
// - -f를 쓰지 않아서 docker-compose.override.yml(APNs 푸시 설정)이 그대로 같이 적용돼요. .env도 같은 폴더 것을 써요
// - 헬스체크가 실패하면 바꾸기 전 파일로 되돌리고 다시 띄워요
pipeline {
  agent any

  parameters {
    string(name: 'IMAGE_TAG', defaultValue: 'latest', description: '배포할 이미지 태그. CI가 커밋 해시(7자리)로 넘겨요')
    string(name: 'TARGET_HOST', defaultValue: '172.16.1.5', description: '배포할 서버')
    string(name: 'COMPOSE_DIR', defaultValue: '/home/user/compose', description: 'docker-compose.yml · .env가 있는 폴더 (수동 배포와 같은 곳)')
    string(name: 'COMPOSE_PROJECT', defaultValue: 'compose', description: '수동 배포와 같아야 해요 (다르면 빈 DB로 새로 떠요)')
    string(name: 'SERVER_IMAGE', defaultValue: 'docker.io/dlacowns21/unibloom-server', description: '백엔드 이미지 (태그 없이)')
    string(name: 'WEB_IMAGE', defaultValue: 'docker.io/dlacowns21/unibloom-web', description: '프론트 이미지 (태그 없이)')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 15, unit: 'MINUTES')
  }

  stages {
    stage('VM 배포') {
      steps {
        withCredentials([
          sshUserPrivateKey(
            credentialsId: 'unibloom-prod-ssh',
            keyFileVariable: 'SSH_KEY',
            usernameVariable: 'SSH_USER'
          )
        ]) {
          sh '''
set +x
set -eu

ssh \
  -i "$SSH_KEY" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=yes \
  "$SSH_USER"@"$TARGET_HOST" \
  "COMPOSE_DIR='$COMPOSE_DIR' \
   COMPOSE_PROJECT='$COMPOSE_PROJECT' \
   IMAGE_TAG='$IMAGE_TAG' \
   SERVER_IMAGE='$SERVER_IMAGE' \
   WEB_IMAGE='$WEB_IMAGE' \
   bash -s" <<'REMOTE'

set -euo pipefail

fail() {
  echo "오류: $1" >&2
  exit 1
}

echo '1. 접속 · 입력 확인'
hostname
whoami
echo "Compose 경로: $COMPOSE_DIR (프로젝트 $COMPOSE_PROJECT)"
echo "Backend 이미지: $SERVER_IMAGE:$IMAGE_TAG"
echo "Frontend 이미지: $WEB_IMAGE:$IMAGE_TAG"

# sed에 그대로 들어가는 값이라 허용 글자만 받아요
printf '%s' "$IMAGE_TAG" | grep -Eq '^[A-Za-z0-9._-]{1,64}$' || fail "IMAGE_TAG 형식이 맞지 않아요: $IMAGE_TAG"
printf '%s' "$SERVER_IMAGE$WEB_IMAGE" | grep -Eq '^[a-z0-9./:-]+$' || fail '이미지 주소 형식이 맞지 않아요'

cd "$COMPOSE_DIR" || fail "디렉터리가 없어요: $COMPOSE_DIR"
[ -w docker-compose.yml ] || fail 'docker-compose.yml을 고칠 수 없어요 (권한 확인)'
[ -r .env ] || fail '.env가 필요해요'
docker info >/dev/null || fail 'Docker 데몬 상태 또는 사용자 Docker 권한을 확인하세요'

# -f 없이 기본 파일(docker-compose.yml + docker-compose.override.yml)을 읽어요
compose() {
  docker compose -p "$COMPOSE_PROJECT" "$@"
}

echo '2. image: 줄을 태그로 바꾸기 (백업 후)'

backup="docker-compose.yml.bak-jenkins-$(date +%m%d%H%M)"
cp -a docker-compose.yml "$backup"
echo "백업: $backup"

sed -i \
  -e "/image:.*unibloom-server:/ s#image:.*#image: $SERVER_IMAGE:$IMAGE_TAG#" \
  -e "/image:.*unibloom-web:/ s#image:.*#image: $WEB_IMAGE:$IMAGE_TAG#" \
  docker-compose.yml
grep -n 'image:' docker-compose.yml

restore() {
  echo "되돌려요: $backup → docker-compose.yml" >&2
  cp -a "$backup" docker-compose.yml
  compose up -d --no-deps --no-build --force-recreate backend frontend || true
}

echo '3. Compose 설정 확인'

compose config --quiet || { cp -a "$backup" docker-compose.yml; fail 'compose 설정 오류 (파일은 되돌렸어요)'; }
# compose 버전에 따라 --images가 서비스 하나가 아니라 전체 이미지를 여러 줄로 내줘요. 줄 단위로 찾고, docker.io/ 접두어 차이는 무시해요
norm() { sed -e 's#^docker[.]io/##' -e 's#^library/##'; }
images="$(compose config --images | norm)"
printf '%s\\n' "$images" | grep -Fx "$(printf '%s' "$SERVER_IMAGE:$IMAGE_TAG" | norm)" >/dev/null || { echo "$images" >&2; cp -a "$backup" docker-compose.yml; fail 'backend image가 바뀌지 않았어요 (파일은 되돌렸어요)'; }
printf '%s\\n' "$images" | grep -Fx "$(printf '%s' "$WEB_IMAGE:$IMAGE_TAG" | norm)" >/dev/null || { echo "$images" >&2; cp -a "$backup" docker-compose.yml; fail 'frontend image가 바뀌지 않았어요 (파일은 되돌렸어요)'; }
echo "이미지 확인: $(printf '%s' "$images" | tr '\\n' ' ')"

echo '4. Docker Hub 이미지 다운로드'

compose pull backend frontend || { cp -a "$backup" docker-compose.yml; fail '이미지를 받지 못했어요 (파일은 되돌렸어요)'; }

echo '5. DB 시작 · 준비 대기'

compose up -d --no-recreate db

db_ready=false
for attempt in $(seq 1 30); do
  if compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' </dev/null >/dev/null 2>&1; then
    db_ready=true
    break
  fi
  sleep 3
done
[ "$db_ready" = true ] || fail 'DB가 준비되지 않았어요'

echo '6. 프론트와 백엔드 교체'

compose up -d --no-deps --no-build --pull never --force-recreate backend frontend

check_health() {
  local name="$1" url="$2" code=""
  for attempt in $(seq 1 30); do
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 3 --max-time 5 "$url" || true)"
    case "$code" in
      2??) echo "$name 정상: HTTP $code"; return 0 ;;
    esac
    sleep 3
  done
  echo "$name 헬스체크 실패: 마지막 HTTP 응답 $code" >&2
  return 1
}

echo '7. 헬스체크'

if ! check_health '백엔드' 'http://localhost:8080/actuator/health' || ! check_health '프론트' 'http://localhost:3000/'; then
  restore
  fail '헬스체크 실패 — 바꾸기 전 버전으로 되돌렸어요'
fi

echo '8. 최종 컨테이너 상태'

compose ps
docker logs unibloom-server 2>&1 | grep -m1 -E 'push_(enabled|disabled)' || true

echo "배포 완료: $IMAGE_TAG"

REMOTE
          '''
        }
      }
    }
  }

  post {
    success {
      echo "CD 성공: ${params.IMAGE_TAG}"
    }
    failure {
      echo 'CD 실패: 로그에서 마지막 진행 단계와 오류를 확인하세요.'
    }
  }
}
