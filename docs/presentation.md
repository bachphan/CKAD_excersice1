# Thuyết trình Capstone — BabyMilk Shop

> Kịch bản nói + lệnh demo trực tiếp, dùng cho buổi chấm bài CKAD. Thời lượng gợi ý: **7-10 phút**.
> Mọi lệnh dưới đây đã test thật trên cluster live — copy-paste chạy được ngay, không cần chỉnh.

---

## 0. Chuẩn bị trước khi thuyết trình (làm 1 lần, trước giờ demo)

```bash
# Xác nhận cluster khoẻ, mở sẵn browser
bash scripts/smoke-test.sh
```

Nếu thấy `✅ TẤT CẢ 27 CHECK PASS` — sẵn sàng trình bày.

---

## 1. Mở đầu (30 giây)

> "Em làm **BabyMilk Shop** — e-commerce bán sữa công thức cho trẻ em. Bài toán: cha mẹ lọc sữa
> theo độ tuổi/thương hiệu/giá, đặt hàng nhanh; hệ thống trừ kho nguyên tử không cho bán vượt tồn
> kho dù nhiều người đặt cùng lúc; admin quản lý sản phẩm/đơn hàng và được cảnh báo tự động khi
> tồn kho thấp."

> "Toàn bộ chạy thật trên cluster Kubernetes 2 node em tự dựng bằng `kubeadm` trên VirtualBox —
> không phải cloud, không phải minikube/kind."

---

## 2. Kiến trúc tổng quan (1-2 phút)

> "5 microservice độc lập, mỗi service 1 bounded context riêng, 1 database riêng:"

| Service | Trách nhiệm | Port |
|---|---|---|
| `frontend` | Gateway + giao diện — điểm vào duy nhất của browser | 4000 |
| `product-service` | Catalog, tồn kho, trừ/hoàn kho nguyên tử | 4001 |
| `user-service` | Đăng ký/đăng nhập, JWT | 4002 |
| `order-service` | Checkout, lịch sử đơn hàng | 4003 |
| `notification-service` | **Bất đồng bộ** — nhận event qua Redis, ghi thông báo | 4004 |

> "Giao tiếp đa số là HTTP đồng bộ — nhưng có **1 luồng async thật**: sau khi checkout,
> `order-service` PUBLISH event lên Redis Pub/Sub, `notification-service` SUBSCRIBE và xử lý tách
> rời hoàn toàn khỏi luồng chính. Đây là điểm em cố tình làm để chứng minh hiểu rõ khi nào nên
> đồng bộ (trừ kho — user cần biết ngay) và khi nào nên bất đồng bộ (gửi thông báo — không ai cần
> chờ)."

Mở sơ đồ Mermaid nếu cần minh hoạ trực quan: [`docs/architecture.md`](architecture.md).

---

## 3. Demo trực tiếp — đi đúng theo checklist thầy yêu cầu (§6.3)

### 3.1 — Pod Running + Service có Endpoints

```bash
kubectl get pods -n babymilk -o wide
kubectl get endpoints -n babymilk
```

> "7/7 pod Running — 5 app (mỗi pod 4 container: init + app + sidecar log + ambassador nginx) +
> Postgres + Redis. Mọi Service đều có endpoint thật, không Service nào mồ côi."

### 3.2 — Ingress + NodePort hit được app thật

```bash
curl -s http://192.168.56.102:30080/healthz
curl -s http://192.168.56.102:30080/api/products?limit=2
curl -s -H "Host: babymilk.local" http://192.168.56.102:30369/api/products?limit=1
```

> "NodePort `30080` là đường chính. Ingress có **2 path route tới 2 backend khác nhau**:
> `/api/products` đi thẳng `product-service`, bỏ qua gateway; `/` vào `frontend`."

Hoặc mở browser: `http://192.168.56.102:30080`

### 3.3 — ConfigMap/Secret injection

```bash
kubectl exec -n babymilk deploy/product-service -c product-service -- env | grep -E "PGHOST|PGDATABASE"
kubectl get configmap babymilk-config -n babymilk -o yaml
```

> "Toàn bộ config không nhạy cảm qua ConfigMap, giá trị nhạy cảm (JWT_SECRET, password) qua Secret
> — không hardcode gì trong image."

### 3.4 — Probe behavior (liveness tách khỏi readiness)

```bash
# healthz = liveness thuần (luôn 200 nếu process sống)
kubectl exec -n babymilk deploy/order-service -c order-service -- wget -qO- http://localhost:4103/healthz
# readyz = readiness THẬT (ping Postgres)
kubectl exec -n babymilk deploy/order-service -c order-service -- wget -qO- http://localhost:4103/readyz
```

> "Em tách riêng 2 endpoint — dependency chết chỉ gỡ pod khỏi Service Endpoints (readiness fail),
> KHÔNG làm kubelet restart container khoẻ mạnh (liveness vẫn pass). Đây là hiểu đúng bản chất
> khác nhau giữa 2 loại probe, không phải dùng chung `/healthz` cho cả hai."

### 3.5 — Rolling update / Blue-Green

```bash
# Rolling update thật: nâng đúng 1 service qua Helm, không đụng service khác
kubectl get pods -n babymilk -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.creationTimestamp}{"\n"}{end}'
helm upgrade product-service-live k8s/helm/product-service --reuse-values --set hpa.maxReplicas=5
kubectl rollout status deploy/product-service -n babymilk
```

> "Vì tách 5 chart Helm độc lập, nâng cấp 1 service không đụng tới pod của 4 service còn lại — đã
> verify bằng cách so `creationTimestamp` trước/sau."

### 3.6 — HPA

```bash
kubectl get hpa -n babymilk
```

> "`product-service-hpa`: min 1 / max 3 (hoặc 5 nếu vừa demo ở trên), target CPU 50%, đọc metrics
> thật qua `metrics-server`."

### 3.7 — NetworkPolicy effect (allow vs deny)

```bash
# frontend gọi /api/products — ĐƯỢC PHÉP
kubectl exec -n babymilk deploy/frontend -c frontend -- wget -qO- http://product-service:4001/api/products?limit=1
# frontend gọi thẳng /internal/checkout — BỊ CHẶN (CiliumNetworkPolicy L7)
kubectl exec -n babymilk deploy/frontend -c frontend -- wget -qO- --post-data='' http://product-service:4001/internal/checkout
```

> "Lệnh 2 phải trả `403 Forbidden` — chặn ở tầng Cilium L7 (đọc được cả HTTP method/path), không
> phải app tự kiểm tra. Đây là NetworkPolicy HTTP-aware, vượt yêu cầu NetworkPolicy L3/L4 thông
> thường."

### 3.8 — PVC persistence (Postgres sống qua Pod delete)

```bash
kubectl exec -n babymilk deploy/postgres -- psql -U babymilk -d babymilk_products -c "SELECT COUNT(*) FROM products;"
kubectl delete pod -n babymilk -l app=postgres
kubectl wait --for=condition=Ready pod -l app=postgres -n babymilk --timeout=60s
kubectl exec -n babymilk deploy/postgres -- psql -U babymilk -d babymilk_products -c "SELECT COUNT(*) FROM products;"
```

> "Cùng 1 số lượng sản phẩm trước và sau khi xoá pod Postgres — data sống qua PVC (static PV,
> `hostPath`, `persistentVolumeReclaimPolicy: Retain`)."

### 3.9 — Helm history/rollback

```bash
helm history product-service-live
helm rollback product-service-live 1
kubectl get hpa product-service-hpa -n babymilk   # xác nhận maxReplicas trả về giá trị cũ
```

> "Helm là cách deploy **chính thức** cho toàn bộ 6 chart (`babymilk-infra` + 5 service) — không
> phải chart demo phụ. Kustomize (`k8s/base`+`k8s/overlays`) vẫn giữ trong repo, render sạch, để
> đáp ứng riêng yêu cầu Kustomize của đề bài, nhưng không còn dùng để deploy namespace live nữa."

---

## 4. Điểm nổi bật / vượt yêu cầu (1 phút)

> "Vài chỗ em cố tình làm vượt mức tối thiểu:"

- **Multi-container 4 tầng** (init + app + sidecar log + ambassador nginx) trên **cả 5 service**,
  không chỉ 1 pod minh hoạ.
- **Async pattern THẬT** qua Redis Pub/Sub — không chỉ khai báo, có consumer thật ghi data, verify
  bằng cách tạo đơn hàng và xem `GET /api/notifications` trả đúng bản ghi.
- **NetworkPolicy L7 HTTP-aware** (CiliumNetworkPolicy) — phân biệt được method/path, không chỉ
  port.
- **RBAC least-privilege thật**: `stock-monitor-sa` chỉ `get`/`list` Pod, verify bằng
  `kubectl auth can-i`.
- **Helm 6 chart độc lập**, cutover thật từ Kustomize sang Helm cho namespace live, giữ nguyên toàn
  bộ data qua static PV rebind.
- **Kubernetes v1.35.7** — upgrade thật từ `v1.31.14` bằng `kubeadm`, tuần tự qua 4 minor version,
  không cài lại cluster, không mất data.
- **12-Factor App**: soát đủ 12/12, kể cả Concurrency (biết rõ giới hạn Pub/Sub khi scale) và
  Disposability (graceful shutdown `SIGTERM` verify bằng log thật).

---

## 5. Dự phòng câu hỏi khó (Q&A)

| Câu hỏi có thể gặp | Trả lời ngắn |
|---|---|
| "Vì sao chỉ 1 Postgres, không tách DB riêng từng service?" | Schema-per-service trong 1 instance (4 database logic tách biệt) — do ngân sách cluster chỉ 1 node worker (~1.9 CPU/3.2GB). Vẫn không query chéo giữa các service. |
| "Redis Pub/Sub có đảm bảo delivery không?" | Không — cố ý chọn Pub/Sub (không phải queue bền) vì mất 1 thông báo lúc subscriber restart là chấp nhận được ở quy mô này. Nếu cần đảm bảo thật, bước tiếp theo là RabbitMQ/Kafka + outbox pattern. |
| "notification-service scale lên 2 pod có sao không?" | Có — Pub/Sub broadcast tới MỌI subscriber (khác consumer-group của Kafka), sẽ ghi trùng thông báo. Vì vậy cố định `replicaCount: 1`, không gắn HPA cho service này — biết rõ giới hạn. |
| "Sao Kustomize không còn dùng mà vẫn giữ trong repo?" | Đề bài yêu cầu riêng biệt cả Kustomize (P5) và Helm (P6) — Helm mạnh hơn hẳn (deploy độc lập từng service) nên chọn làm chính thức, Kustomize giữ lại render sạch để không mất điểm P5. |
| "Ai đảm bảo Secret không lộ lên git?" | `.gitignore` chặn file secret thật, chỉ commit `.example`. Đã grep toàn bộ lịch sử git xác nhận sạch 100%, không dính auto-fail điều kiện §7. |
| "Ambassador/sidecar để làm gì, không phải thừa thãi?" | Ambassador giữ port công khai cố định dù đổi container đứng sau — không cần sửa NetworkPolicy khi thêm layer network. Sidecar log-shipper minh hoạ pattern tail log node mà không đổi cách app ghi log (giữ 12-Factor #11). |

---

## 6. Giới hạn còn biết (thành thật, không giấu)

- Chỉ 1 worker node — chưa test PodAntiAffinity/HA thật giữa nhiều node.
- Chưa load-test đủ mạnh để thấy HPA tự scale do tải thật (đã test scale tay để verify cơ chế).
- `startupProbe` chỉ có ở `notification-service` (lý do thật: phụ thuộc Postgres+Redis lúc boot) —
  4 service còn lại khởi động nhanh (<3s) nên không cần.
- Namespace `babymilk` tự đặt tên — chưa có tên cụ thể do thầy chỉ định.

---

*Xem thêm: [`README.md`](../README.md) (tổng quan đầy đủ), [`docs/ckad-checklist.md`](ckad-checklist.md)
(map từng yêu cầu §3/§4 với bằng chứng), [`docs/architecture.md`](architecture.md) (sơ đồ Mermaid).*
