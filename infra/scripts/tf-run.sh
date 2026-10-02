#!/usr/bin/env bash
# infra/SPEC.md §3-4 러너 규약의 참고 구현이에요 (Jenkins 러너 · 사람이 직접 실행 공용).
#
#   tf-run.sh <aws|gcp|onprem|aws-network|aws-state|aws-domain|aws-server> <plan|apply|destroy|output|migrate-state>
#
#   aws · gcp · onprem        앱 모듈 (infra/modules/<env>). 매 배포
#   aws-network · aws-state · aws-domain · aws-server   고정 리소스 bootstrap (infra/bootstrap/<stack>). $WORK_ROOT/_bootstrap/<stack>/
#
# state는 환경마다 그 환경의 저장소예요 (SPEC §7-1). AWS 스택은 TF_STATE_BUCKET_AWS가 있으면 S3, GCP는 TF_STATE_BUCKET_GCP가 있으면 GCS, 없으면 로컬
#   onprem은 러너 로컬 (온프레미스 저장소 [미정])
#
# 작업 디렉터리는 레포 밖이에요. state·plan에 비밀값이 들어가요.
#   $WORK_ROOT/$APP/$ENV/state/        로컬 backend의 state (고정, 지우지 않아요. S3로 옮기면 MIGRATED 표시가 남아요)
#   $WORK_ROOT/$APP/$ENV/plans/<id>/   plan마다 분리: src/(모듈 복사본·plan.tfplan) · vars.json · meta.json
#   $WORK_ROOT/$APP/$ENV/current       마지막으로 apply한 plan (output이 써요)
#
# - plan과 apply는 다른 실행이에요 (Jenkins daisy-cd-plan → 승인 → daisy-cd-apply, SPEC §12-7)
# - 승인 대기 중인 plan은 새 plan이 덮어쓰지 않아요. apply는 PLAN_ID로 그 plan만 적용해요
# - 같은 앱·환경에서는 한 번에 한 작업만 돌아요 (flock). state 잠금은 backend가 따로 걸어요
# - 자격증명은 설정하지 않아요. 호출하는 쪽이 환경변수로 넣어요
# - apply·destroy는 승인이 있어야 실행돼요: 터미널에서 환경 이름 입력, 또는 승인된 실행에서 TF_RUN_APPROVED=$ENV
set -euo pipefail
umask 077

usage() {
  cat >&2 <<'EOF'
사용법: tf-run.sh <aws|gcp|onprem|aws-network|aws-state|aws-domain|aws-server> <plan|apply|destroy|output|migrate-state>

  aws · gcp · onprem        앱 모듈 (infra/modules/<env>). IMAGE_TAG 필요
  aws-network · aws-state · aws-domain · aws-server   고정 리소스 bootstrap (infra/bootstrap/<stack>). IMAGE_TAG 필요 없음

  plan           plans/<PLAN_ID>/에 plan을 만들어요 (TF_DESTROY=1이면 삭제 plan)
  apply          plans/<PLAN_ID>/의 plan을 적용해요. 승인 필요
  destroy        삭제 plan을 만들고 바로 적용해요 (터미널용). 승인 필요
  output         마지막으로 apply한 plan의 service_url (bootstrap은 전체 출력 JSON)
  migrate-state  로컬 state를 TF_STATE_BUCKET_AWS로 옮겨요 (S3가 비어 있을 때만). 승인 필요

환경변수
  APP                  앱 이름 (기본 hellocalc). state key와 작업 디렉터리에 써요
  PLAN_ID              plan 식별자. Jenkins는 daisy-cd-plan-<빌드 번호>. plan에서 비우면 manual-<시각>
  IMAGE_TAG            커밋 해시 40자. plan·destroy에 필수 (latest 금지)
  WORK_ROOT            작업 루트, 레포 밖 (기본 ~/daisy-work)
  VAR_FILE             비밀값 없는 변수 파일 (기본 $WORK_ROOT/$APP/$ENV.tfvars.json). plan 때 plan 폴더로 복사해요
  TF_STATE_BUCKET_AWS  AWS 스택의 S3 state 버킷 (key $APP/$ENV/terraform.tfstate, 잠금 use_lockfile). 없으면 로컬 state
  TF_STATE_BUCKET_GCP  GCP의 GCS state 버킷 (prefix $APP/$ENV, 잠금은 GCS가 자동으로). 없으면 로컬 state
  TF_STATE_REGION      state 버킷 리전 (기본 ap-northeast-2)
  EXPECTED_AWS_ACCOUNT apply·destroy 전에 AWS 계정 ID 확인
  EXPECTED_GCP_PROJECT apply·destroy 전에 변수 파일의 project_id 확인
  TF_RUN_APPROVED      승인된 실행(daisy-cd-apply)에서만 $ENV 값으로 설정
  TF_DESTROY=1         plan을 삭제 plan으로 만들어요
  MODULE_SRC           앱 모듈 대신 이 폴더의 코드로 plan해요 (AI 생성 코드, 검증된 스크립트)
  PLAN_ONLY=1          apply·destroy를 막아요 (개인 계정 0원 모드, SPEC §12-5)
EOF
  exit 2
}

die() { echo "tf-run: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || usage
ENV=$1 CMD=$2
case $ENV in
aws | gcp | onprem) KIND=app ;;
aws-network | aws-state | aws-domain | aws-server) KIND=bootstrap ;;
*) usage ;;
esac
case $CMD in plan | apply | destroy | output | migrate-state) ;; *) usage ;; esac

REPO_ROOT=$(cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" && pwd -P)
APP=${APP:-hellocalc}
WORK_ROOT=${WORK_ROOT:-$HOME/daisy-work}
[[ $WORK_ROOT == /* ]] || WORK_ROOT="$PWD/$WORK_ROOT"
case "$WORK_ROOT/" in "$REPO_ROOT/"*) die "WORK_ROOT가 레포 안이에요: $WORK_ROOT" ;; esac
if [[ $KIND == app ]]; then
  MODULE_DIR="${MODULE_SRC:-$REPO_ROOT/infra/modules/$ENV}" # MODULE_SRC: AI가 만든 코드 (infra/ai)
  WORK="$WORK_ROOT/$APP/$ENV"
  STATE_KEY="$APP/$ENV/terraform.tfstate"
  DEFAULT_VAR_FILE="$WORK_ROOT/$APP/$ENV.tfvars.json"
else
  MODULE_DIR="$REPO_ROOT/infra/bootstrap/$ENV"
  WORK="$WORK_ROOT/_bootstrap/$ENV"
  STATE_KEY="_bootstrap/$ENV/terraform.tfstate"
  DEFAULT_VAR_FILE="$WORK_ROOT/_bootstrap/$ENV.tfvars.json"
fi
export TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}
export TF_IN_AUTOMATION=1
mkdir -p "$WORK/state" "$WORK/plans" "$TF_PLUGIN_CACHE_DIR"

# 같은 앱·환경에서 plan·apply가 겹치지 않게 해요
exec 9>"$WORK/.lock"
flock -w "${TF_RUN_LOCK_WAIT:-600}" 9 || die "${WORK#"$WORK_ROOT"/} 에서 다른 작업이 끝나지 않았어요 (${TF_RUN_LOCK_WAIT:-600}초 대기). 끝난 뒤 다시 실행해요"

# state 저장소: 환경마다 그 환경의 저장소 (SPEC §7-1). AWS는 S3, GCP는 GCS, 온프레미스는 러너 로컬
case $ENV in
aws*) BUCKET=${TF_STATE_BUCKET_AWS:-} BKIND=s3 ;;
gcp*) BUCKET=${TF_STATE_BUCKET_GCP:-} BKIND=gcs ;;
*) BUCKET="" BKIND="" ;;
esac
BACKEND=$([[ -n $BUCKET ]] && echo "$BKIND:$BUCKET" || echo local) # plan meta에 남겨서 apply 때 같은 저장소인지 봐요
MIGRATED="$WORK/state/MIGRATED" # migrate-state가 남기는 표시. 내용은 옮긴 곳(s3://…)

PLAN_DIR="" # set_plan_dir에서 정해요
tf() { terraform -chdir="$PLAN_DIR/src" "$@"; }

set_plan_dir() {
  [[ $PLAN_ID =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "PLAN_ID 형식이 맞지 않아요: '$PLAN_ID'"
  PLAN_DIR="$WORK/plans/$PLAN_ID"
}

need_tag() {
  [[ ${IMAGE_TAG:-} =~ ^[0-9a-f]{40}$ ]] || die "IMAGE_TAG는 커밋 해시 40자여야 해요: '${IMAGE_TAG:-}'"
}

init() { # $1 = 디렉터리 (기본 plan 폴더의 src). -reconfigure: 예전 plan 폴더도 지금 backend를 보게 해요
  local dir=${1:-$PLAN_DIR/src}
  local args=(-input=false -no-color -reconfigure)
  if [[ -n $BUCKET && $BKIND == gcs ]]; then
    # GCS는 prefix 아래 default.tfstate에 저장하고 잠금을 자동으로 걸어요
    printf 'terraform {\n  backend "gcs" {}\n}\n' >"$dir/backend.tf"
    args+=(-backend-config="bucket=$BUCKET" -backend-config="prefix=${STATE_KEY%/terraform.tfstate}")
  elif [[ -n $BUCKET ]]; then
    printf 'terraform {\n  backend "s3" {}\n}\n' >"$dir/backend.tf"
    args+=(-backend-config="bucket=$BUCKET"
      -backend-config="key=$STATE_KEY"
      -backend-config="region=${TF_STATE_REGION:-ap-northeast-2}"
      -backend-config="encrypt=true"
      -backend-config="use_lockfile=true")
  else
    # S3로 옮긴 뒤 버킷 설정 없이 돌리면 빈 로컬 state로 전부 새로 만들려고 해요. 그 전에 멈춰요
    [[ ! -f $MIGRATED ]] || die "이 스택의 state는 $(cat "$MIGRATED")로 옮겼어요. TF_STATE_BUCKET_AWS를 설정하고 다시 실행해요"
    printf 'terraform {\n  backend "local" {}\n}\n' >"$dir/backend.tf"
    args+=(-backend-config="path=$WORK/state/terraform.tfstate")
  fi
  [[ -f $dir/.terraform.lock.hcl ]] && args+=(-lockfile=readonly)
  terraform -chdir="$dir" init "${args[@]}"
}

check_account() {
  if [[ $ENV == aws* && -n ${EXPECTED_AWS_ACCOUNT:-} ]]; then
    local actual
    actual=$(aws sts get-caller-identity --query Account --output text)
    [[ $actual == "$EXPECTED_AWS_ACCOUNT" ]] || die "AWS 계정이 달라요: $actual (기대값 $EXPECTED_AWS_ACCOUNT)"
  fi
  if [[ $ENV == gcp && -n ${EXPECTED_GCP_PROJECT:-} ]]; then
    local actual
    actual=$(jq -r '.project_id // empty' "$PLAN_DIR/vars.json")
    [[ $actual == "$EXPECTED_GCP_PROJECT" ]] || die "GCP 프로젝트가 달라요: '$actual' (기대값 $EXPECTED_GCP_PROJECT)"
  fi
}

confirm() {
  [[ ${PLAN_ONLY:-} != 1 ]] || die "PLAN_ONLY=1이라 $CMD 을(를) 막았어요 (개인 계정 0원 모드)"
  if [[ ${TF_RUN_APPROVED:-} == "$ENV" ]]; then
    echo "tf-run: 승인됨 (TF_RUN_APPROVED=$ENV, PLAN_ID=$PLAN_ID)"
    return
  fi
  { : </dev/tty; } 2>/dev/null ||
    die "승인이 필요해요. 터미널에서 실행하거나, 승인된 실행(daisy-cd-apply)에서 TF_RUN_APPROVED=$ENV 로 실행해요"
  printf '%s %s (%s) 을(를) 실행하려면 환경 이름(%s)을 입력하세요: ' "$ENV" "$CMD" "$PLAN_ID" "$ENV" >/dev/tty
  local answer
  read -r answer </dev/tty
  [[ $answer == "$ENV" ]] || die "취소했어요"
}

make_plan() { # $1 = 1이면 삭제 plan
  local var_file=${VAR_FILE:-$DEFAULT_VAR_FILE}
  if [[ $KIND == app ]]; then
    need_tag
    [[ -f $var_file ]] || die "변수 파일이 없어요: $var_file"
  elif [[ ! -f $var_file ]]; then
    var_file=/dev/null # bootstrap은 변수 파일이 없으면 기본값을 써요
  fi
  compgen -G "$MODULE_DIR/*.tf" >/dev/null || die "모듈이 아직 없어요: $MODULE_DIR"
  [[ ! -e $PLAN_DIR ]] || die "같은 PLAN_ID의 plan이 이미 있어요: $PLAN_ID"
  mkdir -p "$PLAN_DIR/src"
  cp "$MODULE_DIR"/*.tf "$PLAN_DIR/src/"
  [[ -f $MODULE_DIR/.terraform.lock.hcl ]] && cp "$MODULE_DIR/.terraform.lock.hcl" "$PLAN_DIR/src/"
  if [[ $var_file == /dev/null ]]; then echo '{}' >"$PLAN_DIR/vars.json"; else cp "$var_file" "$PLAN_DIR/vars.json"; fi
  echo "tf-run: 단계 init" # infra/ai가 실패한 단계를 이 표시로 알아요
  init
  echo "tf-run: 단계 validate"
  tf validate -no-color
  echo "tf-run: 단계 plan"
  local plan_args=()
  [[ $1 == 1 ]] && plan_args+=(-destroy)
  [[ $KIND == app ]] && plan_args+=(-var="image_tag=$IMAGE_TAG")
  tf plan -input=false -no-color ${plan_args[@]+"${plan_args[@]}"} -out=plan.tfplan -var-file="$PLAN_DIR/vars.json"
  # 승인 화면용 요약 한 줄 ("create=3 update=1")
  tf show -json plan.tfplan >"$PLAN_DIR/src/plan.json"
  jq -r '[.resource_changes[]?.change.actions | join("+")]
    | map(select(. != "no-op" and . != "read")) | group_by(.)
    | map("\(.[0])=\(length)") | join(" ")
    | if . == "" then "변경 없음" else . end' "$PLAN_DIR/src/plan.json" | tee "$PLAN_DIR/summary.txt"
  jq -n --arg id "$PLAN_ID" --arg app "$APP" --arg env "$ENV" --arg tag "${IMAGE_TAG:-}" \
    --argjson destroy "$([[ $1 == 1 ]] && echo true || echo false)" \
    --arg sha "$(sha256sum "$PLAN_DIR/src/plan.tfplan" | cut -d' ' -f1)" \
    --arg summary "$(cat "$PLAN_DIR/summary.txt")" --arg at "$(date -u +%FT%TZ)" --arg backend "$BACKEND" \
    '{plan_id: $id, app: $app, env: $env, image_tag: $tag, destroy: $destroy, backend: $backend,
      plan_sha256: $sha, summary: $summary, created_at: $at, applied_at: null}' >"$PLAN_DIR/meta.json"
  echo "tf-run: plan ID $PLAN_ID"
}

apply_plan() {
  [[ -f $PLAN_DIR/meta.json ]] || die "plan이 없어요: $PLAN_ID"
  [[ $(jq -r .applied_at "$PLAN_DIR/meta.json") == null ]] || die "이미 적용한 plan이에요: $PLAN_ID"
  [[ -f $PLAN_DIR/src/plan.tfplan ]] || die "plan 파일이 없어요: $PLAN_ID"
  [[ $(sha256sum "$PLAN_DIR/src/plan.tfplan" | cut -d' ' -f1) == "$(jq -r .plan_sha256 "$PLAN_DIR/meta.json")" ]] ||
    die "plan 파일이 승인한 것과 달라요: $PLAN_ID (다시 plan · 승인해요)"
  # plan을 만든 뒤 state를 S3로 옮겼으면, 그 plan은 옛 state(로컬)에 적용돼요. 다시 plan해야 해요
  local planned_backend
  planned_backend=$(jq -r '.backend // "local"' "$PLAN_DIR/meta.json")
  [[ $planned_backend == "$BACKEND" ]] ||
    die "plan을 만든 뒤 state 위치가 바뀌었어요 (plan: $planned_backend, 지금: $BACKEND). 다시 plan · 승인해요"
  check_account
  confirm
  # 그사이 다른 apply로 state가 바뀌었으면 terraform이 "Saved plan is stale"로 거부해요
  tf apply -input=false -no-color plan.tfplan
  local tmp destroy
  tmp=$(mktemp)
  jq --arg at "$(date -u +%FT%TZ)" '.applied_at = $at' "$PLAN_DIR/meta.json" >"$tmp" && mv "$tmp" "$PLAN_DIR/meta.json"
  rm -f "$PLAN_DIR/src/plan.tfplan" "$PLAN_DIR/src/plan.json" # 비밀값이 들어 있어요
  destroy=$(jq -r .destroy "$PLAN_DIR/meta.json")
  if [[ $destroy == true ]]; then
    rm -f "$WORK/current"
  else
    ln -sfn "plans/$PLAN_ID" "$WORK/current"
    show_output
  fi
}

show_output() { # 앱은 service_url, bootstrap은 전체 출력 JSON
  if [[ $KIND == app ]]; then
    tf output -raw service_url
    echo
  else
    tf output -json
  fi
}

state_summary() { # stdin의 state → {lineage, managed: ["주소=실제 리소스 ID"]}. 비어 있으면 lineage null
  # 같은 인프라인지는 "같은 주소가 같은 실제 리소스 ID를 가리키는지"로 봐요.
  # lineage는 비교하지 않아요: 빈 S3에 state push하면 terraform이 lineage를 새로 붙여요 (1.16.4, daisy-bootstrap #4 · #5)
  # data source는 plan마다 다시 읽는 값이라 빼요
  jq -cs '(.[0] // {}) | {lineage: (.lineage // null),
    managed: ([.resources[]? | select(.mode == "managed")
      | "\(.module // "")\(.type).\(.name)=\([.instances[]?.attributes.id // "" | tostring] | join(","))"] | sort)}'
}

state_diff() { # $1 로컬 요약, $2 S3 요약 → 사람이 읽는 차이 (주소 · lineage만, 값은 없어요)
  jq -rn --argjson a "$1" --argjson b "$2" '
    "  로컬: lineage \(($a.lineage // "없음")[0:8]) · 리소스 \($a.managed | length)개",
    "  S3  : lineage \(($b.lineage // "없음")[0:8]) · 리소스 \($b.managed | length)개",
    "  로컬에만: \(($a.managed - $b.managed) | join(", "))",
    "  S3에만  : \(($b.managed - $a.managed) | join(", "))"'
}

migrate_state() { # 로컬 state를 S3로 옮겨요. S3에 다른 state가 있으면 덮어쓰지 않고, 멈췄다 다시 돌리면 이어가요
  [[ $BKIND == s3 ]] || die "state 이전은 AWS 스택(S3)만 해요. GCP는 처음부터 GCS를 써요"
  [[ -n $BUCKET ]] || die "TF_STATE_BUCKET_AWS가 필요해요 (옮길 S3 버킷)"
  local src="$WORK/state/terraform.tfstate"
  if [[ -f $MIGRATED ]]; then
    echo "tf-run: 이미 옮겼어요 ($ENV → $(cat "$MIGRATED"))"
    return
  fi
  if [[ ! -f $src ]]; then
    echo "tf-run: 옮길 로컬 state가 없어요 ($ENV, 건너뛰어요)"
    return
  fi
  PLAN_ID=migrate-state # confirm 메시지용
  confirm
  local dir want got
  dir="$WORK/migrate-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  init "$dir" # backend.tf만 있는 빈 설정으로 S3 state에 붙어요
  want=$(state_summary <"$src")
  got=$(terraform -chdir="$dir" state pull | state_summary)
  if [[ $(jq '.managed | length' <<<"$want") == 0 ]]; then
    echo "tf-run: 옮길 리소스가 없어요 (빈 state). S3에서 새로 시작해요"
  elif [[ $(jq -c .managed <<<"$got") == "$(jq -c .managed <<<"$want")" ]]; then # 오른쪽은 따옴표: 없으면 [ ] 를 패턴으로 봐요
    echo "tf-run: S3에 같은 리소스를 가리키는 state가 이미 있어요 (앞서 올린 것). 그대로 써요"
  elif [[ $(jq '.managed | length' <<<"$got") != 0 ]]; then
    state_diff "$want" "$got"
    die "S3에 다른 state가 있어요: s3://$BUCKET/$STATE_KEY (덮어쓰지 않아요)"
  else
    terraform -chdir="$dir" state push "$src"
    got=$(terraform -chdir="$dir" state pull | state_summary)
    if [[ $(jq -c .managed <<<"$got") != "$(jq -c .managed <<<"$want")" ]]; then
      state_diff "$want" "$got"
      die "S3에 올린 state가 로컬과 달라요. 로컬 state는 그대로 뒀어요: $src"
    fi
  fi
  mv "$src" "$src.migrated" # 백업으로 남겨요. MIGRATED 표시가 있으면 로컬 backend로는 돌지 않아요
  echo "s3://$BUCKET/$STATE_KEY" >"$MIGRATED"
  rm -rf "$dir"
  echo "tf-run: state 이전 완료 $ENV → s3://$BUCKET/$STATE_KEY (리소스 $(jq '.managed | length' <<<"$want")개)"
}

prune_plans() { # 하루 지난 plan 폴더를 지워요. 마지막으로 apply한 plan은 남겨요
  local keep
  keep=$(readlink "$WORK/current" 2>/dev/null || true)
  keep=${keep##*/}
  find "$WORK/plans" -mindepth 1 -maxdepth 1 -type d -mtime +0 ! -name "${keep:-.}" -exec rm -rf {} +
}

case $CMD in
plan)
  PLAN_ID=${PLAN_ID:-manual-$(date +%Y%m%d-%H%M%S)}
  set_plan_dir
  prune_plans
  make_plan "$([[ ${TF_DESTROY:-} == 1 ]] && echo 1 || echo 0)"
  ;;
apply)
  [[ -n ${PLAN_ID:-} ]] || die "PLAN_ID가 필요해요 (승인한 plan)"
  set_plan_dir
  apply_plan
  ;;
destroy)
  [[ -e $WORK/current ]] || die "적용한 plan이 없어요 (apply한 적이 없으면 지울 것도 없어요)"
  # 마지막으로 적용한 plan의 이미지 태그와 변수로 삭제 plan을 만들어요
  [[ $KIND == app ]] && IMAGE_TAG=${IMAGE_TAG:-$(jq -r .image_tag "$WORK/current/meta.json")}
  VAR_FILE=${VAR_FILE:-$WORK/current/vars.json}
  PLAN_ID=${PLAN_ID:-manual-destroy-$(date +%Y%m%d-%H%M%S)}
  set_plan_dir
  make_plan 1
  apply_plan
  ;;
output)
  [[ -e $WORK/current ]] || die "적용한 plan이 없어요: $WORK/current"
  PLAN_DIR="$WORK/current"
  init >&2 # state를 옮겼어도 지금 backend에서 읽어요. stdout은 출력값만
  show_output
  ;;
migrate-state)
  migrate_state
  ;;
esac
