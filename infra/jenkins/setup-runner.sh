#!/usr/bin/env bash
# Jenkins 러너(CI + CD) 설치 스크립트 — Ubuntu 24.04 (arm64 · amd64)
#
# 로컬 VM(daisy-runner)과 팀원 서버에서 같은 스크립트를 실행해요. 여러 번 실행해도 안전해요.
#   sudo bash infra/jenkins/setup-runner.sh
#   sudo TERRAFORM_VERSION=1.x.y bash infra/jenkins/setup-runner.sh   # 다른 버전으로 바꿀 때
#
# 설치: Java 21, Jenkins LTS, Docker CE + buildx, qemu(binfmt), terraform, AWS CLI v2, gcloud CLI
# 자격증명은 설치하지 않아요. Jenkins Credentials에만 넣어요 (infra/SPEC.md 참고).
set -euo pipefail

TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.16.4}"   # 러너·AI 작성 규칙과 같은 버전 (infra/AGENTS.md §2)
SWAP_TARGET_GIB="${SWAP_TARGET_GIB:-4}"

[[ $EUID -eq 0 ]] || { echo "root로 실행해 주세요: sudo bash $0" >&2; exit 1; }
. /etc/os-release
[[ "${ID}" == "ubuntu" ]] || { echo "Ubuntu 전용이에요 (현재: ${ID})" >&2; exit 1; }
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
ARCH="$(dpkg --print-architecture)"
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n==> %s\n' "$*"; }

add_repo() { # add_repo <이름> <키 URL> <키 파일> <dearmor:yes|no> <sources 줄>
  local name=$1 key_url=$2 key_file=$3 dearmor=$4 line=$5
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -s $key_file ]]; then
    if [[ $dearmor == yes ]]; then
      curl -fsSL "$key_url" | gpg --dearmor --yes -o "$key_file"
    else
      curl -fsSL "$key_url" -o "$key_file"
    fi
    chmod a+r "$key_file"
  fi
  echo "$line" > "/etc/apt/sources.list.d/${name}.list"
}

# jenkins.io는 요청마다 미러를 무작위로 골라서, 응답 없는 미러에 걸리면 재시도로 다른 미러를 받아요
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-daisy-retries

log "기본 패키지"
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg unzip jq git fontconfig python3-yaml \
  open-vm-tools qemu-user-static binfmt-support
timedatectl set-ntp true   # VM이 잠들었다 깨면 시계가 틀어져 AWS 서명 오류가 나요

log "swap (${SWAP_TARGET_GIB}GiB 이상)"
swap_bytes=$(swapon --show=SIZE --bytes --noheadings | awk '{s+=$1} END {print s+0}')
if (( swap_bytes < (SWAP_TARGET_GIB - 1) * 1024 ** 3 )) && [[ ! -f /swapfile-daisy ]]; then
  fallocate -l "${SWAP_TARGET_GIB}G" /swapfile-daisy
  chmod 600 /swapfile-daisy
  mkswap /swapfile-daisy
  swapon /swapfile-daisy
  echo '/swapfile-daisy none swap sw 0 0' >> /etc/fstab
fi

log "apt 저장소 (Jenkins · Docker · HashiCorp · Google Cloud)"
add_repo jenkins https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  /etc/apt/keyrings/jenkins-keyring.asc no \
  "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/"
add_repo docker https://download.docker.com/linux/ubuntu/gpg \
  /etc/apt/keyrings/docker.asc no \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable"
add_repo hashicorp https://apt.releases.hashicorp.com/gpg \
  /etc/apt/keyrings/hashicorp.gpg yes \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${CODENAME} main"
add_repo google-cloud-sdk https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  /etc/apt/keyrings/cloud.google.gpg yes \
  "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
apt-get update -q

log "Java 21 · Jenkins LTS"
apt-get install -y -q openjdk-21-jre-headless jenkins
systemctl enable --now jenkins

log "Docker CE · buildx"
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin
systemctl enable --now docker
# VMware NAT DNS 프록시는 EDNS 질의에 깨진 응답을 줘서, Go 리졸버를 쓰는 buildkit이 레지스트리 주소를 못 찾아요.
# VMware 게스트에서만 컨테이너 DNS를 공용 DNS로 지정해요 (VM 자체 DNS는 그대로).
if [[ $(systemd-detect-virt 2>/dev/null || true) == vmware ]]; then
  want=$(jq -cn --arg d "${DOCKER_DNS:-1.1.1.1 8.8.8.8}" '$d | split(" ")')
  have=$(jq -c '.dns // []' /etc/docker/daemon.json 2>/dev/null || echo '[]')
  if [[ $want != "$have" ]]; then
    tmp=$(mktemp)
    jq --argjson d "$want" '.dns = $d' /etc/docker/daemon.json >"$tmp" 2>/dev/null ||
      jq -n --argjson d "$want" '{dns: $d}' >"$tmp"
    install -m 644 "$tmp" /etc/docker/daemon.json
    rm -f "$tmp"
    systemctl restart docker
    sudo -u jenkins docker buildx rm daisy-builder >/dev/null 2>&1 || true   # 새 DNS로 다시 만들어요
  fi
fi
if ! id -nG jenkins | grep -qw docker; then
  usermod -aG docker jenkins
  systemctl restart jenkins   # 그룹 변경은 재시작해야 적용돼요
fi
# 멀티 아키텍처 푸시에는 docker-container 드라이버가 필요해요
if ! sudo -u jenkins docker buildx inspect daisy-builder >/dev/null 2>&1; then
  sudo -u jenkins docker buildx create --name daisy-builder --driver docker-container --use
fi
sudo -u jenkins docker buildx inspect daisy-builder --bootstrap >/dev/null

log "terraform"
apt-mark unhold terraform >/dev/null 2>&1 || true
if [[ -n $TERRAFORM_VERSION ]]; then
  apt-get install -y -q --allow-downgrades "terraform=${TERRAFORM_VERSION}-*"
else
  apt-get install -y -q terraform
fi
apt-mark hold terraform >/dev/null   # 해커톤 중 자동 업그레이드로 버전이 바뀌지 않게
install -d -o jenkins -g jenkins /var/lib/jenkins/.terraform.d/plugin-cache /var/lib/jenkins/daisy-work

log "AWS CLI v2"
if ! command -v aws >/dev/null; then
  tmp=$(mktemp -d)
  aws_arch=$([[ $ARCH == arm64 ]] && echo aarch64 || echo x86_64)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  "$tmp/aws/install"
  rm -rf "$tmp"
fi

log "gcloud CLI"
apt-get install -y -q google-cloud-cli

log "설치 결과"
echo "os         : ${PRETTY_NAME} (${ARCH})"
echo "java       : $(java -version 2>&1 | head -1)"
echo "jenkins    : $(dpkg-query -W -f='${Version}' jenkins) ($(systemctl is-active jenkins))"
echo "docker     : $(docker --version) ($(systemctl is-active docker))"
echo "buildx     : $(sudo -u jenkins docker buildx inspect daisy-builder | awk -F': *' '/^Platforms/ {print $2; exit}')"
echo "terraform  : $(terraform version | head -1) (hold)"
echo "aws        : $(aws --version)"
echo "gcloud     : $(gcloud version 2>/dev/null | head -1)"
echo "swap       : $(free -h | awk '/^Swap/ {print $2}')"
echo "jenkins UI : http://$(hostname -I | awk '{print $1}'):8080"
if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
  echo "초기 관리자 비밀번호: sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
fi
