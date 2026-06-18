#!/bin/bash
# ===============================================
# LoveTrack Backend - 一键部署到远程 Linux 服务器
# ===============================================
# 用法:
#   1. 修改下方 SERVER / SSH_USER / REMOTE_DIR
#   2. bash deploy.sh
# ===============================================
set -euo pipefail

# ---------- 配置（按需修改）----------
SERVER="your-server-ip"          # 服务器 IP 或域名
SSH_USER="root"                  # SSH 用户名
REMOTE_DIR="/opt/lovetrack"      # 服务器上的部署目录
SSH_PORT="22"                    # SSH 端口

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
err()  { echo -e "${RED}[error]${NC} $1"; }

# ---------- 预检 ----------
if [ "$SERVER" = "your-server-ip" ]; then
  err "请先编辑 deploy.sh 顶部的 SERVER / SSH_USER / REMOTE_DIR"
  exit 1
fi

SSH="ssh -p ${SSH_PORT} -o ConnectTimeout=5 ${SSH_USER}@${SERVER}"
SCP="scp -P ${SSH_PORT} -o ConnectTimeout=5"

# ---------- 检查服务器连通性 ----------
log "检查服务器连通性..."
if ! ${SSH} "echo ok" > /dev/null 2>&1; then
  err "无法连接 ${SSH_USER}@${SERVER}:${SSH_PORT}"
  exit 1
fi
log "服务器连通 ✅"

# ---------- 服务器安装 Docker（如未装）----------
log "检查 Docker..."
if ${SSH} "command -v docker > /dev/null 2>&1" 2>/dev/null; then
  log "Docker 已安装 ✅"
else
  warn "Docker 未安装，正在自动安装..."
  ${SSH} "curl -fsSL https://get.docker.com | bash"
  log "Docker 安装完成 ✅"
fi

# ---------- 创建远程目录 ----------
log "创建远程目录 ${REMOTE_DIR}..."
${SSH} "mkdir -p ${REMOTE_DIR}"

# ---------- 上传文件 ----------
log "上传后端文件..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
${SCP} -r \
  "${SCRIPT_DIR}/Dockerfile" \
  "${SCRIPT_DIR}/docker-compose.yml" \
  "${SCRIPT_DIR}/package.json" \
  "${SCRIPT_DIR}/src/" \
  "${SSH_USER}@${SERVER}:${REMOTE_DIR}/"

log "文件上传完成 ✅"

# ---------- 远程启动 ----------
log "远程构建 & 启动..."
${SSH} "cd ${REMOTE_DIR} && docker compose up -d --build --remove-orphans"

log "等待服务就绪..."
sleep 3

# ---------- 验证 ----------
if ${SSH} "curl -sf http://localhost:3000/healthz" > /dev/null 2>&1; then
  log "部署成功 🎉"
  log "  HTTP:      http://${SERVER}:3000/healthz"
  log "  WebSocket: ws://${SERVER}:3000/sync?userId=YOUR_ID"
  echo ""
  ${SSH} "curl -s http://localhost:3000/healthz"
else
  warn "健康检查失败，查看日志："
  ${SSH} "cd ${REMOTE_DIR} && docker compose logs --tail=20"
fi
