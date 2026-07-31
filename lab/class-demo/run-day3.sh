#!/bin/bash
# ============================================================================
# run-day3.sh — Day 3: Environment, Configuration & Security (Lab 3.1 - 3.4)
# Chạy FULL tự động trên node master, show kết quả từng bước.
# Bám sát Day3-SecurityConfig.md — 3.1/3.3 demo tạm, 3.2/3.4 đã PERMANENT (chỉ xem).
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
yellow "║   DAY 3 — ENVIRONMENT, CONFIGURATION & SECURITY          ║"
yellow "║   (Lab 3.1-3.4)                                          ║"
yellow "╚══════════════════════════════════════════════════════════╝"

# ============================================================================
step "LAB 3.1 — ConfigMap & Secret Injection (namespace default, demo tạm)"
# ============================================================================

step "3.1-B0: Cleanup"
run "Xoá resource cũ nếu sót" \
  "kubectl delete pod injection-demo --ignore-not-found=true; kubectl delete secret demo-secret --ignore-not-found=true; kubectl delete configmap demo-config --ignore-not-found=true"

step "3.1-B1: Tạo Secret từ file, ConfigMap từ literal"
run "Secret từ file" \
  "echo 'secret-from-file-value' > /tmp/api-key.txt && kubectl create secret generic demo-secret --from-file=apiKey=/tmp/api-key.txt"
run "ConfigMap từ literal (gọi --from-literal 2 lần riêng biệt)" \
  "kubectl create configmap demo-config --from-literal=greeting=Hello --from-literal=env=lab"

step "3.1-B2: Pod inject CẢ 2 kiểu (Secret -> env var, ConfigMap -> volume)"
cat > /tmp/injection-demo.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: injection-demo
  labels:
    created-by: ckad-lab
spec:
  containers:
  - name: demo
    image: busybox:1.36
    command: ['sh', '-c', 'sleep 3600']
    env:
    - name: API_KEY
      valueFrom:
        secretKeyRef: {name: demo-secret, key: apiKey}
    volumeMounts:
    - name: config-vol
      mountPath: /etc/demo-config
  volumes:
  - name: config-vol
    configMap:
      name: demo-config
EOF
run "Apply pod injection-demo" "kubectl apply -f /tmp/injection-demo.yaml"
kubectl wait --for=condition=ready pod/injection-demo --timeout=60s >/dev/null 2>&1
check "Pod injection-demo Ready" $?

step "3.1-B3: Verify"
run "Secret qua env var" "kubectl exec injection-demo -- env | grep API_KEY"
kubectl exec injection-demo -- env 2>/dev/null | grep -q "API_KEY=secret-from-file-value"
check "API_KEY đúng giá trị từ file secret" $?
run "ConfigMap qua volume: mỗi key = 1 FILE" "kubectl exec injection-demo -- ls /etc/demo-config"
run "Nội dung file greeting" "kubectl exec injection-demo -- cat /etc/demo-config/greeting"
kubectl exec injection-demo -- cat /etc/demo-config/greeting 2>/dev/null | grep -q "Hello"
check "ConfigMap greeting=Hello đọc được từ file" $?

step "3.1-B4: Cleanup"
run "Dọn pod + secret + configmap" \
  "kubectl delete pod injection-demo; kubectl delete secret demo-secret; kubectl delete configmap demo-config; rm -f /tmp/injection-demo.yaml /tmp/api-key.txt"

# ============================================================================
step "LAB 3.2 — Security Context Lockdown (ĐÃ PERMANENT — chỉ xem + verify thật)"
# ============================================================================

step "3.2-B1: Xem cấu hình đang áp dụng thật"
run "securityContext cấp POD" \
  "kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.securityContext}'; echo"
run "securityContext cấp CONTAINER (app)" \
  "kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.containers[0].securityContext}'; echo"
PODSC=$(kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}')
CONTSC=$(kubectl get deploy product-service -n $NS -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}')
check "runAsNonRoot=true (pod level)" $([ "$PODSC" = "true" ] && echo 0 || echo 1)
check "readOnlyRootFilesystem=true (container level)" $([ "$CONTSC" = "true" ] && echo 0 || echo 1)

step "3.2-B2: Chứng minh THẬT non-root + read-only filesystem"
run "id trong container app (mong đợi uid=1000)" "kubectl exec -n $NS deploy/product-service -- id"
kubectl exec -n $NS deploy/product-service -- id 2>/dev/null | grep -q "uid=1000"
check "Container chạy uid=1000 (node), không phải root" $?
run "Thử ghi file vào root fs (mong đợi LỖI Read-only)" \
  "kubectl exec -n $NS deploy/product-service -- touch /test-write"
if [ $? -ne 0 ]; then green "  ✅ PASS: Ghi bị chặn đúng (Read-only file system)"; PASS=$((PASS+1)); else red "  ❌ FAIL: Đáng lẽ phải bị chặn ghi"; FAIL=$((FAIL+1)); fi

step "3.2-B3: App vẫn hoạt động 100% dưới ràng buộc"
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/api/products")
check "Catalog vẫn trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 3.3 — ServiceAccount & RBAC (namespace default — XEM GHI CHÚ ĐIỀU CHỈNH)"
# ============================================================================
yellow "  📌 ĐIỀU CHỈNH so với tài liệu gốc (chạy ở namespace babymilk):"
yellow "     1) babymilk giờ có ResourceQuota -> Job bắt buộc khai resources"
yellow "     2) QUAN TRỌNG HƠN: babymilk giờ có Egress NetworkPolicy (Lab 4.3)"
yellow "        default-deny -> pod trong babymilk KHÔNG gọi được K8s API server"
yellow "        (10.96.0.1:443 bị chặn) -> Job kubectl nào cũng treo/fail."
yellow "     => Lab này chuyển sang namespace default (không NetworkPolicy),"
yellow "        logic RBAC y hệt. Bản thân đây là bài học thật: NetworkPolicy"
yellow "        egress ảnh hưởng cả các pod cần gọi K8s API!"

step "3.3-B0: Cleanup"
run "Xoá resource cũ nếu sót" \
  "kubectl delete job rbac-demo-job rbac-negative-test --ignore-not-found=true; kubectl delete rolebinding rbac-demo-binding --ignore-not-found=true; kubectl delete role pod-reader --ignore-not-found=true; kubectl delete serviceaccount rbac-demo-sa --ignore-not-found=true"

step "3.3-B1: Tạo SA + Role (chỉ get/list/watch pods) + RoleBinding + Job (namespace default)"
cat > /tmp/rbac-demo.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rbac-demo-sa
  namespace: default
  labels: {created-by: ckad-lab}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
  labels: {created-by: ckad-lab}
rules:
- apiGroups: ['']
  resources: ['pods']
  verbs: ['get', 'list', 'watch']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: rbac-demo-binding
  namespace: default
  labels: {created-by: ckad-lab}
subjects:
- kind: ServiceAccount
  name: rbac-demo-sa
  namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: batch/v1
kind: Job
metadata:
  name: rbac-demo-job
  namespace: default
  labels: {created-by: ckad-lab}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels: {created-by: ckad-lab}
    spec:
      serviceAccountName: rbac-demo-sa
      restartPolicy: Never
      containers:
      - name: kubectl-demo
        image: bitnami/kubectl:latest
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c', 'kubectl get pods']
        resources:
          requests: {cpu: 20m, memory: 32Mi}
          limits: {cpu: 100m, memory: 128Mi}
EOF
run "Apply SA + Role + RoleBinding + Job" "kubectl apply -f /tmp/rbac-demo.yaml"

step "3.3-B2: Verify POSITIVE case (SA gọi được API, đọc pod trong namespace mình)"
run "Chờ Job Complete" "kubectl wait --for=condition=complete job/rbac-demo-job --timeout=90s"
check "rbac-demo-job Complete" $?
run "Log job (gọi API thành công — KHÔNG có Forbidden)" "kubectl logs -l job-name=rbac-demo-job"
kubectl logs -l job-name=rbac-demo-job 2>/dev/null | grep -q "Forbidden"
check "SA list pod thành công (không bị Forbidden)" $([ $? -ne 0 ] && echo 0 || echo 1)

step "3.3-B3: Demo NGƯỢC LẠI — xác nhận Role giới hạn THẬT (bước quan trọng nhất)"
cat > /tmp/rbac-negative-test.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: rbac-negative-test
  namespace: default
  labels: {created-by: ckad-lab}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels: {created-by: ckad-lab}
    spec:
      serviceAccountName: rbac-demo-sa
      restartPolicy: Never
      containers:
      - name: kubectl-demo
        image: bitnami/kubectl:latest
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c', 'echo "--- Thu xoa pod (phai bi tu choi) ---"; kubectl delete pod -n default -l created-by=ckad-lab; echo "--- Thu doc namespace khac (phai bi tu choi) ---"; kubectl get pods -n babymilk']
        resources:
          requests: {cpu: 20m, memory: 32Mi}
          limits: {cpu: 100m, memory: 128Mi}
EOF
run "Apply negative-test Job" "kubectl apply -f /tmp/rbac-negative-test.yaml"
sleep 12
run "Log negative test (mong đợi 2 dòng Forbidden)" "kubectl logs -l job-name=rbac-negative-test"
FORBIDDEN=$(kubectl logs -l job-name=rbac-negative-test 2>/dev/null | grep -c "Forbidden")
check "Cả 2 hành động trái phép đều bị Forbidden (least-privilege thật)" $([ "$FORBIDDEN" -ge 2 ] && echo 0 || echo 1)
run "Chắc chắn pod product-service KHÔNG bị xoá thật" "kubectl get pods -n $NS -l app=product-service"

step "3.3-B4: Cleanup"
run "Dọn toàn bộ resource RBAC demo" \
  "kubectl delete -f /tmp/rbac-demo.yaml; kubectl delete -f /tmp/rbac-negative-test.yaml; rm -f /tmp/rbac-demo.yaml /tmp/rbac-negative-test.yaml"

# ============================================================================
step "LAB 3.4 — Namespace Quotas (quota ĐÃ PERMANENT — demo pod bị từ chối)"
# ============================================================================

step "3.4-B1: Xem quota đang áp dụng"
run "ResourceQuota babymilk-quota" "kubectl describe resourcequota babymilk-quota -n $NS | sed -n '1,16p'"

step "3.4-B2: Cleanup"
run "Xoá pod test cũ" "kubectl delete pod quota-buster -n $NS --ignore-not-found=true"

step "3.4-B3: Pod xin VƯỢT quota -> bị từ chối NGAY LÚC TẠO"
cat > /tmp/quota-buster.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: quota-buster
  namespace: babymilk
  labels: {created-by: ckad-lab}
spec:
  containers:
  - name: quota-buster
    image: busybox:1.36
    command: ['sleep', '3600']
    resources:
      requests: {cpu: "1000m", memory: "100Mi"}
      limits: {cpu: "1000m", memory: "100Mi"}
EOF
run "Apply pod xin 1000m CPU (mong đợi bị TỪ CHỐI)" "kubectl apply -f /tmp/quota-buster.yaml"
if [ $? -ne 0 ]; then green "  ✅ PASS: Bị từ chối đúng (exceeded quota — admission control chặn ngay lúc tạo)"; PASS=$((PASS+1)); else red "  ❌ FAIL: Đáng lẽ phải bị quota chặn"; FAIL=$((FAIL+1)); fi

step "3.4-B4: Đối chiếu — giảm xuống 100m (trong quota) -> tạo được"
run "Sửa 1000m -> 100m rồi apply lại" "sed -i 's/1000m/100m/g' /tmp/quota-buster.yaml && kubectl apply -f /tmp/quota-buster.yaml"
check "Pod 100m được tạo (nằm trong quota)" $?
run "Pod status + quota sau khi tạo" \
  "kubectl get pod quota-buster -n $NS; kubectl describe resourcequota babymilk-quota -n $NS | sed -n '5,12p'"

step "3.4-B5: Cleanup"
run "Xoá pod test" "kubectl delete pod quota-buster -n $NS; rm -f /tmp/quota-buster.yaml"

# ============================================================================
step "VERIFY CUỐI DAY 3 — app thật không bị ảnh hưởng"
# ============================================================================
run "Pod babymilk" "kubectl get pods -n $NS"
READY_COUNT=$(kubectl get pods -n $NS --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NODEPORT/healthz")
check "App vẫn trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)
run "Không còn resource demo sót (created-by=ckad-lab)" \
  "kubectl get pod,job,role,rolebinding,serviceaccount -l created-by=ckad-lab --all-namespaces"

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ DAY 3 HOÀN THÀNH — TẤT CẢ $PASS CHECK PASS"
else
  red "❌ DAY 3: $FAIL/$((PASS+FAIL)) CHECK FAIL — xem log phía trên"
fi
echo "============================================================"
