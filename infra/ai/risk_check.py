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
    else:
        violations = check_common(plan, src_text)  # GCP 규칙은 GCP 모듈과 함께 추가해요
    for line in violations:
        print(f"위험: {line}")
    if not violations:
        print(f"risk_check: {a.env} 통과 (R-1~R-6 · 비용 제약 · 고정 네트워크)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
