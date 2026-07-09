# ---- Stage 1: cài production deps (pg là pure JS, không cần build toolchain nữa)
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ---- Stage 2: runtime gọn nhẹ, chạy non-root
FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY migrations ./migrations
COPY src ./src
USER node
EXPOSE 4001
CMD ["node", "src/server.js"]
