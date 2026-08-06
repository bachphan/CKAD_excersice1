#!/bin/bash
# deploy.sh — Apply Kustomize lên cluster K8s.
# LƯU Ý: Kustomize KHÔNG còn là cách deploy chính thức cho namespace babymilk live (đã cutover
# sang Helm, xem README.md mục 11.7) — script này giữ lại để test/parity riêng (namespace khác,
# hoặc lúc cần verify Kustomize vẫn hoạt động đúng cho yêu cầu P5).
# Giả định: đã build+import image vào worker (scripts/build.sh + README.md mục 11.2),
# đã tạo k8s/base/02-secret.yaml (README.md mục 11.3), metrics-server + ingress-nginx đã cài
# (README.md mục 11.4/11.5). Chạy từ thư mục gốc repo: bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Render thử trước (không apply) để soát lỗi YAML sớm"
kubectl kustomize k8s/overlays/prod > /dev/null

echo "==> Diff với cluster đang chạy (nếu có) trước khi apply"
kubectl diff -k k8s/overlays/prod || true

echo "==> Apply Secret riêng (không qua kustomize — xem README.md mục 11.3)"
if [ -f k8s/base/02-secret.yaml ]; then
  kubectl apply -f k8s/base/02-secret.yaml
else
  echo "    (bỏ qua — k8s/base/02-secret.yaml chưa tồn tại, copy từ 02-secret.yaml.example trước)"
fi

echo "==> Apply Kustomize overlays/prod"
kubectl apply -k k8s/overlays/prod

echo "==> Chờ rollout tất cả Deployment"
for d in product-service user-service order-service notification-service frontend postgres redis; do
  kubectl rollout status "deployment/$d" -n babymilk --timeout=120s
done

echo "==> Xong. Verify: bash scripts/smoke-test.sh"
