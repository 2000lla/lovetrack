#!/bin/bash
# ===============================================
# LoveTrack Backend - 服务器本地一键启动
# ===============================================
# 直接运行在 Linux 服务器上，自动选择启动方式：
#   - 优先 Docker Compose（推荐）
#   - Fallback PM2 + Node.js（无 Docker 时）
#
# 用法:
#   bash start.sh            # 启动（默认 Docker）
#   bash start.sh pm2        # 强制使用 PM2
#   bash start.sh stop       # 停止服务
#   bash start.sh status     # 查看状态
#   bash start.sh logs       # 查看日志
# ===============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[lovetrack]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
err()  { echo -e "${RED}[error]${NC} $1"; }

# ---------- 辅助函数 ----------
docker_start() {
  if ! command -v docker &> /dev/null; then
    err "Docker 未安装"
    return 1
  fi
  log "使用 Docker Compose 启动..."
  docker compose up -d --build --remove-orphans
  sleep 2
  if curl -sf http://localhost:3000/healthz > /dev/null 2>&1; then
    log "启动成功 ✅  http://localhost:3000/healthz"
    curl -s http://localhost:3000/healthz
  else
    warn "健康检查未通过，查看日志: docker compose logs"
  fi
}

docker_stop() {
  log "停止 Docker 服务..."
  docker compose down
}

docker_status() {
  docker compose ps
  echo ""
  curl -s http://localhost:3000/healthz 2>/dev/null || echo "服务未响应"
}

docker_logs() {
  docker compose logs -f --tail=50
}

install_nodejs_universal() {
  # 通用 Node.js 安装 — 支持 CentOS/RHEL/Debian/Ubuntu/Alpine
  local NODE_VER="v20.19.0"
  local NODE_TAR="node-${NODE_VER}-linux-x64.tar.xz"
  local NODE_URL="https://nodejs.org/dist/${NODE_VER}/${NODE_TAR}"
  local NODE_DIR="/usr/local/nodejs"

  # 方法1: 已有包管理器 → 用包管理器
  if command -v apt-get &> /dev/null; then
    log "检测到 Debian/Ubuntu，使用 apt 安装 Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    return 0
  fi

  if command -v dnf &> /dev/null; then
    log "检测到 Fedora/RHEL 8+，使用 dnf 安装 Node.js..."
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
    sudo dnf install -y nodejs
    return 0
  fi

  if command -v yum &> /dev/null; then
    log "检测到 CentOS/RHEL 7，使用 yum 安装 Node.js..."
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
    sudo yum install -y nodejs
    return 0
  fi

  # 方法2: 通用二进制安装（适用于所有 Linux）
  log "使用通用二进制安装 Node.js ${NODE_VER}..."
  if [ ! -f "/tmp/${NODE_TAR}" ]; then
    curl -fsSL "${NODE_URL}" -o "/tmp/${NODE_TAR}"
  fi
  sudo mkdir -p "${NODE_DIR}"
  sudo tar -xJf "/tmp/${NODE_TAR}" -C "${NODE_DIR}" --strip-components=1
  sudo ln -sf "${NODE_DIR}/bin/node" /usr/local/bin/node
  sudo ln -sf "${NODE_DIR}/bin/npm" /usr/local/bin/npm
  sudo ln -sf "${NODE_DIR}/bin/npx" /usr/local/bin/npx
  log "Node.js 安装完成 ✅"
}

pm2_start() {
  # 确保 Node.js >= 18
  if ! command -v node &> /dev/null; then
    log "Node.js 未安装，正在自动安装..."
    install_nodejs_universal
  fi

  local NODE_VERSION=$(node -v 2>/dev/null | cut -d. -f1 | tr -d 'v')
  if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt 18 ]; then
    err "需要 Node.js >= 18，当前: $(node -v 2>/dev/null || echo 'none')"
    return 1
  fi

  # 安装依赖
  log "安装依赖..."
  npm install --omit=dev

  # 安装 PM2（全局）
  if ! command -v pm2 &> /dev/null; then
    log "安装 PM2..."
    npm install -g pm2
  fi

  # 启动/重载
  if pm2 list | grep -q "lovetrack"; then
    log "重载现有 PM2 进程..."
    pm2 reload lovetrack
  else
    log "启动 PM2 进程..."
    pm2 start src/server.js --name lovetrack
  fi

  # 保存 PM2 列表（开机自启）
  pm2 save
  if ! pm2 startup | grep -q "already"; then
    pm2 startup
  fi

  log "PM2 启动完成 ✅"
  pm2 status
}

pm2_stop() {
  log "停止 PM2 进程..."
  pm2 stop lovetrack || true
}

pm2_status() {
  pm2 status
  echo ""
  curl -s http://localhost:3000/healthz 2>/dev/null || echo "服务未响应"
}

pm2_logs() {
  pm2 logs lovetrack --lines=50
}

# ---------- 主入口 ----------
MODE="${1:-docker}"

case "$MODE" in
  docker|start)
    if command -v docker &> /dev/null; then
      docker_start
    else
      warn "Docker 不可用，fallback 到 PM2..."
      pm2_start
    fi
    ;;
  pm2)
    pm2_start
    ;;
  stop)
    if command -v docker &> /dev/null && docker compose ps &> /dev/null; then
      docker_stop
    elif command -v pm2 &> /dev/null; then
      pm2_stop
    else
      warn "没有运行中的服务"
    fi
    ;;
  status)
    if command -v docker &> /dev/null && docker compose ps &> /dev/null 2>&1; then
      docker_status
    elif command -v pm2 &> /dev/null; then
      pm2_status
    else
      warn "没有运行中的服务"
    fi
    ;;
  logs)
    if command -v docker &> /dev/null && docker compose ps &> /dev/null 2>&1; then
      docker_logs
    elif command -v pm2 &> /dev/null; then
      pm2_logs
    else
      warn "没有运行中的服务"
    fi
    ;;
  *)
    echo "用法: bash start.sh [docker|pm2|stop|status|logs]"
    echo "  docker (默认) — Docker Compose 启动"
    echo "  pm2            — PM2 进程管理启动"
    echo "  stop           — 停止服务"
    echo "  status         — 查看状态"
    echo "  logs           — 查看日志"
    ;;
esac
