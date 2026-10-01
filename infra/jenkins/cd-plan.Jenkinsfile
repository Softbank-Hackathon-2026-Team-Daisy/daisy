// CD ① 준비: 환경 선택 → 입력 정리 → 환경별 병렬 [재사용 또는 AI 생성 → validate · plan → 위험 검사, 최대 3번] → plan 요약 (승인 대기)
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12-7). 승인되면 daisy-cd-apply가 이 plan을 적용해요.
//   plan ID = daisy-cd-plan-<빌드 번호>. plan마다 작업 폴더가 따로라 승인 대기 중인 plan을 덮어쓰지 않아요
//   승인 정보는 웹·앱 → 서버 승인 API에서 받고, 서버가 daisy-cd-apply를 PLAN_BUILD · APPROVAL_ID로 시작해요 (§16-6)
//   AI 생성 · 수정 루프 · 재사용은 infra/ai/plan_with_ai.py가 해요 (SPEC §17). USE_AI를 끄면 기준 모듈 그대로 (MOCK 대안 경로)
// 온프레미스는 황지환 영역이라 아직 선택지에 없어요.
//
// 필요한 Jenkins Credentials: aws-deployer (Username/Password = 액세스 키 ID/시크릿), gcp-deployer (Secret file = SA JSON),
//   claude-api-key (Secret text = Anthropic API 키, USE_AI일 때)
// 선택 Jenkins 전역 환경변수: TF_STATE_BUCKET, EXPECTED_AWS_ACCOUNT, EXPECTED_GCP_PROJECT
// 러너에 1번 등록: $JENKINS_HOME/daisy-work/targets/<env>.json (예: {"project_id": "...", "region": "asia-northeast3"})
pipeline {
  agent any
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }
  parameters {
    booleanParam(name: 'DEPLOY_AWS', defaultValue: true, description: 'AWS (ECS Fargate · ALB)')
    booleanParam(name: 'DEPLOY_GCP', defaultValue: false, description: 'GCP (Cloud Run)')
    booleanParam(name: 'DESTROY', defaultValue: false, description: '체크하면 삭제 plan을 만들어요 (승인되면 daisy-cd-apply가 지워요)')
    booleanParam(name: 'USE_AI', defaultValue: true, description: 'AI로 Terraform을 생성 · 수정해요. 끄면 기준 모듈을 그대로 써요 (MOCK 대안 경로)')
    string(name: 'IMAGE_TAG', defaultValue: '', description: '커밋 해시 40자')
    string(name: 'IMAGE_REPO', defaultValue: '', description: '태그 없는 이미지 주소. 예: docker.io/<계정>/hellocalc')
    string(name: 'APP', defaultValue: 'hellocalc', description: 'state key · 작업 디렉터리 이름')
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: 'deploy.yaml을 읽을 앱 저장소')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    TF_DESTROY = "${params.DESTROY ? '1' : ''}"   // tf-run.sh plan이 삭제 plan을 만들어요
    PLAN_ID = "${env.JOB_NAME}-${env.BUILD_NUMBER}" // 승인·적용할 때 이 ID로 찾아요
    USE_AI = "${params.USE_AI ? '1' : '0'}"
    AI_PY = '/opt/daisy-ai/venv/bin/python'         // setup-runner.sh가 만든 가상환경 (anthropic SDK)
  }
  stages {
    stage('Prepare') {
      steps {
        script {
          if (!(params.IMAGE_TAG ==~ /[0-9a-f]{40}/)) {
            error("IMAGE_TAG는 커밋 해시 40자여야 해요: '${params.IMAGE_TAG}'")
          }
          if (!params.IMAGE_REPO?.trim()) {
            error('IMAGE_REPO가 비어 있어요')
          }
          if (targets().isEmpty()) {
            error('배포 환경을 하나 이상 선택해 주세요')
          }
          currentBuild.description = "${params.DESTROY ? '삭제 ' : ''}${targets().join(', ')} ← ${params.IMAGE_TAG.take(7)}"
        }
        dir('app') {
          git url: params.APP_REPO, branch: 'main'
          sh 'git checkout --quiet "$IMAGE_TAG"'   // deploy.yaml을 이미지와 같은 커밋 기준으로 읽어요
        }
      }
    }

    stage('Infra code') {
      steps {
        script {
          for (t in targets()) {
            // deploy.yaml + 대상 환경 등록값 → 변수 파일. AI 입력이자 재사용 판단(입력 지문)의 기준이에요
            sh """
              mkdir -p "\$WORK_ROOT/\$APP"
              target_file="\$WORK_ROOT/targets/${t}.json"
              if [ ! -f "\$target_file" ]; then
                [ "${t}" != gcp ] || { echo "GCP 대상 환경 등록이 필요해요: \$target_file"; exit 1; }
                target_file=-
              fi
              python3 infra/jenkins/render-tfvars.py app/deploy.yaml "\$target_file" "\$IMAGE_REPO" \
                > "\$WORK_ROOT/\$APP/${t}.tfvars.json"
              cat "\$WORK_ROOT/\$APP/${t}.tfvars.json"
            """
          }
        }
      }
    }

    stage('Plan') {
      // 환경마다: 재사용(AI 0회) 또는 AI 생성 → validate · plan → 위험 검사, 실패하면 오류 로그로 AI가 고쳐요 (총 3번)
      steps {
        script {
          def failed = []
          forEachTarget('plan') { t ->
            try {
              withCloud(t) { sh "\"\$AI_PY\" infra/ai/plan_with_ai.py ${t}" }
            } catch (err) {
              failed << t
              echo "${t}: 검증을 통과한 plan을 만들지 못했어요. 다른 환경은 계속 진행해요"
            }
          }
          env.FAILED_TARGETS = failed.join(',')
        }
      }
    }

    stage('Summary') {
      steps {
        script {
          // 서버·사람이 승인 화면에 쓸 요약. 비밀값이 없는 메타데이터만 담아요 (plan.json은 넣지 않아요)
          sh """
            for t in ${targets().join(' ')}; do
              m="\$WORK_ROOT/\$APP/\$t/plans/\$PLAN_ID/meta.json"
              a="\$WORK_ROOT/\$APP/\$t/ai/\$PLAN_ID/ai.json"
              ai=\$( [ -f "\$a" ] && jq -c '{mode, ai_calls, message, usage_total}' "\$a" || echo null )
              if [ -f "\$m" ]; then
                jq -c --argjson ai "\$ai" '{env, ok: true, summary, ai: \$ai}' "\$m"
              else
                jq -nc --arg env "\$t" --argjson ai "\$ai" '{env: \$env, ok: false, summary: null, ai: \$ai}'
              fi
            done | jq -s --arg plan_build "\$BUILD_NUMBER" --arg plan_id "\$PLAN_ID" --arg app "\$APP" \
                     --arg image_tag "\$IMAGE_TAG" --argjson destroy ${params.DESTROY} \
                     '{plan_id: \$plan_id, plan_build: (\$plan_build|tonumber), app: \$app, image_tag: \$image_tag,
                       destroy: \$destroy, targets: (map({key: .env, value: (del(.env))}) | from_entries)}' > plan-summary.json
            cat plan-summary.json
          """
          archiveArtifacts artifacts: 'plan-summary.json'
          def changes = sh(script: '''jq -r '.targets | to_entries | map("\\(.key): " + (if .value.ok then .value.summary + " (" + (.value.ai.mode // "-") + ")" else "실패" end)) | join(", ")' plan-summary.json''',
                           returnStdout: true).trim()
          currentBuild.description = "승인 대기 ${params.DESTROY ? '(삭제) ' : ''}${changes}"
          def failed = env.FAILED_TARGETS ? env.FAILED_TARGETS.split(',') as List : []
          if (failed.size() == targets().size()) {
            error("모든 환경이 검증을 통과하지 못했어요: ${failed.join(', ')}")
          }
          if (failed) {
            unstable("검증을 통과하지 못한 환경: ${failed.join(', ')}. 나머지 환경만 승인 · 적용할 수 있어요")
          }
          echo "승인되면 daisy-cd-apply를 PLAN_BUILD=${env.BUILD_NUMBER}, APPROVAL_ID=<승인 ID>로 실행해요"
        }
      }
    }
  }
  post {
    cleanup {   // always는 success보다 먼저 돌아요. 작업 공간 정리는 맨 마지막에
      deleteDir()
    }
  }
}

def targets() {
  def selected = []
  if (params.DEPLOY_AWS) { selected << 'aws' }
  if (params.DEPLOY_GCP) { selected << 'gcp' }
  return selected
}

// 환경별로 병렬 실행해요. 한 환경이 실패해도 나머지는 끝까지 진행해요 (server 결정 기록과 같아요)
def forEachTarget(String label, Closure body) {
  def branches = [:]
  for (t in targets()) {
    def target = t
    branches["${label} ${target}"] = { body(target) }
  }
  parallel branches
}

// 자격증명은 이 블록 안에서만 환경변수로 주입해요.
// state 버킷(S3)을 쓰면 GCP 배포도 AWS 자격증명(버킷 권한)이 필요해요. 환경별 state 저장소(SPEC §7)로 바뀌면 지워요.
// AI를 쓸 때만 Anthropic API 키를 넣어요 (삭제 plan은 AI를 부르지 않아요)
def withCloud(String target, Closure body) {
  def creds = []
  if (target == 'aws' || env.TF_STATE_BUCKET?.trim()) {
    creds << usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
  }
  if (target == 'gcp') {
    creds << file(credentialsId: 'gcp-deployer', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
  }
  if (params.USE_AI && !params.DESTROY) {
    creds << string(credentialsId: 'claude-api-key', variable: 'ANTHROPIC_API_KEY')
  }
  withCredentials(creds) { body() }
}
