#!/usr/bin/env bash
# infra/SPEC.md §3-4 러너 규약의 참고 구현이에요 (Jenkins 러너 · 사람이 직접 실행 공용).
# 팀의 정식 러너가 정해지면(SPEC D-2) 그쪽이 같은 순서를 따르면 돼요.
#
#   tf-run.sh <aws|gcp> <plan|apply|destroy|output>
#
# - 작업 디렉터리는 레포 밖: $WORK_ROOT/$APP/$ENV/{src,state}. state·plan에 비밀값이 들어가요
# - src/는 plan 때만 infra/modules/$ENV/에서 새로 복사하고, state/는 지우지 않아요
# - 자격증명은 설정하지 않아요. 호출하는 쪽이 환경변수로 넣어요
# - apply·destroy는 승인이 있어야 실행돼요: 터미널에서 환경 이름 입력, 또는 Jenkins input 승인 뒤 TF_RUN_APPROVED=$ENV
set -euo pipefail
umask 077

usage() {
  cat >&2 <<'EOF'
사용법: tf-run.sh <aws|gcp> <plan|apply|destroy|output>

환경변수
  APP                  앱 이름 (기본 hellocalc). state key와 작업 디렉터리에 써요
  IMAGE_TAG            커밋 해시 40자. plan·destroy에 필수 (latest 금지)
  WORK_ROOT            작업 루트, 레포 밖 (기본 ~/daisy-work)
  VAR_FILE             비밀값 없는 변수 파일 (기본 $WORK_ROOT/$APP/$ENV.tfvars.json)
  TF_STATE_BUCKET      있으면 S3 backend (key $APP/$ENV/terraform.tfstate), 없으면 로컬 state
  TF_STATE_REGION      state 버킷 리전 (기본 ap-northeast-2)
  EXPECTED_AWS_ACCOUNT apply·destroy 전에 AWS 계정 ID 확인
  EXPECTED_GCP_PROJECT apply·destroy 전에 VAR_FILE의 project_id 확인
  TF_RUN_APPROVED      Jenkins input 승인 뒤에만 $ENV 값으로 설정
  TF_DESTROY=1         plan을 삭제 plan으로 만들어요 (Jenkins CD의 DESTROY). apply가 그 plan으로 지워요
EOF
  exit 2
}

die() { echo "tf-run: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || usage
ENV=$1 CMD=$2
case $ENV in aws | gcp) ;; *) usage ;; esac
case $CMD in plan | apply | destroy | output) ;; *) usage ;; esac

REPO_ROOT=$(cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" && pwd -P)
MODULE_DIR="$REPO_ROOT/infra/modules/$ENV"
APP=${APP:-hellocalc}
WORK_ROOT=${WORK_ROOT:-$HOME/daisy-work}
[[ $WORK_ROOT == /* ]] || WORK_ROOT="$PWD/$WORK_ROOT"
case "$WORK_ROOT/" in "$REPO_ROOT/"*) die "WORK_ROOT가 레포 안이에요: $WORK_ROOT" ;; esac
WORK="$WORK_ROOT/$APP/$ENV"
VAR_FILE=${VAR_FILE:-$WORK_ROOT/$APP/$ENV.tfvars.json}
export TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}
export TF_IN_AUTOMATION=1
mkdir -p "$WORK/state" "$TF_PLUGIN_CACHE_DIR"

tf() { terraform -chdir="$WORK/src" "$@"; }

need_tag() {
  [[ ${IMAGE_TAG:-} =~ ^[0-9a-f]{40}$ ]] || die "IMAGE_TAG는 커밋 해시 40자여야 해요: '${IMAGE_TAG:-}'"
}

need_var_file() {
  [[ -f $VAR_FILE ]] || die "변수 파일이 없어요: $VAR_FILE"
}

init() {
  local args=(-input=false -no-color)
  if [[ -n ${TF_STATE_BUCKET:-} ]]; then
    printf 'terraform {\n  backend "s3" {}\n}\n' >"$WORK/src/backend.tf"
    args+=(-backend-config="bucket=$TF_STATE_BUCKET"
      -backend-config="key=$APP/$ENV/terraform.tfstate"
      -backend-config="region=${TF_STATE_REGION:-ap-northeast-2}"
      -backend-config="encrypt=true"
      -backend-config="use_lockfile=true")
  else
    printf 'terraform {\n  backend "local" {}\n}\n' >"$WORK/src/backend.tf"
    args+=(-backend-config="path=$WORK/state/terraform.tfstate")
  fi
  [[ -f $WORK/src/.terraform.lock.hcl ]] && args+=(-lockfile=readonly)
  tf init "${args[@]}"
}

check_account() {
  if [[ $ENV == aws && -n ${EXPECTED_AWS_ACCOUNT:-} ]]; then
    local actual
    actual=$(aws sts get-caller-identity --query Account --output text)
    [[ $actual == "$EXPECTED_AWS_ACCOUNT" ]] || die "AWS 계정이 달라요: $actual (기대값 $EXPECTED_AWS_ACCOUNT)"
  fi
  if [[ $ENV == gcp && -n ${EXPECTED_GCP_PROJECT:-} ]]; then
    local actual
    actual=$(jq -r '.project_id // empty' "$VAR_FILE")
    [[ $actual == "$EXPECTED_GCP_PROJECT" ]] || die "GCP 프로젝트가 달라요: '$actual' (기대값 $EXPECTED_GCP_PROJECT)"
  fi
}

confirm() {
  if [[ ${TF_RUN_APPROVED:-} == "$ENV" ]]; then
    echo "tf-run: 승인됨 (TF_RUN_APPROVED=$ENV)"
    return
  fi
  { : </dev/tty; } 2>/dev/null ||
    die "승인이 필요해요. 터미널에서 실행하거나, Jenkins input 승인 뒤 TF_RUN_APPROVED=$ENV 로 실행해요"
  printf '%s %s 을(를) 실행하려면 환경 이름(%s)을 입력하세요: ' "$ENV" "$CMD" "$ENV" >/dev/tty
  local answer
  read -r answer </dev/tty
  [[ $answer == "$ENV" ]] || die "취소했어요"
}

summarize() { # plan JSON → "create=3 update=1" 한 줄 (Jenkins 승인 화면용)
  tf show -json "$1" >"$WORK/src/plan.json"
  jq -r '[.resource_changes[]?.change.actions | join("+")]
    | map(select(. != "no-op" and . != "read")) | group_by(.)
    | map("\(.[0])=\(length)") | join(" ")
    | if . == "" then "변경 없음" else . end' "$WORK/src/plan.json" | tee "$WORK/src/summary.txt"
}

case $CMD in
plan)
  need_tag
  need_var_file
  compgen -G "$MODULE_DIR/*.tf" >/dev/null || die "모듈이 아직 없어요: $MODULE_DIR"
  rm -rf "$WORK/src"
  mkdir -p "$WORK/src"
  cp "$MODULE_DIR"/*.tf "$WORK/src/"
  [[ -f $MODULE_DIR/.terraform.lock.hcl ]] && cp "$MODULE_DIR/.terraform.lock.hcl" "$WORK/src/"
  init
  tf validate -no-color
  plan_args=()
  [[ ${TF_DESTROY:-} == 1 ]] && plan_args+=(-destroy)
  tf plan -input=false -no-color ${plan_args[@]+"${plan_args[@]}"} -out=plan.tfplan -var-file="$VAR_FILE" -var="image_tag=$IMAGE_TAG"
  summarize plan.tfplan
  ;;
apply)
  [[ -f $WORK/src/plan.tfplan ]] || die "plan이 없어요. 먼저 plan을 실행해요"
  need_var_file
  check_account
  confirm
  tf apply -input=false -no-color plan.tfplan
  rm -f "$WORK/src/plan.tfplan"
  tf output -raw service_url && echo
  ;;
destroy)
  need_tag
  need_var_file
  [[ -d $WORK/src/.terraform ]] || die "작업 디렉터리가 없어요: $WORK/src (apply한 적이 없으면 지울 것도 없어요)"
  init
  tf plan -destroy -input=false -no-color -out=destroy.tfplan -var-file="$VAR_FILE" -var="image_tag=$IMAGE_TAG"
  summarize destroy.tfplan
  check_account
  confirm
  tf apply -input=false -no-color destroy.tfplan
  rm -f "$WORK/src/destroy.tfplan"
  ;;
output)
  [[ -d $WORK/src/.terraform ]] || die "작업 디렉터리가 없어요: $WORK/src"
  tf output -raw service_url
  echo
  ;;
esac
