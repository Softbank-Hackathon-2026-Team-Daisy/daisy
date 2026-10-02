#!/usr/bin/env python3
"""plan JSON과 생성 코드로 위험한 설정을 찾아요 (infra/SPEC.md §4-3 R-1~R-6, §4-2 비용 제약, §5-0 고정 네트워크).

    risk_check.py --env aws --plan-json plans/<id>/src/plan.json --src plans/<id>/src

위반이 있으면 한 줄씩 출력하고 exit 1. AI 수정 루프가 이 출력을 오류 로그로 받아요.
기준 모듈은 이 검사를 모두 통과해요.
"""
import argparse
import json
import pathlib
import re
import sys

OPEN_CIDRS = {"0.0.0.0/0", "::/0"}
PUBLIC_PORTS = {80, 443}
FORBIDDEN_AWS = {  # 고정 네트워크 · 비용 제약
    "aws_vpc", "aws_subnet", "aws_internet_gateway", "aws_route_table", "aws_route_table_association",
    "aws_nat_gateway", "aws_eip",
}
DB_CLASSES = {"db.t4g.micro", "db.t3.micro"}
FORBIDDEN_POLICY_ARNS = ("AdministratorAccess", "PowerUserAccess", "IAMFullAccess")


def changes(plan: dict):
    """만들거나 바꾸는 리소스만 (삭제 · 그대로인 것은 빼요)."""
    for rc in plan.get("resource_changes", []):
        actions = rc["change"]["actions"]
        if "create" in actions or "update" in actions:
            yield rc["type"], rc["address"], rc["change"].get("after") or {}


def check_aws(plan: dict, src_text: str) -> list[str]:
    v = []
    for typ, addr, after in changes(plan):
        if typ in FORBIDDEN_AWS:
            v.append(f"{addr}: {typ}는 만들지 않아요 (고정 네트워크·비용 제약). vpc_id · 서브넷 변수를 써요")

        # R-1 인터넷 인바운드는 LB의 80 · 443만
        if typ == "aws_vpc_security_group_ingress_rule":
            cidrs = {after.get("cidr_ipv4"), after.get("cidr_ipv6")} & OPEN_CIDRS
            if cidrs and not _ports_public(after.get("from_port"), after.get("to_port"), after.get("ip_protocol")):
                v.append(f"{addr}: {sorted(cidrs)} 인바운드는 80 · 443만 허용해요 (R-1)")
        if typ == "aws_security_group_rule" and after.get("type") == "ingress":
            cidrs = set(after.get("cidr_blocks") or []) | set(after.get("ipv6_cidr_blocks") or [])
            if cidrs & OPEN_CIDRS and not _ports_public(after.get("from_port"), after.get("to_port"), after.get("protocol")):
                v.append(f"{addr}: 인터넷 인바운드는 80 · 443만 허용해요 (R-1)")
        if typ == "aws_security_group":
            for rule in after.get("ingress") or []:
                cidrs = set(rule.get("cidr_blocks") or []) | set(rule.get("ipv6_cidr_blocks") or [])
                if cidrs & OPEN_CIDRS and not _ports_public(rule.get("from_port"), rule.get("to_port"), rule.get("protocol")):
                    v.append(f"{addr}: 인라인 ingress의 인터넷 인바운드는 80 · 443만 허용해요 (R-1)")

        # R-3 · R-5 · 비용: DB
        if typ == "aws_db_instance":
            if after.get("publicly_accessible") is not False:
                v.append(f"{addr}: publicly_accessible = false여야 해요 (R-3)")
            if after.get("storage_encrypted") is not True:
                v.append(f"{addr}: storage_encrypted = true여야 해요 (R-5)")
            if after.get("multi_az"):
                v.append(f"{addr}: Multi-AZ는 쓰지 않아요 (비용 제약)")
            if after.get("instance_class") not in DB_CLASSES:
                v.append(f"{addr}: instance_class는 {sorted(DB_CLASSES)} 중 하나예요 (비용 제약)")

        # 비용: ECS
        if typ == "aws_ecs_service" and (after.get("desired_count") or 0) > 2:
            v.append(f"{addr}: desired_count는 2 이하예요 (비용 제약)")
        if typ == "aws_ecs_task_definition":
            if int(after.get("cpu") or 0) > 1024 or int(after.get("memory") or 0) > 2048:
                v.append(f"{addr}: 태스크는 1 vCPU / 2048 MiB 이하예요 (비용 제약)")
        if typ == "aws_ecs_cluster":
            for s in after.get("setting") or []:
                if s.get("name") == "containerInsights" and s.get("value") not in ("disabled", None):
                    v.append(f"{addr}: Container Insights는 꺼요 (비용 제약)")
        if typ == "aws_cloudwatch_log_group" and after.get("retention_in_days") not in (1, 3):
            v.append(f"{addr}: 로그 보존은 3일이에요 (비용 제약)")

        # R-6 최소 권한
        if typ == "aws_iam_role_policy_attachment" and any(n in str(after.get("policy_arn")) for n in FORBIDDEN_POLICY_ARNS):
            v.append(f"{addr}: {after.get('policy_arn')} 같은 넓은 권한은 붙이지 않아요 (R-6)")
        if typ in ("aws_iam_role_policy", "aws_iam_policy") and isinstance(after.get("policy"), str):
            if _wildcard_action(after["policy"]):
                v.append(f"{addr}: Action \"*\" 정책은 쓰지 않아요 (R-6)")

    # 코드 텍스트 검사: plan에 값이 아직 없는 경우와 data 소스 정책을 잡아요
    if re.search(r'actions\s*=\s*\[\s*"\*"\s*\]', src_text):
        v.append('iam 정책 문서: actions = ["*"]는 쓰지 않아요 (R-6)')
    v += check_common(plan, src_text)
    return v


def check_onprem(plan: dict, src_text: str) -> list[str]:
    """(가칭 · 황지환 확인) 온프레미스 Docker 컨테이너 규칙. 노출은 pfSense를 거친 Service VM IP로만 해요."""
    v = []
    for typ, addr, after in changes(plan):
        if typ != "docker_container":
            continue
        if after.get("privileged"):
            v.append(f"{addr}: privileged 컨테이너는 쓰지 않아요 (R-6)")
        if after.get("network_mode") == "host":
            v.append(f"{addr}: host 네트워크는 쓰지 않아요. 포트를 게시해요 (R-2)")
        for port in after.get("ports") or []:
            if port.get("ip") in (None, "", "0.0.0.0", "::"):
                v.append(f"{addr}: 포트는 Service VM IP(host_ip)에만 바인딩해요. 0.0.0.0 금지 (R-1)")
        for m in (after.get("volumes") or []) + (after.get("mounts") or []):
            if "docker.sock" in str(m.get("host_path") or m.get("source") or ""):
                v.append(f"{addr}: Docker 소켓을 컨테이너에 마운트하지 않아요 (R-6)")
    if re.search(r'^\s*host\s*=\s*"tcp://', src_text, re.M):
        v.append("Docker provider는 ssh://로만 접속해요. 인증 없는 tcp:// 금지")
    return v + check_common(plan, src_text)


FORBIDDEN_GCP = {"google_compute_network", "google_compute_subnetwork", "google_compute_router",
                 "google_compute_router_nat", "google_compute_address", "google_compute_global_address"}
GCP_PRIMITIVE_ROLES = {"roles/owner", "roles/editor"}
GCP_PUBLIC_INVOKER = {"google_cloud_run_v2_service_iam_member", "google_cloud_run_v2_service_iam_binding",
                      "google_cloud_run_service_iam_member", "google_cloud_run_service_iam_binding"}


def check_gcp(plan: dict, src_text: str) -> list[str]:
    """GCP Cloud Run 규칙 (SPEC §6). 공개는 Cloud Run 호출 권한(allUsers run.invoker)만, 요청이 없으면 0대."""
    v = []
    for typ, addr, after in changes(plan):
        if typ in FORBIDDEN_GCP:
            v.append(f"{addr}: {typ}는 만들지 않아요 (Cloud Run은 네트워크 · 고정 IP가 필요 없어요, 비용 제약)")
        if typ.startswith("google_") and any(k in typ for k in ("_iam_member", "_iam_binding", "_iam_policy")):
            role = after.get("role") or ""
            members = [after.get("member")] + list(after.get("members") or [])
            if role in GCP_PRIMITIVE_ROLES:
                v.append(f"{addr}: {role} 같은 기본 역할은 주지 않아요. 필요한 역할만 줘요 (R-6)")
            if any(m in ("allUsers", "allAuthenticatedUsers") for m in members if m) and not (
                    typ in GCP_PUBLIC_INVOKER and role == "roles/run.invoker"):
                v.append(f"{addr}: 전체 공개(allUsers)는 Cloud Run 호출 권한(roles/run.invoker)에만 줘요 (R-1 · R-6)")
        if typ == "google_cloud_run_v2_service":
            if after.get("deletion_protection") is not False:
                v.append(f"{addr}: deletion_protection = false여야 해요 (해커톤 중 지우고 다시 만들어요)")
            for t in after.get("template") or []:
                scaling = (t.get("scaling") or [{}])[0]
                if (scaling.get("min_instance_count") or 0) > 0:
                    v.append(f"{addr}: min_instance_count는 0이어야 해요 (요청이 없으면 과금 0)")
                if not isinstance(scaling.get("max_instance_count"), int) or scaling["max_instance_count"] > 2:
                    v.append(f"{addr}: max_instance_count를 2 이하로 정해요 (비용 상한)")
                for c in t.get("containers") or []:
                    for r in c.get("resources") or []:
                        limits = r.get("limits") or {}
                        if _gcp_cpu(limits.get("cpu")) > 1:
                            v.append(f"{addr}: CPU는 1 이하예요 (비용 상한)")
                        if _gcp_mib(limits.get("memory")) > 2048:
                            v.append(f"{addr}: 메모리는 2Gi 이하예요 (비용 상한)")
    return v + check_common(plan, src_text)


def _gcp_cpu(value) -> float:
    """Cloud Run cpu 한도 문자열 → 코어 수 ("1" · "2" · "1000m"). 모르면 0"""
    text = str(value or "0")
    try:
        return float(text[:-1]) / 1000 if text.endswith("m") else float(text)
    except ValueError:
        return 0


def _gcp_mib(value) -> float:
    """Cloud Run memory 한도 문자열 → MiB ("512Mi" · "1Gi" · "2G"). 모르면 0"""
    m = re.fullmatch(r"([0-9.]+)\s*(Mi|Gi|M|G)?", str(value or "0"))
    if not m:
        return 0
    n, unit = float(m.group(1)), m.group(2) or "Mi"
    return n * {"Mi": 1, "Gi": 1024, "M": 1 / 1.048576, "G": 1000 / 1.048576}[unit]


def check_common(plan: dict, src_text: str) -> list[str]:
    v = []
    if re.search(r"^\s*backend\s+\"[a-z0-9_]+\"\s*\{", _without_runner_backend(src_text), re.M):
        v.append("backend 블록은 쓰지 않아요. 러너가 주입해요")
    if re.search(r"^\s*(access_key|secret_key|token|profile|credentials)\s*=", src_text, re.M):
        v.append("provider에 자격증명(access_key · secret_key · token · profile · credentials)을 쓰지 않아요")
    # R-4 비밀값 리터럴
    if re.search(r'(password|secret_string|secret_data)\s*=\s*"(?!\$\{)[^"]+"', src_text):
        v.append('비밀값을 문자열로 쓰지 않아요. secrets 변수 → Secrets Manager 참조로 넣어요 (R-4)')
    if "-----BEGIN" in src_text:
        v.append("개인 키 같은 비밀값이 코드에 있어요 (R-4)")

    root = plan.get("configuration", {}).get("root_module", {})
    tag = root.get("variables", {}).get("image_tag")
    if tag is None:
        v.append("필수 변수 image_tag가 없어요")
    elif "default" in tag:
        v.append("image_tag에는 기본값을 두지 않아요")
    if "service_url" not in root.get("outputs", {}):
        v.append("필수 출력 service_url이 없어요")
    return v


def _ports_public(from_port, to_port, protocol) -> bool:
    if str(protocol) == "-1":
        return False
    if from_port is None or to_port is None:
        return False
    return int(from_port) == int(to_port) and int(from_port) in PUBLIC_PORTS


def _wildcard_action(policy_json: str) -> bool:
    try:
        doc = json.loads(policy_json)
    except ValueError:
        return False
    stmts = doc.get("Statement", [])
    for s in stmts if isinstance(stmts, list) else [stmts]:
        actions = s.get("Action", [])
        actions = actions if isinstance(actions, list) else [actions]
        if s.get("Effect") == "Allow" and any(a in ("*", "*:*") for a in actions):
            return True
    return False


def _without_runner_backend(src_text: str) -> str:
    # 러너가 넣는 backend.tf의 빈 backend 블록은 빼고 봐요
    return re.sub(r'terraform\s*\{\s*backend\s+"(s3|local|gcs)"\s*\{\s*\}\s*\}', "", src_text)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--env", required=True)
    p.add_argument("--plan-json", required=True, type=pathlib.Path)
    p.add_argument("--src", required=True, type=pathlib.Path)
    a = p.parse_args()

    plan = json.loads(a.plan_json.read_text(encoding="utf-8"))
    src_text = "\n".join(f.read_text(encoding="utf-8") for f in sorted(a.src.glob("*.tf")))
    if a.env == "aws":
        violations = check_aws(plan, src_text)
    elif a.env == "onprem":
        violations = check_onprem(plan, src_text)
    elif a.env == "gcp":
        violations = check_gcp(plan, src_text)
    else:
        violations = check_common(plan, src_text)
    for line in violations:
        print(f"위험: {line}")
    if not violations:
        scope = {"aws": "R-1~R-6 · 비용 제약 · 고정 네트워크", "onprem": "컨테이너 격리 · 바인딩 · 구조",
                 "gcp": "R-4 · R-6 · 공개 범위 · 비용 제약"}.get(a.env, "구조")
        print(f"risk_check: {a.env} 통과 ({scope})")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
