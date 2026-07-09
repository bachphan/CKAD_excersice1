# ---- Stage 1: cài production deps
FROM node:22-alpine AS deps
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --omit=dev

# ---- Stage 2: runtime
FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY migrations ./migrations
COPY src ./src
RUN mkdir -p /app/data && chown -R node:node /app/data
USER node
EXPOSE 4002
CMD ["node", "src/server.js"]
