# Day 4 — Services and Networking / Storage (CKAD 20%)

Chạy trên **node master**. ⚠️ **Đọc kỹ cảnh báo ở Lab 4.2 trước khi demo cả ngày này.**

---

## Lab 4.1 — ClusterIP & NodePort

**Mục tiêu**: Diagnose và fix Service selector mismatch, verify Endpoints.
**Ảnh hưởng**: Demo tạm, namespace `default`, dùng `nginx` (không phải image dự án — tách biệt vấn đề
selector khỏi lỗi app-logic).

### Bước 0: Cleanup
```bash
kubectl delete deployment lab41-backend --ignore-not-found=true
kubectl delete svc lab41-backend-svc lab41-frontend-svc --ignore-not-found=true
```

### Bước 1: Deploy + Service CỐ Ý sai selector
```bash
cat > lab41.yaml <<'EOF'
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
kubectl apply -f lab41.yaml
```

### Bước 2: Chẩn đoán
```bash
kubectl get pods -l app=lab41-backend                              # Pod healthy?
kubectl get endpoints lab41-backend-svc lab41-frontend-svc          # So sánh 2 Service
kubectl describe svc lab41-backend-svc | grep -E 'Selector|Endpoints'
```
**Kết quả mong đợi**: pod `Running`, `lab41-frontend-svc` có Endpoint, `lab41-backend-svc` thì `<none>`.

### Bước 3: Fix
```bash
kubectl patch svc lab41-backend-svc -p '{"spec":{"selector":{"app":"lab41-backend"}}}'
kubectl get endpoints lab41-backend-svc
```

### Cleanup
```bash
kubectl delete -f lab41.yaml
```

---

## Lab 4.2 — Ingress Routing

> ## ⚠️ CẢNH BÁO — KHÔNG DEMO LIVE PHẦN NÀY TRỪ KHI CÓ THỜI GIAN DƯ DẢ + BACKUP PLAN
>
> Lần thử trước đó, bật Cilium Ingress Controller làm agent Cilium trên **chính node chạy app thật**
> bị kẹt hơn 10 phút, cuối cùng phải **reboot cả node worker** mới khắc phục được (containerd restart
> không đủ, vấn đề nằm ở cache eBPF tầng kernel). Trong lúc đó app KHÔNG downtime (nhờ Cilium giữ rule
> cũ), nhưng bất kỳ pod MỚI nào cũng không schedule được (node bị Cilium tự taint).
>
> **Khuyến nghị khi đứng lớp**: chỉ trình bày Ý TƯỞNG + đọc qua lệnh bên dưới, KHÔNG chạy thật, trừ khi:
> - Có ít nhất 15-20 phút dự phòng nếu sự cố lặp lại
> - Đã thông báo trước với lớp là phần này "có rủi ro, đang thử nghiệm"
> - Biết chắc cách khắc phục (xem "Nếu sự cố xảy ra" bên dưới)

### Lệnh sẽ chạy NẾU quyết định demo live
```bash
cilium upgrade --set ingressController.enabled=true \
  --set ingressController.loadbalancerMode=shared \
  --set ingressController.service.type=NodePort \
  --set ingressController.service.insecureNodePort=30092 \
  --set ingressController.service.secureNodePort=30093

kubectl -n kube-system rollout restart daemonset cilium
kubectl -n kube-system rollout restart deployment cilium-operator
kubectl get pods -n kube-system -l k8s-app=cilium -o wide -w
```

### Nếu sự cố xảy ra (agent kẹt "Init:0/6" quá 5 phút trên node worker)
```bash
# Bước 1: rollback config (thường KHÔNG đủ, nhưng thử trước)
cilium upgrade --set ingressController.enabled=false
kubectl delete pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=k8s-worker1

# Bước 2: nếu vẫn kẹt, restart containerd (thường KHÔNG đủ)
ssh bachpt1@192.168.56.102 "sudo systemctl restart containerd"

# Bước 3: nếu vẫn kẹt, REBOOT hẳn node worker (cách chắc chắn nhất, ~1-2 phút gián đoạn)
ssh bachpt1@192.168.56.102 "sudo reboot"
# Đợi ~60-90s rồi kiểm tra:
kubectl get nodes
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl get pods -n babymilk
curl -s http://192.168.56.102:30080/healthz
```
**Kết quả mong đợi sau reboot**: cả 2 agent Cilium `1/1 Running`, taint hết, app tự phục hồi hoàn
toàn, data Postgres còn nguyên (đã verify thật — xem `lab/lab_4.2.txt` gốc).

---

## Lab 4.3 — NetworkPolicy Isolation (Egress)

**Mục tiêu**: Frontend → backend only, chặn backend ra internet.
**Ảnh hưởng**: **ĐÃ LÀ PERMANENT** (`k8s/base/21-networkpolicy-egress.yaml`). Phần demo chỉ XEM LẠI +
verify, không cần apply gì mới.

### Xem policy đang áp dụng
```bash
kubectl get networkpolicy -n babymilk
kubectl describe networkpolicy default-deny-egress -n babymilk
kubectl describe networkpolicy allow-dns-egress -n babymilk
```

### Demo: app vẫn hoạt động đầy đủ (login + checkout) dưới egress deny
```bash
RESPONSE=$(curl -s -X POST http://192.168.56.102:30080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@babymilk.local","password":"admin12345"}')
TOKEN=$(echo "$RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -X POST http://192.168.56.102:30080/api/orders \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"items":[{"productId":3,"quantity":1}],"fullName":"Demo","phone":"0900000000","address":"HCMC","paymentMethod":"cod"}' \
  -w "\nHTTP: %{http_code}\n"
```
**Kết quả mong đợi**: `201` — toàn bộ luồng (frontend→user-service, frontend→order-service,
order-service→product-service, cả 3 backend→postgres, kèm DNS resolve) đều hoạt động.

### Demo NGƯỢC LẠI — backend KHÔNG ra được internet
```bash
kubectl exec -n babymilk deploy/product-service -- timeout 6 wget -qO- http://example.com
echo "exit code: $?"
```
**Kết quả mong đợi**: treo tới hết 6s rồi bị `timeout` giết (exit code 143) — KHÔNG có response,
đúng hành vi "silent drop" của NetworkPolicy (khác với bị từ chối tường minh).

**Bài học nhấn mạnh khi giảng**: quên mở DNS egress là lỗi phổ biến nhất — thiếu nó, pod không resolve
được CẢ hostname nội bộ (như `postgres`, `product-service`), làm app sập toàn bộ.

---

## Lab 4.4 — Persistent Volume Claims (dynamic provisioning)

**Mục tiêu**: PVC dynamic provisioning, viết data, xoá pod, tạo lại, verify persistence.
**Ảnh hưởng**: `local-path-provisioner`/StorageClass `local-path` **ĐÃ CÀI PERMANENT** trên cluster
(hạ tầng chung, không phải của riêng babymilk). Phần demo tạo PVC/pod tạm rồi xoá sạch.

### Xem StorageClass đã có sẵn
```bash
kubectl get storageclass
```

### Bước 0: Cleanup
```bash
kubectl delete pod lab44-writer lab44-reader --ignore-not-found=true
kubectl delete pvc lab44-dynamic-pvc --ignore-not-found=true
```

### Bước 1: Tạo PVC (dynamic — KHÔNG tự tạo PV tay)
```bash
cat > lab44-pvc.yaml <<'EOF'
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
kubectl apply -f lab44-pvc.yaml
kubectl get pvc lab44-dynamic-pvc
```
**Giải thích**: `STATUS: Pending` là ĐÚNG lúc này — `local-path` dùng `WaitForFirstConsumer`, PV thật
chỉ tạo khi có Pod THỰC SỰ dùng PVC (để biết provisioning trên node nào).

### Bước 2: Pod ghi data → kích hoạt provisioning
```bash
cat > lab44-writer.yaml <<'EOF'
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
kubectl apply -f lab44-writer.yaml
kubectl wait --for=condition=ready pod/lab44-writer --timeout=30s
kubectl get pvc lab44-dynamic-pvc
kubectl exec lab44-writer -- cat /data/proof.txt
```

### Bước 3: Test persistence CHẶT CHẼ (pod khác, KHÔNG ghi gì, chỉ đọc)
```bash
kubectl delete pod lab44-writer --wait=true
cat > lab44-reader.yaml <<'EOF'
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
kubectl apply -f lab44-reader.yaml
kubectl wait --for=condition=ready pod/lab44-reader --timeout=30s
kubectl exec lab44-reader -- cat /data/proof.txt
```
**Kết quả mong đợi**: vẫn in ra `UNIQUE-MARKER-42` — pod hoàn toàn mới, container không có lệnh ghi,
chứng minh persistence THẬT (không phải trùng hợp lệnh ghi lại).

### Cleanup
```bash
kubectl delete pod lab44-reader
kubectl delete pvc lab44-dynamic-pvc
kubectl get pv | grep lab44 || echo "PV đã tự dọn (reclaimPolicy: Delete)"
```
