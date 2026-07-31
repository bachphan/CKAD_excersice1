#!/bin/bash
# ============================================================================
# run-day4.sh — Day 4: Services & Networking / Storage (Lab 4.1 - 4.4)
# Chạy FULL tự động trên node master, show kết quả từng bước.
# Bám sát Day4-NetworkingStorage.md.
#
# ⚠ LAB 4.2 (Ingress): SKIP LIVE DEMO theo đúng cảnh báo trong tài liệu —
#   lần chạy trước làm agent Cilium kẹt, phải reboot node worker. Script này
#   chỉ IN phần lý thuyết + lệnh tham khảo, KHÔNG chạy cilium upgrade.
# ============================================================================

set -uo pipefail
PASS=0; FAIL=0; SKIP=0
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
yellow "║   DAY 4 — SERVICES & NETWORKING / STORAGE (Lab 4.1-4.4)  ║"
yellow "╚══════════════════════════════════════════════════════════╝"

# ============================================================================
step "LAB 4.1 — ClusterIP & NodePort (diagnose selector mismatch)"
# ============================================================================

step "4.1-B0: Cleanup"
run "Xoá resource cũ nếu sót" \
  "kubectl delete deployment lab41-backend --ignore-not-found=true; kubectl delete svc lab41-backend-svc lab41-frontend-svc --ignore-not-found=true"

step "4.1-B1: Deploy + Service CỐ Ý sai selector"
cat > /tmp/lab41.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab41-backend
  labels: {created-by: ckad-lab}
spec:
  replicas: 2
  selector:
    matchLabels: {app: lab41-backend}
  template:
    metadata:
      labels: {app: lab41-backend, created-by: ckad-lab}
    spec:
      containers:
      - name: backend
        image: nginx:1.25
        imagePullPolicy: IfNotPresent
        ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: lab41-backend-svc
  labels: {created-by: ckad-lab}
spec:
  type: ClusterIP
  selector: {app: lab41-backend-WRONG}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: lab41-frontend-svc
  labels: {created-by: ckad-lab}
spec:
  type: NodePort
  selector: {app: lab41-backend}
  ports: [{port: 80, targetPort: 80, nodePort: 30091}]
EOF
run "Apply lab41 (1 deploy + 2 svc, 1 svc SAI selector)" "kubectl apply -f /tmp/lab41.yaml"
run "Chờ 2 pod nginx Ready" "kubectl wait --for=condition=ready pod -l app=lab41-backend --timeout=90s"
check "2 pod lab41-backend Running" $?

step "4.1-B2: Chẩn đoán — so sánh Endpoints 2 Service"
run "Pod healthy?" "kubectl get pods -l app=lab41-backend"
run "Endpoints 2 Service (1 cái phải <none>)" "kubectl get endpoints lab41-backend-svc lab41-frontend-svc"
EP_WRONG=$(kubectl get endpoints lab41-backend-svc --no-headers 2>/dev/null | awk '{print $2}')
EP_RIGHT=$(kubectl get endpoints lab41-frontend-svc --no-headers 2>/dev/null | awk '{print $2}')
check "Service SAI selector: Endpoints <none>" $([ "$EP_WRONG" = "<none>" ] && echo 0 || echo 1)
check "Service ĐÚNG selector: có Endpoints" $([ "$EP_RIGHT" != "<none>" ] && [ -n "$EP_RIGHT" ] && echo 0 || echo 1)
run "Selector của Service bị sai" "kubectl describe svc lab41-backend-svc | grep -E 'Selector|Endpoints'"

step "4.1-B3: Fix selector -> Endpoints xuất hiện ngay"
run "Patch selector đúng" \
  "kubectl patch svc lab41-backend-svc -p '{\"spec\":{\"selector\":{\"app\":\"lab41-backend\"}}}'"
sleep 3   # chờ Endpoints controller cập nhật sau patch
run "Endpoints sau fix" "kubectl get endpoints lab41-backend-svc"
EP_FIXED=$(kubectl get endpoints lab41-backend-svc --no-headers 2>/dev/null | awk '{print $2}')
check "Endpoints xuất hiện sau khi fix selector" $([ "$EP_FIXED" != "<none>" ] && [ -n "$EP_FIXED" ] && echo 0 || echo 1)

step "4.1-B4: Cleanup"
run "Xoá lab41" "kubectl delete -f /tmp/lab41.yaml; rm -f /tmp/lab41.yaml"

# ============================================================================
step "LAB 4.2 — Ingress Routing — ⏭ SKIP LIVE DEMO (theo cảnh báo tài liệu)"
# ============================================================================
red "  ╔══════════════════════════════════════════════════════════╗"
red "  ║  ⚠ KHÔNG CHẠY LIVE — lần trước bật Cilium Ingress làm    ║"
red "  ║  agent Cilium trên node worker (node chạy TOÀN BỘ app)   ║"
red "  ║  kẹt >10 phút, phải REBOOT node mới khắc phục được.      ║"
red "  ║  Chi tiết: lab/lab_4.2.txt + Day4-NetworkingStorage.md   ║"
red "  ╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  📖 Lý thuyết (chỉ đọc, không chạy):"
echo "     Cluster chưa có IngressClass nào. Cilium có Ingress Controller"
echo "     nhưng KHÔNG bật mặc định. Lệnh sẽ chạy NẾU demo live:"
echo ""
echo "     \$ cilium upgrade --set ingressController.enabled=true \\"
echo "         --set ingressController.loadbalancerMode=shared \\"
echo "         --set ingressController.service.type=NodePort \\"
echo "         --set ingressController.service.insecureNodePort=30092 \\"
echo "         --set ingressController.service.secureNodePort=30093"
echo "     \$ kubectl -n kube-system rollout restart daemonset cilium"
echo ""
echo "     Nếu sự cố lặp lại (agent kẹt Init:0/6 >5 phút trên worker):"
echo "       1. cilium upgrade --set ingressController.enabled=false"
echo "       2. ssh worker 'sudo systemctl restart containerd'  (thường không đủ)"
echo "       3. ssh worker 'sudo reboot'                        (chắc chắn nhất)"
echo ""
SKIP=$((SKIP+1))
yellow "  ⏭ SKIP: Lab 4.2 — chỉ trình bày lý thuyết (anh toàn theo tài liệu)"

# ============================================================================
step "LAB 4.3 — NetworkPolicy Isolation Egress (ĐÃ PERMANENT — xem + verify)"
# ============================================================================

step "4.3-B1: Xem policy đang áp dụng"
run "Danh sách NetworkPolicy" "kubectl get networkpolicy -n $NS"
run "default-deny-egress (tóm tắt)" "kubectl describe networkpolicy default-deny-egress -n $NS | head -12"
run "allow-dns-egress (tóm tắt)" "kubectl describe networkpolicy allow-dns-egress -n $NS | head -12"
kubectl get networkpolicy default-deny-egress -n $NS --no-headers >/dev/null 2>&1
check "default-deny-egress tồn tại" $?
kubectl get networkpolicy allow-dns-egress -n $NS --no-headers >/dev/null 2>&1
check "allow-dns-egress tồn tại (quên rule này là app sập vì không resolve DNS)" $?

step "4.3-B2: App vẫn hoạt động đầy đủ (login + checkout) dưới egress deny"
RESPONSE=$(curl -s --max-time 8 -X POST "$NODEPORT/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@babymilk.local","password":"admin12345"}')
TOKEN=$(echo "$RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
check "Login admin thành công (lấy được token)" $([ -n "$TOKEN" ] && echo 0 || echo 1)
if [ -n "$TOKEN" ]; then
  CODE=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" -X POST "$NODEPORT/api/orders" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
    -d '{"items":[{"productId":3,"quantity":1}],"fullName":"Demo Day4","phone":"0900000000","address":"HCMC","paymentMethod":"cod"}')
  echo "    POST /api/orders -> HTTP $CODE"
  check "Checkout thành công (201) — toàn bộ luồng nội bộ + DNS OK" $([ "$CODE" = "201" ] && echo 0 || echo 1)
fi

step "4.3-B3: Demo NGƯỢC LẠI — backend KHÔNG ra được internet"
run "product-service gọi example.com (mong đợi TREO tới timeout)" \
  "kubectl exec -n $NS deploy/product-service -- timeout 6 wget -qO- http://example.com; echo \"exit code: \$?\""
EXIT_CODE=$(kubectl exec -n $NS deploy/product-service -- timeout 6 wget -qO- http://example.com >/dev/null 2>&1; echo $?)
check "Ra internet bị chặn (silent drop, exit code $EXIT_CODE ≠ 0)" $([ "$EXIT_CODE" != "0" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 4.4 — PVC Dynamic Provisioning (local-path StorageClass)"
# ============================================================================

step "4.4-B1: Xem StorageClass đã cài sẵn"
run "StorageClass" "kubectl get storageclass"
kubectl get storageclass local-path --no-headers >/dev/null 2>&1
check "StorageClass local-path tồn tại" $?

step "4.4-B2: Cleanup"
run "Xoá resource cũ nếu sót" \
  "kubectl delete pod lab44-writer lab44-reader --ignore-not-found=true; kubectl delete pvc lab44-dynamic-pvc --ignore-not-found=true"

step "4.4-B3: Tạo PVC (dynamic — Pending là ĐÚNG: WaitForFirstConsumer)"
cat > /tmp/lab44-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lab44-dynamic-pvc
  labels: {created-by: ckad-lab}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests: {storage: 1Gi}
EOF
run "Apply PVC" "kubectl apply -f /tmp/lab44-pvc.yaml"
run "PVC status (Pending = chờ Pod dùng, ĐÚNG thiết kế)" "kubectl get pvc lab44-dynamic-pvc"
PVC_STATUS=$(kubectl get pvc lab44-dynamic-pvc --no-headers 2>/dev/null | awk '{print $2}')
check "PVC Pending (WaitForFirstConsumer — PV chỉ tạo khi có Pod dùng)" $([ "$PVC_STATUS" = "Pending" ] && echo 0 || echo 1)

step "4.4-B4: Pod ghi data -> kích hoạt provisioning"
cat > /tmp/lab44-writer.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: lab44-writer
  labels: {created-by: ckad-lab}
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ['sh', '-c', 'echo UNIQUE-MARKER-42 > /data/proof.txt && sleep 3600']
    volumeMounts: [{name: data, mountPath: /data}]
  volumes:
  - name: data
    persistentVolumeClaim: {claimName: lab44-dynamic-pvc}
EOF
run "Apply writer pod" "kubectl apply -f /tmp/lab44-writer.yaml"
run "Chờ writer Ready" "kubectl wait --for=condition=ready pod/lab44-writer --timeout=60s"
check "Writer pod Ready" $?
run "PVC giờ đã Bound" "kubectl get pvc lab44-dynamic-pvc"
PVC_STATUS=$(kubectl get pvc lab44-dynamic-pvc --no-headers 2>/dev/null | awk '{print $2}')
check "PVC Bound sau khi có Pod dùng" $([ "$PVC_STATUS" = "Bound" ] && echo 0 || echo 1)
run "Đọc lại file vừa ghi" "kubectl exec lab44-writer -- cat /data/proof.txt"

step "4.4-B5: Test persistence CHẶT CHẼ (pod khác, chỉ đọc, KHÔNG ghi)"
run "Xoá writer (chờ xoá hẳn)" "kubectl delete pod lab44-writer --wait=true"
cat > /tmp/lab44-reader.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: lab44-reader
  labels: {created-by: ckad-lab}
spec:
  containers:
  - name: reader
    image: busybox:1.36
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts: [{name: data, mountPath: /data}]
  volumes:
  - name: data
    persistentVolumeClaim: {claimName: lab44-dynamic-pvc}
EOF
run "Apply reader pod (mới hoàn toàn)" "kubectl apply -f /tmp/lab44-reader.yaml"
run "Chờ reader Ready" "kubectl wait --for=condition=ready pod/lab44-reader --timeout=60s"
check "Reader pod Ready" $?
run "Reader đọc file (mong đợi UNIQUE-MARKER-42)" "kubectl exec lab44-reader -- cat /data/proof.txt"
MARKER=$(kubectl exec lab44-reader -- cat /data/proof.txt 2>/dev/null)
check "Data còn nguyên qua pod mới (persistence THẬT)" $([ "$MARKER" = "UNIQUE-MARKER-42" ] && echo 0 || echo 1)

step "4.4-B6: Cleanup"
run "Xoá reader + PVC" "kubectl delete pod lab44-reader; kubectl delete pvc lab44-dynamic-pvc"
sleep 5
run "PV tự dọn (reclaimPolicy: Delete)" "kubectl get pv | grep lab44 || echo 'PV đã tự dọn sạch'"
run "Dọn file tạm" "rm -f /tmp/lab44-pvc.yaml /tmp/lab44-writer.yaml /tmp/lab44-reader.yaml"

# ============================================================================
step "VERIFY CUỐI DAY 4 — app thật không bị ảnh hưởng"
# ============================================================================
run "Pod babymilk" "kubectl get pods -n $NS"
READY_COUNT=$(kubectl get pods -n $NS --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "App vẫn trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)
run "Không còn resource demo sót" \
  "kubectl get pod,svc,deployment,pvc -l created-by=ckad-lab --all-namespaces"

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ DAY 4 HOÀN THÀNH — $PASS CHECK PASS, $SKIP LAB SKIP (4.2 Ingress, theo cảnh báo)"
else
  red "❌ DAY 4: $FAIL/$((PASS+FAIL)) CHECK FAIL — xem log phía trên"
fi
echo "============================================================"
