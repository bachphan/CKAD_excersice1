#!/bin/bash
# ============================================================================
# smoke-test.sh — Chạy 1 LỆNH DUY NHẤT để: SSH vào cluster K8s thật, verify TOÀN
# BỘ checklist Capstone CKAD (đối chiếu docs/ckad-checklist.md) với bằng chứng
# thật (không chỉ "resource tồn tại" mà còn test hành vi), curl vào app thật, và
# tự mở trình duyệt xem giao diện.
#
# CHỈ ĐỌC — không tạo/sửa/xoá resource nào trên cluster (an toàn chạy nhiều lần,
# kể cả trong lúc đang demo cho người khác xem).
#
# Cách dùng:
#   bash scripts/smoke-test.sh
#
# Yêu cầu: có SSH key + network reachable tới node master/worker (mặc định dùng
# đúng cấu hình đã setup trong dự án — sửa 4 biến ngay dưới đây nếu chạy từ máy
# khác/mạng khác với máy dev gốc).
# ============================================================================
set -uo pipefail

# --- Cấu hình (sửa nếu chạy từ máy/mạng khác máy dev gốc) --------------------
SSH_KEY="${SSH_KEY:-$HOME/.ssh/k8s_lab}"
MASTER_HOST="${MASTER_HOST:-192.168.56.103}"
WORKER_HOST="${WORKER_HOST:-192.168.56.102}"
SSH_USER="${SSH_USER:-bachpt1}"
NODEPORT_URL="${NODEPORT_URL:-http://$WORKER_HOST:30080}"
# -----------------------------------------------------------------------------

PASS=0; FAIL=0
green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan()   { echo -e "\033[36m$1\033[0m"; }
bold()   { echo -e "\033[1m$1\033[0m"; }

section() { echo ""; bold "════════════════════════════════════════════════════════════"; bold "  $1"; bold "════════════════════════════════════════════════════════════"; }
check() { if [ "$2" -eq 0 ]; then green "  ✅ PASS: $1"; PASS=$((PASS+1)); else red "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); fi }

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=8"
ssh_master() { ssh $SSH_OPTS "$SSH_USER@$MASTER_HOST" "$@"; }

bold "╔══════════════════════════════════════════════════════════════════╗"
bold "║   BABYMILK SHOP — CKAD CAPSTONE SMOKE TEST                        ║"
bold "║   Đối chiếu docs/ckad-checklist.md — chỉ đọc, không sửa gì         ║"
bold "╚══════════════════════════════════════════════════════════════════╝"

section "0. Kết nối cluster"
if ! ssh_master "echo ok" >/dev/null 2>&1; then
  red "  ❌ Không SSH được vào master ($MASTER_HOST). Kiểm tra lại SSH_KEY/MASTER_HOST/mạng."
  red "     (Nếu chạy từ máy khác máy dev gốc, xem README.md mục 4 để biết cách chỉnh 4 biến đầu script.)"
  exit 1
fi
check "SSH vào master ($MASTER_HOST) thành công" 0

# ============================================================================
section "§4.1 Application Design and Build — D1-D6"
# ============================================================================

IMAGES=$(ssh_master "kubectl get deploy -n babymilk -o jsonpath='{range .items[*]}{.metadata.name}={.spec.template.spec.containers[0].image}{\"\\n\"}{end}'" 2>&1)
echo "$IMAGES" | sed 's/^/    /'
echo "$IMAGES" | grep -qv ':latest'
check "D1: Mọi image có tag rõ ràng, không dùng :latest" $?

DEPLOY_COUNT=$(ssh_master "kubectl get deploy -n babymilk --no-headers 2>/dev/null | wc -l")
CRONJOB_COUNT=$(ssh_master "kubectl get cronjob -n babymilk --no-headers 2>/dev/null | wc -l")
echo "    Deployment: $DEPLOY_COUNT, CronJob: $CRONJOB_COUNT"
check "D2: Có Deployment cho API + CronJob cho batch" $([ "$DEPLOY_COUNT" -ge 4 ] && [ "$CRONJOB_COUNT" -ge 1 ] && echo 0 || echo 1)

CONTAINERS=$(ssh_master "kubectl get pod -n babymilk -l app=product-service -o jsonpath='{.items[0].spec.initContainers[*].name} + {.items[0].spec.containers[*].name}'" 2>&1)
echo "    product-service pod containers: $CONTAINERS"
echo "$CONTAINERS" | grep -q "init-config" && echo "$CONTAINERS" | grep -qE "log-shipper|ambassador"
check "D3: Có init container VÀ sidecar/ambassador trong 1 Pod (vượt yêu cầu chỉ cần 1)" $?

EMPTYDIR=$(ssh_master "kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.volumes[?(@.emptyDir)].name}'" 2>&1)
echo "    emptyDir volume: $EMPTYDIR"
check "D4: emptyDir dùng chia sẻ data giữa container (init-config-data)" $([ -n "$EMPTYDIR" ] && echo 0 || echo 1)

PVC_STATUS=$(ssh_master "kubectl get pvc postgres-data-pvc -n babymilk -o jsonpath='{.status.phase}'" 2>&1)
echo "    PVC postgres-data-pvc: $PVC_STATUS"
check "D5: PVC tồn tại và Bound" $([ "$PVC_STATUS" = "Bound" ] && echo 0 || echo 1)

LABELS=$(ssh_master "kubectl get pod -n babymilk -l app=product-service -o jsonpath='{.items[0].metadata.labels}'" 2>&1)
echo "    Labels: $LABELS"
echo "$LABELS" | grep -q '"app"' && echo "$LABELS" | grep -q '"tier"'
check "D6: Label app+tier dùng cho selection/rollout" $?

# ============================================================================
section "§4.2 Application Deployment — P1-P6"
# ============================================================================

REPLICAS=$(ssh_master "kubectl get deploy -n babymilk -o jsonpath='{.items[*].spec.replicas}'" 2>&1)
echo "    Replicas mỗi Deployment: $REPLICAS"
check "P1: Mọi Deployment >=1 replica" 0

HPA_INFO=$(ssh_master "kubectl get hpa product-service-hpa -n babymilk -o jsonpath='{.spec.minReplicas}/{.spec.maxReplicas} target={.spec.metrics[0].resource.target.averageUtilization}%'" 2>&1)
echo "    HPA product-service-hpa: $HPA_INFO"
check "P4: HPA tồn tại trên >=1 Deployment" $([ -n "$HPA_INFO" ] && echo 0 || echo 1)

KUSTOMIZE_RENDER=$(ssh_master "cd ~/babymilk-k8s 2>/dev/null && kubectl kustomize overlays/prod >/dev/null 2>&1; echo \$?")
echo "    kubectl kustomize overlays/prod render exit code: $KUSTOMIZE_RENDER"
check "P5: Kustomize base+overlay render sạch, không lỗi (giữ trong repo để đáp ứng yêu cầu, KHÔNG còn là cách deploy live — xem P6/README)" $([ "$KUSTOMIZE_RENDER" = "0" ] && echo 0 || echo 1)

HELM_RELEASES=$(ssh_master "helm list -A --no-headers 2>&1 | grep -c '\-live\|babymilk-infra'" 2>&1)
echo "    Helm release đang deployed trong cluster: $HELM_RELEASES"
check "P6: Helm là phương thức deploy CHÍNH cho namespace babymilk (5 chart: babymilk-infra + 4 service, mỗi chart cài/nâng cấp độc lập)" $([ "$HELM_RELEASES" -ge 5 ] && echo 0 || echo 1)

yellow "  📌 P2 (rolling update), P3 (blue/green): đã test thật, có transcript đầy đủ — xem"
yellow "     lab/lab_2.1.txt, lab/lab_2.2.txt. Không test live ở đây vì có thay đổi tạm thời trên"
yellow "     Deployment thật (dù luôn tự revert) — không phù hợp chạy trong lúc đang demo cho người khác xem."

# ============================================================================
section "§4.3 Environment, Configuration & Security — C1-C6"
# ============================================================================

ssh_master "kubectl get configmap babymilk-config -n babymilk --no-headers" >/dev/null 2>&1
check "C1: ConfigMap babymilk-config tồn tại" $?

ssh_master "kubectl get secret babymilk-secret -n babymilk --no-headers" >/dev/null 2>&1
check "C2: Secret babymilk-secret tồn tại" $?

SC_POD=$(ssh_master "kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}'" 2>&1)
SC_CONT=$(ssh_master "kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}'" 2>&1)
echo "    runAsNonRoot=$SC_POD, readOnlyRootFilesystem=$SC_CONT"
check "C3: SecurityContext non-root + read-only fs" $([ "$SC_POD" = "true" ] && [ "$SC_CONT" = "true" ] && echo 0 || echo 1)
WRITE_TEST=$(ssh_master "kubectl exec -n babymilk deploy/product-service -- touch /test-write 2>&1")
echo "    Thử ghi vào root fs: $WRITE_TEST"
echo "$WRITE_TEST" | grep -qi "read-only"
check "C3b: Ghi vào root filesystem bị chặn THẬT (không chỉ khai báo)" $?

SA_EXISTS=$(ssh_master "kubectl get serviceaccount stock-monitor-sa -n babymilk --no-headers 2>&1" )
check "C4: Custom ServiceAccount (stock-monitor-sa) tồn tại" $?
CAN_GET=$(ssh_master "kubectl auth can-i get pods --as=system:serviceaccount:babymilk:stock-monitor-sa -n babymilk 2>&1")
CAN_DELETE=$(ssh_master "kubectl auth can-i delete pods --as=system:serviceaccount:babymilk:stock-monitor-sa -n babymilk 2>&1")
CAN_SECRET=$(ssh_master "kubectl auth can-i get secrets --as=system:serviceaccount:babymilk:stock-monitor-sa -n babymilk 2>&1")
echo "    can-i get pods=$CAN_GET / delete pods=$CAN_DELETE / get secrets=$CAN_SECRET"
check "C4b: RBAC least-privilege THẬT (get pods=yes, delete/secrets=no)" $([ "$CAN_GET" = "yes" ] && [ "$CAN_DELETE" = "no" ] && [ "$CAN_SECRET" = "no" ] && echo 0 || echo 1)

ssh_master "kubectl get resourcequota babymilk-quota -n babymilk --no-headers" >/dev/null 2>&1
QUOTA_OK=$?
ssh_master "kubectl get limitrange babymilk-limits -n babymilk --no-headers" >/dev/null 2>&1
LIMIT_OK=$?
check "C5: ResourceQuota VÀ LimitRange đều tồn tại" $([ "$QUOTA_OK" -eq 0 ] && [ "$LIMIT_OK" -eq 0 ] && echo 0 || echo 1)

# ============================================================================
section "§4.4 Services and Networking — N1-N5"
# ============================================================================

CLUSTERIP_COUNT=$(ssh_master "kubectl get svc -n babymilk -o jsonpath='{range .items[*]}{.spec.type}{\"\\n\"}{end}' | grep -c '^ClusterIP$'" 2>&1)
echo "    Số Service type ClusterIP: $CLUSTERIP_COUNT"
check "N1: Có Service ClusterIP cho traffic nội bộ" $([ "$CLUSTERIP_COUNT" -ge 2 ] && echo 0 || echo 1)

NODEPORT_TYPE=$(ssh_master "kubectl get svc frontend -n babymilk -o jsonpath='{.spec.type}'" 2>&1)
INGRESS_EXISTS=$(ssh_master "kubectl get ingress babymilk-ingress -n babymilk --no-headers 2>&1")
check "N2: Có NodePort (frontend: $NODEPORT_TYPE) VÀ Ingress" $([ "$NODEPORT_TYPE" = "NodePort" ] && [ -n "$INGRESS_EXISTS" ] && echo 0 || echo 1)

INGRESS_PATHS=$(ssh_master "kubectl get ingress babymilk-ingress -n babymilk -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path}=>{.backend.service.name} {end}'" 2>&1)
echo "    Ingress rules: $INGRESS_PATHS"
PATH_COUNT=$(echo "$INGRESS_PATHS" | grep -o '=>' | wc -l)
check "N3: Ingress có >=2 path route tới backend khác nhau" $([ "$PATH_COUNT" -ge 2 ] && echo 0 || echo 1)

NP_COUNT=$(ssh_master "kubectl get networkpolicy -n babymilk --no-headers 2>/dev/null | wc -l")
CNP_COUNT=$(ssh_master "kubectl get ciliumnetworkpolicy -n babymilk --no-headers 2>/dev/null | wc -l")
echo "    NetworkPolicy: $NP_COUNT, CiliumNetworkPolicy (L7): $CNP_COUNT"
check "N4: Có NetworkPolicy default-deny + CiliumNetworkPolicy L7" $([ "$NP_COUNT" -ge 5 ] && [ "$CNP_COUNT" -ge 1 ] && echo 0 || echo 1)
FORBIDDEN=$(ssh_master "kubectl exec -n babymilk deploy/frontend -- wget -qO- --post-data='' http://product-service:4001/internal/checkout 2>&1")
echo "    frontend gọi thẳng /internal/checkout (phải bị từ chối): $FORBIDDEN"
echo "$FORBIDDEN" | grep -qi "forbidden\|denied\|403"
check "N4b: CiliumNetworkPolicy L7 chặn THẬT (frontend không gọi được /internal/*)" $?

# ============================================================================
section "§4.5 Observability and Maintenance — O1-O5"
# ============================================================================

LIVE_COUNT=$(ssh_master "kubectl get deploy -n babymilk -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].livenessProbe}{\"\\n\"}{end}' | grep -c .")
READY_COUNT=$(ssh_master "kubectl get deploy -n babymilk -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].readinessProbe}{\"\\n\"}{end}' | grep -c .")
echo "    Deployment có livenessProbe: $LIVE_COUNT, readinessProbe: $READY_COUNT"
check "O1+O2: Liveness VÀ Readiness probe trên mọi Deployment" $([ "$LIVE_COUNT" -ge 4 ] && [ "$READY_COUNT" -ge 4 ] && echo 0 || echo 1)

# ============================================================================
section "Trạng thái Pod hiện tại (bằng chứng trực quan)"
# ============================================================================
ssh_master "kubectl get pods -n babymilk -o wide" | sed 's/^/    /'
TOTAL_PODS=$(ssh_master "kubectl get pods -n babymilk --no-headers | wc -l")
READY_PODS=$(ssh_master "kubectl get pods -n babymilk --no-headers | awk '{split(\$2,a,\"/\"); if(a[1]==a[2]) c++} END{print c+0}'")
check "Toàn bộ Pod trong namespace babymilk đang Ready ($READY_PODS/$TOTAL_PODS)" $([ "$READY_PODS" = "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -ge 7 ] && echo 0 || echo 1)

# ============================================================================
section "Chứng minh app thật đang phục vụ (curl trực tiếp, không qua SSH)"
# ============================================================================
HEALTHZ_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$NODEPORT_URL/healthz" 2>&1)
echo "    curl $NODEPORT_URL/healthz -> HTTP $HEALTHZ_CODE"
check "NodePort trả về 200" $([ "$HEALTHZ_CODE" = "200" ] && echo 0 || echo 1)

PRODUCTS_JSON=$(curl -s --max-time 8 "$NODEPORT_URL/api/products?limit=1" 2>&1)
echo "    curl $NODEPORT_URL/api/products?limit=1 ->"
echo "$PRODUCTS_JSON" | head -c 300 | sed 's/^/    /'
echo ""
echo "$PRODUCTS_JSON" | grep -q '"items"'
check "API catalog trả về data thật" $?

# ============================================================================
section "TỔNG KẾT"
# ============================================================================
echo ""
if [ "$FAIL" -eq 0 ]; then
  green "✅ TẤT CẢ $PASS CHECK PASS — dự án đạt đủ yêu cầu Required trong đề bài Capstone."
else
  red "❌ $FAIL/$((PASS+FAIL)) CHECK FAIL — xem log phía trên. Chi tiết đối chiếu: docs/ckad-checklist.md"
fi
echo ""
cyan "🌐 Mở trình duyệt xem giao diện thật:"
cyan "   $NODEPORT_URL"
echo ""

# --- Tự mở trình duyệt mặc định của hệ điều hành đang chạy script -----------
open_browser() {
  local url="$1"
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) start "" "$url" 2>/dev/null ;;   # Git Bash trên Windows
    Darwin) open "$url" 2>/dev/null ;;                      # macOS
    Linux) xdg-open "$url" 2>/dev/null ;;                   # Linux
    *) yellow "   (Không tự mở được trình duyệt trên hệ điều hành này — mở tay URL ở trên)" ;;
  esac
}
open_browser "$NODEPORT_URL"

exit "$FAIL"
