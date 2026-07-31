#!/bin/bash
# ============================================================================
# run-day5.sh — Day 5: Observability & Exam Prep (Lab 5.1 - 5.4)
# Chạy FULL tự động trên node master, show kết quả từng bước.
# Bám sát Day5-ObservabilityExamPrep.md — an toàn, Lab 5.2 chỉ đọc.
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
yellow "║   DAY 5 — OBSERVABILITY & EXAM PREP (Lab 5.1-5.4)        ║"
yellow "╚══════════════════════════════════════════════════════════╝"

# ============================================================================
step "LAB 5.1 — Self-Healing App (startupProbe + readinessProbe file-based)"
# ============================================================================

step "5.1-B0: Cleanup"
run "Xoá pod cũ nếu sót" "kubectl delete pod lab51-selfheal --ignore-not-found=true"

step "5.1-B1: Pod mô phỏng app khởi động CHẬM 20s"
cat > /tmp/lab51-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: lab51-selfheal
  labels: {created-by: ckad-lab}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      echo "container started, simulating slow init 20s..."
      sleep 20
      touch /tmp/ready
      echo "app ready, now serving"
      while true; do sleep 5; done
    startupProbe:
      exec: {command: ['sh', '-c', 'test -f /tmp/ready']}
      periodSeconds: 5
      failureThreshold: 10
    readinessProbe:
      exec: {command: ['sh', '-c', 'test -f /tmp/ready']}
      periodSeconds: 5
    livenessProbe:
      exec: {command: ['sh', '-c', 'test -f /tmp/ready']}
      periodSeconds: 10
EOF
run "Apply pod lab51-selfheal" "kubectl apply -f /tmp/lab51-pod.yaml"

step "5.1-B2: Theo dõi tiến trình (0/1 một lúc rồi tự lên 1/1 — KHÔNG bị giết giữa chừng)"
for i in 1 2 3 4 5 6 7 8; do
  kubectl get pod lab51-selfheal --no-headers 2>/dev/null | sed 's/^/    /'
  READY_NOW=$(kubectl get pod lab51-selfheal --no-headers 2>/dev/null | awk '{print $2}')
  [ "$READY_NOW" = "1/1" ] && break
  sleep 5
done
run "Chờ pod 1/1 (tối đa 60s)" "kubectl wait --for=condition=ready pod/lab51-selfheal --timeout=60s"
check "Pod tự lên 1/1 sau ~20s khởi động chậm" $?

step "5.1-B3: Verify events — startupProbe fail vài lần nhưng KHÔNG có Killing"
run "Events (tail)" "kubectl describe pod lab51-selfheal | tail -12"
kubectl describe pod lab51-selfheal 2>/dev/null | grep -q "Startup probe failed"
check "Có event 'Startup probe failed' (probe hoạt động)" $?
kubectl describe pod lab51-selfheal 2>/dev/null | grep -q "Killing"
check "KHÔNG có event 'Killing' (failureThreshold=10 còn dư quota chờ)" $([ $? -ne 0 ] && echo 0 || echo 1)

step "5.1-B4: Cleanup"
run "Xoá pod" "kubectl delete pod lab51-selfheal; rm -f /tmp/lab51-pod.yaml"

# ============================================================================
step "LAB 5.2 — CLI Observability (CHỈ ĐỌC trên pod thật babymilk)"
# ============================================================================

step "5.2-B1: Log container hiện tại"
run "logs deploy/product-service (20 dòng cuối)" "kubectl logs -n $NS deploy/product-service --tail=20"

step "5.2-B2: Log lần chạy TRƯỚC (--previous, chỉ có nếu container từng restart)"
run "Pod + số lần RESTARTS" "kubectl get pods -n $NS"
RESTART_POD=$(kubectl get pods -n $NS --no-headers | awk '$4>0 {print $1; exit}')
if [ -n "$RESTART_POD" ]; then
  run "Pod $RESTART_POD có RESTARTS>0 -> xem --previous" "kubectl logs -n $NS $RESTART_POD --previous --tail=15"
  check "Đọc được log --previous" $?
else
  yellow "  (Không pod nào có RESTARTS>0 — bỏ qua --previous, đây là trạng thái tốt)"
fi

step "5.2-B3: Events — timeline tổng quan (xem ĐẦU TIÊN khi debug)"
run "events theo thứ tự thởi gian" "kubectl get events -n $NS --sort-by=.lastTimestamp | tail -15"

step "5.2-B4: Resource usage real-time (metrics-server)"
run "top pods" "kubectl top pods -n $NS"
check "kubectl top pods đọc được metrics" $?
run "top nodes" "kubectl top nodes"
check "kubectl top nodes đọc được metrics" $?

# ============================================================================
step "LAB 5.3 — Broken YAML Triage (CẢ 3 LỖI cùng lúc, sửa từng cái)"
# ============================================================================

step "5.3-B0: Cleanup"
run "Xoá resource cũ nếu sót" "kubectl delete -f /tmp/lab53-broken.yaml --ignore-not-found=true 2>/dev/null || true"

step "5.3-B1: Deploy manifest với 3 LỖI (image sai + selector sai + targetPort sai)"
cat > /tmp/lab53-broken.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab53-app
  labels: {created-by: ckad-lab}
spec:
  replicas: 1
  selector:
    matchLabels: {app: lab53-app}
  template:
    metadata:
      labels: {app: lab53-app, created-by: ckad-lab}
    spec:
      containers:
      - name: app
        image: docker.io/babymilk/frontend:1.0-typo
        imagePullPolicy: Never
        ports: [{containerPort: 4000}]
        env: [{name: PORT, value: "4000"}]
---
apiVersion: v1
kind: Service
metadata:
  name: lab53-svc
  labels: {created-by: ckad-lab}
spec:
  type: NodePort
  selector: {app: lab53-app-WRONG}
  ports: [{port: 80, targetPort: 9999, nodePort: 30099}]
EOF
run "Apply manifest lỗi" "kubectl apply -f /tmp/lab53-broken.yaml"
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.56.102:30099/ 2>/dev/null)
check "Không truy cập được (HTTP $CODE) — đúng vì 3 lỗi" $([ "$CODE" != "200" ] && echo 0 || echo 1)

step "5.3-B2: Triage lỗi 1 — Pod có chạy được không? (image sai)"
sleep 5
run "Pod status" "kubectl get pods -l app=lab53-app"
run "Lý do" "kubectl describe pod -l app=lab53-app | grep -E 'Image:|Reason' | head -5"
kubectl get pods -l app=lab53-app --no-headers 2>/dev/null | grep -q "ErrImageNeverPull"
check "Phát hiện lỗi 1: ErrImageNeverPull (tag 1.0-typo không tồn tại)" $?
run "Sửa image 1.0-typo -> 1.0" "sed -i 's/1.0-typo/1.0/' /tmp/lab53-broken.yaml && kubectl apply -f /tmp/lab53-broken.yaml"
run "Chờ Deployment available (KHÔNG wait theo pod — pod lỗi cũ còn sót sẽ làm wait fail oan)" \
  "kubectl wait --for=condition=available deployment/lab53-app --timeout=90s"
check "Deployment available sau khi sửa image" $?
AVAIL=$(kubectl get deploy lab53-app -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
check "Có đúng 1 replica available" $([ "$AVAIL" = "1" ] && echo 0 || echo 1)

step "5.3-B3: Triage lỗi 2 — Service có thấy pod không? (selector sai)"
run "Endpoints (vẫn <none> dù pod Running)" "kubectl get endpoints lab53-svc"
EP=$(kubectl get endpoints lab53-svc --no-headers 2>/dev/null | awk '{print $2}')
check "Phát hiện lỗi 2: Endpoints <none> (selector lab53-app-WRONG)" $([ "$EP" = "<none>" ] && echo 0 || echo 1)
run "Soi label pod vs selector svc" \
  "kubectl get pods -l app=lab53-app --show-labels; kubectl get svc lab53-svc -o jsonpath='{.spec.selector}'; echo"
run "Sửa selector" "sed -i 's/app: lab53-app-WRONG/app: lab53-app/' /tmp/lab53-broken.yaml && kubectl apply -f /tmp/lab53-broken.yaml"
sleep 3   # chờ Endpoints controller cập nhật
EP=$(kubectl get endpoints lab53-svc --no-headers 2>/dev/null | awk '{print $2}')
check "Endpoints xuất hiện sau khi sửa selector" $([ "$EP" != "<none>" ] && [ -n "$EP" ] && echo 0 || echo 1)

step "5.3-B4: Triage lỗi 3 — Đúng port chưa? (targetPort sai)"
run "Port của svc vs port thật của container" \
  "kubectl get svc lab53-svc -o jsonpath='{.spec.ports}'; echo; kubectl get pod -l app=lab53-app -o jsonpath='{.items[0].spec.containers[0].ports}'; echo"
check "Phát hiện lỗi 3: targetPort=9999 nhưng container nghe 4000" 0
run "Sửa targetPort 9999 -> 4000" "sed -i 's/targetPort: 9999/targetPort: 4000/' /tmp/lab53-broken.yaml && kubectl apply -f /tmp/lab53-broken.yaml"
sleep 3
run "Test end-to-end qua NodePort 30099" "curl -s --max-time 5 http://192.168.56.102:30099/healthz -w '\nHTTP: %{http_code}\n'"
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.56.102:30099/healthz)
check "Sửa xong cả 3 lỗi -> healthz trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)

step "5.3-B5: Cleanup"
run "Xoá lab53" "kubectl delete -f /tmp/lab53-broken.yaml; rm -f /tmp/lab53-broken.yaml"

# ============================================================================
step "LAB 5.4 — Helm Deploy & Rollback (RIÊNG BIỆT, không liên quan Kustomize)"
# ============================================================================

step "5.4-B0: Cleanup"
run "Gỡ release cũ nếu sót" "helm uninstall lab54-nginx 2>/dev/null || true"

step "5.4-B1: Install với value override (KHÔNG set image.tag — Bitnami chỉ free tag latest)"
# helm hay fail chập chờn do NAT chậm khi tải chart -> retry tối đa 3 lần
helm_retry() { for i in 1 2 3; do "$@" && return 0; echo "    (helm thất bại lần $i, thử lại sau 10s...)"; sleep 10; done; return 1; }
run "helm install lab54-nginx (có retry)" \
  "helm_retry helm install lab54-nginx bitnami/nginx --set replicaCount=1 --set resources.requests.cpu=50m --set resources.requests.memory=32Mi --set resources.limits.cpu=100m --set resources.limits.memory=64Mi --set service.type=ClusterIP"
check "helm install thành công" $?

step "5.4-B2: Verify install"
run "Chờ pod Ready" "kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=lab54-nginx --timeout=120s"
check "Pod nginx Ready" $?
run "Pod + helm status" "kubectl get pods -l app.kubernetes.io/instance=lab54-nginx; helm status lab54-nginx | head -8"

step "5.4-B3: Upgrade (replicaCount 1 -> 2)"
run "helm upgrade (có retry)" \
  "helm_retry helm upgrade lab54-nginx bitnami/nginx --set replicaCount=2 --set resources.requests.cpu=50m --set resources.requests.memory=32Mi --set resources.limits.cpu=100m --set resources.limits.memory=64Mi --set service.type=ClusterIP"
check "helm upgrade thành công" $?
run "Chờ 2 pod Ready" "kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=lab54-nginx --timeout=120s"
N=$(kubectl get pods -l app.kubernetes.io/instance=lab54-nginx --no-headers 2>/dev/null | grep -c Running)
check "Đủ 2 pod sau upgrade" $([ "$N" = "2" ] && echo 0 || echo 1)
run "helm history" "helm history lab54-nginx"

step "5.4-B4: Rollback về revision 1"
run "helm rollback" "helm rollback lab54-nginx 1"
check "helm rollback thành công" $?
run "Chờ về 1 pod" "sleep 5; kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=lab54-nginx --timeout=120s"
N=$(kubectl get pods -l app.kubernetes.io/instance=lab54-nginx --no-headers 2>/dev/null | grep -c Running)
check "Về đúng 1 pod sau rollback" $([ "$N" = "1" ] && echo 0 || echo 1)
run "helm history (chú ý: rollback tạo REVISION MỚI, không quay ngược số)" "helm history lab54-nginx"

step "5.4-B5: Cleanup"
run "helm uninstall" "helm uninstall lab54-nginx"

# ============================================================================
step "VERIFY CUỐI DAY 5 — app thật không bị ảnh hưởng"
# ============================================================================
run "Pod babymilk" "kubectl get pods -n $NS"
READY_COUNT=$(kubectl get pods -n $NS --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "App vẫn trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)
run "Không còn resource demo sót" \
  "kubectl get pod,svc,deployment -l created-by=ckad-lab --all-namespaces; helm list -a | grep lab54 || echo '(không còn helm release demo)'"

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ DAY 5 HOÀN THÀNH — TẤT CẢ $PASS CHECK PASS"
else
  red "❌ DAY 5: $FAIL/$((PASS+FAIL)) CHECK FAIL — xem log phía trên"
fi
echo "============================================================"

exit "$FAIL"
