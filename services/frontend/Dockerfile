# Frontend không có dependency — chỉ cần copy file, không cần stage build.
FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json server.js ./
COPY public ./public
USER node
EXPOSE 4000
CMD ["node", "server.js"]
