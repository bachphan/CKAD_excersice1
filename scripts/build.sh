#!/bin/bash
# build.sh — Build 5 image Docker của BabyMilk Shop tại máy dev (cần Docker Desktop).
# Chạy từ thư mục gốc repo: bash scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building product-service:2.4"
docker build -t babymilk/product-service:2.4 ./services/product-service

echo "==> Building user-service:2.2"
docker build -t babymilk/user-service:2.2 ./services/user-service

echo "==> Building order-service:2.2"
docker build -t babymilk/order-service:2.2 ./services/order-service

echo "==> Building notification-service:1.0"
docker build -t babymilk/notification-service:1.0 ./services/notification-service

echo "==> Building frontend:1.3"
docker build -t babymilk/frontend:1.3 ./services/frontend

echo "==> Pulling postgres:16-alpine"
docker pull postgres:16-alpine

echo "==> Pulling redis:7-alpine"
docker pull redis:7-alpine

echo "==> Done. Xem README.md mục 11.2 để đưa image vào cluster (không có registry riêng)."
