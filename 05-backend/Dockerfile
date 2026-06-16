FROM node:20-alpine

WORKDIR /app

# 先拷贝 package.json 利用 Docker 缓存
COPY package.json ./

# 安装生产依赖
RUN npm install --omit=dev && npm cache clean --force

# 拷贝源码
COPY src/ ./src/

# 暴露端口
EXPOSE 3000

# 健康检查（容器内）
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/healthz || exit 1

# 启动
CMD ["node", "src/server.js"]