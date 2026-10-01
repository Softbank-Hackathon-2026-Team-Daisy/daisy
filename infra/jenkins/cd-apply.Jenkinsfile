// CD ② 적용: 승인된 plan(PLAN_BUILD) → 병렬 apply → 헬스체크 · 스모크 테스트
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12-7).
//   이 Job을 시작하는 것이 곧 승인이에요. 서버가 웹·앱 승인 API를 받은 뒤 PLAN_BUILD · APPROVAL_ID로 시작해요 (§16-6)
//   사람이 직접 테스트할 때는 APPROVAL_ID에 manual-<이름>을 적어요. 승인 ID 없이는 실행되지 않아요
//   승인한 plan만 적용해요: plan ID로 폴더를 찾고, plan 파일 해시가 다르거나 이미 적용한 plan이면 거부해요
//   그사이 다른 apply로 state가 바뀌었으면 terraform이 stale plan으로 거부해요 → 다시 plan · 승인
//
// 필요한 Jenkins Credentials: aws-deployer, gcp-deployer (daisy-cd-plan과 같아요). 온프레미스는 러너의 고정 경로 SSH 키를 써요
pipeline {
  agent any
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }
  parameters {
    string(name: 'PLAN_BUILD', defaultValue: '', description: '승인한 daisy-cd-plan 빌드 번호')
    string(name: 'APPROVAL_ID', defaultValue: '', description: '서버 승인 ID (apv_…). 사람이 직접 테스트할 때는 manual-<이름>')
    string(name: 'APP', defaultValue: 'hellocalc', description: 'plan을 만든 앱 이름')
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: '스모크 테스트 스크립트를 가져올 앱 저장소')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    PLAN_ID = "daisy-cd-plan-${params.PLAN_BUILD}"
  }
  stages {
    stage('Verify') {
      steps {
        script {
          if (!(params.PLAN_BUILD ==~ /[0-9]+/)) {
            error("PLAN_BUILD는 daisy-cd-plan 빌드 번호여야 해요: '${params.PLAN_BUILD}'")
          }
          if (!params.APPROVAL_ID?.trim()) {
            error('APPROVAL_ID가 필요해요. 승인 없이 적용하지 않아요')
          }
          if (env.PLAN_ONLY == '1') {
            error('PLAN_ONLY=1이라 적용하지 않아요 (개인 계정 0원 모드, SPEC §12-5)')
          }
          def found = sh(script: '''
            for m in "$WORK_ROOT/$APP"/*/plans/"$PLAN_ID"/meta.json; do
              [ -f "$m" ] && jq -r .env "$m"
            done
          ''', returnStdout: true).trim()
          if (!found) {
            error("plan을 찾지 못했어요: ${env.PLAN_ID} (APP=${params.APP})")
          }
          env.APPLY_TARGETS = found.split('\n').join(',')
          def first = applyTargets()[0]
          env.PLAN_DESTROY = sh(script: "jq -r .destroy \"\$WORK_ROOT/\$APP/${first}/plans/\$PLAN_ID/meta.json\"", returnStdout: true).trim()
          env.PLAN_IMAGE_TAG = sh(script: "jq -r .image_tag \"\$WORK_ROOT/\$APP/${first}/plans/\$PLAN_ID/meta.json\"", returnStdout: true).trim()
          currentBuild.description = "${params.APPROVAL_ID} → ${env.PLAN_ID} (${env.PLAN_DESTROY == 'true' ? '삭제 ' : ''}${env.APPLY_TARGETS})"
          echo "승인 ${params.APPROVAL_ID}: ${env.PLAN_ID} 를 ${env.APPLY_TARGETS} 에 적용해요"
        }
      }
    }

    stage('Apply') {
      steps {
        script {
          forEachTarget('apply') { t ->
            withCloud(t) {
              withEnv(["TF_RUN_APPROVED=${t}"]) { sh "bash infra/scripts/tf-run.sh ${t} apply" }
            }
          }
        }
      }
    }

    stage('Health check') {
      when { expression { env.PLAN_DESTROY != 'true' } }
      steps {
        dir('app') {
          git url: params.APP_REPO, branch: 'main'
          sh 'git checkout --quiet "$PLAN_IMAGE_TAG"'   // 배포한 이미지와 같은 커밋의 스모크 테스트를 써요
        }
        script {
          forEachTarget('check') { t ->
            withCloud(t) {
              sh """
                url=\$(bash infra/scripts/tf-run.sh ${t} output)
                hc=\$(jq -r '.healthcheck' "\$WORK_ROOT/\$APP/${t}/plans/\$PLAN_ID/vars.json")
                for i in \$(seq 1 30); do
                  if curl -fsS --max-time 5 -o /dev/null -w "${t}: %{http_code} · %{time_total}s\\n" "\$url\$hc"; then break; fi
                  [ "\$i" -lt 30 ] || { echo "${t}: 헬스체크 실패 \$url\$hc"; exit 1; }
                  sleep 10
                done
                if [ -f app/scripts/smoke-test.sh ]; then
                  BASE_URL="\$url" EXPECTED_COMMIT="\$PLAN_IMAGE_TAG" sh app/scripts/smoke-test.sh
                fi
                echo "${t}: \$url" > "result-${t}.txt"
              """
            }
          }
        }
      }
    }
  }
  post {
    success {
      script {
        if (env.PLAN_DESTROY == 'true') {
          echo "삭제 완료: ${env.APPLY_TARGETS}"
        } else {
          sh 'cat result-*.txt'
        }
      }
    }
    cleanup {   // always는 success보다 먼저 돌아요. 작업 공간 정리는 맨 마지막에
      deleteDir()
    }
  }
}

def applyTargets() {
  return env.APPLY_TARGETS ? env.APPLY_TARGETS.split(',') as List : []
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

// 자격증명은 이 블록 안에서만 환경변수로 주입해요 (daisy-cd-plan과 같아요)
def withCloud(String target, Closure body) {
  def creds = []
  if (target == 'aws') {
    creds << usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
  }
  if (target == 'gcp') {
    creds << file(credentialsId: 'gcp-deployer', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
  }
  withCredentials(creds) { body() }
}
