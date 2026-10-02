#!/usr/bin/env python3
"""Jenkins ↔ 서버 연결 (infra/SPEC.md §12-9). daisy-cd-plan · daisy-cd-apply가 서버 요청으로 시작됐을 때만 써요.

서버는 buildWithParameters로 request_id · payload(JSON)를 보내고 (server/docs/jenkins-transport.md),
결과는 대상별 콜백 POST $DAISY_CALLBACK_URL 로 받아요 (server/docs/jenkins-callbacks.md).
스크립트 ID는 서버가 콜백 응답(receipt_id)으로 정해서, plan 콜백보다 script 콜백이 먼저예요.

    daisy_server.py parse <plan|apply> <payload.json>   요청 확인 → $DAISY_DIR/job.json. 대상 환경을 한 줄씩 출력
    daisy_server.py bind-app <deploy.yaml>              (plan) 앱 이름을 정하고 state 위치를 대조. 남은 대상 환경 출력
    daisy_server.py state-identity <env> <app>          서버 대상 등록에 넣을 state_identity
    daisy_server.py state <env> <status> [--attempt N] [--error 메시지]
    daisy_server.py stage <env> <step> <started|completed|failed> [--occurrence ID] [--message 메시지]
    daisy_server.py log <env> <level> <step|-> <메시지>  배포 화면 로그 한 줄 (요약만, 비밀값 패턴은 가려요)
    daisy_server.py plan-ready <env>                    검증된 스크립트 · plan → script · plan 콜백
    daisy_server.py plan-failed <env>                   plan_with_ai.py 실패 → failed (ai.json의 메시지 · 실패 단계)
    daisy_server.py check-plan <env>                    (apply) 승인한 plan 대조: ok · stale · 실패 사유 출력
    daisy_server.py applied <env> <service_url>         succeeded + 승인 plan · 입력 · 이미지 증거
    daisy_server.py stale <env>                         승인한 plan이 낡아 적용하지 않았어요 → plan_stale (서버가 다시 plan)
    daisy_server.py fail-open [--error 메시지]           아직 끝나지 않은 대상을 모두 failed로 (빌드가 중간에 멈췄을 때)
    daisy_server.py build-report <succeeded|failed> --started-at <시각>   (daisy-ci) 빌드 결과 → 서버 빌드 기록 `(가칭)`

환경변수
  DAISY_DIR             작업 공간 안 상태 폴더 (job.json · 순번 · 보낸 콜백 기록 events.jsonl)
  DAISY_CALLBACK_URL    서버 콜백 주소 (…/internal/jenkins/callbacks). dry-run이면 보내지 않고 기록만 해요
  DAISY_CALLBACK_TOKEN  서비스 인증 토큰 (Jenkins Credentials daisy-callback-token). 헤더 X-Daisy-Jenkins-Token
  JOB_NAME · BUILD_NUMBER  Jenkins가 넣어요. 콜백의 job_full_name · build_number
  APP · WORK_ROOT · PLAN_ID                    plan-ready (tf-run.sh와 같아요)
  TF_STATE_BUCKET_AWS · DAISY_RUNNER_ID        state-identity (러너 로컬 state는 러너 이름으로 구분해요)

비밀값은 콜백에 넣지 않아요: plan 원문 · state · 변수 값 대신 리소스 주소 · 동작 · 개수만 보내고, 오류 문구는 가려요.
infra/ai/plan_with_ai.py도 이 모듈로 단계 · AI 사용량을 보내요 (DAISY_DIR가 있을 때만).
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

ENVS = ("aws", "gcp", "onprem")
FILES = ("main.tf", "variables.tf", "outputs.tf")
SEQUENCED = {"plan", "plan_stale", "state", "log", "stage"}  # source_sequence가 필요한 kind
PLAN_TTL = datetime.timedelta(hours=23)  # tf-run.sh가 하루 지난 plan 폴더를 지워요. 그 전에 만료
REPO = pathlib.Path(__file__).resolve().parents[2]
# 서버 금지 패턴(DeploymentExecutionService.safeText · AiUsageService)과 같은 범위를 미리 가려요
SECRET = re.compile(
    r"(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)|bearer\s+\S+"
    r"|(?:password|secret|token|authorization|credential|access[_-]?key)\s*[:=]\s*\S*"
    r"|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# AI 비용 추정 (infra/SPEC.md §17-2, USD / 1M 토큰). 서버에는 cost_basis=estimated로 보내요
PRICE = {"input": 4.0, "output": 20.0, "cache_write": 5.0, "cache_read": 0.20}


class Fail(Exception):
    pass


# ---------- 상태 폴더 ----------

def ddir() -> pathlib.Path:
    d = os.environ.get("DAISY_DIR")
    if not d:
        raise Fail("DAISY_DIR가 없어요")
    p = pathlib.Path(d)
    p.mkdir(parents=True, exist_ok=True)
    return p


class locked:
    """병렬 단계(환경별)가 같은 상태 폴더를 쓰니까 파일 잠금으로 순서를 지켜요."""

    def __enter__(self):
        self.f = open(ddir() / ".lock", "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def load_job() -> dict:
    path = ddir() / "job.json"
    if not path.exists():
        raise Fail("job.json이 없어요 (parse 전이에요)")
    return json.loads(path.read_text(encoding="utf-8"))


def save_job(job: dict) -> None:
    tmp = ddir() / "job.json.tmp"
    tmp.write_text(json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(ddir() / "job.json")


def target(job: dict, env: str) -> dict:
    t = job["targets"].get(env)
    if not t:
        raise Fail(f"이 요청에 {env} 대상이 없어요")
    return t


def next_seq(dt: str) -> int:
    with locked():
        f = ddir() / "seq" / dt
        f.parent.mkdir(exist_ok=True)
        n = int(f.read_text()) + 1 if f.exists() else 0
        f.write_text(str(n))
        return n


def mark_done(dt: str) -> None:
    (ddir() / "done").mkdir(exist_ok=True)
    (ddir() / "done" / dt).touch()


def is_done(dt: str) -> bool:
    return (ddir() / "done" / dt).exists()


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def clean(text: str, limit: int) -> str:
    text = SECRET.sub("[가림]", ANSI.sub("", text or "")).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    if len(text) > limit:
        text = "…" + text[-(limit - 1):]
    return text or "(내용 없음)"


# ---------- 콜백 ----------

def send(kind: str, dt: str, payload: dict, event_id: str | None = None) -> dict:
    """콜백 하나를 보내고 서버 ACK({execution_id, external_event_id, receipt_id})를 돌려줘요.

    같은 external_event_id · 같은 내용의 재전송은 서버가 같은 ACK로 답해요 (멱등). 그래서 통신 오류 · 5xx는 다시 보내요.
    """
    job = load_job()
    seq = next_seq(dt) if kind in SEQUENCED else None
    job_name, build = os.environ["JOB_NAME"], int(os.environ["BUILD_NUMBER"])
    env = {
        "execution_id": job["execution_id"],
        "request_id": job["request_id"],
        "job_full_name": job_name,
        "build_number": build,
        "external_event_id": event_id or f"{job_name}#{build}/{dt}/{seq}-{kind}",
        "source_sequence": seq,
        "occurred_at": now(),
        "deployment_target_id": dt,
        "kind": kind,
        "payload": payload,
    }
    env = {k: v for k, v in env.items() if v is not None}
    body = json.dumps(env, ensure_ascii=False, separators=(",", ":")).encode()
    url = os.environ.get("DAISY_CALLBACK_URL", "")
    if not url:
        raise Fail("DAISY_CALLBACK_URL이 없어요 (Jenkins 전역 환경변수, infra/SPEC.md §12-9)")
    if url == "dry-run":
        ack = {"execution_id": env["execution_id"], "external_event_id": env["external_event_id"],
               "receipt_id": "dry-" + hashlib.sha256(body).hexdigest()[:16]}
    else:
        ack = post(url, body)
    with locked():
        with open(ddir() / "events.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"sent": env, "ack": ack}, ensure_ascii=False) + "\n")
    print(f"서버 콜백 {kind} {dt}{'' if seq is None else f' #{seq}'} → {ack.get('receipt_id')}")
    return ack


def post(url: str, body: bytes) -> dict:
    token = os.environ.get("DAISY_CALLBACK_TOKEN", "")
    if not token:
        raise Fail("DAISY_CALLBACK_TOKEN이 없어요 (Jenkins Credentials daisy-callback-token)")
    last = ""
    for i in range(5):
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "Content-Type": "application/json", "X-Daisy-Jenkins-Token": token})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return json.loads(r.read(65536) or b"{}")
        except urllib.error.HTTPError as e:
            detail = clean(e.read(2048).decode("utf-8", "replace"), 500)
            if e.code < 500 and e.code != 429:  # 400 형식 · 403 인증 · 409 충돌은 다시 보내도 같아요
                raise Fail(f"서버가 콜백을 거절했어요: HTTP {e.code} {detail}")
            last = f"HTTP {e.code} {detail}"
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = f"{type(e).__name__}: {e}"
        if i < 4:
            time.sleep(min(2 ** i, 8))  # 1 · 2 · 4 · 8초. 서버가 잠깐 안 될 때 plan이 오래 멈추지 않게 해요
    raise Fail(f"서버 콜백을 보내지 못했어요 (5번 시도): {last}")


# ---------- 요청 해석 ----------

def parse(kind: str, payload_file: str) -> None:
    """서버 payload → job.json. 식별자만 먼저 저장해서, 뒤 검사가 실패해도 대상별 failed를 보낼 수 있게 해요."""
    try:
        p = json.loads(pathlib.Path(payload_file).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise Fail(f"payload가 JSON이 아니에요: {e}")
    if not isinstance(p, dict):
        raise Fail("payload가 JSON 객체가 아니에요")
    job = {
        "operation": p.get("operation"),
        "request_id": p.get("request_id"),
        "execution_id": p.get("execution_id"),
        "deployment_id": p.get("deployment_id"),
        "targets": {},
    }
    for k in ("request_id", "execution_id", "deployment_id"):
        if not isinstance(job[k], str) or not job[k]:
            raise Fail(f"payload에 {k}가 없어요")
    pending = []
    for t in p.get("targets") or []:
        dt = t.get("deployment_target_id")
        env = (t.get("snapshot") or {}).get("environment_type")
        if not isinstance(dt, str) or not dt:
            raise Fail("대상에 deployment_target_id가 없어요")
        pending.append((env, dt, t))
    if not pending:
        raise Fail("payload에 대상이 없어요")
    # 식별자를 먼저 저장해요 (환경 이름이 이상해도 대상 ID로 실패를 알릴 수 있게 임시 키를 써요)
    for env, dt, t in pending:
        key = env if env in ENVS and env not in job["targets"] else f"?{dt}"
        job["targets"][key] = {"deployment_target_id": dt, "target_id": t.get("target_id"),
                               "input_hash": t.get("input_hash"), "state_identity": t.get("state_identity"),
                               "attempt": t.get("attempt")}
    save_job(job)

    if job["request_id"] != os.environ.get("REQUEST_ID"):
        raise Fail("Job 파라미터 request_id와 payload의 request_id가 달라요")
    expected = ("prepare", "replan") if kind == "plan" else ("apply",)
    if job["operation"] not in expected:
        raise Fail(f"이 Job은 {'/'.join(expected)} 요청만 받아요: {job['operation']}")
    bad = [k for k in job["targets"] if k.startswith("?")]
    if bad:
        raise Fail("대상 환경 종류(snapshot.environment_type)가 aws · gcp · onprem이 아니거나 한 요청에 겹쳐요: "
                   + ", ".join(job["targets"][k]["deployment_target_id"] for k in bad))
    for env, t in job["targets"].items():
        if not isinstance(t["input_hash"], str) or not t["input_hash"]:
            raise Fail(f"{env} 대상에 input_hash가 없어요")
        if not isinstance(t["state_identity"], str) or not t["state_identity"]:
            raise Fail(f"{env} 대상에 state_identity가 없어요")

    job.update(image(p))
    repo = p.get("repository_snapshot") or {}
    job["repository_url"] = repo.get("repository_url") or ""
    job["branch"] = repo.get("default_branch") or "main"
    job["manifest_path"] = repo.get("manifest_path") or "deploy.yaml"
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9._/-]+", job["repository_url"]):
        raise Fail(f"repository_url이 공개 https 저장소 주소가 아니에요: {job['repository_url']!r}")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", job["branch"]):
        raise Fail(f"default_branch 형식이 맞지 않아요: {job['branch']!r}")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", job["manifest_path"]) or ".." in job["manifest_path"]:
        raise Fail(f"manifest_path 형식이 맞지 않아요: {job['manifest_path']}")
    job["allow_ai"] = p.get("allow_ai_autofix", True) is not False

    if kind == "apply":
        plans = {x.get("deployment_target_id"): x for x in p.get("plans") or []}
        apps = set()
        for env, t in job["targets"].items():
            plan = plans.get(t["deployment_target_id"])
            if not plan:
                raise Fail(f"{env} 대상의 승인 plan이 payload.plans에 없어요")
            m = re.fullmatch(r"daisy-plan:([A-Za-z0-9._-]+)/([a-z]+)/([A-Za-z0-9._-]{1,80})", plan.get("artifact_ref") or "")
            if not m or m.group(2) != env:
                raise Fail(f"{env} 대상의 artifact_ref를 이 러너의 plan으로 읽을 수 없어요: {plan.get('artifact_ref')}")
            if plan.get("input_hash") != t["input_hash"]:
                raise Fail(f"{env} 대상의 승인 plan input_hash가 대상과 달라요")
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", plan.get("digest") or ""):
                raise Fail(f"{env} 대상의 plan digest 형식이 맞지 않아요")
            t.update({"plan_id": plan.get("plan_id"), "digest": plan["digest"], "artifact_ref": plan["artifact_ref"],
                      "plan_ref": m.group(3)})
            if not isinstance(t["attempt"], int):  # #70 전 서버는 안 보내요 → 승인한 plan에 기록된 시도 수
                t["attempt"] = plan_attempt(pathlib.Path(os.environ["WORK_ROOT"]) / m.group(1) / env / "plans" / m.group(3))
            apps.add(m.group(1))
        if len(apps) != 1:
            raise Fail(f"한 요청의 대상이 서로 다른 앱의 plan을 가리켜요: {sorted(apps)}")
        job["app"] = apps.pop()
    save_job(job)
    for env in job["targets"]:
        print(env)


def base_attempt(t: dict) -> int:
    """서버가 넘긴 환경별 생성 시도 수 (0~3, #70). 서버는 attempt가 줄어드는 상태 보고를 거절해요"""
    a = t.get("attempt")
    return min(max(a, 0), 3) if isinstance(a, int) else 0


def plan_attempt(plan_dir: pathlib.Path) -> int:
    """plan 폴더 ai.json의 시도 수: AI로 만들었으면 통과한 시도(앞선 시도 수 포함), 아니면 시작 값"""
    f = plan_dir / "ai.json"
    if not f.exists():
        return 0
    ai = json.loads(f.read_text(encoding="utf-8"))
    base = ai.get("attempt_base", 0)
    if ai.get("mode") == "generated":
        return min(3, base + next((a["attempt"] for a in reversed(ai.get("attempts", [])) if a.get("ok")), 0))
    return base


def image(p: dict) -> dict:
    """image_refs {service: {image_ref, digest?, commit_sha}} → 모듈 입력 image(태그 없는 주소) · image_tag(커밋 해시)."""
    commit = p.get("commit_sha") or ""
    refs = p.get("image_refs")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise Fail(f"commit_sha가 커밋 해시 40자가 아니에요: {commit!r}")
    if not isinstance(refs, dict) or len(refs) != 1:
        raise Fail("지금 기준 모듈은 서비스 1개(모놀리스)만 배포해요. image_refs 서비스 수: "
                   + str(len(refs) if isinstance(refs, dict) else 0))
    (service, ref), = refs.items()
    # 레지스트리/저장소:태그. 셸에 그대로 넘겨도 안전한 글자만 받아요
    m = re.fullmatch(r"([a-z0-9.-]+(?::[0-9]+)?/[a-z0-9._/-]+):([0-9a-f]{40})", (ref or {}).get("image_ref") or "")
    if not m:
        raise Fail(f"image_ref가 '<저장소>:<커밋 해시 40자>' 형식이 아니에요: {(ref or {}).get('image_ref')!r}")
    if m.group(2) != commit or ref.get("commit_sha") != commit:
        raise Fail("image_ref 태그 · commit_sha가 배포 커밋과 달라요")
    return {"commit_sha": commit, "image_refs": refs, "service": service, "image_repo": m.group(1),
            "image_tag": commit}


def state_identity(env: str, app: str) -> str:
    """tf-run.sh가 실제로 쓰는 state 위치. 서버는 이 문자열로 같은 state의 동시 실행을 막아요 (#35 §4)."""
    if env == "aws" and os.environ.get("TF_STATE_BUCKET_AWS"):
        return f"s3://{os.environ['TF_STATE_BUCKET_AWS']}/{app}/{env}/terraform.tfstate"
    if env == "gcp" and os.environ.get("TF_STATE_BUCKET_GCP"):  # GCS backend는 prefix 아래 default.tfstate
        return f"gs://{os.environ['TF_STATE_BUCKET_GCP']}/{app}/{env}/default.tfstate"
    runner = os.environ.get("DAISY_RUNNER_ID") or os.uname().nodename
    return f"local://{runner}/{app}/{env}/terraform.tfstate"


def bind_app(deploy_yaml: str) -> None:
    """deploy.yaml의 name = 앱 이름 = state key · 작업 폴더 (tf-run.sh APP).

    state 위치가 서버 등록(state_identity)과 다르면 기본은 경고만 해요. 서버 데모 대상이 아직 임시 값(<프로젝트>/<대상>)을 써요.
    Jenkins 전역 DAISY_STATE_IDENTITY_CHECK=strict면 그 대상을 실행 전에 실패로 알려요 (#70 요청)
    """
    import yaml  # Ubuntu: python3-yaml

    job = load_job()
    try:
        name = (yaml.safe_load(pathlib.Path(deploy_yaml).read_text(encoding="utf-8")) or {}).get("name")
    except (OSError, yaml.YAMLError) as e:
        raise Fail(f"{job['manifest_path']}을 읽지 못했어요: {e}")
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", name):
        raise Fail(f"{job['manifest_path']}의 name이 앱 이름 형식(소문자 · 숫자 · -)이 아니에요: {name!r}")
    job["app"] = name
    save_job(job)
    strict = os.environ.get("DAISY_STATE_IDENTITY_CHECK") == "strict"  # Jenkins 전역. 서버가 실제 값을 등록하면 켜요 (#70)
    for env, t in job["targets"].items():
        want = state_identity(env, name)
        if t["state_identity"] != want:
            msg = (f"{env} 대상의 서버 state_identity '{t['state_identity']}'가 실제 state 위치 '{want}'와 달라요. "
                   "서버 대상 등록을 이 값으로 맞춰 주세요")
            if strict:
                fail_target(env, msg + " (같은 state를 서버가 다른 잠금으로 볼 수 있어서 실행하지 않았어요)")
                continue
            print("경고: " + msg, file=sys.stderr)
        print(env)


# ---------- 결과 ----------

STEPS = {"generate", "validate", "plan", "risk_check", "apply", "health_check"}


def log_line(env: str, level: str, step: str | None, message: str) -> None:
    """배포 화면 로그 한 줄 (서버 log.batch, A-07). 콘솔 전체가 아니라 사람이 볼 요약 줄만 보내요. 비밀값 패턴은 가려요."""
    t = target(load_job(), env)
    payload = {"level": level if level in ("debug", "info", "warn", "error") else "info", "message": clean(message, 8000)}
    if step in STEPS:
        payload["step"] = step
    send("log", t["deployment_target_id"], payload)


def set_state(env: str, status: str, attempt: int | None = None) -> None:
    """진행 상태 (generating · validating · applying · verifying). 끝 상태는 fail_target · applied · stale이 보내요.

    attempt를 주지 않으면 이 대상의 시작 값이에요 (apply는 승인한 plan의 시도 수를 그대로 써요)
    """
    t = target(load_job(), env)
    send("state", t["deployment_target_id"], {"status": status, "attempt": base_attempt(t) if attempt is None else attempt})


def fail_target(env: str, error: str, attempt: int | None = None) -> None:
    t = target(load_job(), env)
    attempt = max(attempt or 0, base_attempt(t))
    if is_done(t["deployment_target_id"]):
        return
    try:
        log_line(env, "error", None, error)  # 배포 화면 로그에도 남겨요
    except Fail as e:
        print(f"{env}: 실패 로그를 보내지 못했어요 — {e}", file=sys.stderr)
    send("state", t["deployment_target_id"], {"status": "failed", "attempt": attempt, "error_summary": clean(error, 4000)})
    mark_done(t["deployment_target_id"])
    print(f"{env}: 실패로 알렸어요 — {clean(error, 300)}")


def files_digest(src: pathlib.Path) -> str:
    h = hashlib.sha256()
    for name in FILES:
        h.update(name.encode() + b"\0" + (src / name).read_bytes() + b"\0")
    return "sha256:" + h.hexdigest()


def plan_ready(env: str) -> None:
    """검증을 통과한 plan → script(검증된 스크립트) · plan 콜백. 서버가 승인 대기로 바꿔요."""
    job = load_job()
    t = target(job, env)
    dt = t["deployment_target_id"]
    work = pathlib.Path(os.environ["WORK_ROOT"]) / job["app"] / env
    plan_id = os.environ["PLAN_ID"]
    plan_dir = work / "plans" / plan_id
    meta = json.loads((plan_dir / "meta.json").read_text(encoding="utf-8"))
    ai = json.loads((plan_dir / "ai.json").read_text(encoding="utf-8")) if (plan_dir / "ai.json").exists() else {}
    mode = ai.get("mode") or "reference"
    src = plan_dir / "src"

    if mode in ("reused", "generated"):
        artifact = f"daisy-script:{job['app']}/{env}/verified/{ai['fingerprint']}"
        compat = ai["fingerprint"]
    else:  # reference: 기준 모듈 그대로 (USE_AI=0 · 서버 allow_ai_autofix=false)
        artifact = f"daisy-script:reference/{env}"
        compat = None
    digest = files_digest(src)
    model = next((a["usage"]["model"] for a in reversed(ai.get("attempts", [])) if "usage" in a), None)
    metadata = {"tool_version": terraform_version(src), "validation_tool": "terraform validate · plan · risk_check",
                "schema_version": "1"}
    if model:
        metadata.update({"provider": "anthropic", "model": model})
    script = {"artifact_ref": artifact, "content_digest": digest, "metadata": metadata, "validated_at": meta["created_at"]}
    if compat:
        script["compatibility_key"] = compat
    ack = send("script", dt, script, event_id=f"script:{env}:{digest[7:]}")

    base = ai.get("attempt_base", base_attempt(t))
    attempt = plan_attempt(plan_dir) if ai else base
    # 서버는 재사용 plan에 attempt 0을 요구하고, attempt가 줄어드는 보고는 거절해요.
    # 이미 AI로 만든 대상을 다시 plan하면서(replan) 그 스크립트를 재사용하면 재사용이 아니라 같은 시도로 보고해요
    reused = mode == "reused" and attempt == 0
    created = datetime.datetime.fromisoformat(meta["created_at"].replace("Z", "+00:00"))
    expires = (created + PLAN_TTL).isoformat().replace("+00:00", "Z")
    resources, counts = plan_resources(src / "plan.json")
    log_line(env, "info", "plan", f"승인 대기: {meta['summary']} · " + {
        "reused": "검증된 스크립트 재사용 (AI 0회)", "generated": f"AI 생성 {attempt}번째 시도로 통과",
    }.get(mode, "기준 모듈"))
    send("plan", dt, {
        "source_plan_id": f"{plan_id}/{env}",
        "input_hash": t["input_hash"],
        "script_id": ack["receipt_id"],
        "reused_script": reused,
        "attempt": attempt,
        "artifact_ref": f"daisy-plan:{job['app']}/{env}/{plan_id}",
        "digest": "sha256:" + meta["plan_sha256"],
        # 서버 PlanRevision이 받는 키만 보내요 (summary: counts · has_delete · risks, resources: address · actions). 다른 키는 400
        "summary": {
            "counts": {k: counts[k] for k in ("create", "update", "delete")},
            "has_delete": counts["delete"] > 0,
            "risks": [],  # 위험 검사(infra/ai/risk_check.py)를 통과한 plan만 보내요. 위반은 승인 대상이 아니에요
        },
        "resources": resources,
        "expires_at": expires,
        "artifact_expires_at": expires,
    })
    mark_done(dt)  # 이 빌드에서 알릴 것은 끝났어요. 승인 대기는 서버가 바꿔요


def plan_failed(env: str) -> None:
    """plan_with_ai.py가 실패한 환경 → failed. 오류는 ai.json의 메시지와 마지막 시도의 실패 단계예요."""
    job = load_job()
    ai_file = pathlib.Path(os.environ["WORK_ROOT"]) / job["app"] / env / "ai" / os.environ["PLAN_ID"] / "ai.json"
    ai = json.loads(ai_file.read_text(encoding="utf-8")) if ai_file.exists() else {}
    last = (ai.get("attempts") or [{}])[-1]
    error = ai.get("message") or "검증을 통과한 plan을 만들지 못했어요"
    if last.get("stage") and last.get("error"):
        error += f"\n[{last['stage']}] {first_error(last['error'])}"
    fail_target(env, error, attempt=min(3, ai.get("attempt_base", base_attempt(target(job, env))) + ai.get("ai_calls", 0)))


def first_error(log: str) -> str:
    """terraform · 위험 검사 출력에서 사람이 볼 첫 오류 몇 줄 (전체 로그는 Jenkins 콘솔에 있어요)."""
    lines = ANSI.sub("", log).splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Error:") or "위반" in line or "FAIL" in line:
            return "\n".join(lines[i:i + 6])
    return "\n".join(lines[-6:])


def usage(env: str, attempt: int, step: str, u: dict | None, status: str) -> None:
    """AI 호출 1번 = 콜백 1개. 원천 ID는 Anthropic 요청 ID라 재전송해도 한 번만 세요. 사용량을 모르면 비워요 (0으로 만들지 않아요).

    step: generate(처음 생성) · fix(실패를 고치는 호출). status: succeeded · failed(쓸 수 없는 응답 · API 오류)
    """
    t = target(load_job(), env)
    payload = {"provider": "anthropic", "model": (u or {}).get("model") or "claude-opus-5-5", "step": step,
               "attempt": attempt, "status": status}
    if u:
        payload.update({
            "input_tokens": u["input_tokens"], "output_tokens": u["output_tokens"],
            "usage_details": {"cache_creation_input_tokens": u["cache_creation_input_tokens"],
                              "cache_read_input_tokens": u["cache_read_input_tokens"]},
            "cost_usd": round((u["input_tokens"] * PRICE["input"] + u["output_tokens"] * PRICE["output"]
                               + u["cache_creation_input_tokens"] * PRICE["cache_write"]
                               + u["cache_read_input_tokens"] * PRICE["cache_read"]) / 1e6, 6),
            "cost_basis": "estimated",
        })
    rid = (u or {}).get("request_id")
    job_build = f"{os.environ['JOB_NAME']}#{os.environ['BUILD_NUMBER']}"
    send("usage", t["deployment_target_id"], payload,
         event_id=f"anthropic:{rid}" if rid else f"{job_build}/{env}/ai-{attempt}")


def check_plan(env: str) -> str:
    """승인한 plan이 이 러너에 그대로 있는지 대조해요. ok · stale(없거나 만료 → 다시 plan) · 그 밖은 실패 사유."""
    job = load_job()
    t = target(job, env)
    plan_dir = pathlib.Path(os.environ["WORK_ROOT"]) / job["app"] / env / "plans" / t["plan_ref"]
    if not (plan_dir / "meta.json").exists() or not (plan_dir / "src" / "plan.tfplan").exists():
        return "stale"  # 하루가 지나 정리됐거나 다른 러너의 plan이에요. 적용한 것이 없으니 다시 plan해요
    meta = json.loads((plan_dir / "meta.json").read_text(encoding="utf-8"))
    if meta.get("applied_at"):
        return f"이미 적용한 plan이에요: {t['plan_ref']}"
    if "sha256:" + meta["plan_sha256"] != t["digest"]:
        return "plan 파일이 승인한 것과 달라요 (digest 불일치)"
    if meta.get("image_tag") != job["image_tag"] or meta.get("destroy"):
        return "승인한 plan의 이미지 · 종류가 요청과 달라요"
    created = datetime.datetime.fromisoformat(meta["created_at"].replace("Z", "+00:00"))
    if datetime.datetime.now(datetime.timezone.utc) >= created + PLAN_TTL:
        return "stale"
    return "ok"


def plan_resources(plan_json: pathlib.Path):
    """plan JSON에서 리소스 주소와 terraform 동작 배열만 뽑아요. 값(before · after)은 비밀값이 있을 수 있어서 넣지 않아요.

    교체(["delete", "create"])는 terraform 요약처럼 추가 · 삭제에 모두 세요. 그래서 has_delete도 참이 돼요 (서버 검사와 같아요).
    """
    plan = json.loads(plan_json.read_text(encoding="utf-8"))
    out, counts = [], {"create": 0, "update": 0, "delete": 0}
    for rc in plan.get("resource_changes") or []:
        actions = [a for a in rc.get("change", {}).get("actions") or [] if a in ("create", "update", "delete")]
        if not actions:  # no-op · read
            continue
        for a in set(actions):
            counts[a] += 1
        out.append({"address": rc["address"], "actions": actions})
    return out, counts


def terraform_version(src: pathlib.Path) -> str:
    import subprocess

    try:
        v = json.loads(subprocess.run(["terraform", "version", "-json"], capture_output=True, text=True,
                                      cwd=src, timeout=30).stdout)
        return f"terraform {v['terraform_version']}"
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return "terraform"


def applied(env: str, url: str) -> None:
    job = load_job()
    t = target(job, env)
    send("state", t["deployment_target_id"], {"status": "succeeded", "attempt": base_attempt(t), "result": {
        "plan_id": t["plan_id"],
        "plan_digest": t["digest"],
        "input_hash": t["input_hash"],
        "image_refs": job["image_refs"],
        "public_urls": {job["service"]: url},
    }})
    mark_done(t["deployment_target_id"])


def stale(env: str) -> None:
    t = target(load_job(), env)
    send("plan_stale", t["deployment_target_id"], {
        "plan_id": t["plan_id"], "plan_digest": t["digest"], "input_hash": t["input_hash"],
        "confirmed_not_applied": True,  # terraform이 적용 전에 거부했어요 (Saved plan is stale)
        "execution_terminated": True,
    })
    mark_done(t["deployment_target_id"])


def fail_open(error: str | None, status: str = "failed") -> None:
    """빌드가 끝났는데 결과를 알리지 못한 대상 → failed (중단이면 cancelled)."""
    job = load_job()
    err_file = ddir() / "error.txt"
    msg = error or (err_file.read_text(encoding="utf-8") if err_file.exists() else "Jenkins 빌드가 중간에 멈췄어요. 콘솔 로그를 확인해 주세요")
    for env, t in job["targets"].items():
        dt = t["deployment_target_id"]
        if is_done(dt):
            continue
        try:
            if status == "cancelled":
                send("state", dt, {"status": "cancelled", "attempt": base_attempt(t), "error_summary": clean(msg, 4000)})
                mark_done(dt)
            else:
                fail_target(env, msg)
        except Fail as e:  # 하나가 거절돼도 나머지 대상은 알려요
            print(f"{env}: 결과를 알리지 못했어요 — {e}", file=sys.stderr)


# ---------- CLI ----------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("parse"); s.add_argument("kind", choices=["plan", "apply"]); s.add_argument("payload")
    s = sub.add_parser("bind-app"); s.add_argument("deploy_yaml")
    s = sub.add_parser("state-identity"); s.add_argument("env", choices=ENVS); s.add_argument("app")
    s = sub.add_parser("state"); s.add_argument("env"); s.add_argument("status")
    s.add_argument("--attempt", type=int); s.add_argument("--error")
    s = sub.add_parser("stage"); s.add_argument("env"); s.add_argument("step")
    s.add_argument("phase", choices=["started", "completed", "failed"])
    s.add_argument("--occurrence"); s.add_argument("--message")
    s = sub.add_parser("log"); s.add_argument("env"); s.add_argument("level"); s.add_argument("step")
    s.add_argument("message")
    s = sub.add_parser("plan-ready"); s.add_argument("env")
    s = sub.add_parser("plan-failed"); s.add_argument("env")
    s = sub.add_parser("check-plan"); s.add_argument("env")
    s = sub.add_parser("applied"); s.add_argument("env"); s.add_argument("url")
    s = sub.add_parser("stale"); s.add_argument("env")
    s = sub.add_parser("build-report"); s.add_argument("status", choices=["succeeded", "failed"])
    s.add_argument("--started-at", required=True); s.add_argument("--deploy-yaml", default="app/deploy.yaml")
    s.add_argument("--error")
    s = sub.add_parser("fail-open"); s.add_argument("--error")
    s.add_argument("--status", choices=["failed", "cancelled"], default="failed")
    a = ap.parse_args()
    try:
        if a.cmd == "parse":
            parse(a.kind, a.payload)
        elif a.cmd == "bind-app":
            bind_app(a.deploy_yaml)
        elif a.cmd == "state-identity":
            print(state_identity(a.env, a.app))
        elif a.cmd == "state":
            if a.status == "failed":
                fail_target(a.env, a.error or "실패", a.attempt)
            else:
                set_state(a.env, a.status, a.attempt)
        elif a.cmd == "stage":
            stage(a.env, a.step, a.phase, a.occurrence, a.message)
        elif a.cmd == "log":
            log_line(a.env, a.level, a.step, a.message)
        elif a.cmd == "plan-ready":
            plan_ready(a.env)
        elif a.cmd == "plan-failed":
            plan_failed(a.env)
        elif a.cmd == "check-plan":
            print(check_plan(a.env))
        elif a.cmd == "applied":
            applied(a.env, a.url)
        elif a.cmd == "stale":
            stale(a.env)
        elif a.cmd == "fail-open":
            fail_open(a.error, a.status)
        elif a.cmd == "build-report":
            build_report(a.status, a.started_at, a.deploy_yaml, a.error)
    except Fail as e:
        print(f"daisy_server: {e}", file=sys.stderr)
        try:
            (ddir() / "error.txt").write_text(str(e), encoding="utf-8")
        except (Fail, OSError):
            pass
        return 1
    return 0


def build_report(status: str, started_at: str, deploy_yaml: str, error: str | None) -> None:
    """daisy-ci 결과 → 서버 빌드 기록 (source_version). 수신 주소 DAISY_BUILD_URL이 없으면 건너뛰어요.

    본문은 서버 BuildRegistry.BuildReport와 같은 이름이에요 (#53, 수신 POST /internal/jenkins/builds #72).
    서버는 source(jenkins:<인스턴스 ID>)와 Job→프로젝트 매핑(daisy.jenkins.ci-projects)으로 보낸 쪽을 확인해요.
    프로젝트는 Job 파라미터 PROJECT_ID, 서비스 이름은 deploy.yaml name이에요. 같은 빌드를 다시 보내도 서버가 한 행으로 모아요.
    """
    url = os.environ.get("DAISY_BUILD_URL", "")
    if not url:
        print("DAISY_BUILD_URL이 없어서 서버에 빌드 결과를 보내지 않아요")
        return
    import yaml  # Ubuntu: python3-yaml

    commit = os.environ["IMAGE_TAG"]
    report = {
        # 파라미터가 Jenkinsfile에 새로 생긴 첫 빌드에는 값이 없어요. Job 기본값과 같은 데모 프로젝트를 써요
        "project_id": os.environ.get("PROJECT_ID") or "prj_demo_monolith",
        # 서버는 source가 jenkins:<서버 설정 daisy.jenkins.instance-id>일 때만 받아요 (#72). Job은 external_build_id로 알려요
        "source": f"jenkins:{os.environ.get('DAISY_INSTANCE_ID') or 'unibloom-onprem'}",
        "external_build_id": f"{os.environ['JOB_NAME']}#{os.environ['BUILD_NUMBER']}",
        "commit_sha": commit,
        "branch": os.environ.get("APP_BRANCH", "main"),
        "status": status,
        "run_url": os.environ.get("BUILD_URL"),
        "started_at": started_at,
        "finished_at": now(),
    }
    if status == "succeeded":
        service = yaml.safe_load(pathlib.Path(deploy_yaml).read_text(encoding="utf-8"))["name"]
        image = {"image_ref": os.environ["IMAGE_REF"], "commit_sha": commit}
        if re.fullmatch(r"sha256:[0-9a-f]{64}", os.environ.get("IMAGE_DIGEST", "")):
            image["digest"] = os.environ["IMAGE_DIGEST"]
        report["image_refs"] = {service: image}
    else:
        report["error_summary"] = clean(error or "CI 빌드가 실패했어요. Jenkins 콘솔을 확인해 주세요", 2000)
    ack = post(url, json.dumps(report, ensure_ascii=False).encode())
    print(f"서버 빌드 기록 {status} → {ack}")


def stage(env: str, step: str, phase: str, occurrence: str | None = None, message: str | None = None) -> None:
    """단계 시작 · 끝. 같은 occurrence의 시작 · 끝으로 서버가 소요 시간을 계산해요. 대상 상태는 바꾸지 않아요.

    step: generate · validate · plan · risk_check · apply · health_check (server/docs/database-design.md §7)
    """
    t = target(load_job(), env)
    occ = occurrence or f"{os.environ['JOB_NAME']}#{os.environ['BUILD_NUMBER']}/{env}/{step}"
    payload = {"stage_occurrence_id": occ, "step": step, "phase": phase, "level": "error" if phase == "failed" else "info"}
    if message:
        payload["message"] = clean(message, 2000)
    send("stage", t["deployment_target_id"], payload)


if __name__ == "__main__":
    sys.exit(main())
