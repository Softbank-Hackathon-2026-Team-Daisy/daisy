# syntax=docker/dockerfile:1.7
# Unibloom 웹 이미지 (web/ React + Vite → nginx 정적 서버). 이미지 빌드 · 게시는 인프라 담당이라 web/ 밖에 둬요
#
#   docker build -f infra/images/web/Dockerfile --build-arg VITE_API_BASE_URL=https://api.unibloom.cloud -t <repo>:<커밋> web/
#
# - 빌드 컨텍스트는 web/ 폴더예요. 깨끗한 체크아웃에서 빌드해요 (node_modules · .pnpm-store가 섞이지 않게)
# - VITE_* 값은 빌드할 때 번들에 들어가요. 컨테이너 환경변수로는 바뀌지 않아요
# - nginx는 SPA라서 없는 경로를 index.html로 돌려요. 해시가 붙은 /assets/는 오래 캐시해요
# - /version.json: 이 이미지를 빌드한 커밋 · 시각. 지금 떠 있는 버전을 밖에서 확인해요 (CI가 GIT_COMMIT · BUILT_AT을 넘겨요)

FROM node:22-alpine AS build
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
ARG VITE_API_BASE_URL=https://api.unibloom.cloud
ARG VITE_USE_MOCK=false
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL VITE_USE_MOCK=$VITE_USE_MOCK
RUN pnpm build

FROM nginx:1.29-alpine
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
  listen 80;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;

  location = /version.json {
    default_type application/json;
    try_files $uri =404;
    add_header Cache-Control "no-store";
  }

  location /assets/ {
    try_files $uri =404;
    add_header Cache-Control "public, max-age=31536000, immutable";
  }

  location / {
    try_files $uri $uri/ /index.html;
    add_header Cache-Control "no-cache";
  }
}
EOF
COPY --from=build /app/dist /usr/share/nginx/html
ARG GIT_COMMIT=unknown
ARG BUILT_AT=unknown
RUN printf '{"commit":"%s","built_at":"%s"}\n' "$GIT_COMMIT" "$BUILT_AT" > /usr/share/nginx/html/version.json
EXPOSE 80
