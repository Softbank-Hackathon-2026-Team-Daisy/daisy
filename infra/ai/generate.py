#!/usr/bin/env python3
"""Claude API로 환경별 Terraform 파일(main.tf · variables.tf · outputs.tf)을 만들어요 (infra/SPEC.md §17).

plan_with_ai.py가 시도마다 한 번 불러요. 따로 실행할 수도 있어요:
    generate.py --env aws --vars vars.json --out DIR
    generate.py --env aws --vars vars.json --out DIR --previous DIR --stage plan --error-file err.txt --attempt 2

- 시스템 프롬프트 = 규칙(rules.md) + 기준 모듈. 매번 같아서 프롬프트 캐시로 재사용해요
- 결과는 구조화 출력(JSON 스키마)으로 받아요. Claude Opus 5.5는 도구 호출 강제를 지원하지 않아요
- 안전 분류기가 거절하면 서버가 대체 모델로 다시 돌려요 (fallbacks: "default")
- API 키는 ANTHROPIC_API_KEY 환경변수로만 받아요 (Jenkins Credentials: claude-api-key)
"""
import argparse
import json
import pathlib
import shutil
import sys

import anthropic

MODEL = "claude-opus-5-5"
FILES = ("main.tf", "variables.tf", "outputs.tf")
REPO = pathlib.Path(__file__).resolve().parents[2]
MAX_ERROR_CHARS = 60_000  # 오류 로그가 이보다 길면 앞부분을 줄이고 줄였다고 적어요

SCHEMA = {
    "type": "object",
    "properties": {
        "files": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "enum": list(FILES)},
                    "content": {"type": "string"},
                },
                "required": ["path", "content"],
                "additionalProperties": False,
            },
        },
        "notes": {"type": "string"},
    },
    "required": ["files", "notes"],
    "additionalProperties": False,
}


class GenerationError(Exception):
    """AI가 쓸 수 있는 파일을 돌려주지 않았어요 (거절 · 출력 한도 · 형식 오류)."""

    def __init__(self, message: str, usage: dict | None = None):
        super().__init__(message)
        self.usage = usage  # 호출은 됐으니 사용량은 남겨요 (서버 ai_usage)


def reference_dir(env: str) -> pathlib.Path:
    return REPO / "infra" / "modules" / env


def system_blocks(env: str) -> list:
    rules = (REPO / "infra" / "ai" / "rules.md").read_text(encoding="utf-8")
    ref = reference_dir(env)
    module = "\n\n".join(
        f"### {name}\n```hcl\n{(ref / name).read_text(encoding='utf-8')}\n```" for name in FILES
    )
    text = f"{rules}\n\n# Reference module for `{env}` (infra/modules/{env})\n\n{module}"
    # 고정 내용만 캐시 앞부분에 둬요. 요청마다 달라지는 값은 user 메시지로 보내요
    return [{"type": "text", "text": text, "cache_control": {"type": "ephemeral"}}]


def user_message(env: str, inputs: dict, previous: dict | None, stage: str | None,
                 error: str | None, attempt: int) -> str:
    parts = [
        f"Target environment: `{env}`",
        "Deployment inputs (Terraform variable values; `image_tag` is passed separately at plan time):",
        "```json\n" + json.dumps(inputs, indent=2, sort_keys=True) + "\n```",
    ]
    if previous:
        if error and len(error) > MAX_ERROR_CHARS:
            error = f"[first {len(error) - MAX_ERROR_CHARS} characters omitted]\n" + error[-MAX_ERROR_CHARS:]
        parts += [
            f"This is attempt {attempt} of 3. The files below failed at stage `{stage}`.",
            "Error output:",
            "```\n" + (error or "(no output)") + "\n```",
            "The files that failed:",
        ]
        parts += [f"### {name}\n```hcl\n{previous[name]}\n```" for name in FILES]
        parts.append("Fix only what the error points at and return all three files.")
    else:
        parts.append("Write the three files for this application.")
    return "\n\n".join(parts)


def generate(env: str, inputs: dict, previous: dict | None = None, stage: str | None = None,
             error: str | None = None, attempt: int = 1) -> tuple[dict, str, dict]:
    """파일 3개, AI 메모, 사용량을 돌려줘요. API 오류는 그대로 올려 보내요 (SDK가 429 · 5xx를 재시도해요)."""
    client = anthropic.Anthropic()
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=64000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
        system=system_blocks(env),
        messages=[{"role": "user", "content": user_message(env, inputs, previous, stage, error, attempt)}],
    ) as stream:
        message = stream.get_final_message()
        request_id = stream.request_id  # 스트림 응답은 메시지가 아니라 스트림에 요청 ID가 있어요

    u = message.usage
    usage = {
        "model": message.model,  # 대체 모델이 답했으면 그 모델이에요
        "request_id": request_id,
        "input_tokens": u.input_tokens,
        "output_tokens": u.output_tokens,
        "cache_creation_input_tokens": u.cache_creation_input_tokens or 0,
        "cache_read_input_tokens": u.cache_read_input_tokens or 0,
        "stop_reason": message.stop_reason,
    }
    if message.stop_reason == "refusal":
        category = message.stop_details.category if message.stop_details else None
        raise GenerationError(f"모델이 요청을 거절했어요 (category={category})", usage)
    if message.stop_reason == "max_tokens":
        raise GenerationError("출력 한도(max_tokens)에 걸려 파일이 잘렸어요", usage)

    text = next((b.text for b in message.content if b.type == "text"), None)
    if text is None:
        raise GenerationError("응답에 JSON 본문이 없어요", usage)
    data = json.loads(text)
    files = {f["path"]: f["content"] for f in data["files"]}
    if sorted(files) != sorted(FILES) or len(data["files"]) != len(FILES):
        raise GenerationError(f"파일 3개(main.tf · variables.tf · outputs.tf)가 정확히 필요해요: {[f['path'] for f in data['files']]}", usage)
    if any(not c.strip() for c in files.values()):
        raise GenerationError("빈 파일이 있어요", usage)
    return files, data["notes"], usage


def write_files(files: dict, out: pathlib.Path, env: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (out / name).write_text(content if content.endswith("\n") else content + "\n", encoding="utf-8")
    # provider 버전은 기준 모듈과 같은 lock 파일로 고정해요
    lock = reference_dir(env) / ".terraform.lock.hcl"
    if lock.exists():
        shutil.copy(lock, out / ".terraform.lock.hcl")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--env", required=True)
    p.add_argument("--vars", required=True, type=pathlib.Path)
    p.add_argument("--out", required=True, type=pathlib.Path)
    p.add_argument("--previous", type=pathlib.Path)
    p.add_argument("--stage")
    p.add_argument("--error-file", type=pathlib.Path)
    p.add_argument("--attempt", type=int, default=1)
    a = p.parse_args()

    inputs = json.loads(a.vars.read_text(encoding="utf-8"))
    previous = {n: (a.previous / n).read_text(encoding="utf-8") for n in FILES} if a.previous else None
    error = a.error_file.read_text(encoding="utf-8") if a.error_file else None
    try:
        files, notes, usage = generate(a.env, inputs, previous, a.stage, error, a.attempt)
    except GenerationError as e:
        print(f"generate: {e}", file=sys.stderr)
        return 1
    write_files(files, a.out, a.env)
    print(json.dumps({"notes": notes, "usage": usage}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
