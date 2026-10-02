"""격리된 로컬 PostgreSQL + 실제 서버 jar의 HTTP 연결을 검증해요.

MOCK: Jenkins/Terraform 대신 콜백 데이터를 보내요. 실제 인프라는 호출하지 않아요.
DAISY_TEST_DB_URL/USER/PASSWORD, JAVA_HOME, PSQL(선택)을 설정하고 서버 폴더에서
python3 scripts/verify-result-flow.py build/libs/daisy-server-0.0.1-SNAPSHOT.jar 로 실행해요.
"""

import datetime as dt
import json
import os
import pathlib
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def main():
    db = urllib.parse.urlsplit(os.environ["DAISY_TEST_DB_URL"].removeprefix("jdbc:"))
    assert db.scheme == "postgresql" and db.hostname in ("127.0.0.1", "localhost")
    assert not db.query, "테스트 URL에는 쿼리 옵션을 넣지 않아요"
    schema = "daisy_flow_" + uuid.uuid4().hex
    assert re.fullmatch(r"daisy_flow_[a-f0-9]{32}", schema)
    pg_env = dict(os.environ, PGPASSWORD=os.environ["DAISY_TEST_DB_PASSWORD"],
                  PGOPTIONS=f"-c search_path={schema}")

    def sql(statement):
        return subprocess.check_output(
            [os.environ.get("PSQL", "psql"), "-X", "-qAt", "-v", "ON_ERROR_STOP=1",
             "-h", db.hostname, "-p", str(db.port or 5432), "-U", os.environ["DAISY_TEST_DB_USER"],
             "-d", db.path.lstrip("/"), "-c", statement], env=pg_env, text=True).strip()

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    # Loopback requests must not go through a developer's configured HTTP proxy.
    http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    password, callback_token = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    viewer_password = secrets.token_urlsafe(32)
    env = dict(os.environ, DAISY_DB_URL=os.environ["DAISY_TEST_DB_URL"] + f"?currentSchema={schema}",
               DAISY_DB_USER=os.environ["DAISY_TEST_DB_USER"],
               DAISY_DB_PASSWORD=os.environ["DAISY_TEST_DB_PASSWORD"],
               DAISY_AUTH_SECRET=secrets.token_urlsafe(48),
               DAISY_DEMO_OWNER_USERNAME="flow-owner", DAISY_DEMO_OWNER_PASSWORD=password,
               DAISY_DEMO_VIEWER_USERNAME="flow-viewer", DAISY_DEMO_VIEWER_PASSWORD=viewer_password,
               DAISY_JENKINS_CALLBACK_TOKEN=callback_token)
    calls_made = set()
    response_codes = {}

    def request(path, body=None, bearer=None, headers=None, expected=200, method=None, raw=False):
        values = {"Content-Type": "application/json", **(headers or {})}
        if bearer:
            values["Authorization"] = "Bearer " + bearer
        req = urllib.request.Request(base + path, headers=values,
                                     data=None if body is None else json.dumps(body).encode(), method=method)
        try:
            response = http.open(req, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            payload = response.read()
            assert response.status == expected, f"{path}: HTTP {response.status}, expected {expected}"
            if response.status < 300:
                calls_made.add((req.get_method().lower(), path.split('?')[0]))
                response_codes[(req.get_method().lower(), path.split('?')[0])] = str(response.status)
            if raw:
                return payload.decode()
            return json.loads(payload) if payload else None

    sql(f'CREATE SCHEMA "{schema}"')
    process = None
    try:
        with tempfile.TemporaryFile() as logs:
            process = subprocess.Popen(
                [str(pathlib.Path(os.environ["JAVA_HOME"]) / "bin/java"), "-jar", sys.argv[1],
                 f"--server.port={port}", "--server.address=127.0.0.1",
                 "--daisy.jenkins.enabled=false", "--daisy.jenkins.worker-enabled=false",
                 "--daisy.jenkins.console-enabled=false", "--daisy.jenkins.callbacks-enabled=true",
                 "--daisy.jenkins.instance-id=flow-test",
                 "--daisy.jenkins.ci-projects=daisy-ci=prj_flow",
                 "--daisy.jenkins.callback-token=${DAISY_JENKINS_CALLBACK_TOKEN}"],
                env=env, stdout=logs, stderr=subprocess.STDOUT)
            for _ in range(120):
                if process.poll() is not None:
                    raise AssertionError("검증용 서버가 기동 중 종료됐어요")
                try:
                    token = request("/auth/token", {"username": "flow-owner", "password": password})["access_token"]
                    if sql("select count(*) from target where id='tgt_demo_aws'") == "1":
                        break
                    time.sleep(0.5)
                except (urllib.error.URLError, TimeoutError):
                    time.sleep(0.5)
                except AssertionError as error:
                    # HTTP 포트가 열린 뒤 데모 계정 시딩이 끝나는 짧은 구간을 기다려요.
                    if "/auth/token: HTTP 401" not in str(error):
                        raise
                    time.sleep(0.5)
            else:
                raise AssertionError("검증용 서버 기동 시간 초과")
            api = request("/v3/api-docs")
            assert api["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
            schemas = api["components"]["schemas"]
            for name, fields in {"CreateDeployment": {"source_version_id", "target_ids"},
                                 "TokenResponse": {"access_token", "expires_at"},
                                 "TargetStatusResponse": {"target_id", "image_digest", "health_summary"}}.items():
                assert fields <= schemas[name]["properties"].keys(), f"문서 필드 이름 불일치: {name}"
            assert {"source_version_id", "target_ids"} <= set(schemas["CreateDeployment"]["required"])
            assert schemas["PlanResponse"]["properties"]["targets"]["items"]["$ref"].endswith("/PlanTarget")
            assert schemas["DeploymentDetailResponse"]["properties"]["targets"]["items"]["$ref"].endswith("/DeploymentTarget")
            for name, field in (("TargetStatusResponse", "current"), ("TargetResponse", "reuse")):
                prop = schemas[name]["properties"][field]
                assert "$ref" not in prop and len(prop["anyOf"]) == 2, "nullable 참조는 null과 객체의 합집합이어야 해요"
                assert any(v.get("type") == "null" for v in prop["anyOf"])
            assert "swagger-ui-bundle.js" in request("/swagger-ui.html", raw=True)
            assert "SwaggerUIBundle" in request("/swagger-ui/swagger-ui-bundle.js", raw=True)
            request("/v3/api-docs/swagger-config")
            assert request("/actuator/health")["status"] == "UP"
            print(f"Swagger UI: {base}/swagger-ui/index.html", flush=True)
            viewer = request("/auth/token", {"username": "flow-viewer", "password": viewer_password})["access_token"]
            request("/auth/token", {"username": "flow-owner", "password": "wrong"}, expected=401)
            request("/auth/me", bearer=token)
            request("/projects", bearer=token)
            registration = {"repository": "audit-fixture/unibloom", "branch": "main"}
            registered = request("/projects", registration, token, expected=201)
            request("/projects", registration, token, expected=409)
            request("/projects", registration, viewer, expected=403)
            registered_id = registered["project"]["id"]
            request(f"/projects/{registered_id}", bearer=token)
            assert request(f"/projects/{registered_id}/targets", bearer=token)["items"] == []
            request(f"/projects/{registered_id}", bearer=token, method="DELETE", expected=204)
            request(f"/projects/{registered_id}", bearer=token, expected=404)
            commit, digest = "a" * 40, "sha256:" + "b" * 64
            images = {"app": {"image_ref": "registry.test/app:" + commit, "commit_sha": commit, "digest": digest}}
            # MOCK: 운영자가 등록한 대상 연결만 시드해요. CI 결과는 실제 내부 수신 경로로 넣어요.
            sql("insert into project(id,name,repository_id,repository_url,default_branch,created_by) "
                "values('prj_flow','Flow','repo-flow','https://example.test/repo','main','acc_demo_owner');"
                "insert into project_member(project_id,account_id,granted_by) "
                "values('prj_flow','acc_demo_owner','acc_demo_owner');"
                "update target set project_id='prj_flow',name='AWS',state_identity='flow:state' "
                "where id='tgt_demo_aws';")
            build = {"project_id": "prj_flow", "source": "jenkins:flow-test", "external_build_id": "daisy-ci#1",
                     "commit_sha": commit, "branch": "main", "status": "succeeded", "image_refs": images}
            service_headers = {"X-Daisy-Jenkins-Token": callback_token}
            request("/internal/jenkins/builds", build, expected=401)
            built = request("/internal/jenkins/builds", build, headers=service_headers)
            assert built["changed"] is True
            assert request("/internal/jenkins/builds", build, headers=service_headers)["changed"] is False
            request("/internal/jenkins/builds", {**build, "source": "jenkins:other"}, headers=service_headers, expected=403)
            create = {"source_version_id": built["source_version_id"], "target_ids": ["tgt_demo_aws"]}
            key = {"Idempotency-Key": "flow-create"}
            deployment = request("/projects/prj_flow/deployments", create, token, key, 201)
            assert deployment == request("/projects/prj_flow/deployments", create, token, key, 201)
            dep = deployment["id"]
            request("/projects/prj_flow/deployments", {"sourceVersionId": built["source_version_id"],
                    "targetIds": ["tgt_demo_aws"]}, token, {"Idempotency-Key": "wrong-casing"}, 400)
            request("/projects/prj_flow", bearer=viewer, expected=404)
            sql("insert into project_member(project_id,account_id,granted_by) "
                "values('prj_flow','acc_demo_viewer','acc_demo_owner')")
            request("/projects/prj_flow/deployments", create, viewer, key, 403)
            request("/projects/prj_flow", bearer=token, method="DELETE", expected=409)

            def scope():
                return json.loads(sql("select row_to_json(x) from (select dt.id as target,dt.input_hash,"
                    "j.id,j.request_id,j.job_full_name from deployment_target dt join jenkins_execution j "
                    f"on j.id=dt.current_execution_id where dt.deployment_id='{dep}') x"))

            def envelope(command, kind, payload, event, seq=None):
                return {"execution_id": command["id"], "request_id": command["request_id"],
                        "job_full_name": command["job_full_name"], "build_number": 18,
                        "external_event_id": event, "source_sequence": seq,
                        "occurred_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                        "deployment_target_id": command["target"], "kind": kind, "payload": payload}

            def callback(body, expected=200):
                return request("/internal/jenkins/callbacks", body,
                               headers={"X-Daisy-Jenkins-Token": callback_token}, expected=expected)

            prepare = scope()
            # MOCK: 워커가 Job을 제출한 경계만 대신 기록해요. Jenkins는 호출하지 않아요.
            sql(f"update jenkins_execution set dispatch_status='dispatching' where id='{prepare['id']}'")
            callback(envelope(prepare, "state", {"status": "generating", "attempt": 1}, "generating", 1))
            usage = envelope(prepare, "usage", {"provider": "anthropic", "model": "fixture-model",
                "step": "generate", "attempt": 1, "status": "succeeded", "input_tokens": 10,
                "output_tokens": 20, "cost_usd": 0.001, "cost_basis": "estimated"},
                "daisy-cd-plan#18/aws/ai-1")
            first = callback(usage)
            assert callback(usage) == first
            usage["payload"]["input_tokens"] = 11
            callback(usage, 409)
            assert sql("select count(*) from ai_usage") == "1"
            assert sql("select external_call_id from ai_usage") == "daisy-cd-plan#18/aws/ai-1"
            callback(envelope(prepare, "usage", {"provider": "anthropic", "model": "fixture-model",
                "step": "fix", "attempt": 2, "status": "failed"}, "daisy-cd-plan#18/aws/ai-2"))
            script = callback(envelope(prepare, "script", {"artifact_ref": "artifact:fixture-code",
                "content_digest": digest, "validated_at": dt.datetime.now(dt.timezone.utc).isoformat()}, "script"))
            callback(envelope(prepare, "plan", {"source_plan_id": "plan-fixture",
                "input_hash": prepare["input_hash"], "script_id": script["receipt_id"],
                "reused_script": False, "attempt": 1, "artifact_ref": "artifact:fixture-plan",
                "digest": digest, "summary": {"counts": {"create": 1, "update": 0, "delete": 0},
                "has_delete": False, "risks": []}, "resources": [{"address": "aws_ecs_service.app", "actions": ["create"]}],
                "expires_at": (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1)).isoformat()}, "plan", 2))
            detail = request(f"/deployments/{dep}", bearer=token)
            approval = {"decision": "approve", "items": detail["pending_approvals"]}
            key = {"Idempotency-Key": "flow-approve"}
            request(f"/deployments/{dep}/approvals", approval, viewer, key, 403)
            accepted = request(f"/deployments/{dep}/approvals", approval, token, key, 202)
            assert accepted == request(f"/deployments/{dep}/approvals", approval, token, key, 202)
            assert sql("select count(*) from jenkins_execution where operation='apply'") == "1"
            apply = scope()
            plan = sql(f"select current_plan_id from deployment_target where id='{apply['target']}'")
            sql(f"update jenkins_execution set dispatch_status='dispatching' where id='{apply['id']}'")
            callback(envelope(apply, "stage", {"stage_occurrence_id": "health-old", "step": "health_check",
                "phase": "started", "level": "info"}, "health-old-start", 1))
            callback(envelope(apply, "stage", {"stage_occurrence_id": "health-1", "step": "health_check",
                "phase": "started", "level": "info"}, "health-start", 2))
            callback(envelope(apply, "stage", {"stage_occurrence_id": "health-1", "step": "health_check",
                "phase": "completed", "level": "info", "message": "헬스체크·스모크 테스트 통과"}, "health-end", 3))
            # MOCK: 이전 occurrence의 늦은 실패가 최신 완료 표시를 덮으면 안 돼요.
            callback(envelope(apply, "stage", {"stage_occurrence_id": "health-old", "step": "health_check",
                "phase": "failed", "level": "error"}, "health-old-failed", 4))
            callback(envelope(apply, "log", {"step": "health_check", "level": "info", "message": "MOCK: 검증용 로그"}, "log", 5))
            success = envelope(apply, "state", {"status": "succeeded", "attempt": 1, "result": {
                "plan_id": plan, "plan_digest": digest, "input_hash": apply["input_hash"],
                "image_refs": images, "public_urls": {"app": "https://aws.unibloom.cloud"}}}, "success", 6)
            callback(success)
            checked = sql("select connection_checked_at from target where id='tgt_demo_aws'")
            callback(success)
            assert sql("select connection_checked_at from target where id='tgt_demo_aws'") == checked
            assert sql("select count(*) from target_lock") == "0"
            callback(envelope(apply, "stage", {"stage_occurrence_id": "late-health", "step": "health_check",
                "phase": "started", "level": "info"}, "late-health-start", 7))
            callback(envelope(apply, "stage", {"stage_occurrence_id": "late-health", "step": "health_check",
                "phase": "failed", "level": "error"}, "late-health-failed", 8))
            result = request(f"/deployments/{dep}", bearer=token)
            assert result["state"] == "succeeded"
            assert result["targets"][0]["url"] == "https://aws.unibloom.cloud"
            assert result["targets"][0]["image_digest"] == digest
            assert result["targets"][0]["step_state"] == "done"
            current = request("/projects/prj_flow/targets/status", bearer=token)["items"][0]
            assert current["current_status"] == "confirmed" and current["connection_state"] == "ok"
            assert current["current"]["deployment_id"] == dep and current["current"]["image_digest"] == digest
            assert current["url"] == "https://aws.unibloom.cloud" and current["image_digest"] == digest
            assert sql("select count(*) from deployment_log where step='health_check' "
                       "and event_type='step.completed' and processing_result='applied' "
                       "and payload ? 'duration_ms'") == "1"
            assert result["targets"][0]["health_summary"] == "배포 시점 헬스 검사 통과"
            assert current["health"] == "healthy" and current["health_summary"] == "배포 시점 헬스 검사 통과"
            health_schema = schemas["TargetStatusResponse"]["properties"]["health_summary"]
            assert "null" in health_schema["type"]
            health_step = next(s for s in result["targets"][0]["steps"] if s["name"] == "health_check")
            assert health_step["state"] == "done" and health_step["duration_ms"] >= 0 and health_step["started_at"]
            target = request("/projects/prj_flow/targets", bearer=token)["items"][0]
            assert target["connection"]["state"] == "ok" and target["runtime"] == "ECS Fargate · ALB"
            calls = request(f"/projects/prj_flow/ai-usage?deployment_id={dep}", bearer=token)["items"]
            assert len(calls) == 2
            assert next(call for call in calls if call["status"] == "succeeded")["tokens"] == 30
            assert next(call for call in calls if call["status"] == "failed")["tokens"] is None
            totals = request(f"/deployments/{dep}/plan", bearer=token)["ai_usage"]
            assert totals["calls"] == 2 and totals["unknown_calls"] == 1
            resources = request(f"/deployments/{dep}/plan?detail=resources", bearer=token)
            assert isinstance(resources, list) and len(resources) == 1
            request(f"/deployments/{dep}/plan?detail=invalid", bearer=token, expected=400)
            assert request(f"/deployments/{dep}/logs?target_id=tgt_demo_aws&tail=5", bearer=token)["items"]
            assert request("/projects/prj_flow/builds", bearer=token)["items"]
            assert request("/projects/prj_flow/scripts", bearer=token)["items"]
            assert request("/projects/prj_flow/deployments?state=succeeded&limit=1", bearer=token)["items"]
            for path in (f"/deployments/{dep}/events", "/projects/prj_flow/events"):
                replay = urllib.request.Request(base + path,
                    headers={"Authorization": "Bearer " + token, "Last-Event-ID": "0"})
                with http.open(replay, timeout=5) as stream:
                    assert stream.headers["Content-Type"].startswith("text/event-stream")
                    assert stream.headers["Cache-Control"] == "no-cache"
                    for _ in range(40):
                        line = stream.readline().decode().strip()
                        if line.startswith("id:"):
                            assert int(line.removeprefix("id:")) > 0
                            break
                    else:
                        raise AssertionError("저장된 SSE 이벤트의 재생 ID가 없어요")
                calls_made.add(("get", path))
                request(path, expected=401)
            request(f"/deployments/{dep}", expected=401)
            selection = {"target_ids": ["tgt_demo_aws"]}
            rollback = request(f"/deployments/{dep}/rollback", {**selection, "reason": "검증용 롤백"}, token,
                               {"Idempotency-Key": "flow-rollback"}, 201)
            request(f"/deployments/{rollback['id']}/cancel", selection, token,
                    {"Idempotency-Key": "flow-cancel"}, 202)
            assert request(f"/deployments/{rollback['id']}", bearer=token)["state"] == "cancelled"
            failed = request("/projects/prj_flow/deployments", create, token,
                             {"Idempotency-Key": "flow-failed"}, 201)
            dep = failed["id"]
            failing = scope()
            sql(f"update jenkins_execution set dispatch_status='dispatching' where id='{failing['id']}'")
            callback(envelope(failing, "state", {"status": "failed", "attempt": 1,
                              "error_summary": "MOCK: 검증 실패"}, "failed", 1))
            retried = request(f"/deployments/{dep}/retry", selection, token,
                              {"Idempotency-Key": "flow-retry"}, 201)
            request(f"/deployments/{retried['id']}/cancel", selection, token,
                    {"Idempotency-Key": "flow-cancel-retry"}, 202)
            assert sql("select count(*) from target_lock") == "0"
            # 실제 호출 경로를 OpenAPI 템플릿과 대조해 누락된 엔드포인트가 있으면 실패해요.
            for path, operations in sorted(api["paths"].items()):
                for method, operation in operations.items():
                    if method not in ("get", "post", "put", "patch", "delete"):
                        continue
                    pattern = re.sub(r"\{[^}]+\}", "[^/]+", path)
                    assert any(m == method and re.fullmatch(pattern, p) for m, p in calls_made), f"미검증: {method} {path}"
                    codes = {code for (m, p), code in response_codes.items() if m == method and re.fullmatch(pattern, p)}
                    missing = codes - operation["responses"].keys()
                    assert not missing, f"OpenAPI {method.upper()} {path}: 실제 {missing} 응답 미기재"
                    assert operation.get("summary"), f"설명 누락: {path}"
                    assert "default" in operation["responses"]
                    if path.endswith("/events"):
                        assert operation["responses"]["200"]["content"]["text/event-stream"]["schema"]["type"] == "string"
                    print(f"COVERED {method.upper()} {path}")
            plan_doc = api["paths"]["/deployments/{deploymentId}/plan"]["get"]
            print("PLAN_RESPONSE_SCHEMA:", json.dumps(plan_doc["responses"], ensure_ascii=False))
            callback_doc = api["paths"]["/internal/jenkins/callbacks"]["post"]
            assert callback_doc["requestBody"]["required"] is True
            assert {"jenkinsCallbackToken": []} in callback_doc["security"]
            assert api["components"]["securitySchemes"]["jenkinsCallbackToken"]["name"] == "X-Daisy-Jenkins-Token"
            print("PASS: 공개 22개·내부 2개 API 경로 HTTP 연결·권한·멱등·취소·재시도·롤백·SSE 재생. 인프라는 MOCK이며 실제 연결·미제공 원본 검증은 별도예요.")
            if "--inspect" in sys.argv:
                input("Swagger UI 확인 후 Enter를 누르면 테스트 서버·스키마를 정리해요: ")
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        sql(f'DROP SCHEMA "{schema}" CASCADE')


if __name__ == "__main__":
    main()
