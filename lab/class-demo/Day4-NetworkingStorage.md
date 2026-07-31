# Day 4 — Services and Networking / Storage (CKAD 20%)

Chạy trên **node master**.

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

**Mục tiêu**: Ingress Controller + Ingress resource, route theo domain (host-based routing), phân
biệt với Service/NodePort (Lab 4.1) — Ingress hoạt động ở tầng L7 (HTTP/domain), Service ở tầng L4.
**Ảnh hưởng**: `ingress-nginx` + `Ingress babymilk-ingress` **ĐÃ LÀ PERMANENT** (cluster add-on +
`k8s/base/80-ingress.yaml`). Phần demo dưới đây CHỈ XEM LẠI + verify routing, không cần cài lại gì.

> 📖 **Câu chuyện đáng kể khi giảng** (bài học thật, không phải lý thuyết suông): lần đầu thử bật
> **Cilium's built-in Ingress Controller** (không phải ingress-nginx đang dùng), agent Cilium trên
> chính node chạy app thật bị kẹt >10 phút, phải reboot cả node worker mới khắc phục — thử lại lần 2
> vẫn kẹt y hệt. Tra GitHub thì ra đây là **bug thật đã biết** của Cilium 1.19.x khi restart agent
> cùng lúc cluster có kube-proxy ([issue #44464](https://github.com/cilium/cilium/issues/44464)),
> không phải lỗi thao tác. Giải pháp: đổi sang **ingress-nginx** (Ingress Controller RIÊNG, không
> gắn vào CNI agent) — thành công ngay lần đầu, không đụng gì tới Cilium. **Bài học**: 1 CNI's
> built-in Ingress Controller bị bug không có nghĩa "Ingress" nói chung không dùng được trên cluster
> đó — đổi sang Controller độc lập là hướng đi đúng. Toàn bộ câu chuyện chi tiết (2 lần thử Cilium
> thất bại + lần thành công với nginx): `lab/lab_4.2.txt`.

### Xem hạ tầng Ingress đang có (không tạo gì mới)
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingress -n babymilk
```
**Kết quả mong đợi**: controller `1/1 Running`, Service `type: NodePort` (port 80/443 map ra 2 NodePort
ngẫu nhiên — ghi lại port `80:XXXXX/TCP` để dùng bước sau), `Ingress babymilk-ingress` có
`CLASS: nginx`, `HOSTS: babymilk.local`.

### Demo: routing THEO DOMAIN — đây là điểm khác biệt cốt lõi so với Service/NodePort
```bash
# Lấy NodePort thật của ingress-nginx (thay vì nhớ số cố định)
INGRESS_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[0].nodePort}')
echo "Ingress NodePort: $INGRESS_PORT"

# Host ĐÚNG -> route vào frontend, trả data thật
curl -s -H "Host: babymilk.local" http://192.168.56.102:$INGRESS_PORT/api/products?limit=1

# Host SAI (không khai trong Ingress) -> 404, KHÔNG route vào đâu cả
curl -s -H "Host: khong-ton-tai.local" http://192.168.56.102:$INGRESS_PORT/api/products -w "\nHTTP: %{http_code}\n"
```
**Kết quả mong đợi**: Host đúng trả JSON sản phẩm thật (200); Host sai trả `404 Not Found` (trang lỗi
chuẩn của nginx, không phải lỗi app) — chứng minh Ingress Controller tự route theo `Host` header,
đúng bản chất Ingress là L7 (HTTP-aware), khác Service/NodePort chỉ biết L4 (IP:port).

> ⚠️ Lưu ý: đừng test bằng path `/healthz` — trùng với 1 endpoint nội bộ mà ingress-nginx tự trả lời
> (không qua proxy) bất kể `Host` gì, dễ gây hiểu lầm là routing sai. Dùng path thật của app như
> `/api/products` để thấy đúng hành vi 404 khi `Host` không khớp.

### (Nếu muốn tự tay tạo lại) Nội dung Ingress resource — chỉ để tham khảo, KHÔNG cần apply lại
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: babymilk-ingress
  namespace: babymilk
spec:
  ingressClassName: nginx
  rules:
  - host: babymilk.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 4000
```

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
