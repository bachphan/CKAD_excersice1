# 🍼 BabyMilk Shop — E-commerce sữa bột cho bé (demo học tập)

Ứng dụng web bán sữa bột chia thành **4 service nhỏ độc lập**, thiết kế để sau này deploy lên cụm Kubernetes tài nguyên hạn chế (1 worker node, ~1.9 CPU / 3.2GB RAM). Chạy dev trực tiếp bằng Node.js, **không cần Docker**.

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

## Các bước tiếp theo: containerize + deploy lên K8s

Dockerfile multi-stage (base `node:22-alpine`, chạy non-root `USER node`) đã viết sẵn trong từng service. Còn lại:

1. **Cài Docker** (Docker Desktop trên Windows, hoặc build trực tiếp trên VM bằng `nerdctl`/`buildctl` với containerd có sẵn).
2. **Build 4 image**: `docker build -t babymilk/product-service:v1 services/product-service` (tương tự 3 cái còn lại). Image ước tính ~130-150MB/backend, ~120MB frontend.
3. **Đưa image vào cluster** (không có registry): `docker save ... | gzip` → scp sang worker → `sudo ctr -n k8s.io images import`; hoặc chạy một local registry, hoặc push lên Docker Hub.
4. **Viết manifest K8s** (namespace riêng, ví dụ `babymilk`):
   - `ConfigMap`: PORT, SERVICE_URL nội bộ (`http://product-service:4001`...), DB_PATH (`/app/data/*.db`).
   - `Secret`: `JWT_SECRET`, `INTERNAL_API_KEY`, `ADMIN_PASSWORD`.
   - 4 × `Deployment` (replicas: 1 — SQLite không share được giữa nhiều pod) + 4 × `Service` (ClusterIP).
   - **Resources**: requests `50m/64Mi`, limits `150m/256Mi` mỗi container → tổng ~200m/256Mi request, vừa node worker.
   - **Probes**: liveness + readiness `httpGet /healthz`.
   - **Storage cho SQLite**: `emptyDir` (mất data khi pod bị xóa — chấp nhận được cho demo) hoặc `hostPath`/`local-path-provisioner` PVC để giữ data.
5. **Expose frontend ra ngoài**: nhanh nhất là `Service type NodePort` (truy cập `http://192.168.56.102:3xxxx` từ máy host); bài bản hơn thì cài Ingress controller (Cilium có sẵn Ingress support) + Ingress route `/` → frontend.
6. **Kiểm chứng**: `kubectl get pods -o wide` (tất cả trên worker), thử mua hàng từ trình duyệt máy host, `kubectl logs` xem flow checkout, thử `kubectl delete pod` product-service để xem order-service trả 503 tử tế thay vì crash.
7. **(Tùy chọn, đúng chất CKAD)**: NetworkPolicy chặn `/internal/*` chỉ cho order-service gọi product-service; HPA cho product-service; PodDisruptionBudget; đổi SQLite → PostgreSQL (1 Deployment postgres + đổi `DB_PATH` thành connection string — schema đã viết sẵn kiểu ANSI).

## Cấu trúc thư mục

```
baby-milk-shop/
├── package.json               # scripts: setup, dev (concurrently cả 4 service)
├── scripts/setup.mjs          # copy .env + npm install tất cả
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
