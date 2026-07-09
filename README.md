# 🍼 BabyMilk Shop — E-commerce sữa bột cho bé (demo học tập CKAD)

Ứng dụng web bán sữa bột chia thành **4 microservice độc lập**, đã build container hóa và **đang chạy thật trên cụm Kubernetes tự dựng bằng kubeadm trên VirtualBox** (không phải cloud, không phải minikube).

## ✅ Trạng thái hiện tại: ĐANG CHẠY TRÊN K8S

| | |
|---|---|
| Truy cập | `http://192.168.56.102:30080` (từ máy trong cùng mạng host-only với cluster) |
| Namespace | `babymilk` |
| Pods | 4/4 `Running`, tất cả trên node `k8s-worker1` |
| Admin | `admin@babymilk.local` / `admin12345` |
| Dữ liệu | 14 sản phẩm sữa mẫu, seed tự động |

```
NAME                               READY   STATUS    RESTARTS   NODE
frontend-64588fcb97-g5hrg          1/1     Running   0          k8s-worker1
order-service-84cf5dc68b-n5c68     1/1     Running   0          k8s-worker1
product-service-5c8b5ffcfb-969jv   1/1     Running   0          k8s-worker1
user-service-697fb96d74-5l2sk      1/1     Running   0          k8s-worker1
```

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

- **CNI**: Cilium v1.19.3 (kèm Cilium Envoy DaemonSet) — thay cho Calico.
- **Network**: mỗi VM có 2 network adapter — NAT (ra internet) + Host-only Adapter (`192.168.56.0/24`, dùng cho giao tiếp giữa các node và từ máy host vào cluster).
- **Vì master bị taint `control-plane:NoSchedule`**, toàn bộ app (kể cả baby-milk-shop) chỉ chạy được trên **node worker duy nhất** — ngân sách tài nguyên thực tế cho app: ~1.9 CPU / ~3.2GB RAM.
- Không có image registry riêng — image build bằng Docker Desktop trên máy dev (Windows), sau đó `docker save` → `scp` → `ctr -n k8s.io images import` trực tiếp vào containerd của node worker.
- Chi tiết đầy đủ quá trình dựng cluster (bao gồm các lỗi đã gặp và cách fix: VT-x, trùng IP NAT giữa 2 node, LVM chỉ cấp phát nửa đĩa...) xem tại `../work_done.md` và `../setup_guide.md` trong repo hạ tầng.

## Kiến trúc

```
Trình duyệt ──> frontend :4000 (static + API gateway, Node thuần 0 dependency)
                   │ proxy /api/*
                   ├── /api/products, /api/meta ──> product-service :4001 (catalog, tồn kho, admin CRUD)
                   ├── /api/auth, /api/users    ──> user-service    :4002 (đăng ký/đăng nhập, JWT, profile)
                   └── /api/orders              ──> order-service   :4003 (checkout, lịch sử đơn)
                                                        │ POST /internal/checkout|restock (X-Internal-Key)
                                                        └────────> product-service (trừ/hoàn kho nguyên tử)
```

- **Tech stack**: Node.js 22 + Express 5 + better-sqlite3 (SQLite, schema SQL ANSI dễ chuyển PostgreSQL) + JWT (`jsonwebtoken`) + scrypt (built-in `node:crypto`) — mỗi backend chỉ có **3 dependency**.
- **Frontend**: vanilla HTML/CSS/JS SPA (hash routing), không build step. Server tĩnh kiêm gateway giúp trình duyệt chỉ gọi 1 origin → không cần CORS, và map thẳng sang Ingress khi lên K8s.
- **Auth**: user-service phát JWT; product/order-service tự verify bằng `JWT_SECRET` chung (stateless, không gọi chéo).
- **Checkout**: order-service gọi `POST /internal/checkout` của product-service — kiểm tra + trừ tồn kho **nguyên tử trong 1 transaction** (hoặc trừ hết, hoặc không trừ gì), trả về snapshot giá/tên để lưu vào đơn (không tin giá client gửi). Hủy đơn → hoàn kho. Gọi chéo có **timeout 5s**, service chết → trả 503, không crash.
- **Giỏ hàng** lưu ở localStorage phía client (nhẹ, không cần state server); đăng nhập chỉ bắt buộc lúc checkout.

## Chạy trên Windows (không cần Docker)

Yêu cầu: Node.js ≥ 22 (đã có).

```powershell
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

Dữ liệu mẫu: 14 sản phẩm sữa được seed tự động lần chạy đầu. DB SQLite nằm ở `services/<tên>/data/*.db` — xóa file này nếu muốn reset.

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
| POST | `/internal/checkout` | X-Internal-Key | Trừ kho nguyên tử (chỉ order-service gọi) |
| POST | `/internal/restock` | X-Internal-Key | Hoàn kho |

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

Tất cả service có `GET /healthz` (dùng cho liveness/readiness probe sau này). Lỗi trả JSON thống nhất: `{"error": {"message": "...", "details": [...]}}`.

## Biến môi trường (mỗi service có `.env.example`)

| Biến | Service | Ghi chú |
|---|---|---|
| `PORT` | tất cả | 4000-4003 |
| `DB_PATH` | 3 backend | đường dẫn file SQLite (K8s: mount volume) |
| `JWT_SECRET` | 3 backend | **phải giống nhau** ở cả 3 → K8s Secret |
| `JWT_EXPIRES_IN`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` | user | seed admin lần đầu |
| `INTERNAL_API_KEY` | product + order | **phải giống nhau** → K8s Secret |
| `PRODUCT_SERVICE_URL`, `PRODUCT_SERVICE_TIMEOUT_MS` | order | K8s: `http://product-service:4001` |
| `PRODUCT/USER/ORDER_SERVICE_URL` | frontend | target proxy → K8s Service DNS |
| `SEED_ON_START` | product | `false` để tắt seed |

## 🚀 Đã triển khai lên K8s — cách làm lại từ đầu

Toàn bộ quy trình dưới đây đã thực hiện thật và app đang chạy (xem mục "Trạng thái hiện tại" ở đầu file). Ghi lại đầy đủ để tái tạo khi cần (VD: sau khi xóa cluster, đổi image version...).

### 1. Build 4 image (trên máy dev, cần Docker Desktop)

```bash
cd baby-milk-shop
docker build -t babymilk/product-service:1.0 ./services/product-service
docker build -t babymilk/user-service:1.0    ./services/user-service
docker build -t babymilk/order-service:1.0   ./services/order-service
docker build -t babymilk/frontend:1.0        ./services/frontend
```

Mỗi image ~55-62MB (`node:22-alpine`, multi-stage, non-root `USER node`).

### 2. Đưa image vào cluster (không có registry riêng)

Chỉ cần đưa vào node **worker** (vì master bị taint, không nhận app pod):

```bash
docker save babymilk/product-service:1.0 babymilk/user-service:1.0 babymilk/order-service:1.0 babymilk/frontend:1.0 -o babymilk-images.tar
scp babymilk-images.tar bachpt1@192.168.56.102:/tmp/
ssh bachpt1@192.168.56.102 "sudo ctr -n k8s.io images import /tmp/babymilk-images.tar"
```

### 3. Tạo Secret (KHÔNG commit giá trị thật lên git)

```bash
cp k8s/02-secret.yaml.example k8s/02-secret.yaml
# Sửa 3 giá trị REPLACE_ME_* trong file, sinh ngẫu nhiên bằng:
openssl rand -hex 24   # JWT_SECRET
openssl rand -hex 16   # INTERNAL_API_KEY
```

`k8s/02-secret.yaml` đã nằm trong `.gitignore` — không bao giờ push file này lên git.

### 4. Apply toàn bộ manifest

```bash
kubectl apply -f k8s/
```

Tạo theo thứ tự: `Namespace babymilk` → `ConfigMap babymilk-config` → `Secret babymilk-secret` → 4 × (`Deployment` + `Service`).

### 5. Kiểm tra & truy cập

```bash
kubectl get pods -n babymilk -o wide       # cả 4 pod phải Running 1/1
curl http://192.168.56.102:30080/healthz    # test từ máy host
```

Mở trình duyệt: **http://192.168.56.102:30080**

### Chi tiết cấu hình đã dùng trong manifest (`k8s/`)

| File | Nội dung |
|---|---|
| `00-namespace.yaml` | Namespace `babymilk` |
| `01-configmap.yaml` | URL nội bộ giữa service (`http://product-service:4001`...), timeout, `SEED_ON_START` |
| `02-secret.yaml` (gitignored) | `JWT_SECRET`, `INTERNAL_API_KEY`, `ADMIN_PASSWORD` |
| `10-product-service.yaml` | Deployment + Service `product-service`, port 4001 |
| `11-user-service.yaml` | Deployment + Service `user-service`, port 4002 |
| `12-order-service.yaml` | Deployment + Service `order-service`, port 4003 |
| `13-frontend.yaml` | Deployment + Service `frontend` (`NodePort 30080`), port 4000 |

Mỗi Deployment: `replicas: 1` (SQLite không share được giữa nhiều pod), `imagePullPolicy: Never` (image chỉ có local trên worker, không có registry để pull), resource `requests: 50m CPU/32-64Mi RAM`, `limits: 100-150m CPU/64-256Mi RAM`, `readinessProbe`/`livenessProbe` qua `GET /healthz`, storage SQLite dùng `emptyDir` (mất data nếu pod bị xóa — chấp nhận được cho demo).

### Việc có thể làm tiếp (chưa làm, đúng chất CKAD)

- [ ] `NetworkPolicy` chặn `/internal/*` — chỉ `order-service` được gọi sang `product-service`, các pod khác bị từ chối.
- [ ] `PersistentVolumeClaim` thay cho `emptyDir` — giữ data khi pod restart.
- [ ] `HorizontalPodAutoscaler` cho `product-service` (test scale theo CPU).
- [ ] `PodDisruptionBudget`.
- [ ] Đổi SQLite → PostgreSQL (schema đã viết ANSI SQL, chỉ cần đổi driver + connection string).
- [ ] Ingress (Cilium có sẵn Ingress support) thay cho NodePort, dùng domain đẹp thay vì gõ IP:port.

## Cấu trúc thư mục

```
baby-milk-shop/
├── package.json               # scripts: setup, dev (concurrently cả 4 service)
├── scripts/setup.mjs          # copy .env + npm install tất cả
├── k8s/                       # manifest K8s — apply bằng `kubectl apply -f k8s/`
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secret.yaml.example # copy thành 02-secret.yaml + điền giá trị thật (gitignored)
│   ├── 10-product-service.yaml
│   ├── 11-user-service.yaml
│   ├── 12-order-service.yaml
│   └── 13-frontend.yaml       # Service type NodePort :30080
└── services/
    ├── product-service/       # :4001 — Express + SQLite (products)
    │   ├── migrations/*.sql   # schema ANSI SQL
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
