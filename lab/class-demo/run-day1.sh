#!/bin/bash
# ============================================================================
# run-day1.sh — Day 1: Application Design and Build (Lab 1.1 - 1.4)
# Chạy FULL tự động trên node master, show kết quả từng bước.
# Bám sát Day1-ApplicationDesignBuild.md — namespace default, an toàn 100%.
# ============================================================================

set -uo pipefail
PASS=0; FAIL=0
green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan()   { echo -e "\033[36m$1\033[0m"; }

step() { echo ""; yellow "════════════════════════════════════════════════════════════"; yellow "  $1"; yellow "════════════════════════════════════════════════════════════"; }

check() { # check "mô tả" <0=pass>
  if [ "$2" -eq 0 ]; then green "  ✅ PASS: $1"; PASS=$((PASS+1));
  else red "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); fi
}

run() { # run "mô tả" "lệnh" — show lệnh + output, trả về exit code qua $?
  cyan "  ▶ $1"
  echo "    \$ $2"
  eval "$2" 2>&1 | sed 's/^/    /'
  return ${PIPESTATUS[0]}
}

cd /tmp

yellow "╔══════════════════════════════════════════════════════════╗"
yellow "║   DAY 1 — APPLICATION DESIGN AND BUILD (Lab 1.1-1.4)     ║"
yellow "╚══════════════════════════════════════════════════════════╝"

# ============================================================================
step "LAB 1.1 — The 60-Second Pod (imperative + dry-run)"
# ============================================================================

step "1.1-B0: Cleanup trước khi demo"
run "Xoá pod cũ nếu còn sót" "kubectl delete pod speedy-pod --ignore-not-found=true"

step "1.1-B1: Sinh manifest bằng imperative + --dry-run=client"
run "kubectl run ... --dry-run=client -o yaml > pod.yaml" \
  "kubectl run speedy-pod --image=docker.io/babymilk/frontend:1.0 --labels=app=web,tier=frontend,env=lab,created-by=ckad-lab --env=PORT=4000 --env=UPSTREAM_TIMEOUT_MS=10000 --dry-run=client -o yaml > pod.yaml && echo '(đã ghi pod.yaml — dry-run KHÔNG tạo gì trên cluster)'"

step "1.1-B2: Viết manifest đầy đủ (thêm resources + imagePullPolicy: Never)"
cat > pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: web
    env: lab
    tier: frontend
    created-by: ckad-lab
  name: speedy-pod
spec:
  containers:
  - name: speedy-pod
    image: docker.io/babymilk/frontend:1.0
    imagePullPolicy: Never
    env:
    - name: PORT
      value: "4000"
    - name: UPSTREAM_TIMEOUT_MS
      value: "10000"
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 250m
        memory: 128Mi
  restartPolicy: Always
EOF
echo "    (đã ghi pod.yaml đầy đủ — imagePullPolicy: Never vì image chỉ có local trên worker)"

step "1.1-B3: Apply"
run "Apply pod.yaml" "kubectl apply -f pod.yaml"

step "1.1-B4: Verify (exam speed path — không cần mở editor)"
kubectl wait --for=condition=ready pod/speedy-pod --timeout=60s >/dev/null 2>&1
run "Pod status" "kubectl get pod speedy-pod -o wide"
STATUS=$(kubectl get pod speedy-pod --no-headers 2>/dev/null | awk '{print $2, $3}')
check "Pod 1/1 Running" $([ "$STATUS" = "1/1 Running" ] && echo 0 || echo 1)

run "Labels (jsonpath)" "kubectl get pod speedy-pod -o jsonpath='{.metadata.labels}'; echo"
run "Env (jsonpath)" "kubectl get pod speedy-pod -o jsonpath='{.spec.containers[0].env}'; echo"
run "Resources (jsonpath)" "kubectl get pod speedy-pod -o jsonpath='{.spec.containers[0].resources}'; echo"
run "Logs" "kubectl logs speedy-pod"
kubectl logs speedy-pod 2>/dev/null | grep -q "listening on http://localhost:4000"
check "Log có 'listening on http://localhost:4000'" $?

step "1.1-B5 (tuỳ chọn): NodePort soi từ Windows"
cat > speedy-pod-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: speedy-pod-svc
  labels:
    created-by: ckad-lab
spec:
  type: NodePort
  selector:
    app: web
    tier: frontend
    env: lab
  ports:
  - port: 4000
    targetPort: 4000
    nodePort: 30081
EOF
run "Apply Service NodePort 30081" "kubectl apply -f speedy-pod-svc.yaml"
run "Endpoints (phải có IP = selector khớp pod)" "kubectl get endpoints speedy-pod-svc"
sleep 2   # chờ Endpoints populate ổn định trước khi curl
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.56.102:30081/healthz)
echo "    curl http://192.168.56.102:30081/healthz -> HTTP $CODE"
check "NodePort 30081 trả 200 (Windows mở browser được)" $([ "$CODE" = "200" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 1.2 — Init + Sidecar Pattern"
# ============================================================================

step "1.2-B0: Cleanup"
run "Xoá pod/svc cũ nếu sót" "kubectl delete pod init-sidecar-demo lab-postgres --ignore-not-found=true; kubectl delete svc lab-postgres init-sidecar-svc --ignore-not-found=true"

step "1.2-B1: Postgres TẠM cho lab (namespace default, không đụng Postgres thật)"
cat > lab-postgres.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: lab-postgres
  labels:
    app: lab-postgres
    created-by: ckad-lab
spec:
  containers:
  - name: postgres
    image: postgres:16-alpine
    env:
    - name: POSTGRES_USER
      value: "babymilk"
    - name: POSTGRES_PASSWORD
      value: "lab-password"
    - name: POSTGRES_DB
      value: "babymilk_products"
    ports:
    - containerPort: 5432
    readinessProbe:
      exec:
        command: ["pg_isready", "-U", "babymilk"]
      initialDelaySeconds: 3
      periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: lab-postgres
  labels:
    created-by: ckad-lab
spec:
  selector:
    app: lab-postgres
  ports:
  - port: 5432
EOF
run "Apply lab-postgres" "kubectl apply -f lab-postgres.yaml"
run "Chờ postgres Ready" "kubectl wait --for=condition=ready pod/lab-postgres --timeout=90s"
check "lab-postgres Ready" $?

step "1.2-B2: Pod init + app + sidecar (image thật product-service:2.1)"
cat > init-sidecar-demo.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: init-sidecar-demo
  labels:
    app: demo
    created-by: ckad-lab
spec:
  securityContext:
    fsGroup: 1000
  initContainers:
  - name: init-setup
    image: busybox:1.36
    command: ['sh', '-c', 'echo "$(date) [init] log file created" > /var/log/app/app.log && chmod 664 /var/log/app/app.log']
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/app
  containers:
  - name: app
    image: docker.io/babymilk/product-service:2.1
    imagePullPolicy: Never
    command: ['sh', '-c', 'node src/server.js >> /var/log/app/app.log 2>&1']
    env:
    - name: PORT
      value: "4001"
    - name: PGHOST
      value: "lab-postgres"
    - name: PGPORT
      value: "5432"
    - name: PGUSER
      value: "babymilk"
    - name: PGDATABASE
      value: "babymilk_products"
    - name: PGPASSWORD
      value: "lab-password"
    - name: JWT_SECRET
      value: "lab-jwt-secret"
    - name: INTERNAL_API_KEY
      value: "lab-internal-key"
    - name: SEED_ON_START
      value: "true"
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/app
  - name: sidecar
    image: busybox:1.36
    command: ['sh', '-c', 'tail -f /var/log/app/app.log']
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/app
  volumes:
  - name: shared-logs
    emptyDir: {}
EOF
run "Apply init-sidecar-demo" "kubectl apply -f init-sidecar-demo.yaml"
run "Chờ pod Ready (tối đa 90s)" "kubectl wait --for=condition=ready pod/init-sidecar-demo --timeout=90s"
check "Pod init-sidecar-demo Ready" $?

step "1.2-B3: Verify — xem log qua SIDECAR, không phải app"
run "Pod status (mong đợi 2/2)" "kubectl get pod init-sidecar-demo"
READY=$(kubectl get pod init-sidecar-demo --no-headers 2>/dev/null | awk '{print $2, $3}')
check "Pod 2/2 Running" $([ "$READY" = "2/2 Running" ] && echo 0 || echo 1)

run "Log init container (init-setup)" "kubectl logs init-sidecar-demo -c init-setup; echo '(rỗng là đúng — init chỉ ghi vào file)'"
run "Log app (RỖNG là đúng — output bị redirect vào file)" "kubectl logs init-sidecar-demo -c app; echo '(rỗng)'"
run "Log SIDECAR (đây mới là log thật)" "kubectl logs init-sidecar-demo -c sidecar"
kubectl logs init-sidecar-demo -c sidecar 2>/dev/null | grep -q "product-service listening on http://localhost:4001"
check "Sidecar thấy 'product-service listening on http://localhost:4001'" $?
kubectl logs init-sidecar-demo -c sidecar 2>/dev/null | grep -q "\[init\] log file created"
check "Sidecar thấy dòng của init container (init chạy TRƯỚC app)" $?

step "1.2-B4 (tuỳ chọn): NodePort soi từ Windows"
cat > init-sidecar-svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: init-sidecar-svc
  labels:
    created-by: ckad-lab
spec:
  type: NodePort
  selector:
    app: demo
  ports:
  - port: 4001
    targetPort: 4001
    nodePort: 30082
EOF
run "Apply Service NodePort 30082" "kubectl apply -f init-sidecar-svc.yaml"
sleep 3   # chờ Endpoints controller populate trước khi curl
COUNT=$(curl -s --max-time 5 "http://192.168.56.102:30082/api/products?limit=100" | grep -o '"id":' | wc -l)
echo "    curl http://192.168.56.102:30082/api/products -> $COUNT sản phẩm"
check "API trả đúng 14 sản phẩm mẫu (seed thật)" $([ "$COUNT" = "14" ] && echo 0 || echo 1)

# ============================================================================
step "LAB 1.3 — Jobs & CronJobs (CronJob stock-monitor đã PERMANENT, chỉ xem + chạy Job tay)"
# ============================================================================

step "1.3-B1: Xem CronJob thật đang có (không tạo gì)"
run "CronJob stock-monitor (chạy 8h sáng mỗi ngày)" "kubectl get cronjob stock-monitor -n babymilk"
kubectl get cronjob stock-monitor -n babymilk --no-headers >/dev/null 2>&1
check "CronJob stock-monitor tồn tại" $?

step "1.3-B2: Chạy Job thủ công 1 lần (KHÔNG đụng CronJob)"
run "Xoá job cũ nếu sót" "kubectl delete job stock-check-manual -n babymilk --ignore-not-found=true"
cat > stock-check-manual.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: stock-check-manual
  namespace: babymilk
  labels:
    created-by: ckad-lab
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app: stock-monitor
        created-by: ckad-lab
    spec:
      restartPolicy: OnFailure
      containers:
      - name: stock-check
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "=== Stock check $(date) ==="
          wget -qO- http://product-service:4001/api/products?limit=100 > /tmp/products.json || exit 1
          grep -o '"name":"[^"]*","brand":"[^"]*"[^}]*"stock":[0-9]\{1,2\}[,}]' /tmp/products.json | head -20
          echo "=== Done ==="
        resources:
          requests: {cpu: 20m, memory: 16Mi}
          limits: {cpu: 50m, memory: 32Mi}
EOF
run "Apply Job stock-check-manual" "kubectl apply -f stock-check-manual.yaml"
run "Chờ Job Complete" "kubectl wait --for=condition=complete job/stock-check-manual -n babymilk --timeout=60s"
check "Job Complete" $?

step "1.3-B3: Verify log Job"
run "Job status" "kubectl get job stock-check-manual -n babymilk"
run "Log job (danh sách tồn kho)" "kubectl logs -n babymilk -l job-name=stock-check-manual"
kubectl logs -n babymilk -l job-name=stock-check-manual 2>/dev/null | grep -q '"name":"Sữa'
check "Log có danh sách sản phẩm sữa (gọi được API qua NetworkPolicy L7)" $?

# ============================================================================
step "LAB 1.4 — Label & Annotation Drill"
# ============================================================================

step "1.4-B0: Cleanup"
run "Xoá drill pod cũ" "kubectl delete pod -l drill=true --ignore-not-found=true"

step "1.4-B1: Bulk-create 4 pod"
run "Tạo 4 pod busybox" "for i in 1 2 3 4; do kubectl run drill-pod-\$i --image=busybox:1.36 --labels=drill=true,batch=one,created-by=ckad-lab --command -- sleep 3600; done"
sleep 3
run "Xem pod kèm labels" "kubectl get pods -l drill=true --show-labels"
N=$(kubectl get pods -l drill=true --no-headers 2>/dev/null | wc -l)
check "Đủ 4 drill pod" $([ "$N" = "4" ] && echo 0 || echo 1)

step "1.4-B2: Bulk update label bằng selector"
run "Gắn tier=canary cho cả 4 pod cùng lúc" "kubectl label pods -l drill=true tier=canary"
run "Query theo label mới" "kubectl get pods -l tier=canary"
N=$(kubectl get pods -l tier=canary --no-headers 2>/dev/null | wc -l)
check "Query tier=canary ra đủ 4 pod" $([ "$N" = "4" ] && echo 0 || echo 1)

step "1.4-B3: Demo LỖI khi thiếu --overwrite (lỗi này là CỐ Ý), rồi fix"
run "Sửa tier=stable KHÔNG --overwrite (mong đợi LỖI)" "kubectl label pods -l drill=true tier=stable"
if [ $? -ne 0 ]; then green "  ✅ PASS: Báo lỗi đúng như mong đợi ('tier' already has a value)"; PASS=$((PASS+1)); else red "  ❌ FAIL: Đáng lẽ phải báo lỗi"; FAIL=$((FAIL+1)); fi
run "Thêm --overwrite -> thành công" "kubectl label pods -l drill=true tier=stable --overwrite"
check "Overwrite thành công" $?
run "Xem lại labels" "kubectl get pods -l drill=true --show-labels"

step "1.4-B4: Annotation (không select được, chỉ lưu metadata)"
run "Gắn annotation cho cả 4 pod" "kubectl annotate pods -l drill=true owner='ckad-lab' purpose='label drill demo'"
run "Xem annotation của drill-pod-1" "kubectl describe pod drill-pod-1 | grep -A3 Annotations"
kubectl describe pod drill-pod-1 2>/dev/null | grep -q "owner: ckad-lab"
check "Annotation owner=ckad-lab hiện đúng" $?

step "1.4-B5: Dọn drill pod"
run "Xoá theo selector (không cần nhớ tên)" "kubectl delete pods -l drill=true"

# ============================================================================
step "DỌN DẸP CUỐI NGÀY (quét theo label created-by=ckad-lab)"
# ============================================================================
run "Xoá mọi resource demo còn sót" "kubectl delete all,job,pvc,configmap,secret -l created-by=ckad-lab --all-namespaces --ignore-not-found=true"
run "Xoá Job stock-check-manual" "kubectl delete job stock-check-manual -n babymilk --ignore-not-found=true"
run "Dọn file tạm trên master" "rm -f /tmp/pod.yaml /tmp/speedy-pod-svc.yaml /tmp/lab-postgres.yaml /tmp/init-sidecar-demo.yaml /tmp/init-sidecar-svc.yaml /tmp/stock-check-manual.yaml"

step "VERIFY CUỐI — app thật babymilk KHÔNG bị ảnh hưởng gì"
run "Pod babymilk" "kubectl get pods -n babymilk"
READY_COUNT=$(kubectl get pods -n babymilk --no-headers | awk '{split($2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}')
check "5/5 pod babymilk vẫn Ready" $([ "$READY_COUNT" -eq 5 ] && echo 0 || echo 1)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.56.102:30080/healthz)
check "App thật vẫn trả 200" $([ "$CODE" = "200" ] && echo 0 || echo 1)

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  green "✅ DAY 1 HOÀN THÀNH — TẤT CẢ $PASS CHECK PASS"
else
  red "❌ DAY 1: $FAIL/$((PASS+FAIL)) CHECK FAIL — xem log phía trên"
fi
echo "============================================================"

exit "$FAIL"
