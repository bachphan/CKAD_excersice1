# Day 2 — Application Deployment (CKAD 20%)

Chạy trên **node master**. Namespace: `babymilk` (đây là các lab **đụng trực tiếp vào app thật** —
đọc kỹ phần "Ảnh hưởng" của từng lab trước khi demo).

---

## Lab 2.1 — Rolling Update & Rollback

**Mục tiêu**: Rolling update v2.0→v2.1, theo dõi rollout, giả lập deploy lỗi, rollback.
**Ảnh hưởng**: Đụng trực tiếp `product-service`. An toàn — rolling update mặc định giữ pod cũ phục vụ
tới khi pod mới Ready, KHÔNG downtime kể cả khi demo lỗi. Baseline hiện tại đã là `:2.1`.

### Bước 0: Xác nhận baseline trước khi demo
```bash
kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.containers[0].image}'
# Kỳ vọng: docker.io/babymilk/product-service:2.3 (bản thêm ảnh sản phẩm, mục 20 work_done.md)
```

### Bước 1: Rolling update thật 2 chiều (:2.3 -> :2.2 -> :2.3, cả 2 tag đều có sẵn trên worker)
```bash
kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:2.2 -n babymilk
kubectl rollout status deployment/product-service -n babymilk

# verify xong thì quay lại :2.3 ngay
kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:2.3 -n babymilk
kubectl rollout status deployment/product-service -n babymilk
```
**Giải thích**: `kubectl set image` chỉ đổi field `image`, không đụng gì khác trong spec. `rollout status`
theo dõi real-time cho tới khi rollout xong (hoặc lỗi).

### Bước 2: Verify version mới (dùng loopback — /healthz không nằm trong path NetworkPolicy cho phép)
```bash
kubectl exec -n babymilk deploy/product-service -- wget -qO- http://localhost:4101/healthz
# Kỳ vọng: {"status":"ok","service":"product-service","version":"2.1"}
```
> ⚠️ **Cập nhật quan trọng từ khi có multi-container pattern** (mục 18 work_done.md):
> - App chính giờ nghe ở `127.0.0.1:4101` (port gốc + 100), còn `ambassador-nginx` CHỈ bind
>   **pod IP** ở port 4001 — từ trong app container gọi `localhost:4001` sẽ bị `Connection refused`.
>   Verify loopback phải gọi **4101**, không phải 4001 như tài liệu cũ.
> - Field `version` trong `/healthz` là chuỗi **hardcode trong code** (`server.js`), KHÔNG tự đổi theo
>   image tag — luôn thấy `"2.1"` dù đang chạy `:2.2` hay `:2.3`. Muốn biết đang chạy tag nào phải
>   check `image` của Deployment, không dựa vào field này.

### Bước 3: MÔ PHỎNG deploy lỗi (tag không tồn tại)
```bash
kubectl set image deployment/product-service product-service=docker.io/babymilk/product-service:bad-tag -n babymilk
kubectl rollout status deployment/product-service -n babymilk --timeout=20s
# Kỳ vọng: timeout, KHÔNG rollout xong — đây là hành vi ĐÚNG

kubectl get pods -n babymilk -l app=product-service
# Thấy pod mới bị ErrImageNeverPull, pod CŨ vẫn Running — APP KHÔNG DOWNTIME
```

### Bước 4: Rollback
```bash
kubectl rollout history deployment/product-service -n babymilk
kubectl rollout undo deployment/product-service -n babymilk
kubectl rollout status deployment/product-service -n babymilk
```
**Giải thích**: `rollout undo` (không chỉ định `--to-revision`) luôn quay về revision LIỀN TRƯỚC —
ở đây đúng là quay lại `:2.3` (bản tốt trước khi thử `:bad-tag`), không phải tag cũ hơn.

### Verify cuối
```bash
kubectl get deploy product-service -n babymilk -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl exec -n babymilk deploy/product-service -- wget -qO- http://localhost:4101/healthz
curl -s http://192.168.56.102:30080/api/products -o /dev/null -w "%{http_code}\n"
```
**Kết quả mong đợi**: image = `:2.3`, healthz trả `"status":"ok"` (version field vẫn ghi `"2.1"` —
xem lưu ý ở Bước 2), catalog trả `200`.

---

## Lab 2.2 — Blue/Green Switch

**Mục tiêu**: 2 Deployment song song (blue/green), chuyển traffic bằng Service selector.
**Ảnh hưởng**: Đụng trực tiếp `frontend`. **QUAN TRỌNG**: phải làm đủ hết Bước 5 (revert) trong CHÍNH
buổi demo — đây là ngoại lệ duy nhất cần "dọn ngay" vì nếu bỏ dở, Service `frontend` (URL demo chính,
NodePort 30080) sẽ bị lệch khỏi file Kustomize đã commit, gây sập app ở lần `apply -k` tiếp theo.

### Bước 0: Cleanup (nếu có phiên demo trước để dở)
```bash
kubectl delete deployment frontend-green -n babymilk --ignore-not-found=true
kubectl delete configmap frontend-green-banner -n babymilk --ignore-not-found=true
kubectl patch svc frontend -n babymilk --type=json \
  -p='[{"op":"remove","path":"/spec/selector/version"}]' 2>/dev/null || true
kubectl patch deployment frontend -n babymilk --type=json \
  -p='[{"op":"remove","path":"/spec/template/metadata/labels/version"}]' 2>/dev/null || true
```

### Bước 1: Gắn "blue" cho frontend đang chạy
```bash
kubectl patch deployment frontend -n babymilk --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/labels/version","value":"blue"}]'
kubectl patch svc frontend -n babymilk -p '{"spec":{"selector":{"app":"frontend","version":"blue"}}}'
sleep 10
curl -s http://192.168.56.102:30080/healthz -o /dev/null -w "%{http_code}\n"    # vẫn phải 200
```

### Bước 2: Tạo bản "green" (cùng image, banner khác qua ConfigMap override)
```bash
cat > frontend-green-index.html <<'HTMLEOF'
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
kubectl create configmap frontend-green-banner -n babymilk --from-file=index.html=frontend-green-index.html

cat > frontend-green.yaml <<'EOF'
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
kubectl apply -f frontend-green.yaml
kubectl wait --for=condition=available deployment/frontend-green -n babymilk --timeout=60s
```

### Bước 3: FLIP sang green — soi trực tiếp trên URL demo thật
```bash
kubectl patch svc frontend -n babymilk -p '{"spec":{"selector":{"app":"frontend","version":"green"}}}'
curl -s http://192.168.56.102:30080/ | grep -o "GREEN DEPLOYMENT"
```
Mở trình duyệt: `http://192.168.56.102:30080` — cả lớp thấy banner xanh lá đổi ngay lập tức, KHÔNG downtime.

### Bước 4: FLIP về lại blue
```bash
kubectl patch svc frontend -n babymilk -p '{"spec":{"selector":{"app":"frontend","version":"blue"}}}'
curl -s http://192.168.56.102:30080/ | grep -o "GREEN DEPLOYMENT" || echo "Đã về blue"
```

### Bước 5: BẮT BUỘC — trả về đúng trạng thái gốc (không được bỏ qua bước này)
```bash
kubectl delete deployment frontend-green -n babymilk
kubectl delete configmap frontend-green-banner -n babymilk
kubectl patch svc frontend -n babymilk --type=json -p='[{"op":"remove","path":"/spec/selector/version"}]'
kubectl patch deployment frontend -n babymilk --type=json -p='[{"op":"remove","path":"/spec/template/metadata/labels/version"}]'
sleep 10
kubectl get pods -n babymilk -l app=frontend --show-labels
kubectl get svc frontend -n babymilk -o jsonpath='{.spec.selector}'
curl -s http://192.168.56.102:30080/healthz -o /dev/null -w "%{http_code}\n"
```
**Kết quả mong đợi**: label chỉ còn `app=frontend,tier=frontend` (không còn `version`), selector chỉ
còn `{"app":"frontend"}`, healthz trả `200`.

---

## Lab 2.3 — Scale & HPA

**Mục tiêu**: Scale tay, hiểu tương tác giữa scale tay ↔ HPA ↔ ResourceQuota.
**Ảnh hưởng**: Đụng `product-service` + HPA. Baseline hiện tại: HPA min1/max3/target 50% — ĐÂY LÀ
CẤU HÌNH PERMANENT, phải trả về đúng sau demo.

> ⚠️ **Tại sao scale lên 2 thay vì 10 như bản gốc?** (cập nhật sau khi chạy thật)
> 1. **Mỗi pod giờ có 3 container** (app + log-shipper + ambassador) nên requests/limits mỗi pod
>    cao hơn nhiều so với thởi điểm lab gốc.
> 2. **ResourceQuota** (`babymilk-quota`, Lab 3.4) giới hạn `limits.cpu=1800m` toàn namespace —
>    đang dùng ~1450m, chỉ đủ chỗ **~1 pod mới**. Scale 10 sẽ bị quota chặn (ReplicaSet không tạo
>    được pod, xem events thấy `exceeded quota` — app không sập nhưng demo bị "khô" vì không pod
>    nào lên).
> 3. **HPA tự kéo về**: với minReplicas=1 và CPU gần 0%, scale tay lên N sẽ bị HPA kéo về 1 trong
>    vòng chục giây — scale tay KHÔNG BAO GIỜ thắng được HPA. Muốn giữ 2 pod ổn định để demo, phải
>    tạm patch `minReplicas=2` (đây là lỗi thật từng gặp khi chạy lại lab này).

### Bước 0: Xác nhận baseline
```bash
kubectl get hpa product-service-hpa -n babymilk
# Kỳ vọng: MINPODS=1, MAXPODS=3, cpu target 50%
kubectl describe resourcequota babymilk-quota -n babymilk | sed -n '1,14p'
# Xem quota còn dư bao nhiêu -> giải thích cho lớp tại sao chỉ scale lên 2
```

### Bước 1: Tạm patch HPA minReplicas=2 (TẠM, sẽ revert — bắt buộc nếu không HPA kéo về 1 ngay)
```bash
kubectl patch hpa product-service-hpa -n babymilk --type=json \
  -p='[{"op":"replace","path":"/spec/minReplicas","value":2}]'
```

### Bước 2: Scale tay lên 2
```bash
kubectl scale deployment/product-service --replicas=2 -n babymilk
kubectl rollout status deployment/product-service -n babymilk
kubectl get pods -n babymilk -l app=product-service
```

### Bước 3: Xem tài nguyên node lúc tải cao (điểm hay để giảng: Requests vs Limits)
```bash
kubectl describe node k8s-worker1 | grep -A8 "Allocated resources"
```
**Giải thích**: Requests quyết định CÓ schedule được hay không (Scheduler chỉ nhìn Requests); Limits
chỉ là trần runtime, có thể overcommit vượt cả 100% mà vẫn schedule bình thường nếu Requests còn đủ chỗ.
Nhưng với namespace có **ResourceQuota**, Limits cũng bị quota chặn ngay từ admission — 2 cơ chế độc lập.

### Bước 4: BẮT BUỘC — trả về baseline (scale 1 + HPA min1/max3/target50%)
```bash
kubectl scale deployment/product-service --replicas=1 -n babymilk
kubectl patch hpa product-service-hpa -n babymilk --type=json \
  -p='[{"op":"replace","path":"/spec/minReplicas","value":1}]'
kubectl rollout status deployment/product-service -n babymilk
kubectl get hpa product-service-hpa -n babymilk   # phải thấy MINPODS=1, MAXPODS=3, target 50%
```

---

## Lab 2.4 — Kustomize Overlay

**Mục tiêu**: Demo cấu trúc `base/` + `overlays/{prod,dev}`, verify bằng `kubectl diff -k`.
**Ảnh hưởng**: CHỈ ĐỌC/XEM — đây là cách deploy CHÍNH THỨC hiện tại của dự án, không có gì để "làm lại".

### Demo: xem cấu trúc + render thử (không apply gì)
```bash
cd ~/babymilk-k8s   # hoặc đúng đường dẫn đã scp k8s/ lên master
find . -type f -name "*.yaml" | sort
kubectl kustomize overlays/prod | head -50
```

### Demo: chứng minh "prod overlay = đúng 100% cluster đang chạy"
```bash
kubectl diff -k overlays/prod
echo "exit code: $?"
```
**Kết quả mong đợi**: KHÔNG có output gì, exit code `0` — đây là bằng chứng file trong git khớp
tuyệt đối với những gì đang chạy thật (không có drift).

### Demo: xem overlay dev (chỉ render, KHÔNG apply — không đủ tài nguyên chạy song song)
```bash
kubectl kustomize overlays/dev | grep -E "^kind:|name: babymilk-dev|nodePort|maxReplicas"
```
**Giải thích**: overlay `dev` đổi namespace → `babymilk-dev`, NodePort → `30090`, HPA maxReplicas → `1`
— minh hoạ cách 1 bộ manifest gốc phục vụ nhiều môi trường chỉ bằng patch, không copy-paste file.

### Cách deploy CHÍNH THỨC (chỉ chạy nếu thật sự cần re-sync, không cần chạy để demo)
```bash
kubectl apply -k overlays/prod
```

> 📌 **Bonus**: từ mục 18 work_done.md, dự án còn có 1 **Helm chart song song**
> (`k8s/helm/babymilk-shop/`) — mirror y hệt `k8s/base` (kể cả pattern 4-container), deploy vào
> namespace riêng `babymilk-helm`, dùng để luyện tập `helm install/upgrade/rollback` mà không đụng
> app thật. Kustomize **vẫn là cách chính thức**, Helm chỉ thêm vào — xem README.md mục "Helm chart".
