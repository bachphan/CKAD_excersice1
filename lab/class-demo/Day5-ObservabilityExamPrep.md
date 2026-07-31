# Day 5 — Observability & Exam Prep

Chạy trên **node master**. Lab 5.1/5.3 dùng namespace `default` (demo tạm). Lab 5.2 chạy trực tiếp
trên pod thật của `babymilk` (chỉ đọc, không thay đổi gì). Lab 5.4 dùng Helm, tách biệt hoàn toàn
khỏi Kustomize.

---

## Lab 5.1 — Self-Healing App

**Mục tiêu**: HTTP liveness probe (đã có sẵn trong app thật), file-based readiness probe, startup probe.
**Ảnh hưởng**: Demo tạm, namespace `default`.

### Bước 0: Cleanup
```bash
kubectl delete pod lab51-selfheal --ignore-not-found=true
```

### Bước 1: Pod mô phỏng app khởi động chậm (20s) với startupProbe + readinessProbe file-based
```bash
cat > lab51-pod.yaml <<'EOF'
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
kubectl apply -f lab51-pod.yaml
```

### Bước 2: Theo dõi tiến trình trực tiếp trước lớp
```bash
watch -n3 kubectl get pod lab51-selfheal
```
**Kết quả mong đợi**: `0/1 Running` trong ~20-25s (KHÔNG bị kill dù startupProbe fail nhiều lần), rồi
tự chuyển `1/1 Running` khi app thật sự sẵn sàng. Bấm `Ctrl+C` để thoát `watch`.

### Verify events (chứng minh startupProbe hoạt động, không phải liveness giết oan)
```bash
kubectl describe pod lab51-selfheal | tail -10
```
**Kết quả mong đợi**: thấy `Warning Unhealthy ... Startup probe failed` vài lần nhưng KHÔNG có dòng
`Killing`/`Restarted` nào — vì `failureThreshold=10` còn dư quota chờ.

### Cleanup
```bash
kubectl delete pod lab51-selfheal
```

---

## Lab 5.2 — CLI Observability

**Mục tiêu**: `kubectl logs -c/--previous`, `kubectl get events`, `kubectl top`.
**Ảnh hưởng**: CHỈ ĐỌC — chạy trực tiếp trên pod thật của `babymilk`, không thay đổi gì.

### Log của container hiện tại
```bash
kubectl logs -n babymilk deploy/product-service --tail=20
```
> 📌 **Từ khi có pattern 4-container/pod** (init + app + sidecar + ambassador, mục 18 work_done.md):
> lệnh trên KHÔNG cần `-c` vẫn đúng vì `product-service` (app chính) là container ĐẦU TIÊN trong pod
> spec (mặc định `kubectl logs` không có `-c` sẽ lấy container đầu). Nhưng để xem log của **container
> khác** trong CÙNG pod bắt buộc phải chỉ định `-c`:
> ```bash
> kubectl logs -n babymilk deploy/product-service -c log-shipper --tail=10   # sidecar đọc log node
> kubectl logs -n babymilk deploy/product-service -c ambassador-nginx --tail=10   # nginx proxy
> kubectl logs -n babymilk deploy/product-service -c init-config              # log init container
> ```
> Đây là điểm hay để nhấn mạnh khi giảng: pod nhiều container KHÔNG có "1 log duy nhất" — mỗi
> container có log riêng, `kubectl logs` không kèm `-c` mặc định chỉ lấy container đầu tiên, dễ
> nhầm là "log app" trong khi có thể đang xem nhầm container khác nếu thứ tự container đổi.

### Log của LẦN CHẠY TRƯỚC (chỉ có nếu container đã từng restart — kiểm tra RESTARTS trước)
```bash
kubectl get pods -n babymilk
# Chọn 1 pod có RESTARTS > 0, thay tên pod vào lệnh dưới:
kubectl logs -n babymilk <pod-name> --previous
```

### Events — timeline tổng quan, nên xem ĐẦU TIÊN khi debug
```bash
kubectl get events -n babymilk --sort-by=.lastTimestamp | tail -15
```

### Resource usage real-time (cần metrics-server, đã cài sẵn)
```bash
kubectl top pods -n babymilk
kubectl top nodes
```

**Bài học nhấn mạnh khi giảng**: thứ tự chẩn đoán hợp lý — (1) `get events` xem timeline tổng quan →
(2) `describe pod` xem chi tiết 1 resource → (3) `logs` (kèm `--previous` nếu cần) xem log ứng dụng thật.

---

## Lab 5.3 — Broken YAML Triage

**Mục tiêu**: Sửa selector mismatch, targetPort mismatch, invalid image — CẢ 3 trong 1 manifest.
**Ảnh hưởng**: Demo tạm, namespace `default`, dùng image `babymilk/frontend` (thật, quen thuộc với lớp).

### Bước 0: Cleanup
```bash
kubectl delete -f lab53-broken.yaml --ignore-not-found=true 2>/dev/null || true
```

### Bước 1: Deploy manifest với CẢ 3 LỖI cùng lúc
```bash
cat > lab53-broken.yaml <<'EOF'
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
kubectl apply -f lab53-broken.yaml
curl -s http://192.168.56.102:30099/ -o /dev/null -w "%{http_code}\n" --max-time 5 || echo "Không truy cập được"
```

### Triage lỗi 1: Pod có chạy được không?
```bash
kubectl get pods -l app=lab53-app
kubectl describe pod -l app=lab53-app | grep -E 'Image:|Reason'
# => ErrImageNeverPull, tag "1.0-typo" không tồn tại

sed -i 's/1.0-typo/1.0/' lab53-broken.yaml
kubectl apply -f lab53-broken.yaml
kubectl wait --for=condition=available deployment/lab53-app --timeout=90s
kubectl get pods -l app=lab53-app     # pod MỚI Running (pod lỗi cũ có thể còn sót 1 lúc)
```

> ⚠️ Lưu ý: đừng `kubectl wait --for=condition=ready pod -l app=lab53-app` lúc này — selector khớp
> CẢ pod cũ đang `ErrImageNeverPull` chưa bị dọn, wait sẽ timeout oan dù pod mới đã tốt. Wait theo
> Deployment (available) là chắc chắn (lỗi thật đã gặp).

### Triage lỗi 2: Pod Running rồi, Service có thấy pod không?
```bash
kubectl get endpoints lab53-svc
# => <none> dù pod đã Running

kubectl get pods -l app=lab53-app --show-labels
kubectl get svc lab53-svc -o jsonpath='{.spec.selector}'
# => selector "lab53-app-WRONG" không khớp label pod thật "lab53-app"

sed -i 's/app: lab53-app-WRONG/app: lab53-app/' lab53-broken.yaml
kubectl apply -f lab53-broken.yaml
kubectl get endpoints lab53-svc       # phải có IP:port rồi
```

### Triage lỗi 3: Có Endpoint rồi, đúng port chưa?
```bash
kubectl get svc lab53-svc -o jsonpath='{.spec.ports}'
kubectl get pod -l app=lab53-app -o jsonpath='{.items[0].spec.containers[0].ports}'
# => Service targetPort=9999, container thật nghe ở 4000

sed -i 's/targetPort: 9999/targetPort: 4000/' lab53-broken.yaml
kubectl apply -f lab53-broken.yaml
curl -s http://192.168.56.102:30099/healthz -w "\nHTTP: %{http_code}\n"
```
**Kết quả mong đợi cuối cùng**: `{"status":"ok","service":"frontend"}`, `HTTP: 200`.

### Cleanup
```bash
kubectl delete -f lab53-broken.yaml
```

---

## Lab 5.4 — Helm Deploy & Rollback

**Mục tiêu**: Install chart với value override, upgrade, rollback.
**Ảnh hưởng**: Demo RIÊNG BIỆT, KHÔNG liên quan tới babymilk-shop (vẫn dùng Kustomize). Helm đã cài
sẵn trên master (`helm version`), repo `bitnami` đã add sẵn.

### Bước 0: Cleanup
```bash
helm uninstall lab54-nginx 2>/dev/null || true
```

### Bước 1: Install với value override
```bash
helm install lab54-nginx bitnami/nginx \
  --set replicaCount=1 \
  --set resources.requests.cpu=50m --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=100m --set resources.limits.memory=64Mi \
  --set service.type=ClusterIP
```
**Lưu ý**: KHÔNG chỉ định `--set image.tag=<version cụ thể>` — Bitnami đã giới hạn chỉ free tag
`latest`, chỉ định tag phiên bản cụ thể sẽ lỗi `not found`.
**Lưu ý 2**: helm đôi khi fail ngẫu nhiên do NAT của VirtualBox chậm/chập chờn lúc tải chart —
chỉ cần retry sau ~10s là được (script `run-day5.sh` đã tích hợp sẵn retry ×3). Các WARNING của
Bitnami về "resourcesPreset"/"Rolling tag" chỉ là khuyến cáo văn phong, không phải lỗi.

### Verify
```bash
kubectl get pods -l app.kubernetes.io/instance=lab54-nginx
helm status lab54-nginx
```

### Bước 2: Upgrade (đổi value)
```bash
helm upgrade lab54-nginx bitnami/nginx \
  --set replicaCount=2 \
  --set resources.requests.cpu=50m --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=100m --set resources.limits.memory=64Mi \
  --set service.type=ClusterIP
helm history lab54-nginx
kubectl get pods -l app.kubernetes.io/instance=lab54-nginx
```

### Bước 3: Rollback
```bash
helm rollback lab54-nginx 1
helm history lab54-nginx
kubectl get pods -l app.kubernetes.io/instance=lab54-nginx
```
**Bài học nhấn mạnh khi giảng**: `helm rollback` giống hệt `kubectl rollout undo` — tạo REVISION MỚI
("Rollback to 1"), không quay ngược số revision, giữ nguyên lịch sử để audit.

### Cleanup
```bash
helm uninstall lab54-nginx
```
