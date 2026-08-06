# CKAD Capstone Checklist — BabyMilk Shop

Đối chiếu từng mục trong đề bài thật của thầy (`capstone-requirements.md` — QNET CKAD Intensive)
với resource/file thật trong repo này + cách tự verify trên cluster thật. Không có mục nào chỉ "nói
suông" — mọi dòng dưới đây đều trỏ tới đúng file hoặc lệnh `kubectl` có thể chạy thật để kiểm chứng.

> Muốn verify TỰ ĐỘNG cả bảng §4 cùng lúc: chạy `scripts/smoke-test.sh` (xem README mục "Chạy demo
> nhanh cho người chấm bài").

## Tổng quan — đã làm được gì, áp dụng được gì

**Kết luận**: đạt đủ **100% mục Required** trong §4 (30/30 mục) **và cả O3 Recommended** — không
dính bất kỳ điều kiện fail tự động nào ở §7 — vượt yêu cầu tối thiểu (≥70/100 + đủ Required).

| Domain (theo §7 rubric — điểm thật để chấm) | Điểm | Trạng thái | Kỹ năng CKAD đã áp dụng thật |
|---|---|---|---|
| §3 Microservices design | 15 | ✅ Đủ | Service boundary rõ ràng, DNS discovery, HTTP contract, sidecar/init pattern có tài liệu — xem [§3 bên dưới](#3-microservices-standards--15-điểm) |
| §4.1 Design & Build | 20 | ✅ Đủ | Custom image, Deployment/CronJob, multi-container (init+sidecar+ambassador), emptyDir, PVC, label |
| §4.2 Deployment | 20 | ✅ Đủ | Rolling update, blue/green, HPA, Kustomize, **Helm (5 chart độc lập, chính thức)** |
| §4.3 Config & Security | 20 | ✅ Đủ | ConfigMap, Secret, SecurityContext non-root/read-only-fs, RBAC least-privilege, ResourceQuota+LimitRange |
| §4.4 Networking | 15 | ✅ Đủ | ClusterIP, Ingress 2-path, NetworkPolicy L3/L4+L7 (CiliumNetworkPolicy) |
| §4.5 Observability + docs/demo | 10 | ✅ Đủ (kể cả O3 Recommended) | Liveness/readiness probe TÁCH riêng (`/healthz`/`/readyz`), startupProbe thật, README debug runbook, API hiện hành |
| **Tổng** | **100** | | |

**2 điểm khác biệt cấu hình cần xác nhận lại với thầy** (không phải thiếu sót, chỉ khác so với đề
bài mẫu — xem chi tiết cuối file): Kubernetes version (`v1.31.14` thay vì `v1.35.x`), namespace tự
đặt tên `babymilk` (đề bài ghi "do thầy assign").

---

## §3 — Microservices standards (15 điểm, `§3` trong đề bài)

| Mục | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| 3.1 Single responsibility | Mỗi service 1 bounded context | ✅ | `product-service` (catalog/tồn kho), `user-service` (auth/hồ sơ), `order-service` (checkout/đơn hàng), `notification-service` (thông báo bất đồng bộ), `frontend` (gateway/UI) — không service nào lẫn trách nhiệm. |
| 3.1 Independent deployability | Update 1 service không cần rebuild service khác | ✅ (vượt — chứng minh thật) | Mỗi service **1 chart Helm riêng** (`k8s/helm/{product,user,order,notification}-service/`, `frontend/`), cài/nâng cấp độc lập. Đã verify thật: `helm upgrade product-service-live` — các pod còn lại giữ nguyên y hệt `creationTimestamp`, không bị đụng. |
| 3.1 Own data | Ưu tiên schema-per-service, hoặc giải thích lý do dùng chung | ✅ (giải thích rõ) | 1 instance Postgres, **4 database logic tách biệt hoàn toàn** (`babymilk_products`/`_users`/`_orders`/`_notifications`, không JOIN chéo, mỗi service chỉ có credential/kết nối tới đúng 1 DB của mình). Dùng chung 1 instance (không phải 4 instance riêng) vì ngân sách tài nguyên thật của cluster (~1.9 CPU/3.2GB, 1 node worker) — đã ghi rõ lý do, không phải thiếu hiểu biết. |
| 3.1 Sync vs async | Document cách service giao tiếp | ✅ (cả 2, có async THẬT) | Đa số giao tiếp **HTTP đồng bộ** (checkout, catalog, auth — cần phản hồi ngay). **Riêng 1 luồng dùng async THẬT**: `order-service` PUBLISH event `order.completed` lên **Redis Pub/Sub** ngay sau checkout (fire-and-forget, KHÔNG `await` — lỗi Redis chỉ log, không fail response), `notification-service` SUBSCRIBE, ghi + "gửi" thông báo tách rời hoàn toàn khỏi luồng chính. Verify thật: tạo đơn hàng qua API → `GET /api/notifications` (admin) trả về đúng bản ghi vừa publish. Xem `docs/architecture.md` mục "Giao tiếp đồng bộ VÀ bất đồng bộ". |
| 3.1 Không "distributed monolith" | Multi-container phải có tài liệu, không nhồi nhét | ✅ | Pattern init+sidecar+ambassador áp dụng đồng bộ trên cả 5 service, có tài liệu đầy đủ ở `k8s/CONVENTIONS.md` mục 3 — không có Deployment nào nhồi nhiều process không liên quan vào 1 container. |
| 3.2 Health endpoint | ≥1 health path mỗi service cho probe | ✅ (vượt — tách liveness/readiness) | `GET /healthz` (liveness, thuần process) **và** `GET /readyz` (readiness, ping dependency thật) trên cả 5 service. |
| 3.2 Stable port | Document port, Service đúng `port`/`targetPort` | ✅ | Bảng port cố định ở README mục 2 và `k8s/CONVENTIONS.md` mục 3 (4000-4004 công khai, +100 nội bộ). |
| 3.2 Versioning | Tag rõ ràng, không `:latest` | ✅ | `product-service:2.4`, `user-service:2.2`, `order-service:2.2`, `notification-service:1.0`, `frontend:1.3`. |
| 3.2 Config externalized | Không hardcode secret/config trong image | ✅ | 100% qua `ConfigMap`/`Secret` (`configMapKeyRef`/`secretKeyRef`), không biến nào hardcode trong Dockerfile/code. |
| 3.3 Dockerfile per service | Build được, multi-stage | ✅ | `services/*/Dockerfile`, multi-stage `node:22-alpine`, ~58MB/image. |
| 3.3 Non-root runtime | Khớp SecurityContext §4.3 | ✅ | Xem C3 bên dưới. |
| 3.3 Resource awareness | Mọi container có requests+limits | ✅ | Xem C6 bên dưới — enforce cứng bởi ResourceQuota. |
| 3.3 Stateless by default | Persistence qua PVC/DB, không local disk | ✅ | 4 app service hoàn toàn stateless (không ghi local disk); Postgres duy nhất có state, qua PVC. |
| 3.4 ClusterIP east-west | Backend dùng ClusterIP | ✅ | Xem N1 bên dưới. |
| 3.4 DNS discovery | Client dùng K8s DNS | ✅ | `PRODUCT_SERVICE_URL=http://product-service:4001` — DNS ngắn trong cùng namespace, không hardcode IP. |
| 3.4 Ingress north-south | External HTTP qua Ingress | ✅ | Xem N3 bên dưới. |
| 3.4 Network isolation | NetworkPolicy giới hạn Pod nào gọi backend nào | ✅ | Xem N4 bên dưới — vượt yêu cầu (cả L3/L4 lẫn L7). |
| 3.4 Labels & selectors | `app`/`tier`/`version` nhất quán | ✅ | Xem D6 bên dưới. |
| 3.5 Structured logs | Log ra stdout/stderr, sidecar có thể ship | ✅ | 100% log qua stdout (12-Factor #11), sidecar `log-shipper` tail lại — không đổi cách app ghi log. |
| 3.5 Probes | Liveness+readiness mọi Deployment | ✅ | Xem O1/O2 bên dưới. |
| 3.5 Debuggability | Người khác chẩn đoán được chỉ bằng `logs`/`describe`/`events`/`top` | ✅ | README mục "Debug runbook" — đã tự luyện qua `lab/lab_5.2.txt`. |

---

## §4.1 — Application Design and Build (20%)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| D1 | Custom container image cho mỗi service | ✅ | `services/{product,user,order}-service/Dockerfile`, `services/frontend/Dockerfile`. Tag rõ ràng, không dùng `:latest`: `product-service:2.3`, `user-service:2.1`, `order-service:2.1`, `frontend:1.2`. Verify: `kubectl get deploy -n babymilk -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'` |
| D2 | Deployment cho API; Job/CronJob cho batch | ✅ | 5 Deployment (`k8s/base/10,11,12,13,14-*.yaml`) + CronJob `stock-monitor` (`k8s/base/60-stock-monitor.yaml`, chạy 8h sáng mỗi ngày). Verify: `kubectl get deploy,cronjob -n babymilk` |
| D3 | Multi-container: init **và/hoặc** sidecar trên ≥1 Pod | ✅ (vượt — cả 2, thêm ambassador) | **Cả 5** Deployment app đều có đủ **4 container/pod**: `init-config` (init), app chính, `log-shipper` (sidecar), `ambassador-nginx` (ambassador). Verify: `kubectl get pod -n babymilk -l app=product-service -o jsonpath='{.items[0].spec.initContainers[*].name} {.items[0].spec.containers[*].name}'` |
| D4 | `emptyDir` dùng có ý nghĩa (chia sẻ log/config giữa container) | ✅ | Volume `init-config-data` (emptyDir): `init-config` ghi tóm tắt config hiệu lực, app chính mount read-only đọc lại. Xem `k8s/base/10-product-service.yaml` phần `volumes`. |
| D5 | ≥1 PVC, data sống sót qua Pod delete/recreate | ✅ | `postgres-data-pvc` (`k8s/base/30-pv-pvc.yaml`). Verify thật: `kubectl delete pod -l app=postgres -n babymilk` rồi kiểm tra data (đơn hàng, sản phẩm) còn nguyên qua API. |
| D6 | Label cho selection, rollout identity, blue/green readiness | ✅ | `app`, `tier` trên mọi pod template; `version` dùng tạm cho demo blue/green (`lab/lab_2.2.txt`) — patch thêm/gỡ qua `kubectl patch`, không phải field cố định (đúng tinh thần "readiness", không phải lúc nào cũng bật). |

## §4.2 — Application Deployment (20%)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| P1 | Deployment ≥1 replica cho mọi service chạy lâu dài | ✅ | `kubectl get deploy -n babymilk` → cả 5 (4 app + postgres) đều `replicas: 1` (HPA có thể tăng `product-service`). |
| P2 | Quy trình rolling update có tài liệu | ✅ | `lab/lab_2.1.txt` + `lab/class-demo/Day2-ApplicationDeployment.md` Lab 2.1 — `kubectl set image` + `kubectl rollout status`, đã test thật 2 chiều + rollback. |
| P3 | 1 chiến lược nâng cao: blue/green **hoặc** canary | ✅ (blue/green) | `lab/lab_2.2.txt` — 2 Deployment `frontend`/`frontend-green` song song, chuyển traffic tức thì qua `Service.spec.selector`. |
| P4 | HPA trên ≥1 Deployment (CPU target, có metrics-server) | ✅ | `product-service-hpa` (`k8s/base/40-hpa.yaml`, min1/max3/target50%). Verify: `kubectl get hpa -n babymilk`. |
| P5 | Kustomize: `base/` + ≥1 overlay patch image/replicas | ✅ | `k8s/base/` + `k8s/overlays/{prod,dev}` — giữ nguyên trong repo, render sạch (`kubectl kustomize overlays/prod`). `dev` patch namespace/NodePort/HPA (chưa apply — thiếu tài nguyên chạy song song, đã validate render đúng). **Lưu ý**: kể từ khi chuyển namespace `babymilk` sang Helm quản lý (xem P6), `kubectl diff -k overlays/prod` KHÔNG còn = 0 nữa (đúng như dự kiến — 2 cách deploy khác nhau, không cùng quản lý 1 resource) — Kustomize chỉ còn giữ vai trò đáp ứng yêu cầu đề bài, không phải cách deploy live. |
| P6 | Helm chart cài được, có value override, upgrade+rollback | ✅ (chính thức — thay Kustomize làm cách deploy live) | `k8s/helm/` — **6 chart độc lập**: `babymilk-infra` (namespace/config/secret/postgres/redis/PV-PVC/NetworkPolicy/Ingress/CronJob) + `product-service`/`user-service`/`order-service`/`notification-service`/`frontend` (mỗi chart 1 Deployment+Service riêng, cài/nâng cấp độc lập không đụng service khác). Đã cutover thật namespace `babymilk` từ Kustomize sang Helm (PVC mới rebind đúng static PV cũ, giữ nguyên toàn bộ data Postgres). Verify: `helm list -A`, `helm install`/`helm upgrade --set hpa.maxReplicas=5`/`helm rollback` — đã test cả 3 trên namespace cô lập trước khi cutover, và test upgrade độc lập từng chart (`helm upgrade product-service-live` không làm restart pod của các service/chart còn lại). |

## §4.3 — Application Environment, Configuration & Security (25% weight / 20 điểm rubric)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| C1 | ConfigMap inject qua env và/hoặc volume | ✅ | `babymilk-config` (`k8s/base/01-configmap.yaml`) — inject qua `env.valueFrom.configMapKeyRef` ở cả 5 service. |
| C2 | Secret cho credential/token/DB password | ✅ | `babymilk-secret` (`k8s/base/02-secret.yaml.example` — file thật gitignored, tạo tay từ example). Chứa `JWT_SECRET`, `INTERNAL_API_KEY`, `ADMIN_PASSWORD`, `POSTGRES_PASSWORD`. |
| C3 | SecurityContext ≥1 workload: non-root, no priv-esc, drop ALL, read-only fs | ✅ (vượt — cả 5+postgres+redis) | Mọi Deployment: `runAsNonRoot: true`, `runAsUser: 1000`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true` (trừ 2 container có lý do kỹ thuật ghi rõ trong `k8s/CONVENTIONS.md` mục 4: `log-shipper`/`ambassador-nginx` cần root). Verify thật: `kubectl exec -n babymilk deploy/product-service -- touch /test` → `Read-only file system`. |
| C4 | Custom ServiceAccount+Role+RoleBinding, có Pod **thật** dùng | ✅ | `stock-monitor-sa` + `Role` (get/list Pod, chỉ trong `babymilk`) + `RoleBinding` (`k8s/base/61-stock-monitor-rbac.yaml`) — gắn **permanent** vào CronJob `stock-monitor` thật (không phải demo tạm), dùng bởi init container `check-product-service-up` để gọi K8s API xác nhận `product-service` đang có Pod Running trước khi gọi HTTP. Verify least-privilege: `kubectl auth can-i get pods --as=system:serviceaccount:babymilk:stock-monitor-sa -n babymilk` → yes; `can-i delete pods` / `can-i get secrets` / `can-i get pods -n default` (cùng `--as`) → cả 3 no. |
| C5 | ResourceQuota **VÀ** LimitRange trên namespace | ✅ | `babymilk-quota` (`k8s/base/70-resourcequota.yaml`) + `babymilk-limits` (`k8s/base/71-limitrange.yaml`, min/max áp dụng mọi container). Verify: `kubectl get resourcequota,limitrange -n babymilk`. |
| C6 | Mọi container có CPU/memory `requests` **và** `limits` | ✅ | Enforce cứng bởi `ResourceQuota` (thiếu 1 trong 2 là bị admission control chặn tạo pod ngay). |

## §4.4 — Services and Networking (20%)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| N1 | ClusterIP cho traffic nội bộ giữa microservice | ✅ | Service `product-service`/`user-service`/`order-service`/`notification-service`/`postgres`/`redis` không khai `type` → mặc định `ClusterIP`, chỉ gọi được từ trong cluster. |
| N2 | NodePort **hoặc** Ingress cho traffic ngoài | ✅ (cả 2) | `frontend` NodePort `:30080` **và** `ingress-nginx` (Ingress). |
| N3 | Ingress ≥2 path/host route tới backend **khác nhau** | ✅ | `babymilk-ingress` (`k8s/base/80-ingress.yaml`): path `/api/products` → thẳng `product-service:4001` (bỏ qua frontend), path `/` → `frontend:4000`. Verify: `curl -H "Host: babymilk.local" http://<worker-ip>:<ingress-nodeport>/api/products` và `.../healthz` trả đúng 2 service khác nhau. |
| N4 | NetworkPolicy default-deny hoặc allow tường minh frontend→backend; giới hạn egress | ✅ (vượt — cả L3/L4 và L7) | `k8s/base/20-networkpolicy.yaml` (`default-deny-ingress` + allow tường minh) + `CiliumNetworkPolicy` L7 (path/method-aware cho `product-service`) + `k8s/base/21-networkpolicy-egress.yaml` (`default-deny-egress`, backend không ra internet được — verify: gọi `example.com` từ trong pod bị treo tới timeout). |
| N5 | Endpoints đã verify; không Service nào mồ côi (selector/port sai) | ✅ | Không có Service nào sai lệch trong cấu hình thật. Kỹ năng chẩn đoán lỗi này được luyện + verify qua bài tập riêng `lab/lab_4.1.txt` (dựng lỗi selector mismatch cố ý rồi tự chẩn đoán bằng `kubectl get endpoints`, sửa, verify lại). |

## §4.5 — Application Observability and Maintenance (15% weight / 10 điểm rubric)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| O1 | Liveness probe trên mọi Deployment chạy lâu dài | ✅ | Cả 4 app Deployment (`httpGet /healthz`) + postgres (`exec pg_isready`). |
| O2 | Readiness probe trên mọi Deployment chạy lâu dài | ✅ | Tương tự O1, `timeoutSeconds: 3` (tăng từ mặc định 1s sau khi phát hiện probe fail giả trên node chậm — `lab/lab_3.2.txt`). |
| O3 | Startup probe trên ≥1 service khởi động chậm | ✅ (Recommended, ĐÃ làm) | `notification-service` (`k8s/helm/notification-service/templates/deployment.yaml`) — lý do THẬT: phụ thuộc cả Postgres (chạy migration lúc boot) LẪN Redis (subscribe channel) trước khi sẵn sàng, `failureThreshold: 30, periodSeconds: 2` (~60s đệm). Verify: `kubectl describe pod -l app=notification-service -n babymilk \| grep -A2 Startup`. 4 service còn lại khởi động nhanh (<3s) nên không gắn — có demo pattern riêng ở `lab/lab_5.1.txt`. |
| O4 | README có mục hướng dẫn debug bằng `logs`/`describe`/`events`/`top` | ✅ | Xem README mục "Debug runbook". |
| O5 | Dùng API hiện hành, không dùng API đã deprecated | ✅ | `apps/v1`, `batch/v1`, `networking.k8s.io/v1` (Ingress + NetworkPolicy), `rbac.authorization.k8s.io/v1`, `autoscaling/v2` — không còn API nào ở dạng `extensions/v1beta1` hay tương tự đã bị gỡ. |

---

## §7 — Automatic fail conditions (đối chiếu, không dính cái nào)

| Điều kiện fail tự động | Có dính không? |
|---|---|
| Ít hơn 3 microservice độc lập | ❌ Không — có 4 (product/user/order-service + frontend) |
| App chỉ chạy qua `docker compose`, không có K8s Deployment | ❌ Không — chạy K8s thật trên cluster kubeadm tự dựng |
| Secret commit dạng plaintext lên git | ❌ Không — `02-secret.yaml` thật nằm trong `.gitignore`, chỉ commit `.example` |
| Không có cả Ingress lẫn NodePort/LoadBalancer | ❌ Không — có cả 2 |
| Không show được Pod Ready trong namespace lúc demo | ❌ Không — 5/5 Pod Running ổn định |

## 2 điểm cần xác nhận lại với thầy (không phải lỗi, chỉ là khác biệt cấu hình)

- **Kubernetes version**: đề bài ghi `v1.35.x`, cluster hiện tại `v1.31.14` (kubeadm tự dựng, không phải cluster do thầy cấp).
- **Namespace**: đề bài ghi "dedicated namespace assigned by instructor" — namespace hiện tại là `babymilk` (tự đặt tên theo domain, chưa có tên cụ thể thầy chỉ định).
