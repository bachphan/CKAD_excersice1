#!/bin/bash
# ============================================================================
# run-day2.sh — Day 2: Application Deployment (Lab 2.1 - 2.4)
# Chạy FULL tự động trên node master, show kết quả từng bước.
# Bám sát Day2-ApplicationDeployment.md — ĐỤNG APP THẬT babymilk (an toàn,
# mọi thay đổi đều revert về baseline cuối script).
#
# ĐIỀU CHỈNH so với tài liệu gốc (cho khớp cluster hiện tại):
#   - Baseline image hiện tại: product-service:2.3 (tài liệu gốc ghi :2.1 — đã bump 2 lần:
#     :2.2 graceful shutdown, :2.3 thêm ảnh sản phẩm, xem mục 17/20 work_done.md)
#   - Lab 2.3: scale lên 2 thay vì 10 — vì giờ mỗi pod có 3 container +
#     ResourceQuota limits.cpu (1800m) chỉ còn dư ~350m (xem giải thích trong script)
# ============================================================================

set -uo pipefail
PASS=0; FAIL=0
green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan()   { echo -e "\033[36m$1\033[0m"; }

step() { echo ""; yellow "════════════════════════════════════════════════════════════"; yellow "  $1"; yellow "════════════════════════════════════════════════════════════"; }

check() {
  if [ "$2" -eq 0 ]; then green "  ✅ PASS: $1"; PASS=$((PASS+1));
  else red "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); fi
}

run() {
  cyan "  ▶ $1"
  echo "    \$ $2"
  eval "$2" 2>&1 | sed 's/^/    /'
  return ${PIPESTATUS[0]}
}

NS="babymilk"
NODEPORT="http://192.168.56.102:30080"

yellow "╔══════════════════════════════════════════════════════════╗"
yellow "║   DAY 2 — APPLICATION DEPLOYMENT (Lab 2.1-2.4)           ║"
yellow "║   ⚠ Đụng app thật babymilk — mọi thay đổi đều revert     ║"
yellow "╚══════════════════════════════════════════════════════════╝"

step "PRE-CHECK: app thật đang khoẻ"
run "Pod babymilk" "kubectl get pods -n $NS"
READY_COUNT=$(kubectl get pods -n $NS --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready trước khi bắt đầu" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "Frontend healthz 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 2.1 — Rolling Update & Rollback (product-service)"
# ============================================================================

step "2.1-B0: Xác nhận baseline image"
CUR_IMG=$(kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "    Baseline hiện tại: $CUR_IMG"
check "Baseline là product-service:2.3" $([ "$CUR_IMG" = "docker.io/babymilk/product-service:2.3" ] && echo 0 || echo 1)

step "2.1-B1: Rolling update THẬT xuống :2.2 (bản cũ hơn, vẫn còn trên worker)"
run "kubectl set image -> :2.2" \
  "kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:2.2 -n $NS"
run "Theo dõi rollout" "kubectl rollout status deployment/product-service -n $NS --timeout=120s"
check "Rollout :2.2 hoàn tất" $?

step "2.1-B2: Verify version (exec loopback — /healthz không nằm trong NetworkPolicy)"
yellow "  📌 Lưu ý: từ khi có ambassador pattern, app nghe ở 127.0.0.1:4101,"
yellow "     ambassador-nginx CHỈ bind pod IP:4001 (localhost:4001 từ app bị từ chối)"
run "healthz từ trong pod (port app thật 4101)" "kubectl exec -n $NS deploy/product-service -- wget -qO- http://localhost:4101/healthz"
kubectl exec -n $NS deploy/product-service -- wget -qO- http://localhost:4101/healthz 2>/dev/null | grep -q '"version":"2.1"'
check "healthz báo version 2.1 (chuỗi hardcode trong code, không đổi theo tag)" $?

step "2.1-B3: Rolling update NGƯỢC LÊN lại :2.3"
run "kubectl set image -> :2.3" \
  "kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:2.3 -n $NS"
run "Theo dõi rollout" "kubectl rollout status deployment/product-service -n $NS --timeout=120s"
check "Rollout :2.3 hoàn tất" $?
kubectl exec -n $NS deploy/product-service -- wget -qO- http://localhost:4101/healthz 2>/dev/null | grep -q '"status":"ok"'
check "healthz trả ok (lưu ý: version field vẫn ghi 2.1 — không đổi theo image tag)" $?

step "2.1-B4: MÔ PHỎNG deploy lỗi (tag không tồn tại) — app KHÔNG downtime"
run "set image -> :bad-tag" \
  "kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:bad-tag -n $NS"
run "rollout status (mong đợi TIMEOUT — đây là hành vi ĐÚNG)" \
  "kubectl rollout status deployment/product-service -n $NS --timeout=20s"
if [ $? -ne 0 ]; then green "  ✅ PASS: Rollout bị kẹt đúng như mong đợi (image không pull được)"; PASS=$((PASS+1)); else red "  ❌ FAIL: Đáng lẽ rollout phải bị kẹt"; FAIL=$((FAIL+1)); fi
run "Pod: mới ErrImageNeverPull, CŨ vẫn Running" "kubectl get pods -n $NS -l app=product-service"
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/api/products")
check "APP VẪN PHỤC VỤ bình thường giữa deploy lỗi (catalog 200)" $([ "$CODE" = "200" ] && echo 0 || echo 1)

step "2.1-B5: Rollback"
run "Lịch sử rollout" "kubectl rollout history deployment/product-service -n $NS"
run "rollout undo (quay về revision liền trước = :2.3)" "kubectl rollout undo deployment/product-service -n $NS"
run "Theo dõi rollback" "kubectl rollout status deployment/product-service -n $NS --timeout=120s"
check "Rollback hoàn tất" $?

step "2.1-B6: Verify cuối"
CUR_IMG=$(kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "    Image sau rollback: $CUR_IMG"
check "Image về đúng :2.3" $([ "$CUR_IMG" = "docker.io/babymilk/product-service:2.3" ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/api/products")
check "Catalog trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 2.2 — Blue/Green Switch (frontend) — BẮT BUỘC revert đủ Bước 5"
# ============================================================================

step "2.2-B0: Cleanup phiên demo trước nếu bị bỏ dở"
run "Dọn green + gỡ patch version cũ" \
  "kubectl delete deployment frontend-green -n $NS --ignore-not-found=true; kubectl delete configmap frontend-green-banner -n $NS --ignore-not-found=true; kubectl patch svc frontend -n $NS --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/selector/version\"}]' 2>/dev/null || true; kubectl patch deployment frontend -n $NS --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/template/metadata/labels/version\"}]' 2>/dev/null || true"

step "2.2-B1: Gắn nhãn BLUE cho frontend đang chạy"
run "Thêm label version=blue vào Deployment frontend" \
  "kubectl patch deployment frontend -n $NS --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/metadata/labels/version\",\"value\":\"blue\"}]'"
run "Service frontend select version=blue" \
  "kubectl patch svc frontend -n $NS -p '{\"spec\":{\"selector\":{\"app\":\"frontend\",\"version\":\"blue\"}}}'"
run "Chờ frontend rollout xong" "kubectl rollout status deployment/frontend -n $NS --timeout=120s"
check "Frontend (blue) rollout xong" $?
sleep 5
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "App vẫn 200 sau khi gắn blue" $([ "$CODE" = "200" ] && echo 0 || echo 1)

step "2.2-B2: Tạo bản GREEN (cùng image, banner khác qua ConfigMap override)"
cat > /tmp/frontend-green-index.html <<'HTMLEOF'
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8" />
  <title>BabyMilk Shop [GREEN]</title>
  <link rel="stylesheet" href="/css/style.css" />
</head>
<body>
  <div style="background:#16a34a;color:white;text-align:center;padding:10px;font-weight:bold;">
    🟢 GREEN DEPLOYMENT — Live demo
  </div>
  <header class="site-header"><div class="container header-inner">
    <a href="#/" class="logo">🍼 BabyMilk<span>Shop</span></a>
    <nav id="main-nav" class="main-nav"></nav>
  </div></header>
  <main id="app" class="container"></main>
  <footer class="site-footer"><div class="container">Demo học tập.</div></footer>
  <div id="toast-root"></div>
  <script type="module" src="/js/app.js"></script>
</body>
</html>
HTMLEOF
run "Tạo ConfigMap banner green" \
  "kubectl create configmap frontend-green-banner -n $NS --from-file=index.html=/tmp/frontend-green-index.html"
cat > /tmp/frontend-green.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-green
  namespace: babymilk
  labels:
    created-by: ckad-lab
spec:
  replicas: 1
  selector:
    matchLabels: {app: frontend, version: green}
  template:
    metadata:
      labels: {app: frontend, version: green}
    spec:
      containers:
      - name: frontend
        image: docker.io/babymilk/frontend:1.0
        imagePullPolicy: Never
        ports: [{containerPort: 4000}]
        env:
        - {name: PORT, value: "4000"}
        - {name: PRODUCT_SERVICE_URL, valueFrom: {configMapKeyRef: {name: babymilk-config, key: PRODUCT_SERVICE_URL}}}
        - {name: USER_SERVICE_URL, valueFrom: {configMapKeyRef: {name: babymilk-config, key: USER_SERVICE_URL}}}
        - {name: ORDER_SERVICE_URL, valueFrom: {configMapKeyRef: {name: babymilk-config, key: ORDER_SERVICE_URL}}}
        - {name: UPSTREAM_TIMEOUT_MS, valueFrom: {configMapKeyRef: {name: babymilk-config, key: UPSTREAM_TIMEOUT_MS}}}
        resources:
          requests: {cpu: 50m, memory: 32Mi}
          limits: {cpu: 100m, memory: 64Mi}
        readinessProbe: {httpGet: {path: /healthz, port: 4000}, initialDelaySeconds: 3, periodSeconds: 5}
        volumeMounts:
        - {name: green-banner, mountPath: /app/public/index.html, subPath: index.html}
      volumes:
      - name: green-banner
        configMap: {name: frontend-green-banner}
EOF
run "Apply Deployment frontend-green" "kubectl apply -f /tmp/frontend-green.yaml"
run "Chờ green Available" "kubectl wait --for=condition=available deployment/frontend-green -n $NS --timeout=90s"
check "frontend-green Available" $?

step "2.2-B3: FLIP sang GREEN trên URL demo thật (:30080)"
run "Patch Service -> green" \
  "kubectl patch svc frontend -n $NS -p '{\"spec\":{\"selector\":{\"app\":\"frontend\",\"version\":\"green\"}}}'"
sleep 5
GREEN=$(curl -s --max-time 5 "$NODEPORT/" | grep -o "GREEN DEPLOYMENT")
echo "    curl / -> tìm thấy: '$GREEN'"
check "Trình duyệt thấy banner GREEN (traffic đã flip, KHÔNG downtime)" $([ "$GREEN" = "GREEN DEPLOYMENT" ] && echo 0 || echo 1)

step "2.2-B4: FLIP về BLUE"
run "Patch Service -> blue" \
  "kubectl patch svc frontend -n $NS -p '{\"spec\":{\"selector\":{\"app\":\"frontend\",\"version\":\"blue\"}}}'"
sleep 5
GREEN=$(curl -s --max-time 5 "$NODEPORT/" | grep -o "GREEN DEPLOYMENT")
check "Đã về blue (không còn thấy GREEN)" $([ -z "$GREEN" ] && echo 0 || echo 1)

step "2.2-B5: BẮT BUỘC — trả về đúng trạng thái gốc"
run "Xoá green deployment + configmap" \
  "kubectl delete deployment frontend-green -n $NS; kubectl delete configmap frontend-green-banner -n $NS"
run "Gỡ version khỏi Service selector" \
  "kubectl patch svc frontend -n $NS --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/selector/version\"}]'"
run "Gỡ version khỏi Deployment template" \
  "kubectl patch deployment frontend -n $NS --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/template/metadata/labels/version\"}]'"
run "Chờ frontend ổn định lại" "kubectl rollout status deployment/frontend -n $NS --timeout=120s"
sleep 5
run "Pod frontend + labels" "kubectl get pods -n $NS -l app=frontend --show-labels"
SEL=$(kubectl get svc frontend -n $NS -o jsonpath='{.spec.selector}')
echo "    Service selector: $SEL"
check "Service selector về đúng {app:frontend}" $([ "$SEL" = '{"app":"frontend"}' ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "healthz 200 sau revert" $([ "$CODE" = "200" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 2.3 — Scale & HPA (product-service)"
# ============================================================================
yellow "  ⚠ ĐIỀU CHỈNH: tài liệu gốc scale lên 10. Hiện tại mỗi pod = 3 container"
yellow "    + ResourceQuota limits.cpu=1800m (đang dùng ~1450m) chỉ đủ chỗ ~1 pod"
yellow "    -> scale lên 2 để demo an toàn, KHÔNG phá quota (bài học cộng gộp Lab 3.4!)"

step "2.3-B0: Xác nhận baseline HPA (PERMANENT: min1/max3/target50%)"
run "HPA hiện tại" "kubectl get hpa product-service-hpa -n $NS"
HPA_MAX=$(kubectl get hpa product-service-hpa -n $NS -o jsonpath='{.spec.maxReplicas}')
check "HPA maxReplicas=3 đúng baseline" $([ "$HPA_MAX" = "3" ] && echo 0 || echo 1)

step "2.3-B1: Xem quota còn dư bao nhiêu (lý do chỉ scale lên 2)"
run "ResourceQuota usage" "kubectl describe resourcequota babymilk-quota -n $NS | sed -n '1,14p'"

step "2.3-B2: Scale lên 2 — PHẢI patch HPA minReplicas=2 trước"
yellow "  📌 Bài học thật vừa phát hiện: nếu scale tay mà HPA min=1, HPA sẽ tự"
yellow "     KÉO VỀ 1 ngay sau đó (CPU thấp) — scale tay không bao giờ thắng HPA."
yellow "     -> Tạm patch minReplicas=2, demo xong revert (baseline min=1/max3/50%)."
run "Patch HPA minReplicas=2 (TẠM, sẽ revert)" \
  "kubectl patch hpa product-service-hpa -n $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/minReplicas\",\"value\":2}]'"
check "Patch HPA min=2 thành công" $?
run "scale -> 2 replicas" "kubectl scale deployment/product-service --replicas=2 -n $NS"
run "Chờ rollout" "kubectl rollout status deployment/product-service -n $NS --timeout=120s"
check "Scale lên 2 thành công" $?
sleep 5
run "Deployment + pod" "kubectl get deployment product-service -n $NS; kubectl get pods -n $NS -l app=product-service"
N=$(kubectl get pods -n $NS -l app=product-service --no-headers 2>/dev/null | grep -c Running)
check "Đủ 2 pod Running" $([ "$N" = "2" ] && echo 0 || echo 1)

step "2.3-B3: Tài nguyên node lúc tải cao (Requests vs Limits)"
run "Allocated resources của worker" "kubectl describe node k8s-worker1 | grep -A8 'Allocated resources'"

step "2.3-B4: BẮT BUỘC — trả về baseline (scale 1 + HPA min=1/max3/50%)"
run "scale về 1" "kubectl scale deployment/product-service --replicas=1 -n $NS"
run "Revert HPA minReplicas về 1" \
  "kubectl patch hpa product-service-hpa -n $NS --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/minReplicas\",\"value\":1}]'"
run "Chờ rollout" "kubectl rollout status deployment/product-service -n $NS --timeout=120s"
HPA_MAX=$(kubectl get hpa product-service-hpa -n $NS -o jsonpath='{.spec.maxReplicas}')
check "HPA vẫn maxReplicas=3 (không bị đụng)" $([ "$HPA_MAX" = "3" ] && echo 0 || echo 1)
HPA_MIN=$(kubectl get hpa product-service-hpa -n $NS -o jsonpath='{.spec.minReplicas}')
check "HPA minReplicas về 1 (đã revert)" $([ "$HPA_MIN" = "1" ] && echo 0 || echo 1)
sleep 5
N=$(kubectl get pods -n $NS -l app=product-service --no-headers 2>/dev/null | grep -c Running)
check "Pod về đúng 1" $([ "$N" = "1" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 2.4 — Kustomize Overlay (CHỈ XEM — cách deploy chính thức)"
# ============================================================================

step "2.4-B1: Xem cấu trúc k8s/ trên master"
run "Cây thư mục manifest" "cd ~/babymilk-k8s && find . -type f -name '*.yaml' | sort"

step "2.4-B2: Render thử prod overlay (không apply)"
run "kubectl kustomize overlays/prod (50 dòng đầu)" "cd ~/babymilk-k8s && kubectl kustomize overlays/prod | head -50"

step "2.4-B3: Chứng minh prod overlay = 100% cluster đang chạy (diff = 0)"
run "kubectl diff -k overlays/prod" "cd ~/babymilk-k8s && kubectl diff -k overlays/prod; echo \"(exit code: \$?)\""
DRIFT=$(cd ~/babymilk-k8s && kubectl diff -k overlays/prod 2>&1 | wc -l)
check "diff = 0 dòng (file git khớp tuyệt đối cluster, không drift)" $([ "$DRIFT" = "0" ] && echo 0 || echo 1)

step "2.4-B4: Xem overlay dev (chỉ render, KHÔNG apply — không đủ tài nguyên)"
run "Điểm khác biệt của dev" \
  "cd ~/babymilk-k8s && kubectl kustomize overlays/dev | grep -E '^kind:|name: babymilk-dev|nodePort|maxReplicas' | head -20"

# ============================================================================
step "VERIFY CUỐI DAY 2 — app thật về đúng baseline"
# ============================================================================
sleep 5
run "Pod babymilk" "kubectl get pods -n $NS"
READY_COUNT=$(kubectl get pods -n $NS --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
DRIFT=$(cd ~/babymilk-k8s && kubectl diff -k overlays/prod 2>&1 | wc -l)
check "kubectl diff -k = 0 (không còn drift sau demo)" $([ "$DRIFT" = "0" ] && echo 0 || echo 1)
SEL=$(kubectl get svc frontend -n $NS -o jsonpath='{.spec.selector}')
check "Service frontend selector {app:frontend}" $([ "$SEL" = '{"app":"frontend"}' ] && echo 0 || echo 1)
HPA_MAX=$(kubectl get hpa product-service-hpa -n $NS -o jsonpath='{.spec.maxReplicas}')
check "HPA maxReplicas=3" $([ "$HPA_MAX" = "3" ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/api/products")
check "Catalog trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)
run "Dọn file tạm" "rm -f /tmp/frontend-green-index.html /tmp/frontend-green.yaml"

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ DAY 2 HOÀN THÀNH — TẤT CẢ $PASS CHECK PASS, CLUSTER VỀ BASELINE"
else
  red "❌ DAY 2: $FAIL/$((PASS+FAIL)) CHECK FAIL — CHẠY restore-to-baseline.sh NGAY"
fi
echo "============================================================"
