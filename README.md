# 🍼 BabyMilk Shop — E-commerce sữa bột cho bé (demo học tập CKAD)

Ứng dụng web bán sữa bột chia thành **4 microservice độc lập + PostgreSQL**, container hóa và **đang chạy thật trên cụm Kubernetes tự dựng bằng kubeadm trên VirtualBox** (không phải cloud, không phải minikube) — kèm đầy đủ NetworkPolicy (L3/L4 + L7), PersistentVolume, và HorizontalPodAutoscaler.

## ✅ Trạng thái hiện tại: ĐANG CHẠY TRÊN K8S — NetworkPolicy + PVC + HPA + PostgreSQL + CronJob + Kustomize

| | |
|---|---|
| Truy cập | `http://192.168.56.102:30080` (từ máy trong cùng mạng host-only với cluster) |
| Namespace | `babymilk` |
| Pods | 5/5 `Running` (4 app + 1 postgres), tất cả trên node `k8s-worker1` |
| Database | PostgreSQL 16 (1 instance, 3 database logic: `babymilk_products/users/orders`) |
| Deploy bằng | Kustomize — `kubectl apply -k k8s/overlays/prod` (xem mục "Deploy" bên dưới) |
| Admin | `admin@babymilk.local` / `admin12345` |
| Dữ liệu | 14 sản phẩm sữa mẫu, seed tự động |

```
NAME                               READY   STATUS    RESTARTS   NODE
frontend-5f7f9c77f-67mtb           1/1     Running   0          k8s-worker1
order-service-6bfd6b99f-rjpb4      1/1     Running   2          k8s-worker1
postgres-65f4dddc66-zv676          1/1     Running   0          k8s-worker1
product-service-65cc887fdd-968st   1/1     Running   1          k8s-worker1
user-service-7b4bd6cf99-74g76      1/1     Running   2          k8s-worker1
```

### Checklist hạ tầng — đã hoàn thành

- [x] **NetworkPolicy** — mặc định deny toàn bộ ingress trong namespace, mở đúng luồng cần thiết. Riêng `product-service` dùng **CiliumNetworkPolicy (L7 HTTP-aware)**: `/internal/*` chỉ `order-service` gọi được, `frontend` + `stock-monitor` (CronJob) chỉ được gọi `/api/*` — đã verify thực tế bằng cách exec vào pod `frontend` gọi thẳng `/internal/checkout`, nhận về `403 Access denied` (chặn ở tầng Cilium Envoy proxy, không phải app tự check).
- [x] **PersistentVolumeClaim** — Postgres data mount qua PVC (hostPath static provisioning, `1Gi`), đã verify: xóa pod Postgres, tạo pod mới, order/product data vẫn còn nguyên.
- [x] **HorizontalPodAutoscaler** — `product-service-hpa` (min 1 / max 3, target CPU **50%**), cần cài thêm `metrics-server` (chưa có sẵn trong cluster kubeadm, phải thêm flag `--kubelet-insecure-tls` vì kubelet dùng self-signed cert). Đã verify HPA đọc được metrics real-time; đã thử scale tay `product-service` lên 10 replicas để test (xem `lab/lab_2.3.txt`) — thành công, sau đó scale về lại 1 và để HPA quản lý.
- [x] **PostgreSQL** — chuyển hoàn toàn 3 backend từ SQLite (`better-sqlite3`, đồng bộ) sang PostgreSQL (`pg`, bất đồng bộ), giữ nguyên toàn bộ business logic (transaction nguyên tử khi checkout dùng `SELECT ... FOR UPDATE` thay cho serialize của SQLite). Đã test đầy đủ: catalog, login, checkout đa sản phẩm, huỷ đơn hoàn kho, chặn mua vượt tồn kho — cả local (Docker Postgres) lẫn trên cluster thật.
- [x] **Job/CronJob** — `stock-monitor` (CronJob, chạy 8h sáng mỗi ngày) tự tạo Job gọi API `product-service` cảnh báo sản phẩm tồn kho thấp. Consumer mới → đã xin quyền tường minh qua CiliumNetworkPolicy (không tái dùng label service khác, tránh dính nhầm vào Service selector thật).
- [x] **Kustomize** — `k8s/` tái cấu trúc thành `base/` + `overlays/{prod,dev}`. `prod` = đúng cấu hình đang chạy thật (verify bằng `kubectl diff -k` = 0 khác biệt trước khi chuyển hẳn cách deploy). `dev` = namespace/NodePort/HPA riêng, đã validate render đúng nhưng **chưa apply lên cluster** (không đủ tài nguyên chạy song song 2 bộ đầy đủ trên node worker duy nhất).
- [x] **Rolling update + Rollback** đã test thật trên `product-service` (v2.0→v2.1→giả lập bản lỗi→rollback), **Blue/Green** đã test thật trên `frontend` (banner xanh lá đổi qua Service selector, đã trả về nguyên trạng sau demo). Chi tiết: `lab/lab_2.1.txt`, `lab/lab_2.2.txt`.
- [x] **SecurityContext** — cả 4 Deployment chạy `runAsNonRoot`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`. Verify: `touch` vào root filesystem bị chặn (`Read-only file system`), checkout đầy đủ luồng vẫn hoạt động 100%. Chi tiết: `lab/lab_3.2.txt`.
- [x] **ResourceQuota** — `babymilk-quota` (sized theo usage thật + margin, không chặn nhầm pod đang chạy), verify bằng cách tạo pod xin vượt quota → bị từ chối đúng luật. Chi tiết: `lab/lab_3.4.txt`.
- [x] **NetworkPolicy Egress** — `default-deny-egress` + allow DNS + allow đúng luồng nội bộ; backend **không ra được internet** (verify: request treo tới timeout, không có response). Chi tiết: `lab/lab_4.3.txt`.
- [x] **StorageClass động** — cài `local-path-provisioner`, verify dynamic provisioning + persistence thật (pod hoàn toàn khác, không ghi gì, vẫn đọc được data cũ). Chi tiết: `lab/lab_4.4.txt`.
- [ ] **Ingress** — thử bật Cilium Ingress Controller, gặp sự cố hạ tầng thật (agent Cilium trên node worker kẹt >10 phút, phải reboot node để khắc phục) → đã **rollback**, chưa hoàn thành. Chi tiết đầy đủ (nguyên nhân + cách khắc phục): `lab/lab_4.2.txt`.
- [x] **12-Factor App** — soát lại theo [12factor.net](https://www.12factor.net/), đạt 11/12 (Config, Backing services, Build/release/run, Processes stateless, Port binding, Concurrency, Dev/prod parity, Logs, Admin processes đều đạt). Điểm thiếu duy nhất (**#9 Disposability** — graceful shutdown) đã fix: cả 4 service bắt `SIGTERM`/`SIGINT`, đóng HTTP server + connection pool trước khi thoát thay vì bị kill đột ngột. Verify thật bằng `kubectl delete pod` giữa lúc rolling update, thấy đúng log `SIGTERM received, shutting down gracefully...` → `server + db pool closed, exiting`.

## 🖥️ Môi trường hạ tầng (K8s cluster)

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
- **Helm**: cài trên node master (`helm version` v3.21.3) — chỉ dùng cho ví dụ luyện tập riêng (`lab/lab_5.4.txt`), KHÔNG dùng để quản lý baby-milk-shop (vẫn dùng Kustomize).
- **Network**: mỗi VM có 2 network adapter — NAT (ra internet) + Host-only Adapter (`192.168.56.0/24`, dùng cho giao tiếp giữa các node và từ máy host vào cluster).
- **Vì master bị taint `control-plane:NoSchedule`**, toàn bộ app (kể cả baby-milk-shop) chỉ chạy được trên **node worker duy nhất** — ngân sách tài nguyên thực tế cho app: ~1.9 CPU / ~3.2GB RAM.
- Không có image registry riêng — image build bằng Docker Desktop trên máy dev (Windows), sau đó `docker save` → `scp` → `ctr -n k8s.io images import` trực tiếp vào containerd của node worker.
- Chi tiết đầy đủ quá trình dựng cluster (bao gồm các lỗi đã gặp và cách fix: VT-x, trùng IP NAT giữa 2 node, LVM chỉ cấp phát nửa đĩa...) xem tại `../work_done.md` và `../setup_guide.md` trong repo hạ tầng.

## Kiến trúc

```
Trình duyệt ──> frontend :4000 (static + API gateway, Node thuần 0 dependency)
                   │ proxy /api/*
                   ├── /api/products, /api/meta ──> product-service :4001 ──┐
                   ├── /api/auth, /api/users    ──> user-service    :4002   ├──> PostgreSQL
                   └── /api/orders              ──> order-service   :4003 ──┘   (3 database
                                                        │ POST /internal/checkout|restock          riêng)
                                                        │ (X-Internal-Key, CHỈ order-service
                                                        │  được gọi — enforce bằng CiliumNetworkPolicy L7)
                                                        └────────> product-service (trừ/hoàn kho nguyên tử)
```

- **Tech stack backend**: Node.js 22 + Express 5 + `pg` (PostgreSQL, bất đồng bộ) + JWT (`jsonwebtoken`) + scrypt (built-in `node:crypto`) — mỗi backend chỉ có **3 dependency**.
- **Frontend**: vanilla HTML/CSS/JS SPA (hash routing), không build step. Server tĩnh kiêm gateway giúp trình duyệt chỉ gọi 1 origin → không cần CORS, và map thẳng sang Ingress khi lên K8s.
- **Database**: PostgreSQL 16 (1 instance dùng chung, 3 database logic `babymilk_products`/`babymilk_users`/`babymilk_orders` — đúng tinh thần "database-per-service" nhưng tiết kiệm tài nguyên hơn 3 Postgres riêng biệt, phù hợp ngân sách 1 node worker). Schema tạo bằng migration SQL tự chạy khi service khởi động (`SERIAL PRIMARY KEY`, ANSI SQL).
- **Auth**: user-service phát JWT; product/order-service tự verify bằng `JWT_SECRET` chung (stateless, không gọi chéo).
- **Checkout**: order-service gọi `POST /internal/checkout` của product-service — kiểm tra + trừ tồn kho **nguyên tử trong 1 transaction Postgres thật** (`BEGIN` / `SELECT ... FOR UPDATE` khoá dòng chống race condition / `COMMIT`), trả về snapshot giá/tên để lưu vào đơn (không tin giá client gửi). Hủy đơn → hoàn kho. Gọi chéo có **timeout 5s**, service chết → trả 503, không crash.
- **NetworkPolicy 2 tầng**: L3/L4 chuẩn K8s (`frontend` → `user-service`/`order-service`; 3 backend → `postgres`), và L7 HTTP-aware riêng cho `product-service` qua CiliumNetworkPolicy (path-based, phân biệt `/api/*` vs `/internal/*` dù cùng 1 port).
- **Giỏ hàng** lưu ở localStorage phía client (nhẹ, không cần state server); đăng nhập chỉ bắt buộc lúc checkout.

## Chạy trên Windows (cần Postgres local hoặc Docker)

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

## REST API

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

## Biến môi trường (mỗi service có `.env.example`)

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

## 🚀 Đã triển khai lên K8s — cách làm lại từ đầu

Toàn bộ quy trình dưới đây đã thực hiện thật và app đang chạy (xem mục "Trạng thái hiện tại" ở đầu file). Ghi lại đầy đủ để tái tạo khi cần (VD: sau khi xóa cluster, đổi image version...).

### 1. Build image (trên máy dev, cần Docker Desktop)

```bash
cd baby-milk-shop
docker build -t babymilk/product-service:2.2 ./services/product-service
docker build -t babymilk/user-service:2.1    ./services/user-service
docker build -t babymilk/order-service:2.1   ./services/order-service
docker build -t babymilk/frontend:1.1        ./services/frontend
docker pull postgres:16-alpine
```

Mỗi image backend ~58MB (`node:22-alpine`, multi-stage, non-root `USER node`; từ khi bỏ `better-sqlite3` sang `pg` — pure JS — không cần build toolchain `python3/make/g++` nữa nên image nhẹ hơn bản v1.0).

### 2. Đưa image vào cluster (không có registry riêng)

Chỉ cần đưa vào node **worker** (vì master bị taint, không nhận app pod):

```bash
docker save babymilk/product-service:2.2 babymilk/user-service:2.1 babymilk/order-service:2.1 babymilk/frontend:1.1 postgres:16-alpine -o babymilk-images.tar
scp babymilk-images.tar bachpt1@192.168.56.102:/tmp/
ssh bachpt1@192.168.56.102 "sudo ctr -n k8s.io images import /tmp/babymilk-images.tar"
```

### 3. Tạo Secret (KHÔNG commit giá trị thật lên git)

```bash
cp k8s/base/02-secret.yaml.example k8s/base/02-secret.yaml
# Sửa các giá trị REPLACE_ME_* trong file, sinh ngẫu nhiên bằng:
openssl rand -hex 24   # JWT_SECRET
openssl rand -hex 16   # INTERNAL_API_KEY, POSTGRES_PASSWORD
kubectl apply -f k8s/base/02-secret.yaml
```

`k8s/base/02-secret.yaml` đã nằm trong `.gitignore` — không bao giờ push file này lên git. Secret KHÔNG nằm trong `kustomization.yaml` (áp dụng tách riêng, xem lý do ở mục Kustomize bên dưới).

### 4. Cài metrics-server (bắt buộc để HPA hoạt động, không có sẵn trong kubeadm)

```bash
curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -o metrics-server.yaml
# Thêm dòng "- --kubelet-insecure-tls" vào phần args của container metrics-server
# (kubelet dùng cert tự ký do kubeadm tạo, metrics-server mặc định không tin cậy được)
kubectl apply -f metrics-server.yaml
```

### 5. Tạo thư mục hostPath trên worker (cho PV static provisioning)

```bash
ssh bachpt1@192.168.56.102 "sudo mkdir -p /mnt/babymilk-data/postgres && sudo chown -R 999:999 /mnt/babymilk-data/postgres"
```

### 6. Deploy bằng Kustomize

```bash
kubectl apply -k k8s/overlays/prod
```

`prod` = đúng cấu hình đang chạy thật (namespace `babymilk`, NodePort `30080`). Trước khi deploy lần đầu hoặc sau khi sửa manifest, luôn kiểm tra trước bằng:

```bash
kubectl kustomize k8s/overlays/prod   # render thử, xem có ra đúng YAML mong đợi không
kubectl diff -k k8s/overlays/prod     # so sánh với cluster đang chạy TRƯỚC khi apply
```

### 7. Kiểm tra & truy cập

```bash
kubectl get pods -n babymilk -o wide          # 5 pod phải Running 1/1 (4 app + postgres)
kubectl get hpa -n babymilk                    # xem HPA đọc được metrics chưa
kubectl get cronjob -n babymilk                 # xem CronJob stock-monitor
curl http://192.168.56.102:30080/healthz        # test từ máy host
```

Mở trình duyệt: **http://192.168.56.102:30080**

### Kustomize — cấu trúc `k8s/`

```
k8s/
├── base/                        # toàn bộ manifest gốc + kustomization.yaml
│   ├── kustomization.yaml
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secret.yaml.example   # copy thành 02-secret.yaml (gitignored), apply riêng, KHÔNG qua kustomize
│   ├── 10-product-service.yaml
│   ├── 11-user-service.yaml
│   ├── 12-order-service.yaml
│   ├── 13-frontend.yaml         # Service NodePort :30080
│   ├── 20-networkpolicy.yaml    # NetworkPolicy Ingress L3/L4 + CiliumNetworkPolicy L7
│   ├── 21-networkpolicy-egress.yaml  # NetworkPolicy Egress (default-deny + allow DNS/nội bộ)
│   ├── 30-pv-pvc.yaml           # PV/PVC Postgres (hostPath static)
│   ├── 40-hpa.yaml              # HPA product-service (min1/max3, CPU 50%)
│   ├── 60-stock-monitor.yaml    # CronJob cảnh báo tồn kho thấp
│   └── 70-resourcequota.yaml    # ResourceQuota namespace babymilk
└── overlays/
    ├── prod/kustomization.yaml  # resources: [../../base], KHÔNG patch — đúng cấu hình chạy thật
    └── dev/kustomization.yaml   # namespace babymilk-dev, NodePort 30090, HPA max=1, CronJob suspend
                                  # (chưa apply lên cluster — không đủ tài nguyên chạy song song với prod)
```

Mỗi Deployment backend: `replicas: 1`, `imagePullPolicy: Never` (image chỉ có local trên worker, không có registry để pull), resource `requests: 50m CPU/32-64Mi RAM`, `limits: 100-150m CPU/64-256Mi RAM`, `readinessProbe`/`livenessProbe` qua `GET /healthz`. Postgres: `requests: 100m/128Mi`, `limits: 300m/384Mi`, probe bằng `pg_isready`, data mount qua PVC.

### Việc có thể làm tiếp (chưa làm — ngoài phạm vi hiện tại)

- [ ] `PodDisruptionBudget`.
- [ ] Ingress (Cilium có sẵn Ingress support) thay cho NodePort — đã thử 1 lần, gặp sự cố hạ tầng (Cilium agent kẹt), đã rollback. Cần thử lại cẩn thận hơn (xem `lab/lab_4.2.txt` để biết chi tiết + rủi ro).
- [ ] Load test mạnh hơn (nhiều pod song song / công cụ như `k6`, `hey`) để thực sự quan sát HPA scale-up — app hiện tại quá nhẹ nên chưa chạm ngưỡng CPU 50% trong test thủ công (đã scale tay lên 10 replicas để test riêng phần scale, xem `lab/lab_2.3.txt`).
- [ ] Thêm init container `wait-for-postgres` cho 3 backend — hiện tại nếu Postgres chưa sẵn sàng lúc pod backend start, pod sẽ crash rồi tự retry theo cơ chế restart mặc định của K8s (chấp nhận được, nhưng init container sẽ gọn hơn).
- [ ] Thêm worker node thứ 2 để test PodAntiAffinity / HA thật, và có đủ tài nguyên apply thật overlay `dev` song song với `prod`.
- [x] ~~Tăng `timeoutSeconds` cho readiness/liveness probe~~ — đã fix, `timeoutSeconds: 3` cho cả 4 Deployment (Lab 3.2).

## Cấu trúc thư mục

```
baby-milk-shop/
├── package.json               # scripts: setup, dev (concurrently cả 4 service)
├── scripts/setup.mjs          # copy .env + npm install tất cả
├── k8s/                       # manifest K8s — apply bằng `kubectl apply -k k8s/overlays/prod`
│   ├── base/                  # xem chi tiết ở mục "Kustomize — cấu trúc k8s/" phía trên
│   └── overlays/{prod,dev}/
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
