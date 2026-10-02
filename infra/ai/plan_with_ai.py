#!/usr/bin/env python3
"""환경 하나의 AI 생성 · 검증 루프 (infra/SPEC.md §17). daisy-cd-plan이 환경마다 불러요.

    plan_with_ai.py <aws|gcp|azure|onprem>

환경변수: APP · PLAN_ID · IMAGE_TAG · WORK_ROOT (tf-run.sh와 같아요), USE_AI(기본 1), ANTHROPIC_API_KEY, TF_DESTROY

1. 재사용: 입력 지문(vars.json · 기준 모듈 · 규칙)이 같은 검증된 스크립트가 있으면 그대로 plan → 위험 검사 (AI 0회)
2. 생성: 아니면 AI가 만든 코드로 validate · plan → 위험 검사. 실패하면 실패 단계와 오류 로그를 AI에 줘서 고쳐요.
   AI 호출은 환경마다 총 3번 (첫 생성 포함). 넘으면 이 환경은 실패로 끝나고 다른 환경은 계속돼요
3. 통과한 코드는 검증된 스크립트로 저장하고, plan 폴더에 ai.json(방식 · 시도 · 사용량)을 남겨요
- USE_AI=0이면 기준 모듈을 그대로 써요 (# MOCK: AI 없이 대안 경로, 기준 모듈 = N-02 실패 시 대안)
- TF_DESTROY=1이면 AI를 부르지 않고 마지막으로 적용한 코드로 삭제 plan을 만들어요
- 서버 요청으로 돌 때(DAISY_DIR)는 상태 · 단계 · AI 사용량을 서버에 알려요 (infra/jenkins/daisy_server.py, SPEC §12-9)
"""
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

import anthropic

import generate
import risk_check

MAX_AI_CALLS = 3
REPO = generate.REPO
# 서버 요청이면 이 환경이 앞서 쓴 생성 시도 수 (명령 targets[].attempt, #70). replan은 이어서 세고 총 3번을 넘지 않아요
BASE = min(max(int(os.environ.get("AI_ATTEMPT_BASE") or 0), 0), MAX_AI_CALLS)


class Server:
    """서버 요청으로 돌 때만 서버에 알려요. 알림이 실패해도 plan은 계속해요 (결과는 Jenkins가 plan-ready · plan-failed로 보내요)."""

    def __init__(self, env: str):
        self.env, self.ds = env, None
        if os.environ.get("DAISY_DIR"):
            sys.path.insert(0, str(REPO / "infra" / "jenkins"))
            import daisy_server
            self.ds = daisy_server

    def _call(self, name: str, *args):
        if self.ds is None:
            return
        try:
            getattr(self.ds, name)(self.env, *args)
        except Exception as e:  # noqa: BLE001 — 알림 실패로 plan을 멈추지 않아요
            print(f"서버 알림 실패 (plan은 계속해요): {e}")

    def state(self, status: str, attempt: int):
        self._call("set_state", status, BASE + attempt)  # 서버에는 앞선 시도 수에 이어서 보고해요

    def stage(self, step: str, phase: str, attempt: int, message: str | None = None):
        occurrence = f"{os.environ.get('JOB_NAME')}#{os.environ.get('BUILD_NUMBER')}/{self.env}/{step}-{attempt}"
        self._call("stage", step, phase, occurrence, message)

    def usage(self, attempt: int, step: str, usage: dict | None, status: str):
        self._call("usage", BASE + attempt, step, usage, status)

    def log(self, level: str, step: str | None, message: str):
        self._call("log_line", level, step, message)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("aws", "gcp", "azure", "onprem"):
        print("사용법: plan_with_ai.py <aws|gcp|azure|onprem>", file=sys.stderr)
        return 2
    env = sys.argv[1]
    srv = Server(env)
    app = os.environ.get("APP", "hellocalc")
    plan_id = os.environ["PLAN_ID"]
    work = pathlib.Path(os.environ.get("WORK_ROOT", pathlib.Path.home() / "daisy-work")) / app / env
    var_file = work.parent / f"{env}.tfvars.json"
    plan_dir = work / "plans" / plan_id
    ai_dir = work / "ai" / plan_id
    ai_dir.mkdir(parents=True, exist_ok=True)

    if os.environ.get("TF_DESTROY") == "1":
        current = work / "current" / "src"
        src = current if current.exists() else generate.reference_dir(env)
        ok, out = run_plan(env, src, plan_dir)
        return finish(plan_dir, ai_dir, {"mode": "destroy", "source": str(src), "ai_calls": 0}, ok,
                      "" if ok else tail(out, 4000))

    inputs = json.loads(var_file.read_text(encoding="utf-8"))
    fp = fingerprint(env, inputs)
    verified = work / "verified" / fp
    record = {"mode": None, "fingerprint": fp, "ai_calls": 0, "attempts": [], "attempt_base": BASE}

    # MOCK: AI 없이 기준 모듈 그대로 (USE_AI=0)
    if os.environ.get("USE_AI", "1") == "0":
        print("MOCK: USE_AI=0 — AI 없이 기준 모듈을 그대로 써요")
        record["mode"] = "reference"
        srv.log("info", "generate", "AI 없이 기준 모듈로 plan해요")
        srv.state("validating", 0)
        ok, out = plan_and_check(env, generate.reference_dir(env), plan_dir, srv, 0)
        return finish(plan_dir, ai_dir, record, ok, "" if ok else tail(out[1], 4000))

    previous, stage, error = None, None, None
    if verified.exists():
        print(f"재사용: 검증된 스크립트 {fp[:12]} (AI 호출 0회)")
        record["mode"] = "reused"
        srv.log("info", "generate", f"입력이 같은 검증된 스크립트 {fp[:12]}를 재사용해요 (AI 호출 0회)")
        srv.state("validating", 0)
        ok, out_or_stage = plan_and_check(env, verified, plan_dir, srv, 0)
        if ok:
            return finish(plan_dir, ai_dir, record, True, "")
        # 외부 변화(provider · 권한 · 할당량 등)로 실패하면 그 오류로 AI가 고쳐요
        stage, error = out_or_stage
        previous = read_files(verified)
        print(f"재사용 실패 ({stage}) → AI로 고쳐요")
        srv.log("warn", stage if stage in ("validate", "plan", "risk_check") else None,
                f"재사용한 스크립트가 {stage} 단계에서 실패했어요 → AI로 고쳐요")

    record["mode"] = "generated"
    budget = MAX_AI_CALLS - BASE
    if budget <= 0:
        srv.log("error", "generate", f"이 환경은 AI 시도 {MAX_AI_CALLS}번을 이미 다 썼어요")
        return finish(plan_dir, ai_dir, record, False, f"이 환경은 AI 시도 {MAX_AI_CALLS}번을 이미 다 썼어요 (앞선 시도 {BASE}번)")
    for attempt in range(1, budget + 1):
        cand = ai_dir / f"attempt-{attempt}"
        print(f"AI 생성 {BASE + attempt}/{MAX_AI_CALLS}" + (f" (이전 실패: {stage})" if previous else ""))
        step = "fix" if previous else "generate"  # 서버 ai_usage의 step (처음 생성 · 고치기)
        srv.state("generating", attempt)
        srv.stage("generate", "started", attempt)
        srv.log("info", "generate", f"AI Terraform {'수정' if previous else '생성'} {BASE + attempt}/{MAX_AI_CALLS}"
                + (f" (이전 실패: {stage})" if previous else ""))
        try:
            files, notes, usage = generate.generate(env, inputs, previous, stage, error, attempt)
        except generate.GenerationError as e:
            record["attempts"].append({"attempt": attempt, "ok": False, "stage": "generate", "error": str(e)})
            record["ai_calls"] = attempt
            print(f"AI 생성 실패: {e}")
            srv.usage(attempt, step, e.usage, "failed")
            srv.stage("generate", "failed", attempt, str(e))
            srv.log("warn", "generate", f"AI 응답을 쓸 수 없어요: {e}")
            continue  # 같은 입력으로 다시 생성해요
        except anthropic.APIError as e:
            # 키 · 권한 · 네트워크 문제는 고쳐서 될 일이 아니라 바로 멈춰요 (SDK가 429 · 5xx는 이미 재시도했어요)
            record["attempts"].append({"attempt": attempt, "ok": False, "stage": "api", "error": f"{type(e).__name__}: {e}"})
            record["ai_calls"] = attempt
            srv.usage(attempt, step, None, "failed")
            srv.stage("generate", "failed", attempt, f"AI API 오류: {type(e).__name__}")
            srv.log("error", "generate", f"AI API 오류로 멈췄어요: {type(e).__name__}")
            return finish(plan_dir, ai_dir, record, False, f"AI API 오류: {type(e).__name__}: {e}")
        srv.usage(attempt, step, usage, "succeeded")
        srv.stage("generate", "completed", attempt)
        srv.log("info", "generate", f"AI 메모: {notes} (입력 {usage['input_tokens']} · 출력 {usage['output_tokens']} 토큰)")
        generate.write_files(files, cand, env)
        record["ai_calls"] = attempt
        print(f"AI 메모: {notes}  ·  {usage['model']} in={usage['input_tokens']} out={usage['output_tokens']} "
              f"cache_read={usage['cache_read_input_tokens']}")

        srv.state("validating", attempt)
        ok, out_or_stage = plan_and_check(env, cand, plan_dir, srv, attempt)
        entry = {"attempt": attempt, "ok": ok, "notes": notes, "usage": usage}
        if ok:
            record["attempts"].append(entry)
            if verified.exists():
                shutil.rmtree(verified)
            shutil.copytree(cand, verified)  # 검증된 스크립트로 저장 → 다음 배포는 재사용
            return finish(plan_dir, ai_dir, record, True, "")
        stage, error = out_or_stage
        entry.update({"stage": stage, "error": tail(error, 4000)})
        record["attempts"].append(entry)
        previous = files
        print(f"검증 실패 ({stage}) → {'다시 고쳐요' if attempt < budget else '시도를 다 썼어요'}")
        srv.log("warn", stage if stage in ("validate", "plan", "risk_check") else None,
                f"{stage} 단계 실패 → {'오류 로그로 AI가 고쳐요' if attempt < budget else 'AI 시도 3번을 다 썼어요'}")

    return finish(plan_dir, ai_dir, record, False, f"AI 생성 {MAX_AI_CALLS}번이 모두 검증을 통과하지 못했어요 (마지막 단계: {stage}, 앞선 시도 {BASE}번)")


def plan_and_check(env: str, src: pathlib.Path, plan_dir: pathlib.Path, srv: Server | None = None, attempt: int = 0):
    """(True, "") 또는 (False, (단계, 오류 로그))."""
    srv = srv or Server(env)
    ok, out = run_plan(env, src, plan_dir, srv, attempt)
    if not ok:
        return False, (failed_stage(out), out)
    srv.stage("risk_check", "started", attempt)
    proc = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).with_name("risk_check.py")), "--env", env,
         "--plan-json", str(plan_dir / "src" / "plan.json"), "--src", str(plan_dir / "src")],
        capture_output=True, text=True)
    print(proc.stdout, end="")
    if proc.returncode != 0:
        shutil.rmtree(plan_dir, ignore_errors=True)  # 통과하지 못한 plan은 승인 대상이 아니에요
        srv.stage("risk_check", "failed", attempt, "위험 검사 위반")
        srv.log("error", "risk_check", "위험 검사 위반:\n" + "\n".join(proc.stdout.strip().splitlines()[:10]))
        return False, ("risk_check", proc.stdout + proc.stderr)
    srv.stage("risk_check", "completed", attempt)
    srv.log("info", "risk_check", "위험 검사 통과 (공개 포트 · 권한 · 암호화 · 비용 규칙)")
    return True, ""


def run_plan(env: str, src: pathlib.Path, plan_dir: pathlib.Path, srv: Server | None = None, attempt: int = 0):
    """tf-run.sh plan. 출력을 흘려 보면서 단계 표시(init · validate → validate, plan → plan)를 서버 단계로 알려요."""
    srv = srv or Server(env)
    shutil.rmtree(plan_dir, ignore_errors=True)  # 실패한 시도의 폴더를 비우고 같은 PLAN_ID로 다시 만들어요
    proc = subprocess.Popen(
        ["bash", str(REPO / "infra" / "scripts" / "tf-run.sh"), env, "plan"],
        env={**os.environ, "MODULE_SRC": str(src)}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines, current = [], None
    for line in proc.stdout:
        print(line, end="", flush=True)
        lines.append(line)
        text = line.strip()
        # 사람이 볼 terraform 결과 줄만 로그로 보내요 (전체 출력은 Jenkins 콘솔)
        if text.startswith(("Plan: ", "No changes.", "Success! The configuration is valid")):
            srv.log("info", current, text)
        elif text.startswith(("Error: ", "tf-run: ")) and "단계" not in text and "plan ID" not in text:
            srv.log("error", current, text)
        if "tf-run: 단계 " in line:
            step = "plan" if line.split("tf-run: 단계 ", 1)[1].strip() == "plan" else "validate"
            if step != current:
                if current:
                    srv.stage(current, "completed", attempt)
                current = step
                srv.stage(step, "started", attempt)
    ok = proc.wait() == 0
    if current:
        srv.stage(current, "completed" if ok else "failed", attempt)
    if not ok:
        shutil.rmtree(plan_dir, ignore_errors=True)
    return ok, "".join(lines)


def failed_stage(out: str) -> str:
    """tf-run.sh가 찍는 단계 표시 중 마지막 것이 실패한 단계예요."""
    stages = [line.split("tf-run: 단계 ", 1)[1].strip() for line in out.splitlines() if "tf-run: 단계 " in line]
    return stages[-1] if stages else "plan"


def fingerprint(env: str, inputs: dict) -> str:
    """이미지 태그를 뺀 입력 + 기준 모듈 + 규칙. 같으면 검증된 스크립트를 재사용해요 (§16-7 재사용 기준)."""
    h = hashlib.sha256()
    h.update(env.encode())
    h.update(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode())
    for name in generate.FILES:
        h.update((generate.reference_dir(env) / name).read_bytes())
    h.update((REPO / "infra" / "ai" / "rules.md").read_bytes())
    return h.hexdigest()


def read_files(d: pathlib.Path) -> dict:
    return {n: (d / n).read_text(encoding="utf-8") for n in generate.FILES}


def tail(text: str, n: int) -> str:
    return text if len(text) <= n else "…" + text[-n:]


def finish(plan_dir: pathlib.Path, ai_dir: pathlib.Path, record: dict, ok: bool, message: str) -> int:
    record["ok"] = ok
    if message:
        record["message"] = message
    calls = [a["usage"] for a in record.get("attempts", []) if "usage" in a]
    record["usage_total"] = {
        k: sum(c[k] for c in calls)
        for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
    }
    text = json.dumps(record, ensure_ascii=False, indent=2)
    (ai_dir / "ai.json").write_text(text, encoding="utf-8")
    if ok and plan_dir.exists():
        (plan_dir / "ai.json").write_text(text, encoding="utf-8")
    mode = record.get("mode")
    print(f"plan_with_ai: {'성공' if ok else '실패'} · 방식={mode} · AI 호출 {record.get('ai_calls', 0)}회"
          + (f" · {message}" if message else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
