# CKAD Capstone Checklist — BabyMilk Shop

Đối chiếu từng mục **Required** trong đề bài của thầy (`§4` Mandatory CKAD Requirements) với
resource/file thật trong repo này + cách tự verify trên cluster thật. Không có mục nào chỉ "nói
suông" — mọi dòng dưới đây đều trỏ tới đúng file hoặc lệnh `kubectl` có thể chạy thật để kiểm chứng.

> Muốn verify TỰ ĐỘNG cả bảng này cùng lúc: chạy `scripts/smoke-test.sh` (xem README mục "Chạy demo
> nhanh cho người chấm bài").

---

## §4.1 — Application Design and Build (20%)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| D1 | Custom container image cho mỗi service | ✅ | `services/{product,user,order}-service/Dockerfile`, `services/frontend/Dockerfile`. Tag rõ ràng, không dùng `:latest`: `product-service:2.3`, `user-service:2.1`, `order-service:2.1`, `frontend:1.2`. Verify: `kubectl get deploy -n babymilk -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'` |
| D2 | Deployment cho API; Job/CronJob cho batch | ✅ | 4 Deployment (`k8s/base/10,11,12,13-*.yaml`) + CronJob `stock-monitor` (`k8s/base/60-stock-monitor.yaml`, chạy 8h sáng mỗi ngày). Verify: `kubectl get deploy,cronjob -n babymilk` |
| D3 | Multi-container: init **và/hoặc** sidecar trên ≥1 Pod | ✅ (vượt — cả 2, thêm ambassador) | **Cả 4** Deployment app đều có đủ **4 container/pod**: `init-config` (init), app chính, `log-shipper` (sidecar), `ambassador-nginx` (ambassador). Verify: `kubectl get pod -n babymilk -l app=product-service -o jsonpath='{.items[0].spec.initContainers[*].name} {.items[0].spec.containers[*].name}'` |
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
| P5 | Kustomize: `base/` + ≥1 overlay patch image/replicas | ✅ | `k8s/base/` + `k8s/overlays/{prod,dev}`. `prod` = cấu hình chạy thật (`kubectl diff -k` = 0), `dev` patch namespace/NodePort/HPA (chưa apply — thiếu tài nguyên chạy song song, đã validate render đúng). |
| P6 | Helm chart cài được, có value override, upgrade+rollback | ✅ | `k8s/helm/babymilk-shop/`. Verify thật: `helm install`/`helm upgrade --set hpa.maxReplicas=5`/`helm rollback` — cả 3 đã test trên cluster (namespace riêng `babymilk-helm`, không đụng prod). |

## §4.3 — Application Environment, Configuration & Security (25% weight / 20 điểm rubric)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| C1 | ConfigMap inject qua env và/hoặc volume | ✅ | `babymilk-config` (`k8s/base/01-configmap.yaml`) — inject qua `env.valueFrom.configMapKeyRef` ở cả 4 service. |
| C2 | Secret cho credential/token/DB password | ✅ | `babymilk-secret` (`k8s/base/02-secret.yaml.example` — file thật gitignored, tạo tay từ example). Chứa `JWT_SECRET`, `INTERNAL_API_KEY`, `ADMIN_PASSWORD`, `POSTGRES_PASSWORD`. |
| C3 | SecurityContext ≥1 workload: non-root, no priv-esc, drop ALL, read-only fs | ✅ (vượt — cả 4+postgres) | Mọi Deployment: `runAsNonRoot: true`, `runAsUser: 1000`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true` (trừ 2 container có lý do kỹ thuật ghi rõ trong `k8s/CONVENTIONS.md` mục 4: `log-shipper`/`ambassador-nginx` cần root). Verify thật: `kubectl exec -n babymilk deploy/product-service -- touch /test` → `Read-only file system`. |
| C4 | Custom ServiceAccount+Role+RoleBinding, có Pod **thật** dùng | ✅ | `stock-monitor-sa` + `Role` (get/list Pod, chỉ trong `babymilk`) + `RoleBinding` (`k8s/base/61-stock-monitor-rbac.yaml`) — gắn **permanent** vào CronJob `stock-monitor` thật (không phải demo tạm), dùng bởi init container `check-product-service-up` để gọi K8s API xác nhận `product-service` đang có Pod Running trước khi gọi HTTP. Verify least-privilege: `kubectl auth can-i get pods --as=system:serviceaccount:babymilk:stock-monitor-sa -n babymilk` → yes; `can-i delete pods` / `can-i get secrets` / `can-i get pods -n default` (cùng `--as`) → cả 3 no. |
| C5 | ResourceQuota **VÀ** LimitRange trên namespace | ✅ | `babymilk-quota` (`k8s/base/70-resourcequota.yaml`) + `babymilk-limits` (`k8s/base/71-limitrange.yaml`, min/max áp dụng mọi container). Verify: `kubectl get resourcequota,limitrange -n babymilk`. |
| C6 | Mọi container có CPU/memory `requests` **và** `limits` | ✅ | Enforce cứng bởi `ResourceQuota` (thiếu 1 trong 2 là bị admission control chặn tạo pod ngay). |

## §4.4 — Services and Networking (20%)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| N1 | ClusterIP cho traffic nội bộ giữa microservice | ✅ | Service `product-service`/`user-service`/`order-service` không khai `type` → mặc định `ClusterIP`, chỉ gọi được từ trong cluster. |
| N2 | NodePort **hoặc** Ingress cho traffic ngoài | ✅ (cả 2) | `frontend` NodePort `:30080` **và** `ingress-nginx` (Ingress). |
| N3 | Ingress ≥2 path/host route tới backend **khác nhau** | ✅ | `babymilk-ingress` (`k8s/base/80-ingress.yaml`): path `/api/products` → thẳng `product-service:4001` (bỏ qua frontend), path `/` → `frontend:4000`. Verify: `curl -H "Host: babymilk.local" http://<worker-ip>:<ingress-nodeport>/api/products` và `.../healthz` trả đúng 2 service khác nhau. |
| N4 | NetworkPolicy default-deny hoặc allow tường minh frontend→backend; giới hạn egress | ✅ (vượt — cả L3/L4 và L7) | `k8s/base/20-networkpolicy.yaml` (`default-deny-ingress` + allow tường minh) + `CiliumNetworkPolicy` L7 (path/method-aware cho `product-service`) + `k8s/base/21-networkpolicy-egress.yaml` (`default-deny-egress`, backend không ra internet được — verify: gọi `example.com` từ trong pod bị treo tới timeout). |
| N5 | Endpoints đã verify; không Service nào mồ côi (selector/port sai) | ✅ | Không có Service nào sai lệch trong cấu hình thật. Kỹ năng chẩn đoán lỗi này được luyện + verify qua bài tập riêng `lab/lab_4.1.txt` (dựng lỗi selector mismatch cố ý rồi tự chẩn đoán bằng `kubectl get endpoints`, sửa, verify lại). |

## §4.5 — Application Observability and Maintenance (15% weight / 10 điểm rubric)

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| O1 | Liveness probe trên mọi Deployment chạy lâu dài | ✅ | Cả 4 app Deployment (`httpGet /healthz`) + postgres (`exec pg_isready`). |
| O2 | Readiness probe trên mọi Deployment chạy lâu dài | ✅ | Tương tự O1, `timeoutSeconds: 3` (tăng từ mặc định 1s sau khi phát hiện probe fail giả trên node chậm — `lab/lab_3.2.txt`). |
| O3 | Startup probe trên ≥1 service khởi động chậm | ⚠️ Recommended, chưa có trên workload thật | Có demo/hiểu rõ pattern (`lab/lab_5.1.txt`, pod giả lập khởi động chậm 20s không bị liveness giết oan) nhưng **chưa gắn vào 1 trong 4 Deployment thật** — lý do: cả 4 service khởi động nhanh (<3s), không thực sự cần startupProbe. Mục này chỉ **Recommended** trong đề bài, không phải Required. |
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
