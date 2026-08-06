# 🍼 BabyMilk Shop — Capstone Project CKAD

E-commerce bán sữa bột công thức cho trẻ em, kiến trúc **4 microservice độc lập + PostgreSQL**,
container hóa và **đang chạy thật trên cụm Kubernetes 2 node tự dựng bằng kubeadm trên VirtualBox**
(không phải cloud, không phải minikube/kind) — không thiếu bất kỳ mục "Required" nào trong đề bài
Capstone CKAD.

> 📐 **Sửa/thêm manifest K8s?** Đọc [`k8s/CONVENTIONS.md`](k8s/CONVENTIONS.md) trước — quy chuẩn bắt
> buộc để mọi thay đổi sau này (kể cả do AI khác làm) vẫn nhất quán với phần đã có.
>
> ✅ **Đối chiếu từng yêu cầu Capstone**: xem [`docs/ckad-checklist.md`](docs/ckad-checklist.md) —
> map từng mục D1-O5 trong đề bài tới đúng file/lệnh verify thật.
>
> 🖼️ **Sơ đồ kiến trúc (Mermaid)**: xem [`docs/architecture.md`](docs/architecture.md).
>
> ⚡ **Chấm bài nhanh**: chạy `scripts/smoke-test.sh` — SSH vào cluster, in bằng chứng đạt đủ yêu
> cầu, mở web thật. Xem mục ["Chạy demo nhanh cho người chấm bài"](#-chạy-demo-nhanh-cho-người-chấm-bài) bên dưới.

---

## 1. Tổng quan & User story

**Bài toán**: cha mẹ cần mua sữa công thức đúng độ tuổi cho con, dễ dàng lọc theo thương hiệu/giá/độ
tuổi, đặt hàng nhanh, admin quản lý được tồn kho và đơn hàng.

**User story chính**:
1. Khách vào trang chủ, lọc sữa theo độ tuổi/thương hiệu/khoảng giá → xem chi tiết sản phẩm.
2. Khách đăng ký/đăng nhập → thêm sản phẩm vào giỏ (lưu tạm ở trình duyệt) → checkout.
3. Hệ thống trừ kho **nguyên tử** (không bán vượt tồn kho dù nhiều người đặt cùng lúc), trả lại đơn
   hàng với giá/tên đã "chụp ảnh" tại thời điểm đặt (không tin giá client gửi lên).
4. Admin xem/sửa sản phẩm, đổi trạng thái đơn hàng; hệ thống tự động cảnh báo (CronJob) khi sản phẩm
   nào tồn kho thấp.

## 2. Danh sách microservice

| Service | Port | Trách nhiệm (bounded context) | Database |
|---|---|---|---|
| **frontend** | 4000 | Static SPA (vanilla JS) + API gateway — điểm vào DUY NHẤT của browser | — |
| **product-service** | 4001 | Catalog, tồn kho, trừ/hoàn kho nguyên tử (`/internal/*`) | `babymilk_products` |
| **user-service** | 4002 | Đăng ký/đăng nhập, JWT, hồ sơ người dùng | `babymilk_users` |
| **order-service** | 4003 | Checkout, lịch sử đơn hàng, đổi trạng thái | `babymilk_orders` |
| *(hạ tầng)* postgres | 5432 | 1 instance Postgres 16, 3 database logic riêng biệt | — |
| *(hạ tầng)* stock-monitor | — | CronJob, không có port — cảnh báo tồn kho thấp hàng ngày | — |

4 service trên là **4 Deployment độc lập**, mỗi service có image Docker riêng, deploy/update riêng
(không cần rebuild service khác). Chi tiết kiến trúc + sơ đồ Mermaid: [`docs/architecture.md`](docs/architecture.md).

## 3. Trạng thái hiện tại — ĐANG CHẠY TRÊN K8S

| | |
|---|---|
| Truy cập | `http://192.168.56.102:30080` (NodePort, từ máy cùng mạng host-only với cluster) |
| Namespace | `babymilk` |
| Pods | 5/5 `Running` — 4 app pod **mỗi pod 4 container** (init + app + sidecar log + ambassador nginx) + 1 postgres |
| Database | PostgreSQL 16 (1 instance, 3 database logic riêng) |
| Deploy bằng | **Helm** (chính thức — 5 chart độc lập trong `k8s/helm/`, cài/nâng cấp riêng lẻ từng service) — **Kustomize** (`k8s/base`+`k8s/overlays`) vẫn giữ trong repo, render sạch, để đáp ứng yêu cầu đề bài |
| Admin | `admin@babymilk.local` / `admin12345` |
| Dữ liệu | 14 sản phẩm sữa mẫu (seed tự động), kèm ảnh minh hoạ theo brand |

```
NAME                               READY   STATUS    RESTARTS   NODE
frontend-7d4c8dd454-fnlrk          3/3     Running   0          k8s-worker1
order-service-558d5cf9fc-cp2kv     3/3     Running   0          k8s-worker1
postgres-65f4dddc66-d2zhc          1/1     Running   0          k8s-worker1
product-service-75fb55794c-hlnf2   3/3     Running   0          k8s-worker1
user-service-57f98dc67-qftv2       3/3     Running   0          k8s-worker1
```

### Checklist hạ tầng — đã hoàn thành (map đầy đủ với đề bài: [`docs/ckad-checklist.md`](docs/ckad-checklist.md))

- [x] **NetworkPolicy** — mặc định deny toàn bộ ingress trong namespace, mở đúng luồng cần thiết. Riêng `product-service` dùng **CiliumNetworkPolicy (L7 HTTP-aware)**: `/internal/*` chỉ `order-service` gọi được, `frontend`/`stock-monitor`/`ingress-nginx` chỉ được gọi `/api/*` — đã verify thực tế bằng cách exec vào pod `frontend` gọi thẳng `/internal/checkout`, nhận về `403 Access denied` (chặn ở tầng Cilium Envoy proxy, không phải app tự check).
- [x] **PersistentVolumeClaim** — Postgres data mount qua PVC (hostPath static provisioning, `1Gi`), đã verify: xóa pod Postgres, tạo pod mới, order/product data vẫn còn nguyên.
- [x] **HorizontalPodAutoscaler** — `product-service-hpa` (min 1 / max 3, target CPU **50%**), cần cài thêm `metrics-server` (chưa có sẵn trong cluster kubeadm, phải thêm flag `--kubelet-insecure-tls` vì kubelet dùng self-signed cert). Đã verify HPA đọc được metrics real-time; đã thử scale tay `product-service` lên 10 replicas để test (xem `lab/lab_2.3.txt`) — thành công, sau đó scale về lại 1 và để HPA quản lý.
- [x] **PostgreSQL** — chuyển hoàn toàn 3 backend từ SQLite (`better-sqlite3`, đồng bộ) sang PostgreSQL (`pg`, bất đồng bộ), giữ nguyên toàn bộ business logic (transaction nguyên tử khi checkout dùng `SELECT ... FOR UPDATE` thay cho serialize của SQLite). Đã test đầy đủ: catalog, login, checkout đa sản phẩm, huỷ đơn hoàn kho, chặn mua vượt tồn kho — cả local (Docker Postgres) lẫn trên cluster thật.
- [x] **Job/CronJob** — `stock-monitor` (CronJob, chạy 8h sáng mỗi ngày) tự tạo Job gọi API `product-service` cảnh báo sản phẩm tồn kho thấp. Consumer mới → đã xin quyền tường minh qua CiliumNetworkPolicy (không tái dùng label service khác, tránh dính nhầm vào Service selector thật).
- [x] **Kustomize** — `k8s/` tái cấu trúc thành `base/` + `overlays/{prod,dev}`, giữ nguyên trong repo và render sạch (`kubectl kustomize overlays/prod`) để đáp ứng yêu cầu đề bài. **Không còn là cách deploy live** cho `babymilk` (đã cutover sang Helm, xem mục Helm chart bên dưới) — `kubectl diff -k overlays/prod` vì vậy không còn = 0, đúng như dự kiến. `dev` = namespace/NodePort/HPA riêng, đã validate render đúng nhưng **chưa apply lên cluster** (không đủ tài nguyên chạy song song 2 bộ đầy đủ trên node worker duy nhất).
- [x] **Multi-container pod design pattern** — 4 Deployment (product/user/order-service, frontend) đều có đủ **4 container/pod**: 1 **init container** (`init-config`, ghi tóm tắt config hiệu lực vào `emptyDir` trước khi app chính khởi động), 1 **app chính**, 1 **sidecar logging** (`log-shipper`, đọc trực tiếp file log kubelet ghi trên node qua `hostPath /var/log`, KHÔNG đổi cách app ghi log ra stdout — vẫn giữ đúng 12-Factor #11), 1 **ambassador** (`ambassador-nginx`, nhận traffic ở đúng port Service/NetworkPolicy đã khai báo, forward vào app đang lắng nghe nội bộ ở `127.0.0.1:<port+100>` — app không cần biết gì về network bên ngoài pod). Đã verify thật: `kubectl logs -c <container>` cho từng container, `wget 127.0.0.1:<port>/healthz` từ trong pod xác nhận nginx proxy đúng, và test end-to-end qua NodePort thật. NetworkPolicy/CiliumNetworkPolicy **không cần sửa** vì port công khai (Service targetPort) giữ nguyên số cũ — chỉ đổi container nào đứng sau port đó.
- [x] **Helm — 5 chart độc lập** (`k8s/helm/{babymilk-infra,product-service,user-service,order-service,frontend}/`) — cách deploy **CHÍNH THỨC** cho namespace `babymilk` thật (đã cutover từ Kustomize). `babymilk-infra` quản lý namespace/config/secret/postgres/PVC/quota/networkpolicy/ingress/cronjob; 4 chart service còn lại mỗi chart 1 Deployment+Service, cài/nâng cấp/rollback **độc lập hoàn toàn** — đã verify thật: `helm upgrade product-service-live` không hề đụng tới 4 pod/chart còn lại (giữ nguyên `creationTimestamp`). PVC mới rebind đúng static PV `postgres-data-pv` cũ (giữ `persistentVolumeReclaimPolicy: Retain`) — toàn bộ data Postgres (14 sản phẩm + đơn hàng) sống sót qua cutover. `helm lint` sạch cả 5 chart, test đầy đủ `install`/`upgrade`/`rollback` trên namespace cô lập trước khi cutover vào `babymilk` thật.
- [x] **Rolling update + Rollback** đã test thật trên `product-service` (v2.0→v2.1→giả lập bản lỗi→rollback), **Blue/Green** đã test thật trên `frontend` (banner xanh lá đổi qua Service selector, đã trả về nguyên trạng sau demo). Chi tiết: `lab/lab_2.1.txt`, `lab/lab_2.2.txt`.
- [x] **SecurityContext** — cả 4 Deployment chạy `runAsNonRoot`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`. Verify: `touch` vào root filesystem bị chặn (`Read-only file system`), checkout đầy đủ luồng vẫn hoạt động 100%. Chi tiết: `lab/lab_3.2.txt`.
- [x] **ResourceQuota + LimitRange** — `babymilk-quota` (sized theo usage thật + margin, không chặn nhầm pod đang chạy) + `babymilk-limits` (min/max áp dụng mọi container). Verify bằng cách tạo pod xin vượt quota → bị từ chối đúng luật. Chi tiết: `lab/lab_3.4.txt`.
- [x] **RBAC permanent** — `stock-monitor-sa` + `Role` (chỉ `get`/`list` Pod trong namespace) + `RoleBinding`, gắn vào CronJob `stock-monitor` thật (không phải demo tạm bị xoá sau mỗi lần chạy `restore-to-baseline.sh`): 1 init container dùng SA này gọi K8s API kiểm tra `product-service` có Pod Running không trước khi gọi HTTP (fail-fast thật). Verify least-privilege bằng `kubectl auth can-i`.
- [x] **NetworkPolicy Egress** — `default-deny-egress` + allow DNS + allow đúng luồng nội bộ; backend **không ra được internet** (verify: request treo tới timeout, không có response). Chi tiết: `lab/lab_4.3.txt`.
- [x] **StorageClass động** — cài `local-path-provisioner`, verify dynamic provisioning + persistence thật (pod hoàn toàn khác, không ghi gì, vẫn đọc được data cũ). Chi tiết: `lab/lab_4.4.txt`.
- [x] **Ingress** — thử bật Cilium's built-in Ingress Controller **2 lần**, cả 2 lần đều gặp y hệt 1 bug thật của Cilium 1.19.x khi restart agent cùng kube-proxy ([issue #44464](https://github.com/cilium/cilium/issues/44464)) → **rollback** cả 2 lần, không downtime app. Chuyển sang **`ingress-nginx`** (tách biệt hoàn toàn khỏi CNI agent) — cài thành công ngay lần đầu. `Ingress` thật có **2 path route tới 2 Service khác nhau**: `/api/products` → thẳng `product-service`, `/` → `frontend`. Chi tiết đầy đủ: `lab/lab_4.2.txt`.
- [x] **12-Factor App** — soát lại theo [12factor.net](https://www.12factor.net/), đạt 11/12 lúc đầu, đã fix nốt **#9 Disposability** (graceful shutdown `SIGTERM`/`SIGINT`) → **12/12**. Verify thật bằng `kubectl delete pod` giữa lúc rolling update, thấy đúng log `SIGTERM received, shutting down gracefully...` → `server + db pool closed, exiting`.
- [x] **Ảnh sản phẩm** — 7 ảnh PNG theo brand, migration SQL tự chạy cập nhật `image_url` cho data sẵn có.

---

## 4. Chạy demo nhanh cho người chấm bài

**Cách 1 — 1 lệnh duy nhất, tự động hết** (khuyến nghị cho việc chấm bài):

```bash
bash scripts/smoke-test.sh
```

Script này (chạy từ máy có SSH access tới cluster — mặc định máy dev Windows của sinh viên):
1. SSH vào node master, chạy **toàn bộ** kiểm tra tương ứng `docs/ckad-checklist.md` (Pod/Service/
   NetworkPolicy/RBAC/Ingress/HPA/PVC...) với bằng chứng thật (không chỉ "resource tồn tại" mà còn
   test hành vi: RBAC least-privilege, NetworkPolicy chặn đúng, Ingress route đúng theo path...).
2. In bảng tổng kết PASS/FAIL theo từng domain CKAD (§4.1 → §4.5).
3. `curl` trực tiếp vào app thật (cả đường NodePort lẫn Ingress), in ra response thật.
4. Tự mở trình duyệt mặc định (Windows/Mac/Linux) vào URL app — xem được ngay giao diện thật.

**Cách 2 — Xem từng lab đã làm chi tiết**: `lab/class-demo/` có sẵn 5 file `DayN-*.md` (theo đúng 5
domain CKAD) copy-paste được, hoặc chạy `lab/class-demo/run-all-labs.sh` để chạy tự động cả 20 lab
kèm giải thích domain CKAD (mất ~10-15 phút, có `restore-to-baseline.sh` tự động ở cuối).

**Cách 3 — Đọc transcript đầy đủ**: `lab/lab_1.1.txt` → `lab/lab_5.4.txt` — log lệnh + output thật
của cả 20 lab lúc làm thật lần đầu (bao gồm cả lỗi gặp phải và cách fix).

---

## 5. Debug runbook

Khi nghi ngờ app có vấn đề, thứ tự chẩn đoán khuyến nghị (đã luyện qua `lab/lab_5.2.txt`):

```bash
# 1. Events trước tiên — timeline tổng quan toàn namespace
kubectl get events -n babymilk --sort-by=.lastTimestamp | tail -20

# 2. Describe — chi tiết 1 resource cụ thể (thấy rõ lý do Pending/CrashLoop/...)
kubectl describe pod <tên-pod> -n babymilk

# 3. Logs — log ứng dụng thật. Với pod nhiều container PHẢI chỉ định -c
kubectl logs -n babymilk deploy/product-service                      # container đầu tiên (app chính)
kubectl logs -n babymilk deploy/product-service -c log-shipper       # sidecar
kubectl logs -n babymilk deploy/product-service -c ambassador-nginx  # ambassador
kubectl logs -n babymilk <pod> --previous                            # log lần chạy TRƯỚC (nếu đã restart)

# 4. top — tài nguyên real-time (cần metrics-server)
kubectl top pods -n babymilk
kubectl top nodes

# 5. exec — vào thẳng container kiểm tra (vd network/DNS)
kubectl exec -n babymilk deploy/product-service -- wget -qO- http://localhost:4101/healthz
```

## 6. Yêu cầu môi trường (Prerequisites)

| Thành phần | Bắt buộc | Ghi chú |
|---|---|---|
| Kubernetes | ✅ | `v1.31.14` (kubeadm tự dựng — xem mục 8 để biết cách dựng lại) |
| CNI policy-capable | ✅ | Cilium v1.19.3 (NetworkPolicy L3/L4 + CiliumNetworkPolicy L7) |
| Ingress Controller | ✅ | `ingress-nginx` v1.15.1 |
| metrics-server | ✅ | Bắt buộc cho HPA, cài thêm (không có sẵn trong kubeadm) |
| StorageClass mặc định | ✅ | `local-path` (Rancher `local-path-provisioner`) |
| `kubectl` | ✅ | — |
| `helm` v3 | ✅ | Cách deploy chính thức — 5 chart trong `k8s/helm/` |
| Docker | Chỉ khi cần build lại image | Docker Desktop trên máy dev |
| Node.js ≥ 22 | Chỉ khi chạy local dev (không qua K8s) | — |

## 7. Known limitations

- **K8s version**: cluster hiện tại `v1.31.14` — đề bài gợi ý `v1.35.x` (cluster tự dựng riêng, không
  phải cluster do thầy cấp; cần xác nhận với thầy version nào là bắt buộc).
- **Namespace**: `babymilk` là tự đặt tên theo domain — cần xác nhận với thầy nếu có namespace cụ
  thể được assign.
- **Chỉ 1 worker node** — không test được PodAntiAffinity/HA thật giữa nhiều node, và overlay `dev`
  đã viết xong nhưng chưa apply song song với `prod` vì không đủ tài nguyên (~1.9 CPU/3.2GB tổng).
- **startupProbe** chưa gắn trên service thật (chỉ Recommended, không Required) — 4 service khởi
  động nhanh (<3s) nên chưa thực sự cần; đã hiểu và demo pattern này ở `lab/lab_5.1.txt`.
- **Kustomize không còn phản ánh cluster live** kể từ khi cutover sang Helm — `kubectl diff -k
  overlays/prod` không còn `= 0` (đúng như dự kiến, xem `docs/ckad-checklist.md` mục P5). Vẫn giữ
  trong repo, render sạch, để đáp ứng yêu cầu đề bài.
- **Load test chưa mạnh** — app hiện tại nhẹ, chưa từng chạm ngưỡng CPU 50% để thấy HPA tự scale-up
  thật trong điều kiện tải tự nhiên (đã test scale THỦ CÔNG lên 10 replicas để verify riêng phần
  scale — xem `lab/lab_2.3.txt` — nhưng chưa test scale TỰ ĐỘNG do tải cao thật).
- **Ingress cần domain giả** (`babymilk.local`) — chưa có DNS nội bộ, phải gọi kèm header `Host` thủ
  công hoặc sửa file hosts để test qua domain thật trên browser.

---

## 8. Cài đặt & chạy local (không qua K8s, dev nhanh)

Yêu cầu: Node.js ≥ 22, và 1 PostgreSQL để kết nối (dev nhanh nhất là chạy tạm bằng Docker).

```powershell
# 0. Chạy Postgres tạm cho local dev (nếu chưa có sẵn)
docker run -d --name babymilk-postgres-dev -e POSTGRES_PASSWORD=dev-postgres-password -e POSTGRES_USER=babymilk -p 5432:5432 postgres:16-alpine
docker exec babymilk-postgres-dev psql -U babymilk -d postgres -c "CREATE DATABASE babymilk_products;" -c "CREATE DATABASE babymilk_users;" -c "CREATE DATABASE babymilk_orders;"

cd D:\CKAD\baby-milk-shop

# 1. Cài đặt một lần: copy .env.example -> .env + npm install cho cả 4 service
npm install
npm run setup

# 2. Chạy cả 4 service cùng lúc (Ctrl+C để dừng tất cả)
npm run dev
```

Mở **http://localhost:4000**

| Tài khoản | Email | Mật khẩu |
|---|---|---|
| Admin (seed sẵn) | `admin@babymilk.local` | `admin12345` |
| Khách hàng | tự đăng ký trên web | ≥ 8 ký tự |

Dữ liệu mẫu: 14 sản phẩm sữa được seed tự động lần chạy đầu (khi bảng `products` rỗng). Muốn reset: xóa 3 database Postgres rồi tạo lại (`DROP DATABASE` + `CREATE DATABASE`), hoặc `TRUNCATE` bảng tương ứng.

Chạy riêng lẻ từng service: `npm run dev:product` / `dev:user` / `dev:order` / `dev:web`.

### Thử nhanh API bằng curl

```powershell
curl http://localhost:4000/api/products?ageRange=0-6m
curl http://localhost:4000/api/products?q=meiji"&"minPrice=400000   # PowerShell cần escape &
curl -X POST http://localhost:4000/api/auth/login -H "Content-Type: application/json" -d "{\"email\":\"admin@babymilk.local\",\"password\":\"admin12345\"}"
```

## 9. REST API

### product-service (qua gateway: `/api/...`)
| Method | Path | Auth | Mô tả |
|---|---|---|---|
| GET | `/api/products` | — | Lọc: `q, ageRange, brand, minPrice, maxPrice, sort(newest/price_asc/price_desc/name), page, limit` |
| GET | `/api/products/:id` | — | Chi tiết sản phẩm |
| GET | `/api/meta` | — | Danh sách ageRanges + brands cho bộ lọc |
| POST | `/api/products` | admin | Thêm sản phẩm |
| PUT | `/api/products/:id` | admin | Sửa sản phẩm |
| PATCH | `/api/products/:id/stock` | admin | Cập nhật tồn kho |
| DELETE | `/api/products/:id` | admin | Xóa sản phẩm |
| POST | `/internal/checkout` | X-Internal-Key (chỉ order-service, enforce bằng CiliumNetworkPolicy L7) | Trừ kho nguyên tử |
| POST | `/internal/restock` | X-Internal-Key (chỉ order-service) | Hoàn kho |

### user-service
| Method | Path | Auth | Mô tả |
|---|---|---|---|
| POST | `/api/auth/register` | — | Đăng ký → trả `{token, user}` |
| POST | `/api/auth/login` | — | Đăng nhập → trả `{token, user}` |
| GET | `/api/users/me` | user | Xem hồ sơ |
| PUT | `/api/users/me` | user | Cập nhật hồ sơ |

### order-service
| Method | Path | Auth | Mô tả |
|---|---|---|---|
| POST | `/api/orders` | user | Checkout: `{items:[{productId,quantity}], fullName, phone, address, paymentMethod(cod/bank_transfer)}` |
| GET | `/api/orders/mine` | user | Lịch sử đơn của tôi |
| GET | `/api/orders/:id` | user/admin | Chi tiết đơn (chủ đơn hoặc admin) |
| GET | `/api/orders` | admin | Tất cả đơn |
| PATCH | `/api/orders/:id/status` | admin | Đổi trạng thái (`confirmed/shipping/completed/cancelled`; hủy → hoàn kho) |

Tất cả service có `GET /healthz` (dùng cho liveness/readiness probe). Lỗi trả JSON thống nhất: `{"error": {"message": "...", "details": [...]}}`.

## 10. Biến môi trường (mỗi service có `.env.example`)

| Biến | Service | Ghi chú |
|---|---|---|
| `PORT` | tất cả | 4000-4003 |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | 3 backend | Tên biến chuẩn của `node-postgres` — `Pool` tự đọc, không cần code thêm. `PGDATABASE` khác nhau mỗi service (`babymilk_products`/`users`/`orders`), còn lại dùng chung 1 Postgres instance |
| `JWT_SECRET` | 3 backend | **phải giống nhau** ở cả 3 → K8s Secret |
| `JWT_EXPIRES_IN`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` | user | seed admin lần đầu |
| `INTERNAL_API_KEY` | product + order | **phải giống nhau** → K8s Secret |
| `PRODUCT_SERVICE_URL`, `PRODUCT_SERVICE_TIMEOUT_MS` | order | K8s: `http://product-service:4001` |
| `PRODUCT/USER/ORDER_SERVICE_URL` | frontend | target proxy → K8s Service DNS |
| `SEED_ON_START` | product | `false` để tắt seed |

## 11. Đã triển khai lên K8s — cách làm lại từ đầu

Toàn bộ quy trình dưới đây đã thực hiện thật và app đang chạy (xem mục "Trạng thái hiện tại" ở đầu file). Ghi lại đầy đủ để tái tạo khi cần (VD: sau khi xóa cluster, đổi image version...).

### 11.1. Build image (trên máy dev, cần Docker Desktop)

```bash
cd baby-milk-shop
docker build -t babymilk/product-service:2.3 ./services/product-service
docker build -t babymilk/user-service:2.1    ./services/user-service
docker build -t babymilk/order-service:2.1   ./services/order-service
docker build -t babymilk/frontend:1.2        ./services/frontend
docker pull postgres:16-alpine
```

Mỗi image backend ~58MB (`node:22-alpine`, multi-stage, non-root `USER node`; từ khi bỏ `better-sqlite3` sang `pg` — pure JS — không cần build toolchain `python3/make/g++` nữa nên image nhẹ hơn bản v1.0).

Hoặc dùng script có sẵn: `bash scripts/build.sh`

### 11.2. Đưa image vào cluster (không có registry riêng)

Chỉ cần đưa vào node **worker** (vì master bị taint, không nhận app pod):

```bash
docker save babymilk/product-service:2.3 babymilk/user-service:2.1 babymilk/order-service:2.1 babymilk/frontend:1.2 postgres:16-alpine -o babymilk-images.tar
scp babymilk-images.tar bachpt1@192.168.56.102:/tmp/
ssh bachpt1@192.168.56.102 "sudo ctr -n k8s.io images import /tmp/babymilk-images.tar"
```

### 11.3. Tạo Secret (KHÔNG commit giá trị thật lên git)

```bash
cp k8s/base/02-secret.yaml.example k8s/base/02-secret.yaml
# Sửa các giá trị REPLACE_ME_* trong file, sinh ngẫu nhiên bằng:
openssl rand -hex 24   # JWT_SECRET
openssl rand -hex 16   # INTERNAL_API_KEY, POSTGRES_PASSWORD
kubectl apply -f k8s/base/02-secret.yaml
```

`k8s/base/02-secret.yaml` đã nằm trong `.gitignore` — không bao giờ push file này lên git. Secret KHÔNG nằm trong `kustomization.yaml` (áp dụng tách riêng, xem lý do ở mục Kustomize bên dưới).

### 11.4. Cài metrics-server (bắt buộc để HPA hoạt động, không có sẵn trong kubeadm)

```bash
curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -o metrics-server.yaml
# Thêm dòng "- --kubelet-insecure-tls" vào phần args của container metrics-server
# (kubelet dùng cert tự ký do kubeadm tạo, metrics-server mặc định không tin cậy được)
kubectl apply -f metrics-server.yaml
```

### 11.5. Cài ingress-nginx (bắt buộc cho Ingress)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml
```

### 11.6. Tạo thư mục hostPath trên worker (cho PV static provisioning)

```bash
ssh bachpt1@192.168.56.102 "sudo mkdir -p /mnt/babymilk-data/postgres && sudo chown -R 999:999 /mnt/babymilk-data/postgres"
```

### 11.7. Deploy bằng Helm (CHÍNH THỨC — 5 chart độc lập)

`babymilk-infra` PHẢI cài trước (4 chart service tham chiếu ConfigMap/Secret do chart này tạo):

```bash
cd k8s/helm

# 1. babymilk-infra — namespace/config/secret/postgres/PVC/quota/networkpolicy/ingress/cronjob
helm install babymilk-infra ./babymilk-infra \
  --set namespace=babymilk \
  --set secrets.jwtSecret=$(openssl rand -hex 24) \
  --set secrets.internalApiKey=$(openssl rand -hex 16) \
  --set secrets.postgresPassword=$(openssl rand -hex 16) \
  --set-string secrets.adminPassword='Some-Strong-Pass!' \
  --set ingress.host=babymilk.local

# 2. 4 chart service — độc lập, cài theo thứ tự nào cũng được
helm install product-service-live ./product-service --set namespace=babymilk
helm install user-service-live    ./user-service    --set namespace=babymilk
helm install order-service-live   ./order-service    --set namespace=babymilk
helm install frontend-live        ./frontend         --set namespace=babymilk --set nodePort=30080
```

Nâng cấp **1 service** mà không đụng 4 chart còn lại (lợi ích chính của việc tách chart):

```bash
helm upgrade product-service-live ./product-service --set namespace=babymilk --reuse-values
```

Rollback về revision trước của đúng 1 chart:

```bash
helm rollback product-service-live 1
```

Values quan trọng: `namespace`, `image`/`imagePullPolicy` (mỗi chart service), `hpa.*`
(`product-service`), `nodePort` (`frontend`), `postgres.volumeName`/`postgres.createStaticPV`
(`babymilk-infra` — dùng khi cần bind vào static PV có sẵn thay vì dynamic provisioning),
`secrets.manage` (`babymilk-infra` — đặt `false` để KHÔNG ghi đè Secret đã tồn tại sẵn).

### 11.8. Deploy bằng Kustomize (giữ để đáp ứng đề bài — KHÔNG còn dùng cho `babymilk` live)

```bash
kubectl kustomize k8s/overlays/prod   # chỉ render + validate, KHÔNG apply lên babymilk thật nữa
```

Trước cutover sang Helm, đây từng là cách deploy chính thức (`kubectl apply -k k8s/overlays/prod`,
`prod` = namespace `babymilk`, NodePort `30080`). Vẫn giữ nguyên trong repo, đồng bộ tính năng với
5 chart Helm (xem `k8s/CONVENTIONS.md` mục 2 "feature parity"), để đáp ứng yêu cầu Kustomize trong
đề bài — không apply lên cluster live để tránh 2 công cụ cùng quản lý 1 resource.

### 11.9. Kiểm tra & truy cập

```bash
kubectl get pods -n babymilk -o wide          # 5 pod phải Running (4 app 3/3 hoặc 4/4 lúc init, postgres 1/1)
kubectl get hpa -n babymilk                    # xem HPA đọc được metrics chưa
kubectl get cronjob -n babymilk                 # xem CronJob stock-monitor
curl http://192.168.56.102:30080/healthz        # test từ máy host
```

Mở trình duyệt: **http://192.168.56.102:30080** — hoặc chạy `bash scripts/smoke-test.sh` để tự động hoá toàn bộ bước kiểm tra + mở trình duyệt.

### Helm — cấu trúc `k8s/helm/` (CHÍNH THỨC, 5 chart độc lập)

```
k8s/helm/
├── babymilk-infra/               # PHẢI cài trước — 4 chart service tham chiếu ConfigMap/Secret của chart này
│   ├── Chart.yaml
│   ├── values.yaml                # namespace, secrets.*, postgres.*, ingress.host, resourceQuota.*
│   └── templates/
│       ├── namespace.yaml
│       ├── configmap.yaml
│       ├── secret.yaml            # có {{- if .Values.secrets.manage }} — xem values.yaml
│       ├── postgres.yaml          # Deployment Postgres 16 + Service + ConfigMap init-databases
│       ├── pvc.yaml                # PV (tuỳ chọn, {{- if .Values.postgres.createStaticPV }}) + PVC
│       ├── resourcequota.yaml     # + LimitRange
│       ├── networkpolicy.yaml     # NetworkPolicy L3/L4 + CiliumNetworkPolicy L7
│       ├── ingress.yaml            # 2 path -> 2 backend khác nhau
│       └── stock-monitor.yaml     # CronJob + ServiceAccount/Role/RoleBinding
├── product-service/               # mỗi chart service: Chart.yaml + values.yaml + templates/deployment.yaml
├── user-service/                  # (Deployment 4-container init+app+sidecar+ambassador + Service)
├── order-service/
└── frontend/                      # Service NodePort :30080
```

Mỗi Deployment backend: `replicas: 1`, `imagePullPolicy: Never` (image chỉ có local trên worker, không có registry để pull), resource `requests: 50m CPU/32-64Mi RAM`, `limits: 100-150m CPU/64-256Mi RAM`, `readinessProbe`/`livenessProbe` qua `GET /healthz`. Postgres: `requests: 100m/128Mi`, `limits: 300m/384Mi`, probe bằng `pg_isready`. Lệnh cài đặt đầy đủ + upgrade/rollback độc lập từng chart: xem mục 11.7 ở trên.

### Multi-container pod pattern (init + sidecar + ambassador)

Xem sơ đồ Mermaid + giải thích đầy đủ tại [`docs/architecture.md`](docs/architecture.md). Tóm tắt:

| Container | Vai trò | Port |
|---|---|---|
| `init-config` (init container) | Ghi tóm tắt config hiệu lực (đọc từ ConfigMap) vào `emptyDir` rồi thoát | — |
| `<service-name>` (app chính) | Node.js app thật, KHÔNG đổi gì về logic — chỉ đổi `PORT` sang nội bộ `127.0.0.1:<gốc+100>` | 4101/4102/4103/4100 (nội bộ) |
| `log-shipper` (sidecar) | `busybox tail -F` đọc trực tiếp file log kubelet ghi ở node — app **vẫn ghi log ra stdout** như cũ, không phá 12-Factor #11 | — |
| `ambassador-nginx` | nginx nhận traffic ở đúng port công khai cũ, `proxy_pass` vào app ở `127.0.0.1` | 4001/4002/4003/4000 (công khai) |

Vì port công khai (Service `targetPort`) **giữ nguyên số cũ**, chỉ đổi container nào lắng nghe ở đó → **không cần sửa bất kỳ NetworkPolicy/CiliumNetworkPolicy nào**. `log-shipper` và `ambassador-nginx` chạy `runAsUser: 0` (root) — đánh đổi có chủ đích: log file trên node do kubelet ghi (`640 root:root`) chỉ root đọc được, và nginx image cần `chown` nội bộ lúc khởi động dù chạy root.

### Kustomize — cấu trúc `k8s/base` + `k8s/overlays` (giữ để đáp ứng đề bài, KHÔNG còn deploy live)

```
k8s/
├── base/                        # toàn bộ manifest gốc + kustomization.yaml — đồng bộ tính năng với helm/
│   ├── kustomization.yaml
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secret.yaml.example   # copy thành 02-secret.yaml (gitignored), apply riêng, KHÔNG qua kustomize
│   ├── 05-ambassador-nginx-config.yaml  # ConfigMap nginx.conf cho container ambassador (4 service)
│   ├── 10-product-service.yaml  # Deployment 4-container (init+app+sidecar+ambassador) + Service
│   ├── 11-user-service.yaml     # (cùng pattern 4-container)
│   ├── 12-order-service.yaml    # (cùng pattern 4-container)
│   ├── 13-frontend.yaml         # (cùng pattern 4-container) — Service NodePort :30080
│   ├── 20-networkpolicy.yaml    # NetworkPolicy Ingress L3/L4 + CiliumNetworkPolicy L7
│   ├── 21-networkpolicy-egress.yaml  # NetworkPolicy Egress (default-deny + allow DNS/nội bộ)
│   ├── 30-pv-pvc.yaml           # PV/PVC Postgres (hostPath static)
│   ├── 40-hpa.yaml              # HPA product-service (min1/max3, CPU 50%)
│   ├── 50-postgres.yaml         # Deployment Postgres 16 + Service + ConfigMap init-databases
│   ├── 60-stock-monitor.yaml    # CronJob cảnh báo tồn kho thấp
│   ├── 61-stock-monitor-rbac.yaml    # ServiceAccount+Role+RoleBinding riêng cho CronJob (RBAC thật)
│   ├── 70-resourcequota.yaml    # ResourceQuota namespace babymilk
│   ├── 71-limitrange.yaml       # LimitRange namespace babymilk (đi kèm ResourceQuota)
│   └── 80-ingress.yaml          # Ingress babymilk-ingress (2 path -> 2 backend khác nhau)
└── overlays/
    ├── prod/kustomization.yaml  # resources: [../../base], KHÔNG patch — trước cutover từng = cluster thật
    └── dev/kustomization.yaml   # namespace babymilk-dev, NodePort 30090, HPA max=1, CronJob suspend
                                  # (chưa apply lên cluster — không đủ tài nguyên chạy song song với prod)
```

### Việc có thể làm tiếp (chưa làm — ngoài phạm vi hiện tại)

- [ ] `PodDisruptionBudget`.
- [ ] Load test mạnh hơn (`k6`, `hey`) để thực sự quan sát HPA scale-up tự động do tải cao thật.
- [ ] Thêm init container `wait-for-postgres` cho 3 backend (khác `init-config` hiện có — container đó chỉ ghi tóm tắt config, không chờ Postgres).
- [ ] Thêm worker node thứ 2 để test PodAntiAffinity / HA thật, và apply thật overlay `dev` song song `prod`.
- [ ] `startupProbe` trên workload thật (hiện chỉ demo trên pod giả lập — Recommended, không Required).

## 12. Môi trường hạ tầng (K8s cluster)

Cluster Kubernetes 2 node dựng bằng `kubeadm` trên 2 VM VirtualBox (không dùng cloud/minikube/kind):

| | Node master | Node worker |
|---|---|---|
| VM name (VirtualBox) | `k8s_mtr` | `worker_1` |
| Hostname trong cluster | `bachpt1` | `k8s-worker1` |
| Vai trò | control-plane (taint `NoSchedule` — không nhận app pod) | chạy toàn bộ app workload |
| IP (host-only network) | `192.168.56.103` | `192.168.56.102` |
| OS | Ubuntu Server 26.04 LTS | Ubuntu Server 26.04 LTS |
| Kubernetes | v1.31.14 | v1.31.14 |
| Container runtime | containerd 2.2.2 | containerd 2.2.2 |
| CPU / RAM (allocatable) | 2 core / 3.3GB | 2 core / 3.3GB |
| Disk | 23GB (đã extend LVM từ 12GB mặc định) | 23GB (đã extend LVM từ 12GB mặc định) |

- **CNI**: Cilium v1.19.3 (kèm Cilium Envoy DaemonSet) — thay cho Calico, dùng cho cả L3/L4 NetworkPolicy chuẩn K8s lẫn L7 HTTP-aware CiliumNetworkPolicy.
- **metrics-server**: v0.8.1, cài thêm cho HPA (không có sẵn trong kubeadm), patch `--kubelet-insecure-tls` vì kubelet dùng cert tự ký.
- **StorageClass**: `local-path` (Rancher `local-path-provisioner`) — dynamic provisioning thật, cài thêm vì cluster kubeadm không có sẵn.
- **Ingress Controller**: `ingress-nginx` v1.15.1 (NodePort `80:30369`/`443:31810`) — cài đè lên sau khi Cilium's built-in Ingress Controller dính bug thật 2 lần (agent Cilium kẹt khi restart cùng kube-proxy trên Cilium 1.19.x — [issue #44464](https://github.com/cilium/cilium/issues/44464)). `ingress-nginx` chạy tách biệt hoàn toàn khỏi CNI agent nên không dính lại vấn đề đó.
- **Helm**: cài trên node master (`helm version` v3.21.3) — dùng cho ví dụ luyện tập riêng (`lab/lab_5.4.txt`) **và** chart `k8s/helm/babymilk-shop/` deploy song song.
- **Network**: mỗi VM có 2 network adapter — NAT (ra internet) + Host-only Adapter (`192.168.56.0/24`, dùng cho giao tiếp giữa các node và từ máy host vào cluster).
- **Vì master bị taint `control-plane:NoSchedule`**, toàn bộ app chỉ chạy được trên **node worker duy nhất** — ngân sách tài nguyên thực tế cho app: ~1.9 CPU / ~3.2GB RAM.
- Không có image registry riêng — image build bằng Docker Desktop trên máy dev (Windows), sau đó `docker save` → `scp` → `ctr -n k8s.io images import` trực tiếp vào containerd của node worker.
- Chi tiết đầy đủ quá trình dựng cluster (bao gồm các lỗi đã gặp và cách fix: VT-x, trùng IP NAT giữa 2 node, LVM chỉ cấp phát nửa đĩa...) xem tại `../work_done.md` và `../setup_guide.md` trong repo hạ tầng.

## 13. Cấu trúc thư mục

```
baby-milk-shop/
├── README.md                  # file này
├── docs/
│   ├── architecture.md        # sơ đồ Mermaid + giải thích kiến trúc
│   └── ckad-checklist.md      # map đầy đủ §4 yêu cầu -> file/lệnh verify
├── package.json               # scripts: setup, dev (concurrently cả 4 service)
├── scripts/
│   ├── setup.mjs              # copy .env + npm install tất cả (dev local)
│   ├── build.sh                # build 4 image Docker
│   ├── deploy.sh                # apply Kustomize vào cluster
│   └── smoke-test.sh            # SSH + verify toàn bộ capstone checklist + mở web
├── k8s/                       # manifest K8s — xem chi tiết mục 11
│   ├── helm/                  # 5 chart Helm ĐỘC LẬP — cách deploy chính thức
│   │   ├── babymilk-infra/    # namespace/config/secret/postgres/PVC/quota/networkpolicy/ingress/cronjob
│   │   └── {product,user,order}-service/, frontend/   # mỗi chart 1 Deployment+Service
│   ├── base/                  # Kustomize — giữ để đáp ứng đề bài, không còn deploy live
│   └── overlays/{prod,dev}/
├── lab/                        # 20 lab CKAD đã làm thật (transcript + script tự động)
│   ├── lab_1.1.txt ... lab_5.4.txt
│   └── class-demo/             # bản chuẩn hoá demo trước lớp (Day1-5.md + run-dayN.sh)
└── services/
    ├── product-service/       # :4001 — Express + PostgreSQL (products)
    │   ├── migrations/*.sql   # schema SQL (SERIAL PRIMARY KEY)
    │   ├── src/{server,db,seed,constants}.js
    │   ├── src/lib/{auth,errors,validate}.js
    │   ├── src/routes/{products,internal}.js
    │   ├── Dockerfile         # multi-stage node:22-alpine
    │   └── .env.example
    ├── user-service/          # :4002 — auth JWT, scrypt password
    ├── order-service/         # :4003 — checkout, gọi product-service có timeout
    └── frontend/              # :4000 — static + gateway (0 dependency), SPA vanilla JS
        ├── server.js
        └── public/{index.html, css/style.css, js/{app,api,store}.js}
```
