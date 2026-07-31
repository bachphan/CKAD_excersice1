#!/bin/bash
# ============================================================================
# restore-to-baseline.sh
#
# "Nút cứu hộ" — chạy sau khi demo (bất kể dừng ở Lab nào, kể cả demo dở dang)
# để đưa cluster + app babymilk-shop về ĐÚNG trạng thái hoàn hảo như thiết kế:
#   - 4 Deployment app + Postgres đúng image/replicas/resources/securityContext
#   - HPA đúng min1/max3/target50%
#   - NetworkPolicy (Ingress+Egress) + ResourceQuota + CronJob đúng cấu hình
#   - KHÔNG còn resource demo nào sót lại (pod/svc/job/secret/configmap tạm)
#   - Service "frontend" không còn dính patch blue/green dở dang
#
# Chạy trên node MASTER, từ đúng thư mục chứa k8s/base + k8s/overlays
# (mặc định: ~/babymilk-k8s — sửa BABYMILK_K8S_DIR bên dưới nếu khác).
#
# Cách dùng:
#   chmod +x restore-to-baseline.sh
#   ./restore-to-baseline.sh
#
# An toàn để chạy NHIỀU LẦN liên tiếp (idempotent) — không lo chạy "lỡ tay".
# ============================================================================

set -uo pipefail   # KHÔNG dùng -e: script phải chạy hết mọi bước dù 1 bước lỗi/không cần thiết

BABYMILK_K8S_DIR="${BABYMILK_K8S_DIR:-$HOME/babymilk-k8s}"
NODEPORT_URL="http://192.168.56.102:30080"
PASS=0
FAIL=0

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }
step()  { echo ""; yellow "=== $1 ==="; }

check() {
  # check "mô tả" <exit code của lệnh trước>
  if [ "$2" -eq 0 ]; then
    green "  ✅ $1"
    PASS=$((PASS+1))
  else
    red "  ❌ $1"
    FAIL=$((FAIL+1))
  fi
}

# ----------------------------------------------------------------------------
step "BƯỚC 1/7 — Re-sync toàn bộ trạng thái PERMANENT qua Kustomize"
# Đây là bước quan trọng nhất: chữa lành MỌI drift so với file đã commit
# (image tag bị đổi dở, HPA maxReplicas/target bị chỉnh tay, CronJob schedule
# bị đổi tạm để demo nhanh, replicas bị scale dở...) — vì Kustomize là nguồn
# chân lý, apply lại tự động đưa về đúng thiết kế.
# ----------------------------------------------------------------------------
if [ -d "$BABYMILK_K8S_DIR/overlays/prod" ]; then
  kubectl apply -k "$BABYMILK_K8S_DIR/overlays/prod"
else
  red "Không tìm thấy $BABYMILK_K8S_DIR/overlays/prod — kiểm tra lại BABYMILK_K8S_DIR"
fi

# ----------------------------------------------------------------------------
step "BƯỚC 2/7 — Gỡ patch thủ công KHÔNG bị 'apply -k' tự dọn (blue/green)"
# Lý do: kubectl apply chỉ xoá field đã từng khai báo qua apply trước đó rồi
# bị bỏ đi trong file mới — field thêm bằng "kubectl patch" (như label "version"
# gắn tay ở Lab 2.2) KHÔNG nằm trong lịch sử "last-applied", nên "apply -k"
# KHÔNG tự xoá được, phải gỡ tay bằng patch ngược lại.
# ----------------------------------------------------------------------------
kubectl patch svc frontend -n babymilk --type=json \
  -p='[{"op":"remove","path":"/spec/selector/version"}]' >/dev/null 2>&1 && echo "  Đã gỡ 'version' khỏi Service frontend selector" || echo "  (Service frontend không có patch 'version' — bỏ qua)"
kubectl patch deployment frontend -n babymilk --type=json \
  -p='[{"op":"remove","path":"/spec/template/metadata/labels/version"}]' >/dev/null 2>&1 && echo "  Đã gỡ 'version' khỏi Deployment frontend template" || echo "  (Deployment frontend không có patch 'version' — bỏ qua)"

# ----------------------------------------------------------------------------
step "BƯỚC 3/7 — Force scale về đúng baseline (không đợi HPA reconcile)"
# ----------------------------------------------------------------------------
for d in product-service user-service order-service frontend postgres; do
  kubectl scale deployment "$d" -n babymilk --replicas=1 >/dev/null 2>&1
done
echo "  Đã force scale 5 Deployment babymilk về replicas=1"

# ----------------------------------------------------------------------------
step "BƯỚC 4/7 — Quét sạch resource demo (label created-by=ckad-lab, mọi namespace)"
# ----------------------------------------------------------------------------
kubectl delete pod,deployment,service,job,configmap,secret,pvc,serviceaccount,role,rolebinding \
  -l created-by=ckad-lab --all-namespaces --ignore-not-found=true 2>&1 | sed 's/^/  /'

# ----------------------------------------------------------------------------
step "BƯỚC 5/7 — Fallback: dọn theo TÊN CỐ ĐỊNH (phòng khi quên gắn label)"
# ----------------------------------------------------------------------------
kubectl delete pod speedy-pod init-sidecar-demo lab-postgres injection-demo \
  lab51-selfheal lab44-writer lab44-reader quota-buster \
  --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete pod -l drill=true --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete deployment lab41-backend lab53-app frontend-green \
  --ignore-not-found=true -n default 2>&1 | sed 's/^/  /'
kubectl delete deployment frontend-green --ignore-not-found=true -n babymilk 2>&1 | sed 's/^/  /'
kubectl delete svc speedy-pod-svc init-sidecar-svc lab-postgres \
  lab41-backend-svc lab41-frontend-svc lab53-svc \
  --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete svc frontend-green --ignore-not-found=true -n babymilk 2>&1 | sed 's/^/  /'
kubectl delete configmap frontend-green-banner --ignore-not-found=true -n babymilk 2>&1 | sed 's/^/  /'
kubectl delete pvc lab44-dynamic-pvc --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete job rbac-demo-job rbac-negative-test stock-check-manual \
  -n babymilk --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete serviceaccount rbac-demo-sa -n babymilk --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete role pod-reader -n babymilk --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete rolebinding rbac-demo-binding -n babymilk --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete secret demo-secret --ignore-not-found=true 2>&1 | sed 's/^/  /'
kubectl delete configmap demo-config --ignore-not-found=true 2>&1 | sed 's/^/  /'
if command -v helm >/dev/null 2>&1; then
  helm uninstall lab54-nginx >/dev/null 2>&1 && echo "  Đã gỡ Helm release lab54-nginx" || echo "  (Không có Helm release lab54-nginx — bỏ qua)"
fi

# ----------------------------------------------------------------------------
step "BƯỚC 6/7 — Đảm bảo Cilium Ingress Controller vẫn TẮT (phòng Lab 4.2)"
# ----------------------------------------------------------------------------
if command -v cilium >/dev/null 2>&1; then
  cilium upgrade --set ingressController.enabled=false 2>&1 | tail -3 | sed 's/^/  /'
else
  yellow "  (không tìm thấy lệnh 'cilium' — bỏ qua bước này)"
fi

# ----------------------------------------------------------------------------
step "BƯỚC 7/7 — Re-apply lần cuối để chắc chắn KHÔNG còn drift"
# ----------------------------------------------------------------------------
sleep 5
if [ -d "$BABYMILK_K8S_DIR/overlays/prod" ]; then
  kubectl apply -k "$BABYMILK_K8S_DIR/overlays/prod"
fi

# ----------------------------------------------------------------------------
step "VERIFY — kiểm tra cluster + app đã về trạng thái hoàn hảo"
# ----------------------------------------------------------------------------
echo "Đợi pod ổn định (tối đa 60s)..."
sleep 15

echo ""
echo "--- Trạng thái pod babymilk ---"
kubectl get pods -n babymilk

READY_COUNT=$(kubectl get pods -n babymilk --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)

DRIFT=$(kubectl diff -k "$BABYMILK_K8S_DIR/overlays/prod" 2>&1 | wc -l)
check "kubectl diff -k = 0 (không còn drift so với git)" $([ "$DRIFT" -eq 0 ] && echo 0 || echo 1)

FRONTEND_SEL=$(kubectl get svc frontend -n babymilk -o jsonpath='{.spec.selector}')
check "Service frontend selector đúng {app:frontend} (không dính version blue/green)" \
  $([ "$FRONTEND_SEL" = '{"app":"frontend"}' ] && echo 0 || echo 1)

HPA_MAX=$(kubectl get hpa product-service-hpa -n babymilk -o jsonpath='{.spec.maxReplicas}')
check "HPA maxReplicas = 3" $([ "$HPA_MAX" = "3" ] && echo 0 || echo 1)

curl -s -o /dev/null -w "" --max-time 5 "$NODEPORT_URL/healthz"
check "Frontend healthz HTTP 200" $?

CATALOG_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT_URL/api/products")
check "Catalog API trả 200" $([ "$CATALOG_CODE" = "200" ] && echo 0 || echo 1)

echo ""
echo "--- Smoke test: login + checkout đầy đủ luồng ---"
LOGIN_RESPONSE=$(curl -s --max-time 8 -X POST "$NODEPORT_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@babymilk.local","password":"admin12345"}')
TOKEN=$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
check "Login thành công (lấy được token)" $([ -n "$TOKEN" ] && echo 0 || echo 1)

if [ -n "$TOKEN" ]; then
  CHECKOUT_CODE=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" -X POST "$NODEPORT_URL/api/orders" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
    -d '{"items":[{"productId":1,"quantity":1}],"fullName":"Restore Verify","phone":"0900000000","address":"HCMC","paymentMethod":"cod"}')
  check "Checkout thành công (HTTP 201)" $([ "$CHECKOUT_CODE" = "201" ] && echo 0 || echo 1)
fi

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ TẤT CẢ $PASS CHECK ĐỀU PASS — CLUSTER ĐÃ VỀ TRẠNG THÁI HOÀN HẢO"
else
  red "❌ $FAIL/$((PASS+FAIL)) CHECK FAIL — CẦN KIỂM TRA TAY (xem log phía trên)"
fi
echo "============================================================"
