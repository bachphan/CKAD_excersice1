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
2. **`kubectl diff -k overlays/prod` phải luôn = 0 dòng** sau mỗi lần thay đổi permanent — nghĩa là
   file trong git khớp tuyệt đối với cluster đang chạy. Nếu > 0, phải hiểu rõ tại sao trước khi apply.
3. **Không phá app thật đang chạy** — mọi demo/lab dùng resource TẠM (namespace `default`, hoặc
   label `created-by=ckad-lab` để dọn gọn) trừ khi mục đích rõ ràng là thay đổi permanent cho
   `babymilk` (namespace prod thật). Sau demo luôn verify lại `babymilk` 5/5 pod Ready.
4. **Không registry riêng** — image chỉ tồn tại local trên node worker (`imagePullPolicy: Never`
   cho mọi image `docker.io/babymilk/*`). Image bên thứ 3 (nginx, busybox, postgres...) dùng
   `imagePullPolicy: IfNotPresent`, pull thật từ Docker Hub (worker có internet, xem mục 7).
5. **Namespace `babymilk` chỉ có 1 node worker phục vụ** (`k8s-worker1`, ~1.9 CPU/3.2GB khả dụng vì
   master bị taint `NoSchedule`) — MỌI thay đổi tăng resource requests/limits phải tính lại
   `ResourceQuota` (`k8s/base/70-resourcequota.yaml`), không được chặn nhầm pod đang chạy.

---

## 2. Cấu trúc thư mục & cách deploy (Kustomize là CHÍNH THỨC, Helm là SONG SONG)

```
k8s/
├── base/                         # manifest gốc — sửa TẠI ĐÂY khi đổi vĩnh viễn
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
│   ├── 60-stock-monitor.yaml     # CronJob
│   └── 70-resourcequota.yaml
├── overlays/
│   ├── prod/kustomization.yaml   # resources: [../../base], KHÔNG patch gì — đúng = cluster thật
│   └── dev/kustomization.yaml    # namespace/NodePort/HPA riêng — CHƯA apply lên cluster
│       # (không đủ tài nguyên chạy 2 bộ song song, chỉ dùng để validate render)
└── helm/babymilk-shop/           # bản Helm SONG SONG, KHÔNG thay thế Kustomize — xem mục 9
```

**Quy tắc đặt tên file trong `base/`**: số 2 chữ số ở đầu = thứ tự nên đọc/apply (namespace trước,
config trước app, app trước network policy phụ thuộc label...). Khi thêm file mới, chọn số phù hợp
dải: `0x` = namespace/config, `1x` = app Deployment/Service, `2x` = NetworkPolicy, `3x` = storage,
`4x` = autoscaling, `5x` = database, `6x` = Job/CronJob, `7x` = quota. Nhớ thêm vào `kustomization.yaml`.

**Deploy thay đổi permanent — LUÔN theo đúng thứ tự này:**
```bash
# 1. Sửa file trong k8s/base/ tại máy dev (Windows)
# 2. scp file đã sửa lên master (namespace/deploy KHÔNG phải git repo trên master, chỉ là bản copy)
scp k8s/base/<file>.yaml master:/home/bachpt1/babymilk-k8s/base/

# 3. Áp dụng qua overlay prod (KHÔNG BAO GIỜ apply -f trực tiếp từng file rời — luôn qua -k)
ssh master "cd ~/babymilk-k8s && kubectl apply -k overlays/prod"

# 4. Verify rollout + 0 drift
ssh master "kubectl rollout status deployment/<tên> -n babymilk --timeout=90s"
ssh master "cd ~/babymilk-k8s && kubectl diff -k overlays/prod"   # PHẢI ra rỗng

# 5. Verify thật qua NodePort (không suy đoán)
ssh master "curl -s http://localhost:30080/healthz"

# 6. Commit + push k8s/base thật (trong repo git ở máy dev, KHÔNG phải bản copy trên master)
```

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

---

## 9. Helm chart (`k8s/helm/babymilk-shop/`) — quy tắc khi sửa

- Chart này **mirror `k8s/base`**, kể cả pattern 4-container ở mục 3 — **sửa `k8s/base` xong PHẢI
  đồng bộ sang `k8s/helm/babymilk-shop/templates/` tương ứng** (không để 2 nơi lệch nhau).
- Namespace mặc định `babymilk-helm` — KHÁC `babymilk` (namespace prod thật do Kustomize quản lý) —
  **không đổi giá trị mặc định này** để tránh 2 cách deploy đụng độ resource khi chạy song song.
- PVC dùng `storageClassName: local-path` (dynamic) — KHÔNG dùng static PV `postgres-data-pv`
  (đang bị Kustomize giữ) để tránh xung đột binding.
- Trước khi sửa gì: `helm lint k8s/helm/babymilk-shop` phải sạch. Trước khi coi là xong: thật sự
  `helm install`/`helm upgrade`/`helm rollback` trên cluster (namespace demo riêng), verify pod
  Ready + curl qua NodePort riêng (`frontend.nodePort` trong `values.yaml`, mặc định `30081` — xem
  lưu ý trùng port với lab demo ở mục 10), rồi `helm uninstall` + xoá namespace để giải phóng tài
  nguyên node worker (cluster chỉ có 1 node, không được để namespace demo tồn tại dài hạn).
- **Kustomize vẫn là cách deploy CHÍNH THỨC cho `babymilk` prod thật** — Helm KHÔNG thay thế, chỉ
  thêm vào để luyện tập/demo vòng đời Helm. Nếu sau này quyết định đổi hẳn sang Helm làm chính thức,
  đó là thay đổi lớn cần bàn riêng, không tự ý làm.

## 9b. Ingress — TUYỆT ĐỐI KHÔNG dùng Cilium's built-in Ingress Controller

- Đã thử `cilium upgrade --set ingressController.enabled=true` **2 lần** (2 ngày khác nhau), cả 2
  lần đều làm agent Cilium trên worker kẹt/CrashLoopBackOff — đây là **bug thật đã biết** của Cilium
  1.19.x khi restart agent cùng lúc cluster có kube-proxy
  ([issue #44464](https://github.com/cilium/cilium/issues/44464)). Chi tiết đầy đủ: `lab/lab_4.2.txt`.
- **Dùng `ingress-nginx`** thay thế — Ingress Controller độc lập, không gắn vào CNI agent, đã cài
  thành công (`controller-v1.15.1`, bản `baremetal`, NodePort `80:30369`/`443:31810`).
  Coi là **cluster add-on cài riêng** (giống `metrics-server`/`local-path-provisioner`) —
  **KHÔNG đưa manifest 668 dòng của ingress-nginx vào Kustomize repo**, chỉ document lệnh cài trong
  README. Ngược lại, `Ingress` resource CỦA APP (`k8s/base/80-ingress.yaml`, route `babymilk.local`)
  PHẢI qua Kustomize như mọi resource khác của app.
- Nếu sau này Cilium ra version mới có thể đã fix bug này — vẫn KHÔNG tự ý thử lại
  `ingressController.enabled=true` trên cluster đang chạy app thật mà không hỏi trước, vì lịch sử
  2/2 lần thất bại giống hệt nhau.

---

## 10. Trước khi coi 1 thay đổi K8s là "xong" — checklist bắt buộc

1. `kubectl apply -k overlays/prod` (hoặc `helm upgrade` nếu sửa chart Helm) chạy không lỗi.
2. `kubectl rollout status deployment/<tên> -n babymilk --timeout=90s` → thành công.
3. `kubectl get pods -n babymilk` → đúng số container Ready (vd `3/3` cho 4 Deployment app, `1/1`
   cho postgres) — KHÔNG chỉ nhìn `Running`, phải nhìn tỉ lệ Ready/Total.
4. `kubectl logs <pod> -c <container>` cho TỪNG container mới thêm/sửa — xác nhận không có lỗi.
5. `curl` qua NodePort thật (`http://192.168.56.102:30080/...`) — xác nhận luồng end-to-end, không
   chỉ test nội bộ pod.
6. `kubectl diff -k overlays/prod` → 0 dòng (không còn drift giữa git và cluster).
7. Nếu đổi resource requests/limits → `kubectl describe resourcequota babymilk-quota -n babymilk`
   xác nhận chưa chạm trần.
8. Cập nhật `README.md` (mục checklist/trạng thái liên quan) và `../work_done.md` (mục mới, theo
   đúng format các mục trước — có **Vì sao** và bug/fix thật gặp phải nếu có).
9. Nếu có NodePort mới cho mục đích lab/demo — theo quy ước đã thiết lập: **luôn thêm NodePort** để
   xem được từ browser Windows qua mạng host-only (`192.168.56.x`), tránh trùng với NodePort đang
   dùng (xem bảng port ở mục 3, và các NodePort lab hiện có: `30080` prod, `30081` Helm demo,
   `30081/30082` Lab 1.1/1.2, `30090` dev overlay, `30091` Lab 4.1, `30099` Lab 5.3 — kiểm tra
   `kubectl get svc --all-namespaces -o wide | grep NodePort` trước khi chọn số mới).
10. Commit git với message mô tả **tại sao** đổi (không chỉ **cái gì** đổi), verify `.git/config`
    sạch sau khi push nếu dùng token qua header tạm thời.
