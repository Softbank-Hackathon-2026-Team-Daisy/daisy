// 고정 리소스 bootstrap: plan → Jenkins 승인 → apply → 대상 환경 등록값 갱신
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12-8). 처음 1번(또는 고정 리소스를 바꿀 때)만 돌려요.
//   앱 배포(daisy-cd-plan → daisy-cd-apply)와 달리 서버를 거치지 않는 인프라 관리 작업이라, 관리자가 Jenkins에서 승인해요
//   aws-network를 적용하면 VPC · 서브넷 ID를 $JENKINS_HOME/daisy-work/targets/aws.json에 넣어서 앱 배포가 바로 써요
//   aws-state를 처음 적용하면 state 버킷을 만들고, 이 러너의 로컬 state(aws-state · aws-network · 앱)를 그 버킷으로 옮겨요.
//     그다음 Jenkins 전역 환경변수 TF_STATE_BUCKET_AWS에 버킷 이름을 넣어요 (넣기 전에는 AWS 작업이 멈춰요)
//
// 필요한 Jenkins Credentials: aws-deployer (생성 권한이 있어야 apply돼요)
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  parameters {
    choice(name: 'STACK', choices: ['aws-network', 'aws-state'], description: 'aws-network: 고정 VPC · 서브넷 (무료) / aws-state: state S3 버킷 + 로컬 state 이전 (월 $0.01 미만)')
    booleanParam(name: 'DESTROY', defaultValue: false, description: '체크하면 이 고정 리소스를 지워요. 앱이 남아 있으면 먼저 앱을 지워야 해요')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    TF_DESTROY = "${params.DESTROY ? '1' : ''}"
    PLAN_ID = "${env.JOB_NAME}-${env.BUILD_NUMBER}"
    STACK = "${params.STACK}"   // 파라미터 없이 처음 실행할 때도 셸에 기본값이 보이게 해요
  }
  stages {
    stage('Plan') {
      steps {
        script {
          currentBuild.description = "${params.DESTROY ? '삭제 ' : ''}${params.STACK}"
          withAws { sh 'bash infra/scripts/tf-run.sh "$STACK" plan' }
        }
      }
    }

    stage('Approve') {
      when { expression { env.PLAN_ONLY != '1' } }
      steps {
        script {
          def summary = sh(script: 'cat "$WORK_ROOT/_bootstrap/$STACK/plans/$PLAN_ID/summary.txt"', returnStdout: true).trim()
          def migrate = moveState() ? '\n승인하면 버킷을 만든 뒤 이 러너의 로컬 state(aws-state · aws-network · 앱)를 그 버킷으로 옮겨요' : ''
          timeout(time: 30, unit: 'MINUTES') {
            input message: "${params.DESTROY ? '삭제 plan이에요. ' : ''}${params.STACK} plan을 확인하고 승인해 주세요 (전체 plan은 Plan 단계 로그)\n${summary}${migrate}",
                  ok: params.DESTROY ? '승인 · 삭제' : '승인 · apply'
          }
        }
      }
    }

    stage('Apply') {
      when { expression { env.PLAN_ONLY != '1' } }
      steps {
        script {
          withAws {
            withEnv(["TF_RUN_APPROVED=${params.STACK}"]) { sh 'bash infra/scripts/tf-run.sh "$STACK" apply' }
          }
        }
      }
    }

    // 위 Approve에서 승인한 범위예요. 방금 만든 버킷으로 로컬 state를 옮겨요 (S3에 리소스가 있으면 덮어쓰지 않아요)
    stage('Move state to S3') {
      when { expression { env.PLAN_ONLY != '1' && moveState() } }
      steps {
        script {
          withAws {
            sh '''
            bucket=$(bash infra/scripts/tf-run.sh aws-state output | jq -r .bucket.value)
            export TF_STATE_BUCKET_AWS="$bucket"
            TF_RUN_APPROVED=aws-state bash infra/scripts/tf-run.sh aws-state migrate-state
            TF_RUN_APPROVED=aws-network bash infra/scripts/tf-run.sh aws-network migrate-state
            for d in "$WORK_ROOT"/*/aws; do
              [ -d "$d" ] || continue
              app=$(basename "$(dirname "$d")")
              case $app in _bootstrap | targets) continue ;; esac
              APP="$app" TF_RUN_APPROVED=aws bash infra/scripts/tf-run.sh aws migrate-state
            done
            echo "다음: Jenkins 관리 → System → Global properties → Environment variables에 TF_STATE_BUCKET_AWS=$bucket 를 넣어요"
            echo "      넣기 전에는 AWS plan · apply가 멈춰요 (state를 옮긴 스택은 로컬 backend로 돌지 않아요)"
            '''
          }
        }
      }
    }

    stage('Register target') {
      when { expression { env.PLAN_ONLY != '1' && params.STACK == 'aws-network' && !params.DESTROY } }
      steps {
        script {
          withAws {
            sh '''
            mkdir -p "$WORK_ROOT/targets"
            f="$WORK_ROOT/targets/aws.json"
            [ -f "$f" ] || echo '{}' > "$f"
            bash infra/scripts/tf-run.sh aws-network output > network.json
            jq -s '.[0] * {region: .[1].region.value, vpc_id: .[1].vpc_id.value,
                           public_subnet_ids: .[1].public_subnet_ids.value,
                           private_subnet_ids: .[1].private_subnet_ids.value}' "$f" network.json > "$f.tmp"
            mv "$f.tmp" "$f"
            echo "대상 환경 등록값 갱신: $f"
            cat "$f"
            '''
          }
        }
      }
    }
  }
  post {
    success {
      script {
        if (env.PLAN_ONLY == '1') {
          echo 'PLAN_ONLY: plan까지만 했어요 (승인 · apply 건너뜀). 리소스는 만들지 않았어요'
        }
      }
    }
    cleanup {
      deleteDir()
    }
  }
}

// state 버킷을 처음 만드는 실행이에요 (이미 TF_STATE_BUCKET_AWS를 쓰고 있으면 옮길 게 없어요)
def moveState() {
  return params.STACK == 'aws-state' && !params.DESTROY && !env.TF_STATE_BUCKET_AWS?.trim()
}

// 자격증명은 이 블록 안에서만 환경변수로 주입해요
def withAws(Closure body) {
  withCredentials([usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
    body()
  }
}
