// CD ① 준비: 환경 선택 → 입력 정리 → 환경별 병렬 [재사용 또는 AI 생성 → validate · plan → 위험 검사, 최대 3번] → plan 요약 (승인 대기)
//
// (가칭) 러너 프로토타입이에요 (infra/SPEC.md §12-7). 승인되면 daisy-cd-apply가 이 plan을 적용해요.
//   plan ID = daisy-cd-plan-<빌드 번호>. plan마다 작업 폴더가 따로라 승인 대기 중인 plan을 덮어쓰지 않아요
//   승인 정보는 웹·앱 → 서버 승인 API에서 받고, 서버가 daisy-cd-apply를 시작해요 (§16-6)
//   AI 생성 · 수정 루프 · 재사용은 infra/ai/plan_with_ai.py가 해요 (SPEC §17). USE_AI를 끄면 기준 모듈 그대로 (MOCK 대안 경로)
// 두 가지로 시작해요 (SPEC §12-9)
//   서버 요청: 서버가 request_id · payload(JSON)만 보내요. 대상 · 이미지 · 저장소는 payload에서 읽고,
//             환경마다 상태 · 단계 · AI 사용량 · 스크립트 · plan을 서버 콜백으로 알려요 (infra/jenkins/daisy_server.py)
//   사람이 직접: payload를 비우고 아래 선택 · 입력값으로 실행해요 (콜백 없음)
// 온프레미스: 황지환의 기준 모듈(infra/modules/onprem)을 같은 흐름으로 돌려요. Service VM의 Docker에 SSH로 붙어요.
//   SSH 키 · known_hosts는 러너의 고정 경로에 있고(targets/onprem.json에 경로만), Jenkins Credentials는 쓰지 않아요.
//   plan과 apply가 다른 빌드라, 빌드마다 바뀌는 임시 경로를 쓰면 apply 때 키를 못 찾아요.
//
// 필요한 Jenkins Credentials: aws-deployer (Username/Password = 액세스 키 ID/시크릿), gcp-deployer (Secret file = SA JSON),
//   azure-deployer (Username/Password = 배포 주체 클라이언트 ID/시크릿),
//   claude-api-key (Secret text = Anthropic API 키, USE_AI일 때), daisy-callback-token (Secret text, 서버 요청일 때)
// Jenkins 전역 환경변수: TF_STATE_BUCKET_AWS (AWS state S3 버킷, 없으면 러너 로컬), 선택 EXPECTED_AWS_ACCOUNT, EXPECTED_GCP_PROJECT
//   Azure: ARM_TENANT_ID · ARM_SUBSCRIPTION_ID, TF_STATE_BUCKET_AZURE (state 저장소 계정 이름, 컨테이너 tfstate)
//   서버 요청: DAISY_CALLBACK_URL (…/internal/jenkins/callbacks), DAISY_RUNNER_ID (러너 로컬 state 구분, 예: daisy-cicd),
//   선택 SERVER_USE_AI=0 (리허설 때 AI 비용 없이 기준 모듈로)
// 러너에 1번 등록: $JENKINS_HOME/daisy-work/targets/<env>.json (레포 밖, 계정 · 주소 값)
//   aws.json: daisy-bootstrap이 만들어요 (region · vpc_id · 서브넷 ID)
//   onprem.json: {"docker_host": "ssh://<user>@<Service VM>:22", "ssh_key_path": "...", "known_hosts_path": "...", "host_ip": "<Service VM>", "host_port": 8080}
//   gcp.json: {"project_id": "...", "region": "asia-northeast1", "domain": "...", "subdomain": "gcp"}
//   azure.json: {"resource_group": "daisy-apps", "environment_name": "daisy-env", "domain": "...", "subdomain": "azure"}
pipeline {
  agent any
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }
  parameters {
    booleanParam(name: 'DEPLOY_ONPREM', defaultValue: false, description: '온프레미스 (Service VM의 Docker 컨테이너)')
    booleanParam(name: 'DEPLOY_AWS', defaultValue: true, description: 'AWS (ECS Fargate · ALB)')
    booleanParam(name: 'DEPLOY_GCP', defaultValue: false, description: 'GCP (Cloud Run)')
    booleanParam(name: 'DEPLOY_AZURE', defaultValue: false, description: 'Azure (Container Apps)')
    booleanParam(name: 'DESTROY', defaultValue: false, description: '체크하면 삭제 plan을 만들어요 (승인되면 daisy-cd-apply가 지워요)')
    booleanParam(name: 'USE_AI', defaultValue: true, description: 'AI로 Terraform을 생성 · 수정해요. 끄면 기준 모듈을 그대로 써요 (MOCK 대안 경로)')
    string(name: 'IMAGE_TAG', defaultValue: '', description: '커밋 해시 40자')
    string(name: 'IMAGE_REPO', defaultValue: '', description: '태그 없는 이미지 주소. 예: docker.io/<계정>/hellocalc')
    string(name: 'APP', defaultValue: 'hellocalc', description: 'state key · 작업 디렉터리 이름')
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: 'deploy.yaml을 읽을 앱 저장소')
    string(name: 'request_id', defaultValue: '', description: '서버 요청 ID. 서버가 넣어요 (사람이 실행할 때는 비워요)')
    text(name: 'payload', defaultValue: '', description: '서버 요청 본문(JSON). 있으면 위 선택 · 입력값 대신 이 요청대로 plan하고 결과를 서버에 알려요 (SPEC §12-9)')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    PLAN_ID = "${env.JOB_NAME}-${env.BUILD_NUMBER}" // 승인·적용할 때 이 ID로 찾아요
    AI_PY = '/opt/daisy-ai/venv/bin/python'         // setup-runner.sh가 만든 가상환경 (anthropic SDK)
  }
  stages {
    stage('Prepare') {
      steps {
        script {
          // 이 빌드의 입력은 D_* 환경변수로 모아요 (파라미터 이름의 환경변수는 덮어쓸 수 없어서 이름을 따로 둬요)
          env.DAISY_DIR = "${env.WORKSPACE}/.daisy-server"
          if (params.payload?.trim()) {
            env.D_SERVER = '1'
            if (!env.DAISY_CALLBACK_URL) {
              error('서버 요청인데 Jenkins 전역 환경변수 DAISY_CALLBACK_URL이 없어요 (infra/SPEC.md §12-9)')
            }
            writeFile file: '.daisy-server/payload.json', text: params.payload
            withServer {
              env.D_TARGETS = sh(script: 'REQUEST_ID="$request_id" python3 infra/jenkins/daisy_server.py parse plan "$DAISY_DIR/payload.json"',
                                 returnStdout: true).trim().split('\n').join(',')
            }
            env.D_APP_REPO = jobField('repository_url')
            env.D_BRANCH = jobField('branch')
            env.D_COMMIT = jobField('commit_sha')
            env.D_IMAGE_REPO = jobField('image_repo')
            env.D_MANIFEST = jobField('manifest_path')
            env.D_DESTROY = ''
            // 롤백(allow_ai_autofix=false)이나 리허설(SERVER_USE_AI=0)은 AI 없이 기준 모듈로 plan해요
            env.D_USE_AI = (jobField('allow_ai') == 'true' && env.SERVER_USE_AI != '0') ? '1' : '0'
          } else {
            if (!(params.IMAGE_TAG ==~ /[0-9a-f]{40}/)) {
              error("IMAGE_TAG는 커밋 해시 40자여야 해요: '${params.IMAGE_TAG}'")
            }
            if (!params.IMAGE_REPO?.trim()) {
              error('IMAGE_REPO가 비어 있어요')
            }
            env.D_TARGETS = manualTargets().join(',')
            if (!env.D_TARGETS) {
              error('배포 환경을 하나 이상 선택해 주세요')
            }
            env.D_APP = params.APP
            env.D_APP_REPO = params.APP_REPO
            env.D_BRANCH = 'main'
            env.D_COMMIT = params.IMAGE_TAG
            env.D_IMAGE_REPO = params.IMAGE_REPO
            env.D_MANIFEST = 'deploy.yaml'
            env.D_DESTROY = params.DESTROY ? '1' : ''  // tf-run.sh plan이 삭제 plan을 만들어요
            env.D_USE_AI = params.USE_AI ? '1' : '0'
          }
        }
        dir('app') {
          git url: env.D_APP_REPO, branch: env.D_BRANCH
          sh 'git checkout --quiet "$D_COMMIT"'   // deploy.yaml을 이미지와 같은 커밋 기준으로 읽어요
        }
        script {
          if (env.D_SERVER == '1') {
            // 앱 이름 = deploy.yaml name. state 위치가 서버 대상 등록(state_identity)과 다른 대상은 여기서 실패로 알려요
            withServer {
              env.D_TARGETS = sh(script: 'python3 infra/jenkins/daisy_server.py bind-app "app/$D_MANIFEST"', returnStdout: true)
                                .trim().split('\n').findAll { it }.join(',')
            }
            env.D_APP = jobField('app')
            if (!env.D_TARGETS) {
              error('plan할 대상이 남지 않았어요 (모두 실패로 알렸어요)')
            }
          }
          currentBuild.description = "${env.D_SERVER == '1' ? "서버 ${params.request_id.take(8)} " : ''}" +
            "${env.D_DESTROY ? '삭제 ' : ''}${targets().join(', ')} ← ${env.D_COMMIT.take(7)}"
        }
      }
    }

    stage('Infra code') {
      steps {
        script {
          for (t in targets()) {
            // deploy.yaml + 대상 환경 등록값 → 변수 파일. AI 입력이자 재사용 판단(입력 지문)의 기준이에요
            sh """
              mkdir -p "\$WORK_ROOT/\$D_APP"
              target_file="\$WORK_ROOT/targets/${t}.json"
              [ -f "\$target_file" ] || { echo "${t} 대상 환경 등록이 필요해요: \$target_file (infra/SPEC.md §12-3)"; exit 1; }
              python3 infra/jenkins/render-tfvars.py "app/\$D_MANIFEST" "\$target_file" "\$D_IMAGE_REPO" \
                > "\$WORK_ROOT/\$D_APP/${t}.tfvars.json"
              cat "\$WORK_ROOT/\$D_APP/${t}.tfvars.json"
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
            withCloud(t) {
              try {
                // 서버 요청이면 이 환경이 앞서 쓴 생성 시도 수(#70)에 이어서 세요
                def base = env.D_SERVER == '1' ? "AI_ATTEMPT_BASE=\$(jq -r '.targets.${t}.attempt // 0' \"\$DAISY_DIR/job.json\") " : ''
                tf "${base}\"\$AI_PY\" infra/ai/plan_with_ai.py ${t}"
              } catch (err) {
                failed << t
                echo "${t}: 검증을 통과한 plan을 만들지 못했어요 (${err.getMessage()}). 다른 환경은 계속 진행해요"
                if (env.D_SERVER == '1') {
                  sh(script: "python3 infra/jenkins/daisy_server.py plan-failed ${t}", returnStatus: true)
                }
                return
              }
              if (env.D_SERVER == '1') {
                // 스크립트 → plan 순서로 알려요. 서버가 받으면 승인 대기로 바꿔요
                if (sh(script: "python3 infra/jenkins/daisy_server.py plan-ready ${t}", returnStatus: true) != 0) {
                  failed << t
                  sh(script: "python3 infra/jenkins/daisy_server.py state ${t} failed --error 'plan 결과를 서버에 알리지 못했어요. Jenkins 콘솔을 확인해 주세요'",
                     returnStatus: true)
                }
              }
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
              m="\$WORK_ROOT/\$D_APP/\$t/plans/\$PLAN_ID/meta.json"
              a="\$WORK_ROOT/\$D_APP/\$t/ai/\$PLAN_ID/ai.json"
              ai=\$( [ -f "\$a" ] && jq -c '{mode, ai_calls, message, usage_total}' "\$a" || echo null )
              if [ -f "\$m" ]; then
                jq -c --argjson ai "\$ai" '{env, ok: true, summary, ai: \$ai}' "\$m"
              else
                jq -nc --arg env "\$t" --argjson ai "\$ai" '{env: \$env, ok: false, summary: null, ai: \$ai}'
              fi
            done | jq -s --arg plan_build "\$BUILD_NUMBER" --arg plan_id "\$PLAN_ID" --arg app "\$D_APP" \
                     --arg image_tag "\$D_COMMIT" --argjson destroy ${env.D_DESTROY ? 'true' : 'false'} --arg request_id "\$request_id" \
                     '{plan_id: \$plan_id, plan_build: (\$plan_build|tonumber), app: \$app, image_tag: \$image_tag,
                       destroy: \$destroy, request_id: (\$request_id | if . == "" then null else . end),
                       targets: (map({key: .env, value: (del(.env))}) | from_entries)}' > plan-summary.json
            cat plan-summary.json
          """
          archiveArtifacts artifacts: 'plan-summary.json'
          def changes = sh(script: '''jq -r '.targets | to_entries | map("\\(.key): " + (if .value.ok then .value.summary + " (" + (.value.ai.mode // "-") + ")" else "실패" end)) | join(", ")' plan-summary.json''',
                           returnStdout: true).trim()
          currentBuild.description = "${env.D_SERVER == '1' ? "서버 ${params.request_id.take(8)} · " : ''}승인 대기 ${env.D_DESTROY ? '(삭제) ' : ''}${changes}"
          def failed = env.FAILED_TARGETS ? env.FAILED_TARGETS.split(',') as List : []
          if (failed.size() == targets().size()) {
            error("모든 환경이 검증을 통과하지 못했어요: ${failed.join(', ')}")
          }
          if (failed) {
            unstable("검증을 통과하지 못한 환경: ${failed.join(', ')}. 나머지 환경만 승인 · 적용할 수 있어요")
          }
          if (env.D_SERVER == '1') {
            echo '서버에 plan을 알렸어요. 웹·앱에서 승인하면 서버가 daisy-cd-apply를 시작해요'
          } else {
            echo "승인되면 daisy-cd-apply를 PLAN_BUILD=${env.BUILD_NUMBER}, APPROVAL_ID=<승인 ID>로 실행해요"
          }
        }
      }
    }
  }
  post {
    always {
      script {
        if (env.D_SERVER == '1') {
          // 결과를 알리지 못한 대상이 남았으면(중간에 멈춤 · 중단) 서버가 기다리지 않게 끝 상태를 보내요
          def status = currentBuild.currentResult == 'ABORTED' ? 'cancelled' : 'failed'
          withServer { sh(script: "python3 infra/jenkins/daisy_server.py fail-open --status ${status}", returnStatus: true) }
          sh 'cp "$DAISY_DIR/events.jsonl" server-events.jsonl 2>/dev/null || true'
          archiveArtifacts artifacts: 'server-events.jsonl', allowEmptyArchive: true
        }
      }
    }
    cleanup {   // always는 success보다 먼저 돌아요. 작업 공간 정리는 맨 마지막에
      deleteDir()
    }
  }
}

def manualTargets() {
  def selected = []
  if (params.DEPLOY_ONPREM) { selected << 'onprem' }
  if (params.DEPLOY_AWS) { selected << 'aws' }
  if (params.DEPLOY_GCP) { selected << 'gcp' }
  if (params.DEPLOY_AZURE) { selected << 'azure' }
  return selected
}

def targets() {
  return env.D_TARGETS ? env.D_TARGETS.split(',') as List : []
}

// 서버 요청을 해석한 job.json의 값 (infra/jenkins/daisy_server.py parse)
def jobField(String field) {
  return sh(script: "jq -r '.${field} // empty' \"\$DAISY_DIR/job.json\"", returnStdout: true).trim()
}

// tf-run.sh · plan_with_ai.py가 읽는 이름으로 이 빌드의 입력을 넘겨요
def tf(String script) {
  sh 'export APP="$D_APP" IMAGE_TAG="$D_COMMIT" USE_AI="$D_USE_AI" TF_DESTROY="$D_DESTROY"\n' + script
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

// 서버 요청일 때만 콜백 토큰을 넣어요
def withServer(Closure body) {
  if (env.D_SERVER == '1') {
    withCredentials([string(credentialsId: 'daisy-callback-token', variable: 'DAISY_CALLBACK_TOKEN')]) { body() }
  } else {
    body()
  }
}

// 자격증명은 이 블록 안에서만 환경변수로 주입해요.
// state는 환경마다 그 환경의 저장소라(SPEC §7-1) 각 배포는 자기 환경 키만 받아요.
// 온프레미스는 넣을 자격증명이 없어요 (SSH 키는 러너의 고정 경로).
// AI를 쓸 때만 Anthropic API 키를 넣어요 (삭제 plan은 AI를 부르지 않아요)
def withCloud(String target, Closure body) {
  def creds = []
  if (target == 'aws') {
    creds << usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
  }
  if (target == 'gcp') {
    creds << file(credentialsId: 'gcp-deployer', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
  }
  if (target == 'azure') {
    // 배포 주체: Username = 클라이언트 ID, Password = 클라이언트 시크릿. 테넌트 · 구독은 Jenkins 전역 ARM_TENANT_ID · ARM_SUBSCRIPTION_ID
    creds << usernamePassword(credentialsId: 'azure-deployer', usernameVariable: 'ARM_CLIENT_ID', passwordVariable: 'ARM_CLIENT_SECRET')
  }
  if (env.D_USE_AI == '1' && !env.D_DESTROY) {
    creds << string(credentialsId: 'claude-api-key', variable: 'ANTHROPIC_API_KEY')
  }
  withCredentials(creds) { withServer { body() } }
}
