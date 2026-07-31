# Tài liệu demo CKAD trước lớp

Bộ 5 file này là bản **chuẩn chỉnh, copy-paste được** của toàn bộ 20 lab đã làm (xem `../lab_*.txt`
để đọc transcript gốc/chi tiết đầy đủ, kể cả các sự cố gặp phải trong lúc làm thật).

## ⚡ Cách nhanh nhất: chạy script tự động (run-day*.sh)

Mỗi Day có 1 script chạy FULL toàn bộ lab của ngày đó, tự in kết quả từng bước (PASS/FAIL rõ ràng),
tự dọn dẹp resource demo, và verify app thật không bị ảnh hưởng ở cuối:

```bash
# Script đã có sẵn trên master tại ~/ckad-demo/ (bản gốc trong thư mục này)
ssh bachpt1@192.168.56.103

# Cách 1 — chạy TỪNG Day riêng
bash ~/ckad-demo/run-day1.sh    # Day 1 (19 check)
bash ~/ckad-demo/run-day2.sh    # Day 2 (32 check, đụng app thật — tự revert về baseline)
bash ~/ckad-demo/run-day3.sh    # Day 3 (15 check)
bash ~/ckad-demo/run-day4.sh    # Day 4 (22 check — Lab 4.2 Ingress chạy live thật qua ingress-nginx)
bash ~/ckad-demo/run-day5.sh    # Day 5 (22 check)

# Cách 2 — chạy LIÊN TỤC cả 20 lab (110 check), có giải thích CKAD domain trước mỗi
# Day, dừng hỏi "Enter" giữa mỗi Day, tự chạy restore-to-baseline.sh ở cuối (~10-15 phút)
bash ~/ckad-demo/run-all-labs.sh
```

- An toàn chạy lại nhiều lần (idempotent, mỗi lab đều có Bước 0 cleanup).
- Lab 4.2 (Ingress) giờ chạy **live thật** — dùng `ingress-nginx` (đã cài permanent), không còn
  Cilium's built-in Ingress (dính bug thật, đã đổi hướng — xem `lab/lab_4.2.txt`).
- Nếu script Day nào báo FAIL cuối cùng: chạy `./restore-to-baseline.sh` để đưa cluster về chuẩn.
- Các script đã được điều chỉnh cho khớp cluster hiện tại (multi-container pod, ResourceQuota,
  egress NetworkPolicy, image tag mới nhất...) — khác tài liệu gốc ở vài điểm, mỗi điểm đều có ghi
  chú 📌 trong script và ⚠️ trong file Day tương ứng.

## Cách dùng khi demo trước lớp (thủ công, copy-paste từng khối)

1. **Trước buổi demo**: SSH vào master (`ssh master` hoặc `ssh bachpt1@192.168.56.103`).
2. **Copy file `restore-to-baseline.sh` lên master 1 lần**:
   ```bash
   scp restore-to-baseline.sh bachpt1@192.168.56.103:~/
   ssh bachpt1@192.168.56.103 "chmod +x ~/restore-to-baseline.sh"
   ```
3. **Chạy thử `./restore-to-baseline.sh` trước khi vào lớp** — đảm bảo cluster đang ở trạng thái sạch,
   xem đủ 8/8 check PASS mới yên tâm bắt đầu.
4. **Demo theo từng file `DayN-*.md`** — mỗi lab có sẵn: Cleanup (Bước 0) → Setup/Demo → Verify.
   Copy nguyên khối lệnh, dán vào terminal trên master, chạy tuần tự.
5. **Sau khi demo xong (dù dừng ở lab nào)**: chạy lại `./restore-to-baseline.sh` — cluster tự động
   quay về trạng thái hoàn hảo, sẵn sàng cho buổi demo tiếp theo hoặc câu hỏi của lớp.

## Danh sách file

| File | Nội dung | Ghi chú |
|---|---|---|
| `Day1-ApplicationDesignBuild.md` | Lab 1.1-1.4 | An toàn 100%, namespace `default` |
| `Day2-ApplicationDeployment.md` | Lab 2.1-2.4 | Đụng `babymilk` thật — Lab 2.2 **bắt buộc** làm hết Bước revert trong lúc demo |
| `Day3-SecurityConfig.md` | Lab 3.1-3.4 | Lab 3.2/3.4 chỉ XEM (đã permanent), 3.1/3.3 demo tạm |
| `Day4-NetworkingStorage.md` | Lab 4.1-4.4 | Lab 4.2 (Ingress) dùng `ingress-nginx`, đã permanent, demo live an toàn |
| `Day5-ObservabilityExamPrep.md` | Lab 5.1-5.4 | An toàn, Lab 5.2 chỉ đọc (không đổi gì) |
| `restore-to-baseline.sh` | Script khôi phục tổng | Chạy sau demo (hoặc bất cứ lúc nào nghi ngờ cluster bị lệch) |
| `run-day1.sh` → `run-day5.sh` | Script chạy FULL tự động từng Day | Đã kiểm chứng PASS 100% trên cluster, xem mục phía trên |
| `run-all-labs.sh` | Chạy LIÊN TỤC cả 20 lab + giải thích CKAD domain + tự restore cuối | 110/110 check PASS thật trên cluster (chạy full ~10-15 phút) |

## Nguyên tắc thiết kế

- Mọi resource demo tạo ra đều gắn label `created-by=ckad-lab` — để `restore-to-baseline.sh` quét
  xoá gọn bằng 1 lệnh, không cần nhớ tên từng thứ.
- Các lab đã trở thành **tính năng permanent thật** của `babymilk-shop` (SecurityContext, ResourceQuota,
  Egress NetworkPolicy, CronJob, Kustomize, HPA target 50%, pattern 4-container/pod, Helm chart song
  song, Ingress qua `ingress-nginx`) — các file demo CHỈ XEM LẠI, không tạo lại.
- `restore-to-baseline.sh` an toàn chạy nhiều lần liên tiếp (idempotent) — không sợ chạy "lỡ tay".
