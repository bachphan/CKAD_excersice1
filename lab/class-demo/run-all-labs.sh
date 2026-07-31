#!/bin/bash
# ============================================================================
# run-all-labs.sh — Chạy TOÀN BỘ 20 lab CKAD (Day 1-5) tự động, LIÊN TỤC,
# có giải thích đầy đủ CKAD domain nào đang test + tại sao quan trọng, trước
# khi gọi từng script con (run-day1.sh..run-day5.sh — vẫn giữ nguyên, không
# viết lại logic). Cuối cùng TỰ ĐỘNG chạy restore-to-baseline.sh để đảm bảo
# cluster về đúng trạng thái sạch, dù có Day nào FAIL hay không.
#
# Chạy trên node MASTER, từ đúng thư mục chứa 5 file run-dayN.sh +
# restore-to-baseline.sh (mặc định: ~/ckad-demo — sửa SCRIPT_DIR nếu khác).
#
# Cách dùng:
#   chmod +x run-all-labs.sh
#   ./run-all-labs.sh
#
# Thời gian ước tính: ~10-15 phút cho cả 20 lab (Day 2 đụng app thật lâu nhất
# vì có rolling update + blue/green + scale, mỗi bước đều chờ rollout xong).
# ============================================================================

set -uo pipefail
SCRIPT_DIR="${SCRIPT_DIR:-$HOME/ckad-demo}"
START_TIME=$(date +%s)

green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
cyan()   { echo -e "\033[36m$1\033[0m"; }
bold()   { echo -e "\033[1m$1\033[0m"; }

DAY_RESULTS=()   # "1:PASS" hoặc "2:FAIL" — tổng kết cuối

# ----------------------------------------------------------------------------
# Banner mở đầu — giải thích CKAD là gì, cấu trúc bài thi, script này làm gì
# ----------------------------------------------------------------------------
clear 2>/dev/null || true
bold   "╔══════════════════════════════════════════════════════════════════╗"
bold   "║           CKAD FULL PRACTICE RUN — 20 LAB, 5 NGÀY                 ║"
bold   "╚══════════════════════════════════════════════════════════════════╝"
echo ""
cyan "CKAD (Certified Kubernetes Application Developer) thi 17 câu thực hành trong"
cyan "2 giờ, chia 5 domain chính theo % trọng số chính thức của CNCF:"
echo ""
echo "  ┌─────────────────────────────────────────┬──────┬─────────────────────────┐"
echo "  │ Domain                                   │  %   │ Ánh xạ trong script này │"
echo "  ├─────────────────────────────────────────┼──────┼─────────────────────────┤"
echo "  │ Application Design and Build             │ 20%  │ Day 1 (Lab 1.1-1.4)     │"
echo "  │ Application Deployment                   │ 20%  │ Day 2 (Lab 2.1-2.4)     │"
echo "  │ Application Environment, Config, Security│ 25%  │ Day 3 (Lab 3.1-3.4)     │"
echo "  │ Services & Networking                    │ 20%  │ Day 4 (Lab 4.1-4.4)     │"
echo "  │ Application Observability & Maintenance  │ 15%  │ Day 5 (Lab 5.1-5.4)     │"
echo "  └─────────────────────────────────────────┴──────┴─────────────────────────┘"
echo ""
cyan "Script này chạy LẦN LƯỢT cả 5 script Day, mỗi Day tự cleanup trước/sau, tự"
cyan "verify app thật (namespace babymilk) không bị ảnh hưởng ở cuối mỗi Day."
cyan "Toàn bộ resource demo gắn label created-by=ckad-lab để dọn gọn 1 lệnh."
echo ""
yellow "⚠ Day 2 và Day 4 (Lab 4.3) đụng trực tiếp vào app thật babymilk — an toàn"
yellow "  vì mọi thay đổi đều tự revert trong CHÍNH script, nhưng nếu Ctrl+C giữa"
yellow "  chừng thì PHẢI chạy tay ./restore-to-baseline.sh để dọn sạch."
echo ""
read -p "Nhấn Enter để bắt đầu (hoặc Ctrl+C để huỷ)... " -r
echo ""

# ----------------------------------------------------------------------------
# Hàm chạy 1 Day: in giải thích trước, gọi script con, ghi nhận kết quả
# ----------------------------------------------------------------------------
run_day() {
  local day_num="$1"
  local day_title="$2"
  local domain_pct="$3"
  local explanation="$4"

  echo ""
  bold "┌──────────────────────────────────────────────────────────────────┐"
  bold "│  DAY $day_num — $day_title"
  bold "│  CKAD domain: $domain_pct"
  bold "└──────────────────────────────────────────────────────────────────┘"
  echo -e "$explanation"
  echo ""

  local script="$SCRIPT_DIR/run-day${day_num}.sh"
  if [ ! -f "$script" ]; then
    red "❌ Không tìm thấy $script — SKIP Day $day_num"
    DAY_RESULTS+=("$day_num:MISSING")
    return
  fi

  bash "$script"
  local exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    DAY_RESULTS+=("$day_num:PASS")
  else
    DAY_RESULTS+=("$day_num:FAIL($exit_code check)")
    red ""
    red "⚠ Day $day_num có check FAIL — script vẫn tiếp tục chạy Day tiếp theo,"
    red "  nhưng NHỚ xem kỹ log phía trên trước khi demo thật phần này."
  fi
  echo ""
  read -p "Nhấn Enter để tiếp tục Day kế tiếp (hoặc Ctrl+C để dừng ở đây)... " -r
}

# ============================================================================
# DAY 1 — Application Design and Build
# ============================================================================
run_day 1 "Application Design and Build" "20%" "
$(cyan "Chủ đề: viết & đóng gói app đúng chuẩn K8s ngay từ đầu.")
  • Lab 1.1 — Tạo Pod bằng lệnh imperative + \`--dry-run=client\`, verify không cần
    mở editor (kỹ năng SỐNG CÒN khi thi — chấm điểm theo thời gian).
  • Lab 1.2 — Pattern init container + sidecar container trong 1 Pod, chia sẻ
    dữ liệu qua \`emptyDir\`, xem log đúng container bằng \`-c\`.
  • Lab 1.3 — Job (chạy 1 lần, có \`backoffLimit\`) khác Deployment (chạy mãi) và
    CronJob (Job theo lịch) thế nào.
  • Lab 1.4 — Quản lý Label/Annotation hàng loạt bằng selector, \`--overwrite\`.
$(yellow "An toàn 100% — namespace default, không đụng app thật babymilk.")"

# ============================================================================
# DAY 2 — Application Deployment
# ============================================================================
run_day 2 "Application Deployment" "20%" "
$(cyan "Chủ đề: đưa app LÊN và CẬP NHẬT app một cách an toàn, không downtime.")
  • Lab 2.1 — Rolling update 2 chiều + rollback thật, chứng minh app KHÔNG
    downtime kể cả khi deploy nhầm tag không tồn tại.
  • Lab 2.2 — Blue/Green switch bằng Service selector — đổi toàn bộ traffic
    tức thì, không rolling, dùng khi cần rollback NGAY LẬP TỨC (không đợi
    rolling update tuần tự).
  • Lab 2.3 — Tương tác 3 chiều: scale tay ↔ HPA ↔ ResourceQuota — hiểu vì sao
    scale tay LUÔN thua HPA nếu không patch minReplicas trước.
  • Lab 2.4 — Kustomize: 1 bộ manifest gốc phục vụ nhiều môi trường (prod/dev)
    chỉ bằng patch, \`kubectl diff -k\` chứng minh 0 drift giữa git và cluster.
$(yellow "⚠ ĐỤNG APP THẬT (namespace babymilk) — mọi thay đổi tự revert trong script,")
$(yellow "  đây là Day LÂU NHẤT (~5-7 phút) vì phải chờ rollout thật mỗi bước.")"

# ============================================================================
# DAY 3 — Environment, Configuration & Security
# ============================================================================
run_day 3 "Environment, Configuration & Security" "25% (domain nặng nhất)" "
$(cyan "Chủ đề: cấu hình đúng cách + khoá chặt bảo mật ở tầng Pod/Container.")
  • Lab 3.1 — ConfigMap (env literal) + Secret (từ file) inject vào Pod theo 2
    cơ chế khác nhau: env var (đọc 1 lần lúc start) vs volume mount (tự sync).
  • Lab 3.2 — SecurityContext: non-root, read-only root filesystem, drop hết
    Linux capabilities — verify THẬT bằng cách thử ghi file (phải bị chặn).
  • Lab 3.3 — ServiceAccount + Role + RoleBinding (RBAC least-privilege) — có
    cả demo NGƯỢC LẠI chứng minh quyền bị giới hạn đúng, không chỉ demo xuôi.
  • Lab 3.4 — ResourceQuota chặn pod xin vượt tài nguyên NGAY LÚC TẠO (admission
    control), không phải sau khi đã schedule.
$(yellow "An toàn — Lab 3.1/3.3 namespace default, Lab 3.2/3.4 chỉ XEM LẠI cấu hình")
$(yellow "đã permanent trên babymilk (không apply gì mới).")"

# ============================================================================
# DAY 4 — Services & Networking / Storage
# ============================================================================
run_day 4 "Services & Networking / Storage" "20%" "
$(cyan "Chủ đề: kết nối app với nhau (Service/Ingress) + lưu trữ bền vững (PVC).")
  • Lab 4.1 — Chẩn đoán lỗi Service selector mismatch qua Endpoints — lỗi THẬT
    hay gặp nhất khi thi (Service tưởng đúng nhưng không route được).
  • Lab 4.2 — Ingress routing THEO DOMAIN (khác Service/NodePort chỉ biết
    IP:port) — dùng \`ingress-nginx\`, đã permanent trên cluster. Có 1 câu
    chuyện đáng nhớ về Cilium's built-in Ingress dính bug thật (xem
    lab/lab_4.2.txt) trước khi chuyển sang ingress-nginx thành công.
  • Lab 4.3 — NetworkPolicy Egress: backend không ra được internet nhưng vẫn
    gọi được nội bộ + DNS — minh hoạ \"silent drop\" khác \"từ chối tường minh\".
  • Lab 4.4 — PVC dynamic provisioning (\`WaitForFirstConsumer\`), verify
    persistence THẬT bằng pod hoàn toàn mới, không có lệnh ghi.
$(yellow "An toàn — Lab 4.3/4.4 phần lớn chỉ XEM/verify cấu hình đã permanent.")"

# ============================================================================
# DAY 5 — Observability & Exam Prep
# ============================================================================
run_day 5 "Observability & Exam Prep" "15%" "
$(cyan "Chủ đề: quan sát/chẩn đoán app đang chạy + luyện tốc độ debug cho lúc thi.")
  • Lab 5.1 — startupProbe cho app khởi động chậm — chứng minh KHÔNG bị
    liveness probe giết oan trong lúc đang khởi động.
  • Lab 5.2 — Quy trình chẩn đoán chuẩn: \`get events\` (timeline tổng quan) →
    \`describe\` (chi tiết 1 resource) → \`logs -c/--previous\` (log ứng dụng
    thật, có ví dụ dùng \`-c\` cho pattern 4-container).
  • Lab 5.3 — Triage 1 manifest có CẢ 3 LỖI cùng lúc (image/selector/port sai)
    — sửa đúng THỨ TỰ nguyên nhân gần→xa, kỹ năng tốc độ khi thi.
  • Lab 5.4 — Helm install/upgrade/rollback — \`helm rollback\` tạo REVISION
    MỚI (không quay ngược số), giống \`kubectl rollout undo\`.
$(yellow "An toàn — Lab 5.2 chỉ đọc, không đổi gì. Lab 5.4 hoàn toàn tách biệt Kustomize.")"

# ============================================================================
# TỔNG KẾT + TỰ ĐỘNG RESTORE VỀ BASELINE
# ============================================================================
echo ""
bold "╔══════════════════════════════════════════════════════════════════╗"
bold "║                      TỔNG KẾT 20 LAB                               ║"
bold "╚══════════════════════════════════════════════════════════════════╝"
ANY_FAIL=0
for r in "${DAY_RESULTS[@]}"; do
  day="${r%%:*}"
  status="${r#*:}"
  if [[ "$status" == PASS ]]; then
    green "  ✅ Day $day: PASS"
  else
    red "  ❌ Day $day: $status"
    ANY_FAIL=1
  fi
done

ELAPSED=$(( $(date +%s) - START_TIME ))
echo ""
cyan "Tổng thời gian chạy: $((ELAPSED/60)) phút $((ELAPSED%60)) giây."

echo ""
bold "┌──────────────────────────────────────────────────────────────────┐"
bold "│  Tự động chạy restore-to-baseline.sh — đưa cluster về sạch 100%  │"
bold "└──────────────────────────────────────────────────────────────────┘"
RESTORE_SCRIPT="$SCRIPT_DIR/restore-to-baseline.sh"
if [ -f "$RESTORE_SCRIPT" ]; then
  bash "$RESTORE_SCRIPT"
else
  red "❌ Không tìm thấy $RESTORE_SCRIPT — PHẢI dọn tay bằng cách chạy lại từ đúng thư mục."
  ANY_FAIL=1
fi

echo ""
echo "============================================================"
if [ "$ANY_FAIL" -eq 0 ]; then
  green "✅ TOÀN BỘ 20 LAB + RESTORE ĐỀU PASS — CLUSTER SẴN SÀNG DEMO THẬT"
else
  red "❌ CÓ ÍT NHẤT 1 DAY/BƯỚC FAIL — XEM KỸ LOG PHÍA TRÊN TRƯỚC KHI DEMO THẬT"
fi
echo "============================================================"

exit "$ANY_FAIL"
