#!/bin/bash
# EC2 초기 환경 세팅 스크립트 (최초 1회 실행)
# 사용법: ./scripts/init-ec2.sh
# 주의: docker compose up은 실행하지 않음. 이미지가 없어서 실패함.
#       이 스크립트 실행 후 main 머지 → CD 파이프라인이 자동으로 배포함.

set -e

# ── 설정값 ────────────────────────────────────────────────────
PEM_FILE="./infra/terraform/omc-key.pem"
EC2_USER="ubuntu"
EC2_HOST=$(cd ./infra/terraform && terraform output -raw elastic_ip)
REMOTE_DIR="~/omc"
# ──────────────────────────────────────────────────────────────

echo "▶ EC2 주소: $EC2_HOST"
echo "▶ PEM 파일: $PEM_FILE"

# 1. EC2에 디렉토리 생성
echo ""
echo "[1/4] EC2에 디렉토리 생성..."
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "mkdir -p $REMOTE_DIR"

# 2. docker-compose.prod.yml 전송
echo "[2/5] docker-compose.prod.yml 전송..."
scp -i "$PEM_FILE" -o StrictHostKeyChecking=no \
  ./docker-compose.prod.yml \
  "$EC2_USER@$EC2_HOST:$REMOTE_DIR/docker-compose.prod.yml"

# 3. .env.prod 전송 (.env로도 복사 → --env-file 없이 실행해도 동작)
echo "[3/5] .env.prod 전송..."
scp -i "$PEM_FILE" -o StrictHostKeyChecking=no \
  ./.env.prod \
  "$EC2_USER@$EC2_HOST:$REMOTE_DIR/.env.prod"
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" \
  "cp $REMOTE_DIR/.env.prod $REMOTE_DIR/.env"

# 4. docker 설정 디렉토리 전송 (keycloak, postgres 초기화 스크립트)
echo "[4/5] docker 설정 디렉토리 전송..."
scp -i "$PEM_FILE" -o StrictHostKeyChecking=no -r \
  ./docker \
  "$EC2_USER@$EC2_HOST:$REMOTE_DIR/docker"

echo ""
echo "✅ EC2 초기 환경 세팅 완료!"
echo "▶ 다음 단계: main 머지 → CD 파이프라인이 자동으로 이미지 빌드 + 배포합니다."
