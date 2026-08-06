# Quy chuẩn xây dựng & deploy K8s cho baby-milk-shop

> File này dành cho **bất kỳ AI/dev nào** sau này cần sửa/thêm manifest K8s cho dự án —
> đọc file này TRƯỚC khi đụng vào `k8s/`. Mục tiêu: mọi thay đổi sau này (dù do người hay AI khác
> làm) vẫn nhất quán với phần đã có, không phá vỡ quy ước, không gây drift giữa git và cluster thật.
>
> File này nói về **QUY TẮC** (bất biến, ít đổi). Trạng thái hiện tại đang chạy gì, version nào,
> đã làm lab nào — xem [`../README.md`](../README.md) (đổi liên tục theo tiến độ thật).

---

## 1. Nguyên tắc tối thượng

1. **Cluster thật là nguồn sự thật thứ 2** (git là nguồn sự thật thứ 1) — trước khi coi bất kỳ
   thay đổi nào là "xong", phải verify bằng lệnh thật trên cluster (`kubectl get/describe/logs`,
   `curl` qua NodePort), KHÔNG được giả định/suy đoán kết quả.
2. **Helm là cách deploy CHÍNH THỨC cho namespace `babymilk` (prod thật)** kể từ khi cutover
   (xem mục 9) — sau mỗi lần thay đổi permanent, phải verify bằng `helm list -A` (release đúng
   `deployed`) + `helm diff`/`helm template` so với giá trị đang dùng nếu cần đối chiếu. Kustomize
   (`k8s/overlays/prod`) vẫn giữ trong repo để đáp ứng yêu cầu đề bài (P5) nhưng **KHÔNG còn phản
   ánh cluster thật** — `kubectl diff -k overlays/prod` sẽ KHÔNG = 0 nữa, đây là điều BÌNH THƯỜNG,
   không phải drift cần fix.
3. **Không phá app thật đang chạy** — mọi demo/lab dùng resource TẠM (namespace `default`, hoặc
   label `created-by=ckad-lab` để dọn gọn) trừ khi mục đích rõ ràng là thay đổi permanent cho
   `babymilk` (namespace prod thật). Sau demo luôn verify lại `babymilk` 5/5 pod Ready.
4. **Không registry riêng** — image chỉ tồn tại local trên node worker (`imagePullPolicy: Never`
   cho mọi image `docker.io/babymilk/*`). Image bên thứ 3 (nginx, busybox, postgres...) dùng
   `imagePullPolicy: IfNotPresent`, pull thật từ Docker Hub (worker có internet, xem mục 7).
5. **Namespace `babymilk` chỉ có 1 node worker phục vụ** (`k8s-worker1`, ~1.9 CPU/3.2GB khả dụng vì
   master bị taint `NoSchedule`) — MỌI thay đổi tăng resource requests/limits phải tính lại
   `ResourceQuota` (chart `babymilk-infra`, `k8s/helm/babymilk-infra/templates/resourcequota.yaml`),
   không được chặn nhầm pod đang chạy.

---

## 2. Cấu trúc thư mục & cách deploy (Helm là CHÍNH THỨC, Kustomize giữ để đáp ứng đề bài)

```
k8s/
├── base/                         # manifest gốc Kustomize — VẪN giữ, đáp ứng yêu cầu P5, KHÔNG
│   │                              # còn là nguồn deploy live (xem mục 9b cũ / mục 9 mới)
│   ├── kustomization.yaml        # liệt kê đủ mọi file .yaml trong base/ (trừ 02-secret.yaml)
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secret.yaml.example    # mẫu — 02-secret.yaml thật KHÔNG commit, xem mục 6
│   ├── 05-ambassador-nginx-config.yaml
│   ├── 10/11/12/13-*.yaml        # 4 Deployment app (mỗi cái = Deployment + Service)
│   ├── 20/21-networkpolicy*.yaml
│   ├── 30-pv-pvc.yaml
│   ├── 40-hpa.yaml
│   ├── 50-postgres.yaml
│   ├── 60/61-stock-monitor*.yaml # CronJob + RBAC
│   ├── 70-resourcequota.yaml
│   ├── 71-limitrange.yaml
│   └── 80-ingress.yaml
├── overlays/
│   ├── prod/kustomization.yaml   # resources: [../../base], KHÔNG patch gì
│   └── dev/kustomization.yaml    # namespace/NodePort/HPA riêng — CHƯA apply lên cluster
│       # (không đủ tài nguyên chạy 2 bộ song song, chỉ dùng để validate render)
└── helm/                         # 5 chart Helm ĐỘC LẬP — cách deploy CHÍNH THỨC, xem mục 9
    ├── babymilk-infra/           # namespace/config/secret/postgres/PVC/quota/networkpolicy/ingress/cronjob
    ├── product-service/          # cài/nâng cấp độc lập, không đụng 3 chart service còn lại
    ├── user-service/
    ├── order-service/
    └── frontend/
```

**Quy tắc đặt tên file trong `base/`**: số 2 chữ số ở đầu = thứ tự nên đọc/apply (namespace trước,
config trước app, app trước network policy phụ thuộc label...). Khi thêm file mới, chọn số phù hợp
dải: `0x` = namespace/config, `1x` = app Deployment/Service, `2x` = NetworkPolicy, `3x` = storage,
`4x` = autoscaling, `5x` = database, `6x` = Job/CronJob, `7x` = quota. Nhớ thêm vào `kustomization.yaml`.
Kustomize không còn được apply lên `babymilk` live nữa, nhưng vẫn PHẢI giữ đồng bộ về mặt cấu trúc
(feature parity) với 5 chart Helm — thêm feature mới vào cả 2 nơi để P5 (Kustomize) không bị lạc hậu.

**Deploy thay đổi permanent — LUÔN theo đúng thứ tự này (Helm, cách deploy live):**
```bash
# 1. Sửa template/values trong k8s/helm/<chart>/ tại máy dev (Windows)
# 2. scp chart đã sửa lên master (namespace/deploy KHÔNG phải git repo trên master, chỉ là bản copy)
scp -r k8s/helm/<chart> master:~/helm-v2/

# 3. helm lint trước khi upgrade
ssh master "helm lint ~/helm-v2/<chart>"

# 4. Upgrade ĐÚNG chart bị đổi (không đụng 4 chart còn lại) — namespace=babymilk cho live
ssh master "helm upgrade <release>-live ~/helm-v2/<chart> --set namespace=babymilk --reuse-values"

# 5. Verify rollout thật (không suy đoán)
ssh master "kubectl rollout status deployment/<tên> -n babymilk --timeout=90s"
ssh master "kubectl get pods -n babymilk"           # đúng số container Ready
ssh master "curl -s http://localhost:30080/healthz"  # end-to-end qua NodePort

# 6. Commit + push k8s/helm/<chart> thật (trong repo git ở máy dev, KHÔNG phải bản copy trên master)
```

Nếu thay đổi cũng áp dụng được cho Kustomize (feature parity, xem trên) — cập nhật thêm `k8s/base/`
tương ứng, `scp` lên `~/babymilk-k8s/base/` trên master, `kubectl kustomize overlays/prod` để
validate render sạch (KHÔNG `apply` — Kustomize không còn quản lý `babymilk` live).

---

## 3. Chuẩn 1 Deployment app (product/user/order-service, frontend)

Mỗi Deployment app hiện có **4 container/pod** theo pattern init + sidecar + ambassador (bắt buộc
áp dụng đồng bộ cho cả 4, không được làm khác nhau giữa các service):

| # | Container | Image | Vai trò | Port |
|---|---|---|---|---|
| 1 | `init-config` (initContainer) | `busybox:1.36` | Ghi tóm tắt config hiệu lực vào `emptyDir` trước khi app start | — |
| 2 | `<service-name>` (app chính) | `docker.io/babymilk/<service>:<tag>` | Logic thật, KHÔNG đổi so với code — chỉ đổi biến `PORT` sang nội bộ | `<gốc>+100` |
| 3 | `log-shipper` (sidecar) | `busybox:1.36` | `tail -F` file log kubelet ghi ở node (`hostPath /var/log`, read-only) | — |
| 4 | `ambassador-nginx` | `nginx:1.27-alpine` | Nhận traffic ở port công khai cũ, `proxy_pass` vào app ở `127.0.0.1` | `<gốc>` (công khai) |

**Bảng port quy ước** (giữ cố định — KHÔNG đổi số port công khai khi thêm service mới sẽ theo
pattern +1 từ order-service):

| Service | Port công khai (Service/NetworkPolicy) | Port nội bộ (app thật) |
|---|---|---|
| product-service | 4001 | 4101 |
| user-service | 4002 | 4102 |
| order-service | 4003 | 4103 |
| frontend | 4000 (NodePort 30080) | 4100 |

**Vì sao port công khai giữ nguyên số cũ**: NetworkPolicy/CiliumNetworkPolicy chỉ biết pod IP + port,
không biết container nào đứng sau — giữ nguyên số port công khai nghĩa là **không phải sửa bất kỳ
NetworkPolicy nào** khi thêm ambassador. Khi thêm service mới, đặt port nội bộ = port công khai + 100,
áp dụng cùng convention.

**Nội dung `init-config`** (mẫu, đổi `PGDATABASE` theo service): ghi biến đọc từ `babymilk-config`
ConfigMap ra `/init-config/summary.txt`, không có tác dụng chức năng — chỉ minh hoạ pattern init
container. Nếu sau này cần init container CÓ tác dụng thật (vd chờ Postgres sẵn sàng), viết thêm
container riêng, không sửa `init-config` hiện có.

**Nội dung `log-shipper`**: PHẢI dùng Downward API `POD_NAME` (`fieldRef: metadata.name`) để glob
đúng log file của POD HIỆN TẠI — dùng glob theo tên service (không có `POD_NAME`) sẽ vô tình tail
nhầm log của pod cũ đã bị xoá (bug thật đã gặp và fix, xem `work_done.md` mục 18). App **luôn ghi
log ra stdout như cũ** — sidecar chỉ đọc lại, không được đổi app sang ghi file (phá 12-Factor #11).

**Nội dung `ambassador-nginx`**: file config lấy từ ConfigMap `ambassador-nginx-conf`
(`k8s/base/05-ambassador-nginx-config.yaml`), mount qua `subPath: <service>.conf` vào
`/etc/nginx/conf.d/default.conf`. Thêm service mới → thêm 1 key mới vào ConfigMap này.

---

## 4. SecurityContext — chuẩn bắt buộc cho MỌI Deployment mới

**Cấp Pod** (áp dụng cho toàn bộ container trừ khi override riêng):
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000              # bắt buộc nếu có container non-root cần ghi vào emptyDir/volume dùng chung
  seccompProfile:
    type: RuntimeDefault
```

**Cấp Container — app chính** (bắt buộc, không ngoại lệ):
```yaml
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

**2 NGOẠI LỆ đã biết** (chỉ áp dụng cho đúng 2 container này, có lý do kỹ thuật cụ thể — KHÔNG tự ý
mở rộng ngoại lệ cho container khác mà không có lý do tương đương):
- `log-shipper`: chạy `runAsUser: 0` (root) vì log file trên node do kubelet ghi mode `640 root:root`
  — chỉ root đọc được. Vẫn giữ `capabilities.drop: ["ALL"]` (root nhưng không có capability đặc biệt).
- `ambassador-nginx`: chạy `runAsUser: 0` (root) và **KHÔNG drop capabilities** — nginx image cần
  `chown` nội bộ lúc khởi động (kể cả khi chạy root, thiếu `CAP_CHOWN` do drop ALL sẽ làm nginx
  crash lúc start — bug thật đã gặp, xem `work_done.md` mục 18).

**Init container** (`busybox`): giữ đầy đủ ràng buộc như app chính (`readOnlyRootFilesystem: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`) — không cần ghi gì ngoài
`/init-config` (đã mount riêng, không đụng rootfs).

---

## 5. Resources requests/limits — BẮT BUỘC trên MỌI container (kể cả init)

`ResourceQuota babymilk-quota` (`k8s/base/70-resourcequota.yaml`) chặn tạo pod nếu **bất kỳ**
container nào (kể cả initContainer) thiếu requests/limits — lỗi thật đã gặp: `must specify
limits.cpu for: init-config...`. Bảng giá trị chuẩn đang dùng (giữ nguyên trừ khi có lý do đo đạc
thật để đổi):

| Loại container | requests.cpu | requests.memory | limits.cpu | limits.memory |
|---|---|---|---|---|
| App chính (Node.js) | 50m | 64Mi | 150m | 256Mi |
| Postgres | 100m | 128Mi | 300m | 384Mi |
| `init-config` | 10m | 16Mi | 50m | 32Mi |
| `log-shipper` | 10m | 16Mi | 50m | 32Mi |
| `ambassador-nginx` | 20m | 16Mi | 100m | 64Mi |
| Pod tạm/demo (busybox test) | 10-20m | 16-32Mi | 50-100m | 32-128Mi |

**Sau khi đổi requests/limits của bất kỳ container nào** (thêm container mới, tăng limit...) → PHẢI
tính lại tổng và so với `ResourceQuota` (`requests.cpu: 1200m`, `requests.memory: 1600Mi`,
`limits.cpu: 1800m`, `limits.memory: 2800Mi`) và với ngân sách node thật (~1.9 CPU/3.2GB) — verify
bằng `kubectl describe resourcequota babymilk-quota -n babymilk` sau khi apply.

---

## 6. ConfigMap / Secret

- **ConfigMap** (`babymilk-config`): mọi giá trị KHÔNG nhạy cảm (URL nội bộ, timeout, tên DB...) —
  nằm trong `kustomization.yaml`, apply bình thường qua `-k`.
- **Secret** (`babymilk-secret`): mọi giá trị nhạy cảm (JWT_SECRET, INTERNAL_API_KEY, mật khẩu) —
  file thật `k8s/base/02-secret.yaml` **KHÔNG BAO GIỜ commit** (đã trong `.gitignore`), **KHÔNG liệt
  kê trong `kustomization.yaml`** (apply tách riêng bằng tay: `kubectl apply -f 02-secret.yaml`).
  Chỉ commit `02-secret.yaml.example` với giá trị `REPLACE_ME_*`.
- Thêm biến config mới → thêm key vào `01-configmap.yaml` HOẶC `02-secret.yaml(.example)` tuỳ độ
  nhạy cảm, rồi tham chiếu bằng `configMapKeyRef`/`secretKeyRef` trong Deployment — KHÔNG hardcode
  giá trị trực tiếp trong Deployment (trừ giá trị không đổi giữa các môi trường như `PGDATABASE`).

---

## 7. Image — build, import, versioning

- Build tại máy dev (Windows, Docker Desktop): `docker build -t docker.io/babymilk/<service>:<tag> .`
- Không có registry riêng — đưa image vào containerd của worker bằng:
  `docker save` → `scp` lên worker → `ssh worker "sudo ctr -n k8s.io images import <file>.tar"`.
- **Bump tag mỗi lần đổi code** (semver đơn giản, không cần theo chuẩn semver nghiêm ngặt — xem
  `README.md` mục checklist để biết tag hiện tại của từng service). KHÔNG ghi đè tag cũ (giữ tag cũ
  lại trên worker — hữu ích cho demo rollback/rolling update thật, xem Lab 2.1).
- Image bên thứ 3 (`nginx:1.27-alpine`, `busybox:1.36`, `postgres:16-alpine`...): pull thật qua
  internet (worker có NAT ra ngoài) — dùng `imagePullPolicy: IfNotPresent`, GHIM version cụ thể
  (không dùng `:latest` cho production, trừ demo lab riêng biệt như `bitnami/nginx`).

---

## 8. Probes, Labels, NetworkPolicy — quy ước ngắn

- **readinessProbe + livenessProbe**: mọi app chính dùng `httpGet: {path: /healthz, port: <port nội
  bộ>}`, `timeoutSeconds: 3` (bắt buộc — mặc định 1s từng gây probe fail giả trên node chậm, xem
  Lab 3.2). Postgres dùng `exec: pg_isready`.
- **Labels bắt buộc trên pod template**: `app: <tên>` (dùng cho Service selector), `tier:
  frontend|backend|database` (dùng cho NetworkPolicy `matchExpressions`).
- **Label demo/lab**: mọi resource tạo ra để demo/test (không phải permanent) PHẢI gắn
  `created-by: ckad-lab` để dọn gọn bằng 1 lệnh
  (`kubectl delete all,job,pvc,configmap,secret -l created-by=ckad-lab --all-namespaces`).
- **NetworkPolicy mới**: mặc định-deny đã có sẵn (`20-networkpolicy.yaml` ingress,
  `21-networkpolicy-egress.yaml` egress) — thêm service mới PHẢI thêm rule allow tường minh (ingress
  lẫn egress), không dựa vào rule sẵn có của service khác. `product-service` dùng thêm
  CiliumNetworkPolicy L7 để giới hạn theo HTTP method/path — chỉ dùng L7 khi cần phân biệt path,
  còn lại dùng NetworkPolicy L3/L4 chuẩn K8s là đủ.
- **Pod cần gọi K8s API (RBAC) trong namespace có `default-deny-egress`**: NetworkPolicy chuẩn K8s
  với `podSelector` **KHÔNG match được** `kube-apiserver` vì nó chạy `hostNetwork: true` (không có
  pod IP riêng trong overlay network) — đã thử thật, bị `timeout` (xem `61-stock-monitor-rbac.yaml`).
  Bắt buộc dùng `CiliumNetworkPolicy` với `egress: [{toEntities: [kube-apiserver]}]` — entity đặc
  biệt CHỈ Cilium mới có, đúng cho chính xác case này. RBAC (SA+Role+RoleBinding) đúng KHÔNG đủ —
  vẫn phải có rule egress riêng, 2 lớp độc lập nhau.
- **Cross-namespace `fromEndpoints` trong CiliumNetworkPolicy**: muốn cho phép traffic từ pod ở
  namespace KHÁC (vd `ingress-nginx` gọi vào `babymilk`), phải khai namespace tường minh trong
  `matchLabels` qua nhãn dành riêng `k8s:io.kubernetes.pod.namespace: <namespace>`, kèm theo label
  thật của pod đó — không đơn thuần `matchLabels` như trong cùng namespace (mặc định chỉ match
  cùng namespace với policy).

---

## 9. Helm chart (`k8s/helm/*`) — cách deploy CHÍNH THỨC cho `babymilk` prod thật

5 chart độc lập, cài/nâng cấp/rollback riêng lẻ, KHÔNG dùng Helm chart dependency/library chart —
mỗi service chart tham chiếu ConfigMap/Secret/ambassador-conf của `babymilk-infra` bằng TÊN CỐ ĐỊNH
(`babymilk-config`, `babymilk-secret`, `ambassador-nginx-conf`), không phải bằng Helm dependency:

| Chart | Release live | Quản lý |
|---|---|---|
| `k8s/helm/babymilk-infra/` | `babymilk-infra` | Namespace, ConfigMap, Secret (tuỳ chọn), Postgres+PVC/PV, ResourceQuota+LimitRange, NetworkPolicy (L3/L4+L7), Ingress, CronJob+RBAC |
| `k8s/helm/product-service/` | `product-service-live` | Deployment 4-container + Service + HPA |
| `k8s/helm/user-service/` | `user-service-live` | Deployment 4-container + Service |
| `k8s/helm/order-service/` | `order-service-live` | Deployment 4-container + Service |
| `k8s/helm/frontend/` | `frontend-live` | Deployment 4-container + Service NodePort |

**Thứ tự bắt buộc**: `babymilk-infra` PHẢI cài trước 4 chart service (chúng tham chiếu ConfigMap/
Secret do `babymilk-infra` tạo). Release metadata Helm nằm ở namespace `default` (namespace hiện
tại của context `kubectl`/`helm` trên master) — **khác** với `--set namespace=babymilk` (namespace
chứa resource K8s thật) — 2 khái niệm độc lập, đừng nhầm.

- Mọi chart **mirror `k8s/base`** về mặt tính năng (pattern 4-container ở mục 3, SecurityContext ở
  mục 4, resources ở mục 5...) — sửa 1 bên PHẢI đồng bộ sang bên kia (xem mục 2 "feature parity").
- `babymilk-infra/values.yaml`: `secrets.manage` — mặc định `true` (chart tự tạo Secret từ giá trị
  trong `values.yaml`). Đặt `false` khi Secret đã tồn tại sẵn trong namespace và muốn GIỮ NGUYÊN giá
  trị cũ (không ghi đè) — dùng đúng 1 lần lúc cutover từ Kustomize sang Helm, xem `work_done.md`.
- `postgres.volumeName` + `postgres.createStaticPV`: mặc định rỗng/`false` → PVC dùng dynamic
  provisioning (`storageClassName: local-path`), namespace demo/test bất kỳ. Muốn bind vào ĐÚNG
  static PV có sẵn (namespace `babymilk` thật, PV `postgres-data-pv`, `persistentVolumeReclaimPolicy:
  Retain`): `--set postgres.volumeName=postgres-data-pv --set postgres.createStaticPV=false` — PV
  phải ở trạng thái `Available` (claimRef đã clear) trước khi `helm install`.
- Trước khi sửa gì: `helm lint k8s/helm/<chart>` phải sạch. Trước khi coi là xong: `helm upgrade`
  chart đã sửa trên cluster thật, verify `kubectl get pods -n babymilk` (5/5 Ready) + `curl` qua
  NodePort/Ingress thật — **không suy đoán**.
- Test tính năng MỚI (không phải sửa nhỏ) → LUÔN thử trước trên namespace cô lập (vd
  `babymilk-helmtest`, `ingress.host` riêng để tránh đụng admission webhook host+path duy nhất của
  `ingress-nginx`) rồi mới `helm upgrade` vào `babymilk` thật. Nhớ `helm uninstall` + xoá namespace
  test sau khi xong, không để tồn tại dài hạn (cluster chỉ có 1 node worker).
- **Kustomize (`k8s/base` + `k8s/overlays`) vẫn giữ trong repo, render sạch, để đáp ứng yêu cầu đề
  bài P5** — nhưng KHÔNG còn là cách deploy `babymilk` live, không `apply -k` lên cluster thật nữa.

## 9b. Ingress — TUYỆT ĐỐI KHÔNG dùng Cilium's built-in Ingress Controller

- Đã thử `cilium upgrade --set ingressController.enabled=true` **2 lần** (2 ngày khác nhau), cả 2
  lần đều làm agent Cilium trên worker kẹt/CrashLoopBackOff — đây là **bug thật đã biết** của Cilium
  1.19.x khi restart agent cùng lúc cluster có kube-proxy
  ([issue #44464](https://github.com/cilium/cilium/issues/44464)). Chi tiết đầy đủ: `lab/lab_4.2.txt`.
- **Dùng `ingress-nginx`** thay thế — Ingress Controller độc lập, không gắn vào CNI agent, đã cài
  thành công (`controller-v1.15.1`, bản `baremetal`, NodePort `80:30369`/`443:31810`).
  Coi là **cluster add-on cài riêng** (giống `metrics-server`/`local-path-provisioner`) —
  **KHÔNG đưa manifest 668 dòng của ingress-nginx vào Kustomize/Helm repo**, chỉ document lệnh cài
  trong README. Ngược lại, `Ingress` resource CỦA APP (route `babymilk.local`) PHẢI qua chart
  `babymilk-infra` (`templates/ingress.yaml`) như mọi resource khác của app — `k8s/base/80-ingress.yaml`
  vẫn giữ song song cho Kustomize (P5).
- Nếu sau này Cilium ra version mới có thể đã fix bug này — vẫn KHÔNG tự ý thử lại
  `ingressController.enabled=true` trên cluster đang chạy app thật mà không hỏi trước, vì lịch sử
  2/2 lần thất bại giống hệt nhau.

---

## 10. Trước khi coi 1 thay đổi K8s là "xong" — checklist bắt buộc

1. `helm upgrade <release>-live k8s/helm/<chart> --set namespace=babymilk --reuse-values` chạy
   không lỗi (chỉ upgrade ĐÚNG chart bị đổi).
2. `kubectl rollout status deployment/<tên> -n babymilk --timeout=90s` → thành công.
3. `kubectl get pods -n babymilk` → đúng số container Ready (vd `3/3` cho 4 Deployment app, `1/1`
   cho postgres) — KHÔNG chỉ nhìn `Running`, phải nhìn tỉ lệ Ready/Total. Xác nhận 4 chart/release
   KHÔNG bị đổi không có timestamp/restart count mới (chứng minh upgrade độc lập thật sự).
4. `kubectl logs <pod> -c <container>` cho TỪNG container mới thêm/sửa — xác nhận không có lỗi.
5. `curl` qua NodePort thật (`http://192.168.56.102:30080/...`) — xác nhận luồng end-to-end, không
   chỉ test nội bộ pod.
6. `helm list -A` → release đổi phải ở `deployed`, `REVISION` tăng đúng 1.
7. Nếu đổi resource requests/limits → `kubectl describe resourcequota babymilk-quota -n babymilk`
   xác nhận chưa chạm trần.
8. Nếu thay đổi cũng áp dụng được cho Kustomize (feature parity, xem mục 2) → cập nhật `k8s/base/`
   tương ứng, verify `kubectl kustomize overlays/prod` render sạch (không lỗi, KHÔNG `apply`).
9. Cập nhật `README.md` (mục checklist/trạng thái liên quan) và `../work_done.md` (mục mới, theo
   đúng format các mục trước — có **Vì sao** và bug/fix thật gặp phải nếu có).
9. Nếu có NodePort mới cho mục đích lab/demo — theo quy ước đã thiết lập: **luôn thêm NodePort** để
   xem được từ browser Windows qua mạng host-only (`192.168.56.x`), tránh trùng với NodePort đang
   dùng (xem bảng port ở mục 3, và các NodePort lab hiện có: `30080` prod, `30081` Helm demo,
   `30081/30082` Lab 1.1/1.2, `30090` dev overlay, `30091` Lab 4.1, `30099` Lab 5.3 — kiểm tra
   `kubectl get svc --all-namespaces -o wide | grep NodePort` trước khi chọn số mới).
10. Commit git với message mô tả **tại sao** đổi (không chỉ **cái gì** đổi), verify `.git/config`
    sạch sau khi push nếu dùng token qua header tạm thời.
