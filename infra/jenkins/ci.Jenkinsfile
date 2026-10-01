// CI: 앱 저장소 checkout → 테스트 → 멀티 아키텍처 이미지 빌드 → 레지스트리 푸시 (태그 = 커밋 해시 40자)
//
// (가칭) 로컬 VM 러너 프로토타입이에요 (infra/SPEC.md §12). 앱 저장소는 수정하지 않고 여기서 받아요.
// Cloud Run은 amd64 이미지만 실행해서 linux/amd64·arm64를 함께 푸시해요.
// 필요한 Jenkins Credentials: registry (Username/Password = 레지스트리 계정 + 쓰기 토큰)
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  parameters {
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith.git', description: '앱 저장소 (Dockerfile · deploy.yaml)')
    string(name: 'APP_BRANCH', defaultValue: 'main')
    string(name: 'IMAGE_REPO', defaultValue: '', description: '태그 없는 이미지 주소. 예: docker.io/<계정>/hellocalc (공개 저장소)')
    booleanParam(name: 'TRIGGER_CD', defaultValue: false, description: '푸시 후 daisy-cd-plan을 이 태그로 시작 (plan까지 만들고 승인을 기다려요)')
  }
  stages {
    stage('Checkout') {
      steps {
        script {
          if (!(params.IMAGE_REPO ==~ /[a-z0-9.\-]+(:[0-9]+)?\/[a-z0-9._\-\/]+/)) {
            error("IMAGE_REPO는 태그 없는 이미지 주소여야 해요: '${params.IMAGE_REPO}'")
          }
        }
        dir('app') {
          git url: params.APP_REPO, branch: params.APP_BRANCH
        }
        script {
          env.IMAGE_TAG = sh(script: 'git -C app rev-parse HEAD', returnStdout: true).trim()
          env.IMAGE_REF = "${params.IMAGE_REPO}:${env.IMAGE_TAG}"
          currentBuild.description = env.IMAGE_REF
        }
      }
    }

    stage('Test') {
      // sample-monolith 전용 명령이에요 (Go). deploy.yaml에 테스트 명령이 없어서 앱마다 이 단계를 맞춰요
      // VM에 Go를 설치하지 않으려고 go.mod 버전의 golang 컨테이너에서 돌려요
      steps {
        dir('app') {
          sh '''
            go_version=$(awk '/^go / {print $2; exit}' go.mod)
            docker run --rm --user "$(id -u):$(id -g)" \
              -e HOME=/tmp -e GOCACHE=/tmp/go-cache -e GOPATH=/tmp/go \
              -v "$PWD":/src -w /src "golang:${go_version}" make check
          '''
        }
      }
    }

    stage('Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
          dir('app') {
            sh '''
              registry=${IMAGE_REPO%%/*}
              echo "$REG_TOKEN" | docker login "$registry" -u "$REG_USER" --password-stdin
              docker buildx build --builder daisy-builder \
                --platform linux/amd64,linux/arm64 \
                --build-arg COMMIT="$IMAGE_TAG" \
                --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --label org.opencontainers.image.revision="$IMAGE_TAG" \
                --tag "$IMAGE_REF" --push .
              docker buildx imagetools inspect "$IMAGE_REF"
            '''
          }
        }
      }
    }

    stage('Trigger CD') {
      when { expression { params.TRIGGER_CD } }
      steps {
        build job: 'daisy-cd-plan', wait: false, parameters: [
          string(name: 'IMAGE_REPO', value: params.IMAGE_REPO),
          string(name: 'IMAGE_TAG', value: env.IMAGE_TAG),
          string(name: 'APP_REPO', value: params.APP_REPO),
        ]
      }
    }
  }
  post {
    success {
      echo "푸시 완료: ${env.IMAGE_REF}"
    }
    always {
      sh '''
        docker logout "${IMAGE_REPO%%/*}" >/dev/null 2>&1 || true
        docker image prune -f >/dev/null || true
        docker buildx prune --builder daisy-builder --filter until=72h -f >/dev/null || true
      '''
    }
    cleanup {   // always는 success보다 먼저 돌아요. 작업 공간 정리는 맨 마지막에
      deleteDir()
    }
  }
}
