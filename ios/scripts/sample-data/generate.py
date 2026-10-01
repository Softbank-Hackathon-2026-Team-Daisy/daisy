#!/usr/bin/env python3
"""예시 데이터 번들 만들기 — 앱의 "예시 데이터로 둘러보기 (오프라인)"용.

실제 GitHub의 sample-monolith · sample-msa 커밋과 deploy.yaml을 읽어서, 서버 API와 같은 모양의 응답을
Daisy/Resources/SampleData/sample.json 한 파일로 만들어요. 배포 상태 · 환경 · 비용은 예시예요 (앱에 "예시 데이터" 배지가 떠요).

    python3 ios/scripts/sample-data/generate.py      # gh CLI 로그인이 필요해요

시각은 만든 시각(generated_at) 기준 상대값이고, 앱이 열 때 지금 시각으로 옮겨요.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ORG = "Softbank-Hackathon-2026-Team-Daisy"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Daisy", "Resources", "SampleData", "sample.json")
NOW = datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def ago(**kw):
    return iso(NOW - timedelta(**kw))


def gh(path):
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"gh api {path} 실패: {out.stderr.strip()}")
    return json.loads(out.stdout)


def commits(repo):
    items = gh(f"repos/{ORG}/{repo}/commits?per_page=20")
    return [c for c in items if not c["commit"]["message"].startswith(("Merge ", "Initial commit"))]


def file_text(repo, path):
    return base64.b64decode(gh(f"repos/{ORG}/{repo}/contents/{path}")["content"]).decode()


def subject(c):
    return c["commit"]["message"].split("\n")[0]


# ── 공통: 환경 · 단계 ─────────────────────────────────────────────

T = {"onprem": "tgt_onprem", "aws": "tgt_aws", "gcp": "tgt_gcp"}
TITLES = {"onprem": "home-lab · Docker Compose", "aws": "ap-northeast-2 · ECS Fargate", "gcp": "asia-northeast3 · Cloud Run"}


def url(project, env):
    # 예시 도메인(RFC 2606)이라 실제로 열리지 않아요
    return {"onprem": f"https://{project}.onprem.example.com", "aws": f"https://{project}.aws.example.com",
            "gcp": f"https://{project}.run.example.com"}[env]


# 단계 이름은 웹 화면 표기 그대로 (web/src/pages/flow.ts)
STEP_LABEL = {"generate": "Terraform 생성 (AI)", "validate": "terraform validate", "plan": "terraform plan",
              "risk_check": "위험 설정 검사", "apply": "terraform apply", "health_check": "헬스체크"}


def step(name, state, ms=None, at=None):
    return {"name": STEP_LABEL.get(name, name), "state": state, "duration_ms": ms, "started_at": at}


def digest(sha):
    """이미지 digest 예시: 커밋마다 하나 (같은 이미지면 모든 환경에서 같아요)"""
    return "sha256:" + hashlib.sha256(sha.encode()).hexdigest()[:12]


def tstate(s, st):
    if st == "failed":
        return "failed"
    if s == "apply":
        return "applying"
    if s == "health_check":
        return "succeeded" if st == "done" else "verifying"
    if s == "risk_check" and st == "done":
        return "awaiting_approval"
    return "generating" if s == "generate" else "validating"


def tgt(env, s, st, attempt=1, reused=False, steps=None, u=None, err=None, health=None):
    if reused and steps:
        steps = [dict(x, name="스크립트 재사용") if x["name"] == STEP_LABEL["generate"] else x for x in steps]
    return {"target_id": T[env], "state": tstate(s, st), "step": s, "step_state": st, "attempt": attempt,
            "reused_script": reused, "url": u, "error_summary": err, "title": TITLES[env], "steps": steps,
            "health_summary": health}


VALIDATED = [step("generate", "done", 41000), step("validate", "done", 3100), step("plan", "done", 8200),
             step("risk_check", "done", 900)]
APPLIED = [step("apply", "done", 63000), step("health_check", "done", 4000)]


def usage(calls):
    # 합계만 (10/1 서버: 합계는 A-05 plan, 호출별 상세는 GET /projects/{id}/ai-usage?deployment_id=)
    return {"tokens": sum(c["tokens"] for c in calls), "cost_krw": sum(c["cost_krw"] for c in calls),
            "exchange_rate": 1380, "estimated": True, "calls": len(calls)}


def call(env, step_, attempt, tokens, cost, status, minutes, note=None):
    return {"at": ago(minutes=minutes), "target_id": T[env], "step": step_, "attempt": attempt, "tokens": tokens,
            "cost_krw": cost, "status": status, "note": note}


CALLS = {}  # 프로젝트 → 호출 기록 (ai-usage 목록)


def deployment(pid, did, ver, c, state, targets, created, finished=None, pending=False, calls=None):
    repo = {"prj_monolith": "sample-monolith", "prj_msa": "sample-msa"}[pid]
    for c_ in calls or []:
        c_["deployment_id"] = did
    # apply가 끝난 환경은 올라간 이미지 digest를 같이 줘요 (W-08 동일성 검증)
    for t in targets:
        t["image_digest"] = digest(c["sha"]) if t["state"] in ("verifying", "succeeded") or (t["step"] == "health_check") else None
    CALLS.setdefault(pid, []).extend(calls or [])
    return {"id": did, "project_id": pid, "commit": c["sha"], "image": f"ghcr.io/team-daisy/{repo}:{c['sha'][:7]}",
            "version": ver, "commit_message": subject(c), "state": state, "targets": targets,
            "pending_approval": {"approval_id": f"apv_{did}", "kind": "plan"} if pending else None,
            "created_by": c["commit"]["author"]["name"], "created_at": created, "finished_at": finished,
            "kind": None, "rolled_back_from": None, "ai_usage": usage(calls or [])}


# ── 프로젝트별 시나리오 ────────────────────────────────────────────

def monolith():
    pid, name = "prj_monolith", "sample-monolith"
    cs = commits(name)                        # 최신 먼저
    c = (cs + cs)[:5]                         # 커밋이 모자라도 시나리오 5개를 채워요
    u = lambda e: url("hellocalc", e)
    deps = [
        # 승인 대기 (W-06): 온프레미스는 재사용, AWS는 수정 1회
        deployment(pid, "dep_m6", "v6", c[0], "awaiting_approval",
                   [tgt("onprem", "risk_check", "done", reused=True, steps=VALIDATED),
                    tgt("aws", "risk_check", "done", 2, steps=VALIDATED),
                    tgt("gcp", "risk_check", "done", steps=VALIDATED)], ago(minutes=12), pending=True,
                   calls=[call("aws", "generate", 1, 3120, 82, "failed", 11), call("aws", "fix", 2, 1860, 48, "succeeded", 10, "보안 그룹 0.0.0.0/0 수정"),
                          call("gcp", "generate", 1, 2940, 76, "succeeded", 11)]),
        # 배포 중 (W-07)
        deployment(pid, "dep_m5", "v5", c[1], "running",
                   [tgt("onprem", "health_check", "done", reused=True, steps=APPLIED, u=u("onprem")),
                    tgt("aws", "apply", "running", steps=[step("apply", "running"), step("health_check", "waiting")]),
                    tgt("gcp", "apply", "running", steps=[step("apply", "running"), step("health_check", "waiting")])],
                   ago(hours=1)),
        # 한 환경만 멈춤 (W-05b)
        deployment(pid, "dep_m4", "v4", c[2], "running",
                   [tgt("onprem", "risk_check", "done", reused=True, steps=VALIDATED),
                    tgt("aws", "plan", "failed", 3, steps=[step("generate", "done", 41000), step("validate", "done", 2900), step("plan", "failed", 8000)],
                        err="terraform plan 오류: IAM 권한 부족 (ecs:CreateService)"),
                    tgt("gcp", "validate", "running", 2, steps=[step("generate", "done", 40000), step("validate", "running")])],
                   ago(hours=3), calls=[call("aws", "generate", 1, 3050, 80, "failed", 175), call("aws", "fix", 2, 1900, 49, "failed", 172),
                                        call("aws", "fix", 3, 1880, 49, "failed", 169), call("gcp", "generate", 1, 2900, 75, "failed", 174)]),
        # 성공 (W-08) — 지금 떠 있는 버전
        deployment(pid, "dep_m3", "v3", c[3], "succeeded",
                   [tgt(e, "health_check", "done", reused=(e == "onprem"), steps=APPLIED, u=u(e), health="200 OK · 120ms") for e in T],
                   ago(hours=20), ago(hours=19, minutes=54),
                   calls=[call("aws", "generate", 1, 3100, 81, "succeeded", 1195), call("gcp", "generate", 1, 2950, 76, "succeeded", 1195)]),
        # 일부 성공 (W-08 "일부 성공")
        deployment(pid, "dep_m2", "v2", c[4], "partially_succeeded",
                   [tgt("onprem", "health_check", "done", steps=APPLIED, u=u("onprem"), health="200 OK · 98ms"),
                    tgt("aws", "health_check", "done", steps=APPLIED, u=u("aws"), health="200 OK · 131ms"),
                    tgt("gcp", "health_check", "failed", steps=[step("apply", "done", 58000), step("health_check", "failed", 30000)], u=u("gcp"),
                        err="헬스체크 30초 안에 응답 없음 (/health)")],
                   ago(days=1, hours=2), ago(days=1, hours=1, minutes=52),
                   calls=[call(e, "generate", 1, 3000, 78, "succeeded", 1560) for e in ("onprem", "aws", "gcp")]),
    ]
    current = deps[3]
    statuses = [{"target_id": T[e], "type": e, "name": {"onprem": "온프레미스", "aws": "AWS", "gcp": "GCP"}[e],
                 "current": {"commit": current["commit"], "image": current["image"], "deployment_id": current["id"], "deployed_at": current["finished_at"]},
                 "url": u(e), "health": "healthy", "health_summary": "200 OK · 120ms", "checked_at": ago(seconds=40), "image_digest": digest(current["commit"])} for e in T]
    return pid, name, cs, deps, statuses, file_text(name, "deploy.yaml"), "deploy.yaml"


def msa():
    pid, name = "prj_msa", "sample-msa"
    cs = commits(name)
    c = (cs + cs)[:2]
    u = lambda e: url("hellocalc-frontend", e)
    deps = [
        # 생성 · 검증 중 (W-05)
        deployment(pid, "dep_s2", "v2", c[0], "running",
                   [tgt("onprem", "plan", "done", reused=True, steps=VALIDATED[:3]),
                    tgt("aws", "validate", "running", 2, steps=[step("generate", "done", 44000), step("validate", "running")]),
                    tgt("gcp", "generate", "running", steps=[step("generate", "running")])], ago(minutes=4),
                   calls=[call("aws", "generate", 1, 3400, 88, "failed", 3), call("aws", "fix", 2, 2010, 52, "succeeded", 2, "backend 내부 ingress 규칙 추가")]),
        deployment(pid, "dep_s1", "v1", c[1], "succeeded",
                   [tgt(e, "health_check", "done", steps=APPLIED, u=u(e), health="200 OK · 140ms") for e in T],
                   ago(hours=6), ago(hours=5, minutes=50),
                   calls=[call(e, "generate", 1, 3300, 85, "succeeded", 358) for e in ("onprem", "aws", "gcp")]),
    ]
    current = deps[1]
    statuses = [{"target_id": T[e], "type": e, "name": {"onprem": "온프레미스", "aws": "AWS", "gcp": "GCP"}[e],
                 "current": {"commit": current["commit"], "image": current["image"], "deployment_id": current["id"], "deployed_at": current["finished_at"]},
                 "url": u(e), "health": "healthy", "health_summary": "200 OK · 120ms", "checked_at": ago(seconds=40), "image_digest": digest(current["commit"])} for e in T]
    return pid, name, cs, deps, statuses, file_text(name, "services/frontend/deploy.yaml"), "services/frontend/deploy.yaml"


# ── 조립 ─────────────────────────────────────────────────────────

def page(items):
    return {"items": items, "next_cursor": None}


TARGETS = [
    {"target_id": T["onprem"], "type": "onprem", "name": "온프레미스", "title": "온프레미스 · Docker Compose", "runtime": "Proxmox VM · Docker Compose",
     "location": "home-lab", "location_label": "위치", "access_method": "사설망(VPN) + SSH", "exposure": "팀 도메인 HTTPS", "state_backend": None,
     "reuse": {"available": True, "script_id": "scr_onprem_s1", "reason": "home-lab Proxmox VM · 사설망 · 검증된 스크립트 있음 → 태그만 교체"},
     "connection": {"state": "ok", "checked_at": ago(minutes=1)}},
    {"target_id": T["aws"], "type": "aws", "name": "AWS", "title": "AWS · ECS + ALB", "runtime": "ECS Fargate + ALB",
     "location": "ap-northeast-2", "location_label": "리전", "access_method": "IAM 역할", "exposure": "ALB HTTPS", "state_backend": "S3 (잠금)",
     "reuse": {"available": True, "script_id": "scr_aws_s2", "reason": "ap-northeast-2 · 검증된 스크립트 있음 → 태그만 교체"},
     "connection": {"state": "ok", "checked_at": ago(minutes=1)}},
    {"target_id": T["gcp"], "type": "gcp", "name": "GCP", "title": "GCP · Cloud Run", "runtime": "Cloud Run",
     "location": "asia-northeast3", "location_label": "리전", "access_method": "서비스 계정", "exposure": "Cloud Run URL", "state_backend": "GCS (잠금)",
     "reuse": {"available": False, "reason": "asia-northeast3 · 처음 배포 → AI가 Terraform 생성"}, "connection": {"state": "ok", "checked_at": ago(minutes=1)}},
]

TF = {"aws": 'resource "aws_ecs_service" "app" {\n  name            = var.name\n  cluster         = aws_ecs_cluster.main.id\n  task_definition = aws_ecs_task_definition.app.arn\n  desired_count   = 1\n  launch_type     = "FARGATE"\n}\n',
      "onprem": 'resource "docker_container" "app" {\n  name  = var.name\n  image = var.image\n  ports {\n    internal = 8080\n    external = 8080\n  }\n}\n',
      "gcp": 'resource "google_cloud_run_v2_service" "app" {\n  name     = var.name\n  location = "asia-northeast3"\n  template {\n    containers { image = var.image }\n  }\n}\n'}


def script(sid, env, ver, attempt, status, reuse, commit, note=None, days=2):
    return {"script_id": sid, "target_id": T[env], "version": ver, "origin": "ai_generated", "attempt": attempt,
            "validation": {"validate": True, "plan": status == "verified", "risks": 0}, "status": status,
            "reuse_count": reuse, "last_used_at": ago(hours=1) if reuse else None,
            "files": [{"path": f"{env}/main.tf", "content": TF[env]}], "note": note, "base_commit": commit,
            "input": "deploy.yaml + 기준 모듈", "ai_tokens": 3000 + attempt * 1200, "storage": f"scripts/{env}/{ver}", "created_at": ago(days=days)}


def plan(dep):
    counts = {T["onprem"]: (0, 1, 0), T["aws"]: (2, 1, 1), T["gcp"]: (1, 0, 0)}
    res = {T["onprem"]: [("update", "docker_container.app")],
           T["aws"]: [("create", "aws_ecs_service.app"), ("create", "aws_lb_target_group.app"), ("update", "aws_ecs_task_definition.app"), ("replace", "aws_lb_listener_rule.app")],
           T["gcp"]: [("create", "google_cloud_run_v2_service.app")]}
    targets = []
    for t in dep["targets"]:
        c, u_, d = counts[t["target_id"]]
        risks = [{"level": "medium", "rule": "open_ingress", "resource": "aws_security_group.alb", "message": "443 포트가 0.0.0.0/0에 열려 있어요 (ALB 공개용이라 허용)"}] if t["target_id"] == T["aws"] else []
        targets.append({"target_id": t["target_id"], "counts": {"create": c, "update": u_, "delete": d}, "has_delete": d > 0, "risks": risks,
                        "reused_script": t["reused_script"], "summary": "이미지 태그만 교체" if t["reused_script"] else None, "resources": [{"action": a, "address": addr, "monthly_cost_krw": None} for a, addr in res[t["target_id"]]]})
    return {"deployment_id": dep["id"], "targets": targets, "ai_usage": {k: dep["ai_usage"][k] for k in ("tokens", "cost_krw", "exchange_rate", "estimated", "calls")}}


def main():
    responses = {}
    projects = []
    for pid, name, cs, deps, statuses, yaml_text, yaml_path in (monolith(), msa()):
        repo = f"https://github.com/{ORG}/{name}"
        projects.append({"id": pid, "name": name, "repository": repo, "branch": "main"})
        responses[f"projects/{pid}"] = {"id": pid, "name": name, "repository": repo, "branch": "main",
                                        "build": "Jenkins daisy-ci · docker build", "registry": "ghcr.io/team-daisy", "webhook_last_at": ago(minutes=12)}
        responses[f"projects/{pid}/deployments"] = page(deps)
        responses[f"projects/{pid}/targets/status"] = page(statuses)
        responses[f"projects/{pid}/targets"] = page(TARGETS)
        responses[f"projects/{pid}/builds"] = page([{
            "source_version_id": f"sv_{c['sha'][:7]}", "commit": c["sha"], "message": subject(c), "author": c["commit"]["author"]["name"], "committed_at": c["commit"]["author"]["date"],
            "pipeline": {"status": "success", "run_url": None}, "image": f"ghcr.io/team-daisy/{name}:{c['sha'][:7]}",
            "deployed_to": [], "branch": "main", "image_digest": digest(c["sha"]),
            # Jenkins daisy-ci 단계 (10/1 임채준 답). Jenkins 화면은 외부에 공개하지 않아서 링크는 없어요.
            # Trigger CD는 운영에서 늘 건너뜀 — 서버가 CI 결과를 받아 daisy-cd-plan을 직접 시작해요 (10/1 #25)
            "steps": [step("Checkout", "done", 2000), step("Test", "done", 21000), step("Build & Push", "done", 73000), step("Trigger CD", "skipped")]} for i, c in enumerate(cs)])
        responses[f"projects/{pid}/manifest"] = {"port": 8080, "healthcheck": "/health", "env": ["LOG_LEVEL", "SHUTDOWN_TIMEOUT"], "secrets": [],
                                                 "database": False, "errors": [], "raw": yaml_text, "ref": f"{yaml_path} · main@{cs[0]['sha'][:7]}"}
        responses[f"projects/{pid}/scripts"] = page([
            script(f"scr_aws_{pid}", "aws", "s2", 2, "verified", 4, deps[-1]["commit"], "보안 그룹 수정"),
            script(f"scr_onprem_{pid}", "onprem", "s1", 1, "verified", 6, deps[-1]["commit"], days=3),
            script(f"scr_gcp_{pid}", "gcp", "s1", 3, "discarded", 0, deps[-1]["commit"], days=1)])
        responses[f"projects/{pid}/ai-usage"] = page(sorted(CALLS.get(pid, []), key=lambda c_: c_["at"], reverse=True))
        for d in deps:
            responses[f"deployments/{d['id']}"] = d
            responses[f"deployments/{d['id']}/plan"] = plan(d)
            responses[f"deployments/{d['id']}/logs"] = page([
                {"ts": ago(minutes=m), "target_id": T["aws"], "level": lv, "text": tx} for m, lv, tx in
                [(9, "info", "terraform init"), (9, "info", "terraform validate: Success!"), (8, "error", "Error: creating ECS Service: AccessDeniedException (ecs:CreateService)"),
                 (8, "info", "AI 수정 시도 2/3: IAM 정책에 ecs:CreateService 추가"), (7, "info", "terraform plan: 2 to add, 1 to change, 1 to destroy")]])
            for e in T:
                responses[f"deployments/{d['id']}/targets/{T[e]}/script"] = script(f"scr_{d['id']}_{e}", e, "s2" if e == "aws" else "s1", 1, "verified", 0, d["commit"])
    responses["projects"] = page(projects)
    for e in T:
        responses[f"targets/{T[e]}/resources"] = page([{"address": a, "type": a.split(".")[0]} for a in {
            "onprem": ["docker_container.app", "docker_network.daisy"],
            "aws": ["aws_ecs_service.app", "aws_lb.app", "aws_lb_target_group.app", "aws_ecs_cluster.main"],
            "gcp": ["google_cloud_run_v2_service.app"]}[e]])

    data = {"generated_at": iso(NOW), "note": "예시 데이터 — 실제 GitHub 커밋 · deploy.yaml 위에 배포 상태를 예시로 채웠어요", "responses": responses}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print(f"✅ {os.path.relpath(OUT)} · 응답 {len(responses)}개 · {os.path.getsize(OUT) // 1024} KB · {iso(NOW)}")


if __name__ == "__main__":
    main()
