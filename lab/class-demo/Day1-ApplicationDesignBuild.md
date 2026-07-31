# Day 1 — Application Design and Build (CKAD 20%)

Tất cả lệnh dưới đây chạy trực tiếp trên **node master** (`ssh bachpt1@192.168.56.103`, hoặc alias
`ssh master` nếu đã cấu hình trong `~/.ssh/config`). Namespace demo: `default` (không đụng namespace
`babymilk` — app thật vẫn chạy song song, không bị ảnh hưởng bởi bất kỳ lệnh nào trong file này).

Mọi resource tạo ra trong ngày này đều gắn label `created-by=ckad-lab` để script
`restore-to-baseline.sh` (ở thư mục cha) có thể quét dọn sạch bất cứ lúc nào.

---

## Lab 1.1 — The 60-Second Pod

**Mục tiêu**: Tạo Pod bằng lệnh imperative (labels, env, resources), export bằng `--dry-run=client -o yaml`, verify không cần mở editor.
**Ảnh hưởng**: Demo tạm, không đụng gì tới app thật.

### Bước 0: Cleanup (đảm bảo sạch trước khi demo)
```bash
kubectl delete pod speedy-pod --ignore-not-found=true
```

### Bước 1: Sinh manifest bằng lệnh imperative + dry-run
```bash
kubectl run speedy-pod \
  --image=docker.io/babymilk/frontend:1.0 \
  --labels=app=web,tier=frontend,env=lab,created-by=ckad-lab \
  --env=PORT=4000 \
  --env=UPSTREAM_TIMEOUT_MS=10000 \
  --dry-run=client -o yaml > pod.yaml
```
**Giải thích**: `--dry-run=client` KHÔNG tạo gì trên cluster, chỉ in ra YAML để xem/sửa tiếp — đây là
cách nhanh nhất để có khung YAML mà không phải gõ tay từ đầu. Lưu ý: `--env` chỉ nhận **1 cặp
key=value mỗi lần gọi** (khác `--labels` hỗ trợ dấu phẩy) — phải gọi `--env` nhiều lần cho nhiều biến.

### Bước 2: Thêm resource requests/limits + imagePullPolicy (kubectl run không có flag cho việc này)
```bash
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
```
**Giải thích**: `imagePullPolicy: Never` bắt buộc vì image `babymilk/frontend` chỉ tồn tại local trên
node worker (không có registry) — thiếu dòng này kubelet sẽ cố pull qua mạng và lỗi `ImagePullBackOff`.

### Bước 3: Apply
```bash
kubectl apply -f pod.yaml
```

### Bước 4: Verify KHÔNG cần mở editor (exam speed path)
```bash
kubectl get pod speedy-pod -o wide
kubectl describe pod speedy-pod
kubectl get pod speedy-pod -o jsonpath='{.metadata.labels}'
kubectl get pod speedy-pod -o jsonpath='{.spec.containers[0].env}'
kubectl get pod speedy-pod -o jsonpath='{.spec.containers[0].resources}'
kubectl logs speedy-pod
```
**Kết quả mong đợi**: `READY 1/1`, log in ra `frontend (static + gateway) listening on http://localhost:4000`.

### (Tuỳ chọn) Soi trên browser — thêm NodePort
```bash
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
kubectl apply -f speedy-pod-svc.yaml
```
Mở trình duyệt: `http://192.168.56.102:30081/healthz`

---

## Lab 1.2 — Init + Sidecar Pattern

**Mục tiêu**: Multi-container Pod (init + app + sidecar), chia sẻ data qua `emptyDir`, xem log qua `kubectl logs -c`.
**Ảnh hưởng**: Demo tạm. Cần 1 Postgres tạm (namespace `default`, tách biệt khỏi Postgres thật của `babymilk`).

### Bước 0: Cleanup
```bash
kubectl delete pod init-sidecar-demo --ignore-not-found=true
kubectl delete pod lab-postgres --ignore-not-found=true
kubectl delete svc lab-postgres --ignore-not-found=true
```

### Bước 1: Postgres tạm cho lab (namespace default, KHÔNG đụng Postgres thật)
```bash
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
kubectl apply -f lab-postgres.yaml
kubectl wait --for=condition=ready pod/lab-postgres --timeout=60s
```

### Bước 2: Pod init + app + sidecar (dùng image thật `product-service`)
```bash
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
kubectl apply -f init-sidecar-demo.yaml
```
**Giải thích**: `initContainers` LUÔN chạy xong hết mới tới `containers` — dùng để "mồi" file log trước.
`fsGroup: 1000` + `chmod 664` trong init container: bắt buộc vì init chạy root (uid 0), app chạy
non-root (uid 1000, do Dockerfile có `USER node`) — thiếu 2 dòng này sẽ gặp lỗi
`Permission denied` khi app cố ghi vào file do root tạo.

### Bước 3: Verify — xem log qua sidecar (không phải qua app!)
```bash
kubectl get pod init-sidecar-demo
kubectl logs init-sidecar-demo -c init-setup      # log của init container (chạy 1 lần)
kubectl logs init-sidecar-demo -c app              # RỖNG — vì output đã bị redirect vào file
kubectl logs init-sidecar-demo -c sidecar          # ĐÂY mới thấy log thật (init + migration + listening)
```
**Kết quả mong đợi**: `2/2 Running`, log sidecar có dòng `product-service listening on http://localhost:4001`.

### (Tuỳ chọn) Soi trên browser
```bash
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
kubectl apply -f init-sidecar-svc.yaml
```
Mở: `http://192.168.56.102:30082/api/products?limit=100`

> ⚠️ Lưu ý: API có **phân trang mặc định 12 item/trang** — gọi `/api/products` trần chỉ thấy 12/14
> sản phẩm. Thêm `?limit=100` để thấy đủ 14 (đây là lỗi thật từng gặp khi verify bằng cách đếm số
> item trong JSON trả về).

---

## Lab 1.3 — Jobs & CronJobs

**Mục tiêu**: Job chạy 1 lần (backoffLimit), CronJob theo lịch, phân biệt Job/CronJob với Deployment.
**Ảnh hưởng**: **PERMANENT** — CronJob `stock-monitor` đã là tính năng thật của `babymilk` (namespace
`babymilk`, quản lý qua Kustomize `k8s/base/60-stock-monitor.yaml`). Phần demo dưới đây chỉ để ÔN TẬP
cách chạy Job thủ công, không tạo lại CronJob (đã có sẵn, chạy 8h sáng mỗi ngày).

### Xem CronJob thật đang chạy (không cần tạo gì, chỉ xem)
```bash
kubectl get cronjob stock-monitor -n babymilk
kubectl get jobs -n babymilk
```

### Test thủ công: chạy lại Job 1 lần để demo (KHÔNG đụng CronJob)
```bash
kubectl delete job stock-check-manual -n babymilk --ignore-not-found=true

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
kubectl apply -f stock-check-manual.yaml
```
**Giải thích Job vs Deployment**: Deployment giữ pod LUÔN chạy (restart vô hạn khi chết) — mục tiêu
"luôn sẵn sàng". Job chạy tới khi ĐỦ số lần thành công rồi DỪNG hẳn — mục tiêu "làm xong 1 việc".
`backoffLimit` giới hạn số lần RETRY khi lỗi (khác Deployment retry vô hạn).
**CronJob** không tự làm gì — nó chỉ là "đồng hồ báo thức" tạo Job con mới theo lịch cron.

### Verify
```bash
kubectl get job stock-check-manual -n babymilk
kubectl logs -n babymilk -l job-name=stock-check-manual
```
**Kết quả mong đợi**: `STATUS: Complete`, log in ra danh sách sản phẩm tồn kho thấp.

---

## Lab 1.4 — Label & Annotation Drill

**Mục tiêu**: Bulk-create pod, update label hàng loạt, query bằng selector, dùng `--overwrite`.
**Ảnh hưởng**: Demo tạm, không đụng label `tier` thật đã gắn permanent cho babymilk (Lab 1.4 gốc).

### Bước 0: Cleanup
```bash
kubectl delete pod -l drill=true --ignore-not-found=true
```

### Bước 1: Bulk-create 4 pod
```bash
for i in 1 2 3 4; do
  kubectl run drill-pod-$i --image=busybox:1.36 \
    --labels=drill=true,batch=one,created-by=ckad-lab --command -- sleep 3600
done
kubectl get pods -l drill=true --show-labels
```

### Bước 2: Bulk update label bằng selector
```bash
kubectl label pods -l drill=true tier=canary
kubectl get pods -l tier=canary
```

### Bước 3: Demo lỗi khi thiếu --overwrite, rồi fix
```bash
kubectl label pods -l drill=true tier=stable
# => lỗi: 'tier' already has a value (canary), and --overwrite is false

kubectl label pods -l drill=true tier=stable --overwrite
kubectl get pods -l drill=true --show-labels
```

### Bước 4: Annotation (khác label — không dùng để select, chỉ lưu metadata mô tả)
```bash
kubectl annotate pods -l drill=true owner='ckad-lab' purpose='label drill demo'
kubectl describe pod drill-pod-1 | grep -A3 Annotations
```

**Bài học**: `--labels` (imperative flag) hỗ trợ nhiều cặp cách nhau dấu phẩy; `--env` thì không.
Label gắn tay lên Pod đang chạy (`kubectl label`) chỉ TẠM THỜI — mất khi ReplicaSet tạo pod thay thế;
muốn bền vững phải sửa `spec.template.metadata.labels` trong Deployment (như cách đã làm permanent
cho `tier: backend/frontend/database` của babymilk).

---

## Dọn dẹp cuối ngày (tuỳ chọn — script `restore-to-baseline.sh` cũng làm việc này)
```bash
kubectl delete all,job,pvc,configmap,secret -l created-by=ckad-lab --all-namespaces --ignore-not-found=true
kubectl delete job stock-check-manual -n babymilk --ignore-not-found=true
```
