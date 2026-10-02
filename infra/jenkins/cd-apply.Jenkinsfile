// CD ② 적용: 승인된 plan → 환경별 병렬 [apply → 헬스체크 · 스모크 테스트]
//
// (가칭) 러너 프로토타입이에요 (infra/SPEC.md §12-7).
//   이 Job을 시작하는 것이 곧 승인이에요. 승인한 plan만 적용해요: plan 폴더를 찾고, plan 파일 해시가 다르거나 이미 적용한 plan이면 거부해요
//   그사이 다른 apply로 state가 바뀌었으면 terraform이 stale plan으로 거부해요 → 다시 plan · 승인
// 두 가지로 시작해요 (SPEC §12-9)
//   서버 요청: 서버가 웹·앱 승인을 받은 뒤 request_id · payload(JSON)로 시작해요. payload.plans의 대상별 승인 plan
//             (artifact_ref · digest · input_hash)만 적용하고, 대상마다 applying → verifying → succeeded/failed를 서버에 알려요.
//             승인 plan이 없어졌거나 낡았으면 적용하지 않고 plan_stale을 알려요 (서버가 다시 plan · 승인을 받아요)
//   사람이 직접: PLAN_BUILD · APPROVAL_ID로 실행해요. APPROVAL_ID는 manual-<이름>. 승인 ID 없이는 실행되지 않아요
//
// 필요한 Jenkins Credentials: aws-deployer, gcp-deployer, daisy-callback-token (daisy-cd-plan과 같아요). 온프레미스는 러너의 고정 경로 SSH 키를 써요
pipeline {
  agent any
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }
  parameters {
    string(name: 'PLAN_BUILD', defaultValue: '', description: '승인한 daisy-cd-plan 빌드 번호 (사람이 직접 실행할 때)')
    string(name: 'APPROVAL_ID', defaultValue: '', description: '사람이 직접 테스트할 때 manual-<이름>')
    string(name: 'APP', defaultValue: 'hellocalc', description: 'plan을 만든 앱 이름')
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: '스모크 테스트 스크립트를 가져올 앱 저장소')
    string(name: 'request_id', defaultValue: '', description: '서버 요청 ID. 서버가 넣어요 (사람이 실행할 때는 비워요)')
    text(name: 'payload', defaultValue: '', description: '서버 요청 본문(JSON). 있으면 위 입력값 대신 승인된 대상별 plan을 적용하고 결과를 서버에 알려요 (SPEC §12-9)')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
  }
  stages {
    stage('Verify') {
      steps {
        script {
          env.DAISY_DIR = "${env.WORKSPACE}/.daisy-server"
          if (params.payload?.trim()) {
            env.D_SERVER = '1'
            if (!env.DAISY_CALLBACK_URL) {
              error('서버 요청인데 Jenkins 전역 환경변수 DAISY_CALLBACK_URL이 없어요 (infra/SPEC.md §12-9)')
            }
            writeFile file: '.daisy-server/payload.json', text: params.payload
            def requested = []
            withServer {
              requested = sh(script: 'REQUEST_ID="$request_id" python3 infra/jenkins/daisy_server.py parse apply "$DAISY_DIR/payload.json"',
                             returnStdout: true).trim().split('\n') as List
            }
            if (env.PLAN_ONLY == '1') {
              failWith('PLAN_ONLY=1이라 적용하지 않았어요 (개인 계정 0원 모드, SPEC §12-5)')
            }
            env.D_APP = jobField('app')
            env.D_APP_REPO = jobField('repository_url')
            env.D_BRANCH = jobField('branch')
            env.D_COMMIT = jobField('commit_sha')
            env.D_DESTROY = ''
            env.D_APPROVAL = "server:${jobField('execution_id')}"
            // 승인한 plan이 이 러너에 그대로 있는 대상만 적용해요
            def ready = []
            withServer {
              for (t in requested) {
                def check = sh(script: "python3 infra/jenkins/daisy_server.py check-plan ${t}", returnStdout: true).trim()
                if (check == 'ok') {
                  ready << t
                } else if (check == 'stale') {
                  echo "${t}: 승인한 plan이 없어졌거나 만료됐어요. 적용하지 않고 서버에 다시 plan을 요청해요"
                  sh "python3 infra/jenkins/daisy_server.py stale ${t}"
                } else {
                  echo "${t}: ${check}"
                  sh "python3 infra/jenkins/daisy_server.py state ${t} failed --error '${check.replace("'", '')}'"
                }
              }
            }
            env.APPLY_TARGETS = ready.join(',')
            if (!ready) {
              error('적용할 수 있는 승인 plan이 없어요 (대상별 결과는 서버에 알렸어요)')
            }
          } else {
            if (env.PLAN_ONLY == '1') {
              error('PLAN_ONLY=1이라 적용하지 않아요 (개인 계정 0원 모드, SPEC §12-5)')
            }
            if (!(params.PLAN_BUILD ==~ /[0-9]+/)) {
              error("PLAN_BUILD는 daisy-cd-plan 빌드 번호여야 해요: '${params.PLAN_BUILD}'")
            }
            if (!params.APPROVAL_ID?.trim()) {
              error('APPROVAL_ID가 필요해요. 승인 없이 적용하지 않아요')
            }
            env.D_APP = params.APP
            env.D_APP_REPO = params.APP_REPO
            env.D_BRANCH = 'main'
            env.D_PLAN_ID = "daisy-cd-plan-${params.PLAN_BUILD}"
            env.D_APPROVAL = params.APPROVAL_ID
            def found = sh(script: '''
              for m in "$WORK_ROOT/$D_APP"/*/plans/"$D_PLAN_ID"/meta.json; do
                [ -f "$m" ] && jq -r .env "$m"
              done
            ''', returnStdout: true).trim()
            if (!found) {
              error("plan을 찾지 못했어요: ${env.D_PLAN_ID} (APP=${params.APP})")
            }
            env.APPLY_TARGETS = found.split('\n').join(',')
            def first = applyTargets()[0]
            env.D_DESTROY = sh(script: "jq -r '.destroy' \"\$WORK_ROOT/\$D_APP/${first}/plans/\$D_PLAN_ID/meta.json\"", returnStdout: true).trim() == 'true' ? '1' : ''
            env.D_COMMIT = sh(script: "jq -r '.image_tag' \"\$WORK_ROOT/\$D_APP/${first}/plans/\$D_PLAN_ID/meta.json\"", returnStdout: true).trim()
          }
          currentBuild.description = "${env.D_APPROVAL} → ${env.D_SERVER == '1' ? 'plan ' + planIds() : env.D_PLAN_ID} " +
            "(${env.D_DESTROY ? '삭제 ' : ''}${env.APPLY_TARGETS})"
          echo "승인 ${env.D_APPROVAL}: ${env.APPLY_TARGETS} 에 적용해요"
        }
      }
    }

    stage('Apply · Health check') {
      // 환경마다 apply가 끝나면 바로 그 환경의 헬스체크로 넘어가요. 한 환경이 실패해도 다른 환경은 끝까지 가요
      steps {
        script {
          env.D_APPLY_STARTED = '1'  // 여기부터 멈추면 적용 여부를 확인해야 해요
          if (!env.D_DESTROY) {
            dir('app') {
              git url: env.D_APP_REPO, branch: env.D_BRANCH
              sh 'git checkout --quiet "$D_COMMIT"'   // 배포한 이미지와 같은 커밋의 스모크 테스트를 써요
            }
          }
          forEachTarget('deploy') { t ->
            withCloud(t) {
              applyTarget(t)
              if (!env.D_DESTROY) {
                checkTarget(t)
              }
            }
          }
        }
      }
    }
  }
  post {
    success {
      script {
        if (env.D_DESTROY) {
          echo "삭제 완료: ${env.APPLY_TARGETS}"
        } else {
          sh 'cat result-*.txt'
        }
      }
    }
    always {
      script {
        if (env.D_SERVER == '1') {
          // 결과를 알리지 못한 대상이 남았으면 실패로 알려요. apply 도중 멈췄다면 적용 여부 확인이 필요해요
          def reason = env.D_APPLY_STARTED == '1' ?
            " --error 'Jenkins 빌드가 적용 중에 멈췄어요. 적용 여부를 확인해야 해요 (Jenkins 콘솔 · 클라우드 콘솔)'" : ''
          withServer { sh(script: "python3 infra/jenkins/daisy_server.py fail-open${reason}", returnStatus: true) }
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

// apply. 서버 요청이면 applying → (적용) → verifying, 낡은 plan이면 plan_stale, 그 밖의 실패는 failed로 알려요
def applyTarget(String t) {
  def server = env.D_SERVER == '1'
  if (server) {
    sh "python3 infra/jenkins/daisy_server.py state ${t} applying"
    sh "python3 infra/jenkins/daisy_server.py stage ${t} apply started"
  }
  // Jenkins sh는 /bin/sh(dash)라 pipefail이 없어요. tee로 로그를 남기면서 tf-run 종료 코드를 받으려고 bash로 돌려요
  def rc = sh(script: "#!/bin/bash\n" + planEnv(t) + "set -o pipefail\nTF_RUN_APPROVED=${t} bash infra/scripts/tf-run.sh ${t} apply 2>&1 | tee apply-${t}.log",
              returnStatus: true)
  if (rc == 0) {
    if (server) {
      // terraform 결과 줄(Apply complete! Resources: …)을 배포 화면 로그로 보내요
      sh(script: "python3 infra/jenkins/daisy_server.py log ${t} info apply \"\$(grep -m1 '^Apply complete!' apply-${t}.log || echo '적용 완료')\"",
         returnStatus: true)
      sh "python3 infra/jenkins/daisy_server.py stage ${t} apply completed"
      sh "python3 infra/jenkins/daisy_server.py state ${t} verifying"
    }
    return
  }
  if (server) {
    sh(script: "python3 infra/jenkins/daisy_server.py stage ${t} apply failed", returnStatus: true)
    if (sh(script: "grep -q 'Saved plan is stale' apply-${t}.log", returnStatus: true) == 0) {
      // terraform이 적용 전에 거부했어요. 서버가 새 plan을 만들고 다시 승인을 받아요
      sh(script: "python3 infra/jenkins/daisy_server.py stale ${t}", returnStatus: true)
    } else {
      sh(script: """python3 infra/jenkins/daisy_server.py state ${t} failed --error "\$(grep -m1 -A4 '^Error:' apply-${t}.log || tail -n 5 apply-${t}.log)" """,
         returnStatus: true)
    }
  }
  error("${t}: apply 실패")
}

// 헬스체크 · 스모크 테스트. 서버 요청이면 성공 결과(승인 plan · 입력 · 이미지 · 주소)를 알려요
// 대상 환경 등록에 public_url이 있으면(온프레미스 pfSense HTTPS 등, 모듈 밖에서 연결) 그 주소도 확인하고 그 주소를 알려요
def checkTarget(String t) {
  def server = env.D_SERVER == '1'
  if (server) {
    sh "python3 infra/jenkins/daisy_server.py stage ${t} health_check started"
  }
  // 헬스체크 · 스모크 테스트의 curl은 공용 DNS(Cloudflare DoH)로 이름을 찾아요. 방금 만든 레코드(aws.unibloom.cloud)를
  // 그 전에 누가 조회했으면 온프레미스 DNS(pfSense)가 "없음"을 최대 15분 캐시해서 헬스체크가 실패해요 (10/2 daisy-cd-apply #5)
  def rc = sh(script: planEnv(t) + """
    export CURL_HOME="\$PWD/.curl-${t}"
    mkdir -p "\$CURL_HOME" && echo 'doh-url = "https://1.1.1.1/dns-query"' > "\$CURL_HOME/.curlrc"
    url=\$(bash infra/scripts/tf-run.sh ${t} output)
    hc=\$(jq -r '.healthcheck' "\$WORK_ROOT/\$APP/${t}/plans/\$PLAN_ID/vars.json")
    echo "\$url" > "url-${t}.txt"
    for i in \$(seq 1 30); do
      if curl -fsS --max-time 5 -o /dev/null -w "${t}: %{http_code} · %{time_total}s\\n" "\$url\$hc"; then break; fi
      [ "\$i" -lt 30 ] || { echo "${t}: 헬스체크 실패 \$url\$hc"; exit 1; }
      sleep 10
    done
    if [ -f app/scripts/smoke-test.sh ]; then
      BASE_URL="\$url" EXPECTED_COMMIT="\$D_COMMIT" sh app/scripts/smoke-test.sh
    fi
    pub=\$(jq -r '.public_url // empty' "\$WORK_ROOT/targets/${t}.json")
    if [ -n "\$pub" ]; then
      echo "\$pub" > "url-${t}.txt"
      for i in \$(seq 1 18); do
        if curl -fsS --max-time 10 -o /dev/null -w "${t} 공개 주소: %{http_code} · %{time_total}s\\n" "\$pub\$hc"; then break; fi
        [ "\$i" -lt 18 ] || { echo "${t}: 앱은 떴지만 공개 주소 확인 실패 \$pub\$hc (targets/${t}.json의 public_url을 지우면 내부 주소로 알려요)"; exit 1; }
        sleep 10
      done
      url="\$pub"
    fi
    echo "${t}: \$url" > "result-${t}.txt"
  """, returnStatus: true)
  def url = fileExists("url-${t}.txt") ? readFile("url-${t}.txt").trim() : ''
  if (rc == 0) {
    if (server) {
      sh(script: "python3 infra/jenkins/daisy_server.py log ${t} info health_check '헬스체크 · 스모크 테스트 통과 → ${url}'", returnStatus: true)
      sh "python3 infra/jenkins/daisy_server.py stage ${t} health_check completed"
      sh "python3 infra/jenkins/daisy_server.py applied ${t} '${url}'"
    }
    return
  }
  if (server) {
    sh(script: "python3 infra/jenkins/daisy_server.py stage ${t} health_check failed", returnStatus: true)
    sh(script: "python3 infra/jenkins/daisy_server.py state ${t} failed --error '적용은 끝났지만 헬스체크 · 스모크 테스트를 통과하지 못했어요: ${url}'",
       returnStatus: true)
  }
  error("${t}: 헬스체크 실패")
}

// 실패 사유를 남기고 멈춰요. post의 fail-open이 이 사유로 서버에 알려요
def failWith(String message) {
  writeFile file: '.daisy-server/error.txt', text: message
  error(message)
}

// tf-run.sh가 읽는 이름으로 넘겨요. 서버 요청은 대상마다 승인한 plan이 다를 수 있어요 (다시 plan한 대상)
def planEnv(String t) {
  def plan = env.D_SERVER == '1' ? "\$(jq -r '.targets.${t}.plan_ref' \"\$DAISY_DIR/job.json\")" : '$D_PLAN_ID'
  return "export APP=\"\$D_APP\" PLAN_ID=\"${plan}\"\n"
}

def planIds() {
  return sh(script: '''jq -r '[.targets[].plan_ref] | unique | join(",")' "$DAISY_DIR/job.json"''', returnStdout: true).trim()
}

def applyTargets() {
  return env.APPLY_TARGETS ? env.APPLY_TARGETS.split(',') as List : []
}

// 서버 요청을 해석한 job.json의 값 (infra/jenkins/daisy_server.py parse)
def jobField(String field) {
  return sh(script: "jq -r '.${field} // empty' \"\$DAISY_DIR/job.json\"", returnStdout: true).trim()
}

// 환경별로 병렬 실행해요. 한 환경이 실패해도 나머지는 끝까지 진행해요 (server 결정 기록과 같아요)
def forEachTarget(String label, Closure body) {
  def branches = [:]
  for (t in applyTargets()) {
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

// 자격증명은 이 블록 안에서만 환경변수로 주입해요 (daisy-cd-plan과 같아요)
def withCloud(String target, Closure body) {
  def creds = []
  if (target == 'aws') {
    creds << usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
  }
  if (target == 'gcp') {
    creds << file(credentialsId: 'gcp-deployer', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
  }
  withCredentials(creds) { withServer { body() } }
}
