// unibloom-platform-ci: 플랫폼(웹 · 백엔드) 이미지를 커밋 태그로 빌드해 Docker Hub에 올리고, 배포 Job을 시작해요 (infra/SPEC.md §18)
// - Jenkins Job unibloom-platform-ci의 Pipeline script와 같은 내용이에요
// - Jenkins가 사설망에 있어 GitHub 웹훅이 닿지 않아요. 2분마다 main을 확인(Poll SCM)해서 새 커밋이면 빌드해요
// - 태그는 커밋 해시 앞 7자리 + latest 둘 다 올려요. 배포는 커밋 태그로 해요 (어떤 버전이 떠 있는지 알 수 있게)
// - CD_JOB을 비우면 배포는 시작하지 않아요
pipeline {
  agent any

  parameters {
    string(name: 'APP_REPO', defaultValue: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom.git', description: '플랫폼 저장소')
    string(name: 'APP_BRANCH', defaultValue: 'main', description: '빌드할 브랜치')
    string(name: 'SERVER_IMAGE', defaultValue: 'docker.io/dlacowns21/unibloom-server', description: '백엔드 이미지 (태그 없이)')
    string(name: 'WEB_IMAGE', defaultValue: 'docker.io/dlacowns21/unibloom-web', description: '프론트 이미지 (태그 없이)')
    string(name: 'VITE_API_BASE_URL', defaultValue: 'https://api.unibloom.cloud', description: '웹 빌드에 들어가는 API 주소')
    string(name: 'VITE_USE_MOCK', defaultValue: 'false', description: '웹 목업 모드')
    string(name: 'CD_JOB', defaultValue: 'unibloom-platform-cd', description: '빌드가 끝나면 시작할 배포 Job. 비우면 시작하지 않아요')
  }

  triggers {
    pollSCM('H/2 * * * *')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    SERVER_IMAGE = "${params.SERVER_IMAGE}"
    WEB_IMAGE = "${params.WEB_IMAGE}"
    VITE_API_BASE_URL = "${params.VITE_API_BASE_URL}"
    VITE_USE_MOCK = "${params.VITE_USE_MOCK}"
  }

  stages {
    stage('소스 가져오기') {
      steps {
        deleteDir()
        git branch: params.APP_BRANCH, url: params.APP_REPO
        script {
          env.SOURCE_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = env.SOURCE_COMMIT.take(7)   // 수동 배포와 같은 짧은 커밋 해시
          currentBuild.description = "${env.IMAGE_TAG} (+ latest)"
        }
      }
    }

    stage('빌드 환경 확인') {
      steps {
        sh '''
          docker version
          docker buildx inspect daisy-builder
          test -f infra/images/server/Dockerfile
          test -f infra/images/web/Dockerfile
        '''
      }
    }

    stage('백엔드 빌드 및 게시') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
          sh '''
            set -eu
            set +x
            printf '%s' "$REG_TOKEN" | docker login docker.io -u "$REG_USER" --password-stdin

            docker buildx build \
              --builder daisy-builder \
              --platform linux/amd64 \
              --file infra/images/server/Dockerfile \
              --label "org.opencontainers.image.revision=$SOURCE_COMMIT" \
              --tag "$SERVER_IMAGE:$IMAGE_TAG" \
              --tag "$SERVER_IMAGE:latest" \
              --push \
              server/
          '''
        }
      }
    }

    stage('프론트 빌드 및 게시') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
          sh '''
            set -eu
            set +x
            printf '%s' "$REG_TOKEN" | docker login docker.io -u "$REG_USER" --password-stdin

            docker buildx build \
              --builder daisy-builder \
              --platform linux/amd64 \
              --file infra/images/web/Dockerfile \
              --build-arg "VITE_API_BASE_URL=$VITE_API_BASE_URL" \
              --build-arg "VITE_USE_MOCK=$VITE_USE_MOCK" \
              --build-arg "GIT_COMMIT=$SOURCE_COMMIT" \
              --build-arg "BUILT_AT=$(date -u +%FT%TZ)" \
              --label "org.opencontainers.image.revision=$SOURCE_COMMIT" \
              --tag "$WEB_IMAGE:$IMAGE_TAG" \
              --tag "$WEB_IMAGE:latest" \
              --push \
              web/
          '''
        }
      }
    }

    stage('배포 시작') {
      when { expression { params.CD_JOB?.trim() } }
      steps {
        // 기다리지 않고 시작만 해요. 배포 결과는 배포 Job에서 봐요
        build job: params.CD_JOB.trim(), wait: false, parameters: [
          string(name: 'IMAGE_TAG', value: env.IMAGE_TAG),
          string(name: 'SERVER_IMAGE', value: env.SERVER_IMAGE),
          string(name: 'WEB_IMAGE', value: env.WEB_IMAGE),
        ]
      }
    }
  }

  post {
    success {
      echo """프론트 · 백엔드 이미지 빌드 및 게시가 끝났어요.
      백엔드 이미지: ${env.SERVER_IMAGE}:${env.IMAGE_TAG} (+ latest)
      프론트 이미지: ${env.WEB_IMAGE}:${env.IMAGE_TAG} (+ latest)
      배포 Job: ${params.CD_JOB ?: '(시작 안 함)'}"""
    }
    failure {
      echo '실패한 단계의 Console Output을 확인해 주세요.'
    }
  }
}
