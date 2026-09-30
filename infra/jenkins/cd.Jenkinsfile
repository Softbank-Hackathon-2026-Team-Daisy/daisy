// CD: 환경 선택 → 인프라 코드 확인 → 병렬 plan → 위험 검사 → 승인 → 병렬 apply → 헬스체크
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12). terraform 실행은 infra/scripts/tf-run.sh가 해요.
// MOCK: AI 생성(N-02)·위험 검사와 AI 재시도(N-05)는 server AI(김승환) 영역이라 표시만 해요.
// 온프레미스는 황지환 영역이라 아직 선택지에 없어요.
//
// 필요한 Jenkins Credentials: aws-deployer (Username/Password = 액세스 키 ID/시크릿), gcp-deployer (Secret file = SA JSON)
// 선택 Jenkins 전역 환경변수: TF_STATE_BUCKET, EXPECTED_AWS_ACCOUNT, EXPECTED_GCP_PROJECT
// 러너에 1번 등록: $JENKINS_HOME/daisy-work/targets/<env>.json (예: {"project_id": "...", "region": "asia-northeast3"})
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()   // 같은 작업 디렉터리의 plan을 다른 빌드가 덮어쓰지 않게
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  parameters {
    booleanParam(name: 'DEPLOY_AWS', defaultValue: true, description: 'AWS (ECS Fargate · ALB)')
    booleanParam(name: 'DEPLOY_GCP', defaultValue: false, description: 'GCP (Cloud Run)')
    booleanParam(name: 'DESTROY', defaultValue: false, description: '체크하면 선택한 환경의 리소스를 지워요 (삭제 plan → 승인 → 삭제)')
    string(name: 'IMAGE_TAG', defaultValue: '', description: '커밋 해시 40자')
    string(name: 'IMAGE_REPO', defaultValue: '', description: '태그 없는 이미지 주소. 예: docker.io/<계정>/hellocalc')
    string(name: 'APP', defaultValue: 'hellocalc', description: 'state key · 작업 디렉터리 이름')
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: 'deploy.yaml을 읽을 앱 저장소')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    TF_DESTROY = "${params.DESTROY ? '1' : ''}"   // tf-run.sh plan이 삭제 plan을 만들어요
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
            // 검증된 스크립트 저장소(SPEC D-8)가 정해지면: 있으면 재사용(이미지 태그만 교체), 없으면 AI 생성
            echo "MOCK: ${t} — AI 생성 대신 기준 모듈 infra/modules/${t}를 그대로 써요 (재사용 경로와 같아요)"
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
      steps {
        script {
          forEachTarget('plan') { t ->
            withCloud(t) { sh "bash infra/scripts/tf-run.sh ${t} plan" }
          }
        }
      }
    }

    stage('Risk check') {
      steps {
        echo 'MOCK: 위험 검사(SPEC §4-3 R-1~R-6)와 실패 시 AI 수정·재시도(최대 3회)는 server AI(김승환) 영역이에요. 지금은 통과로 처리해요'
      }
    }

    stage('Approve') {
      steps {
        script {
          def summary = ''
          for (t in targets()) {
            summary += "${t}: " + sh(script: "cat \"\$WORK_ROOT/\$APP/${t}/src/summary.txt\"", returnStdout: true).trim() + '\n'
          }
          timeout(time: 30, unit: 'MINUTES') {
            if (params.DESTROY) {
              input message: "삭제 plan이에요. 지워질 리소스를 확인하고 승인해 주세요 (전체 plan은 Plan 단계 로그)\n${summary}", ok: '승인 · 삭제'
            } else {
              input message: "plan 결과를 확인하고 승인해 주세요 (전체 plan은 Plan 단계 로그)\n${summary}", ok: '승인 · apply'
            }
          }
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
      when { expression { !params.DESTROY } }
      steps {
        script {
          forEachTarget('check') { t ->
            withCloud(t) {
              sh """
                url=\$(bash infra/scripts/tf-run.sh ${t} output)
                hc=\$(jq -r '.healthcheck' "\$WORK_ROOT/\$APP/${t}.tfvars.json")
                for i in \$(seq 1 30); do
                  if curl -fsS --max-time 5 "\$url\$hc"; then echo; break; fi
                  [ "\$i" -lt 30 ] || { echo "${t}: 헬스체크 실패 \$url\$hc"; exit 1; }
                  sleep 10
                done
                if [ -f app/scripts/smoke-test.sh ]; then
                  BASE_URL="\$url" EXPECTED_COMMIT="\$IMAGE_TAG" sh app/scripts/smoke-test.sh
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
        if (params.DESTROY) {
          echo "삭제 완료: ${targets().join(', ')}"
        } else {
          sh 'cat result-*.txt'
        }
      }
    }
    always {
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
// state 버킷(S3)을 쓰면 GCP 배포도 AWS 자격증명(버킷 권한)이 필요해요.
def withCloud(String target, Closure body) {
  def creds = []
  if (target == 'aws' || env.TF_STATE_BUCKET?.trim()) {
    creds << usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
  }
  if (target == 'gcp') {
    creds << file(credentialsId: 'gcp-deployer', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
  }
  withCredentials(creds) { body() }
}
