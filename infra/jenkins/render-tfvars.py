#!/usr/bin/env python3
"""deploy.yaml + 대상 환경 등록값 + 이미지 주소 → terraform 변수 파일 (JSON, 비밀값 없음).

(가칭) Jenkins 프로토타입용 최소 변환이에요. 정식 deploy.yaml 파싱·검증은 server/manifest(김승환) 영역이에요.

    render-tfvars.py <deploy.yaml> <target.json | -> <image_repo> > <app>/<env>.tfvars.json

- target.json: 관리자가 환경 등록 때 1번 넣는 값 (region, project_id 등). 계정 ID가 들어가서 레포 밖에 둬요
- env: deploy.yaml에는 이름만 있고 값의 출처가 [미정]이라 넘기지 않아요 (앱 기본값 사용)
- secrets: 값은 Jenkins Credentials에서 TF_VAR_secrets로만 넣어요
"""
import json
import sys

import yaml  # Ubuntu: python3-yaml

deploy_yaml, target_file, image_repo = sys.argv[1:4]

with open(deploy_yaml, encoding="utf-8") as f:
    spec = yaml.safe_load(f)

tfvars = {
    "name": spec["name"],
    "image": image_repo,
    "port": int(spec["port"]),
    "healthcheck": spec.get("healthcheck", "/health"),
    "database": bool(spec.get("database", False)),
}
if target_file != "-":
    with open(target_file, encoding="utf-8") as f:
        tfvars.update(json.load(f))

json.dump(tfvars, sys.stdout, indent=2)
print()
