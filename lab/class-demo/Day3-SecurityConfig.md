# Day 3 — Application Environment, Configuration & Security (CKAD 25%)

Chạy trên **node master**. Lab 3.1/3.3 dùng namespace `default` (demo tạm). Lab 3.2/3.4 đụng trực
tiếp namespace `babymilk` (đã là cấu hình PERMANENT của dự án — chỉ xem lại, không cần làm lại).

---

## Lab 3.1 — ConfigMap & Secret Injection

**Mục tiêu**: Secret từ file, ConfigMap từ literal, inject cả 2 kiểu (env var + volume mount) trong 1 pod.
**Ảnh hưởng**: Demo tạm, namespace `default`.

### Bước 0: Cleanup
```bash
kubectl delete pod injection-demo --ignore-not-found=true
kubectl delete secret demo-secret --ignore-not-found=true
kubectl delete configmap demo-config --ignore-not-found=true
```

### Bước 1: Tạo Secret từ file, ConfigMap từ literal
```bash
echo 'secret-from-file-value' > /tmp/api-key.txt
kubectl create secret generic demo-secret --from-file=apiKey=/tmp/api-key.txt
kubectl create configmap demo-config --from-literal=greeting=Hello --from-literal=env=lab
```

### Bước 2: Pod inject CẢ 2 kiểu
```bash
cat > injection-demo.yaml <<'EOF'
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
kubectl apply -f injection-demo.yaml
```

### Verify
```bash
kubectl exec injection-demo -- env | grep API_KEY
kubectl exec injection-demo -- ls /etc/demo-config
kubectl exec injection-demo -- cat /etc/demo-config/greeting
```
**Bài học**: Secret qua env var chỉ đọc 1 LẦN lúc container start. ConfigMap qua volume mount TỰ ĐỘNG
sync khi ConfigMap đổi, không cần restart pod — 2 cơ chế khác nhau, chọn tuỳ tình huống.

---

## Lab 3.2 — Security Context Lockdown

**Mục tiêu**: Non-root, read-only root filesystem, drop capabilities, chặn privilege escalation.
**Ảnh hưởng**: **ĐÃ LÀ PERMANENT** trên cả 4 Deployment babymilk (`k8s/base/10,11,12,13-*.yaml`).
Phần dưới đây chỉ để DEMO LẠI/XÁC NHẬN cấu hình đang có, không cần apply gì mới.

### Xem cấu hình đang áp dụng thật
```bash
kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.securityContext}'
echo ""
kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.containers[0].securityContext}'
```
**Kết quả mong đợi**:
`{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}`
`{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}`

### Demo trực tiếp: chứng minh non-root + read-only filesystem THẬT
```bash
kubectl exec -n babymilk deploy/product-service -- id
# uid=1000(node) gid=1000(node) groups=1000(node)

kubectl exec -n babymilk deploy/product-service -- sh -c 'touch /test-write'
# touch: /test-write: Read-only file system   <- LỖI NÀY LÀ ĐÚNG, chứng minh policy hoạt động
```

### Chứng minh app vẫn hoạt động 100% dưới các ràng buộc này
```bash
curl -s http://192.168.56.102:30080/api/products -o /dev/null -w "%{http_code}\n"
```

**Bài học**: `readOnlyRootFilesystem` an toàn cho app KHÔNG ghi file cục bộ (log ra stdout, data ở
Postgres). `runAsNonRoot` là lớp kiểm tra THÊM (image đã tự `USER node` trong Dockerfile) — phòng thủ
theo lớp (defense in depth), không dựa vào 1 chỗ duy nhất.

---

## Lab 3.3 — ServiceAccount & RBAC

**Mục tiêu**: ServiceAccount + Role + RoleBinding, Pod dùng SA token gọi K8s API.
**Ảnh hưởng**: Demo tạm, namespace `default`, xoá sạch sau.

> ⚠️ **Đã chuyển từ namespace `babymilk` sang `default`** (cập nhật sau khi chạy thật) vì 2 lý do:
> 1. **babymilk giờ có Egress NetworkPolicy** (Lab 4.3, `default-deny-egress`) → pod trong babymilk
>    **không gọi được K8s API server** (`10.96.0.1:443` bị chặn) — Job kubectl nào cũng treo/fail.
>    Lab gốc làm trước khi có policy này. Bản thân đây là bài học hay: NetworkPolicy egress ảnh
>    hưởng cả những pod cần gọi K8s API!
> 2. **babymilk có ResourceQuota** → mọi pod bắt buộc khai `resources`. Và lưu ý image
>    `bitnami/kubectl` cần **tối thiểu ~64Mi memory limit** — để 32Mi sẽ bị **OOMKilled** ngay khi
>    `kubectl` khởi động (lỗi thật đã gặp, xem "Memory cgroup out of memory" trên console node).

### Bước 0: Cleanup
```bash
kubectl delete job rbac-demo-job rbac-negative-test --ignore-not-found=true
kubectl delete rolebinding rbac-demo-binding --ignore-not-found=true
kubectl delete role pod-reader --ignore-not-found=true
kubectl delete serviceaccount rbac-demo-sa --ignore-not-found=true
```

### Bước 1: ServiceAccount + Role (chỉ get/list/watch pods) + RoleBinding
```bash
cat > rbac-demo.yaml <<'EOF'
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
kubectl apply -f rbac-demo.yaml
```

### Verify (positive case)
```bash
kubectl wait --for=condition=complete job/rbac-demo-job --timeout=90s
kubectl logs -l job-name=rbac-demo-job
```
**Kết quả mong đợi**: Job `Complete`, log in ra danh sách pod trong `default` (kể cả "No resources
found" cũng là THÀNH CÔNG — nghĩa là API call được phép, chỉ là namespace đang trống).

### Demo NGƯỢC LẠI — xác nhận Role thực sự giới hạn (bước quan trọng nhất, đừng bỏ qua)
```bash
kubectl delete job rbac-negative-test --ignore-not-found=true
cat > rbac-negative-test.yaml <<'EOF'
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
kubectl apply -f rbac-negative-test.yaml
sleep 12
kubectl logs -l job-name=rbac-negative-test
```
**Kết quả mong đợi**: cả 2 lệnh đều trả về `Forbidden` (xóa pod trong chính namespace mình vì Role
không có verb `delete`; đọc namespace `babymilk` vì Role chỉ có phạm vi `default`) — chứng minh
RBAC hoạt động đúng least-privilege.

### Cleanup
```bash
kubectl delete -f rbac-demo.yaml
kubectl delete -f rbac-negative-test.yaml
```

---

## Lab 3.4 — Namespace Quotas

**Mục tiêu**: ResourceQuota, quan sát pod bị từ chối khi vượt quota.
**Ảnh hưởng**: `babymilk-quota` **ĐÃ LÀ PERMANENT** (`k8s/base/70-resourcequota.yaml`). Phần demo chỉ
tạo/xoá 1 pod test, KHÔNG đụng quota thật.

### Xem quota đang áp dụng
```bash
kubectl describe resourcequota babymilk-quota -n babymilk
```

### Bước 0: Cleanup
```bash
kubectl delete pod quota-buster -n babymilk --ignore-not-found=true
```

### Demo: tạo pod xin VƯỢT quota còn lại → bị từ chối
```bash
cat > quota-buster.yaml <<'EOF'
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
kubectl apply -f quota-buster.yaml
```
**Kết quả mong đợi**: `Error from server (Forbidden): ... exceeded quota: babymilk-quota, requested:
limits.cpu=1,requests.cpu=1, used: limits.cpu=1450m,requests.cpu=420m, limited: limits.cpu=1800m,...`
— bị chặn NGAY LÚC TẠO (admission control), không tốn tài nguyên schedule.
(số liệu `used` cao hơn tài liệu gốc vì giờ mỗi app pod có 3 container — xem mục 18 work_done.md)

### Đối chiếu: giảm xuống nằm trong quota → tạo được
```bash
sed -i 's/1000m/100m/g' quota-buster.yaml
kubectl apply -f quota-buster.yaml
kubectl get pod quota-buster -n babymilk
kubectl describe resourcequota babymilk-quota -n babymilk
```

### Cleanup
```bash
kubectl delete pod quota-buster -n babymilk
```
