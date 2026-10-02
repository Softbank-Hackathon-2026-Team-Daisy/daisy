// 고정 리소스 bootstrap: plan → Jenkins 승인 → apply → 대상 환경 등록값 갱신
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12-8). 처음 1번(또는 고정 리소스를 바꿀 때)만 돌려요.
//   앱 배포(daisy-cd-plan → daisy-cd-apply)와 달리 서버를 거치지 않는 인프라 관리 작업이라, 관리자가 Jenkins에서 승인해요
//   aws-network를 적용하면 VPC · 서브넷 ID를 $JENKINS_HOME/daisy-work/targets/aws.json에 넣어서 앱 배포가 바로 써요
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
    choice(name: 'STACK', choices: ['aws-network'], description: 'aws-network: 고정 VPC · 서브넷 (무료)')
    booleanParam(name: 'DESTROY', defaultValue: false, description: '체크하면 이 고정 리소스를 지워요. 앱이 남아 있으면 먼저 앱을 지워야 해요')
  }
  environment {
    WORK_ROOT = "${env.JENKINS_HOME}/daisy-work"
    TF_PLUGIN_CACHE_DIR = "${env.JENKINS_HOME}/.terraform.d/plugin-cache"
    TF_DESTROY = "${params.DESTROY ? '1' : ''}"
    PLAN_ID = "${env.JOB_NAME}-${env.BUILD_NUMBER}"
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
          timeout(time: 30, unit: 'MINUTES') {
            input message: "${params.DESTROY ? '삭제 plan이에요. ' : ''}${params.STACK} plan을 확인하고 승인해 주세요 (전체 plan은 Plan 단계 로그)\n${summary}",
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

// 자격증명은 이 블록 안에서만 환경변수로 주입해요
def withAws(Closure body) {
  withCredentials([usernamePassword(credentialsId: 'aws-deployer', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
    body()
  }
}
