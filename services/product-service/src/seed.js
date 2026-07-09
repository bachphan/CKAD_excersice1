import { pool, query, now } from './db.js';

// Dữ liệu mẫu — chỉ nạp khi bảng products rỗng (idempotent, an toàn khi restart pod).
const PRODUCTS = [
  ['Sữa NAN Optipro 1 800g', 'Nestlé', '0-6m', 385000, 50, 'Thụy Sĩ',
    'Sữa công thức cho trẻ 0-6 tháng, đạm Optipro dễ tiêu hóa, bổ sung HMO tăng đề kháng.',
    'Đạm whey, lactose, dầu thực vật, HMO 2\'-FL, DHA, ARA, vitamin A/D/E/K, canxi, sắt, kẽm.'],
  ['Sữa NAN Optipro 2 800g', 'Nestlé', '6-12m', 375000, 45, 'Thụy Sĩ',
    'Sữa công thức tiếp theo cho trẻ 6-12 tháng, đạm chất lượng Optipro, lợi khuẩn B. lactis.',
    'Đạm whey, lactose, dầu thực vật, HMO, B. lactis, DHA, vitamin nhóm B, canxi, kẽm.'],
  ['Sữa Aptamil Profutura số 1 800g', 'Aptamil', '0-6m', 690000, 30, 'Đức',
    'Dòng cao cấp cho trẻ sơ sinh 0-6 tháng, hệ dưỡng chất SYNEO độc quyền (GOS/FOS + lợi khuẩn).',
    'Lactose, dầu thực vật, GOS/FOS, Bifidobacterium breve, DHA, AA, nucleotides, vitamin & khoáng chất.'],
  ['Sữa Aptamil Essensis số 3 800g', 'Aptamil', '1-3y', 615000, 25, 'New Zealand',
    'Sữa công thức hữu cơ đạm A2 cho trẻ 1-3 tuổi, không biến đổi gen, vị thanh nhạt.',
    'Sữa bò A2 hữu cơ, lactose, dầu thực vật hữu cơ, DHA, GOS, vitamin D, canxi.'],
  ['Sữa Similac Total Comfort 1 820g', 'Abbott', '0-6m', 495000, 40, 'Mỹ',
    'Cho trẻ 0-6 tháng tiêu hóa nhạy cảm: đạm thủy phân một phần, giảm quấy khóc, dễ hấp thu.',
    'Đạm whey thủy phân một phần, maltodextrin, dầu thực vật, HMO 2\'-FL, DHA, lutein, vitamin E.'],
  ['Sữa Similac Eye-Q 4 900g', 'Abbott', '3-6y', 465000, 35, 'Mỹ',
    'Cho trẻ 2-6 tuổi, hệ dưỡng chất Eye-Q Plus hỗ trợ phát triển trí não và thị giác.',
    'Sữa bột tách béo, đường lactose, DHA, lutein, vitamin E tự nhiên, canxi, vitamin D3.'],
  ['Sữa Enfamil A+ NeuroPro số 1 830g', 'Mead Johnson', '0-6m', 545000, 38, 'Mỹ',
    'Cho trẻ 0-6 tháng, bổ sung MFGM và DHA hỗ trợ phát triển não bộ giai đoạn vàng.',
    'Lactose, đạm sữa, MFGM, DHA, ARA, PDX/GOS, choline, vitamin & khoáng chất thiết yếu.'],
  ['Sữa Enfagrow A+ NeuroPro số 3 830g', 'Mead Johnson', '1-3y', 465000, 42, 'Mỹ',
    'Cho trẻ 1-3 tuổi, DHA hàm lượng cao cùng MFGM, hỗ trợ trí não và miễn dịch.',
    'Sữa bột, lactose, dầu thực vật, MFGM, DHA, PDX/GOS, sắt, kẽm, vitamin nhóm B.'],
  ['Sữa Meiji Infant Formula 0-1 800g', 'Meiji', '0-6m', 510000, 28, 'Nhật Bản',
    'Sữa nội địa Nhật cho trẻ 0-1 tuổi, vị nhạt gần sữa mẹ, bổ sung fructooligosaccharide.',
    'Lactose, dầu thực vật, đạm whey, FOS, DHA, taurine, nucleotides, 27 vitamin & khoáng chất.'],
  ['Sữa Meiji Growing Up 1-3 800g', 'Meiji', '1-3y', 455000, 33, 'Nhật Bản',
    'Sữa Meiji cho trẻ 1-3 tuổi, dạng bột dễ pha, hỗ trợ phát triển chiều cao và cân nặng.',
    'Sữa bột nguyên kem, lactose, FOS, DHA, canxi, sắt, kẽm, vitamin D, vitamin K2.'],
  ['Sữa Dielac Alpha Gold IQ 2 800g', 'Vinamilk', '6-12m', 215000, 60, 'Việt Nam',
    'Sữa công thức Việt Nam cho trẻ 6-12 tháng, giá hợp lý, bổ sung sữa non colostrum.',
    'Sữa bột, lactose, dầu thực vật, colostrum, DHA, taurine, cholin, FOS/inulin, vitamin & khoáng.'],
  ['Sữa Dielac Grow Plus 2+ 850g', 'Vinamilk', '3-6y', 285000, 55, 'Việt Nam',
    'Cho trẻ 2-6 tuổi suy dinh dưỡng thấp còi, tăng cân khỏe mạnh sau 3 tháng.',
    'Sữa bột, đường, dầu thực vật, đạm whey, lysine, kẽm, sắt, vitamin nhóm B, FOS.'],
  ['Sữa Friso Gold 2 800g', 'FrieslandCampina', '6-12m', 545000, 26, 'Hà Lan',
    'Cho trẻ 6-12 tháng, quy trình xử lý nhiệt một lần LockNutri bảo toàn đạm tự nhiên.',
    'Sữa bột tách béo, lactose, dầu thực vật, GOS, DHA, AA, nucleotides, vitamin & khoáng chất.'],
  ['Sữa Friso Gold 4 850g', 'FrieslandCampina', '3-6y', 425000, 48, 'Hà Lan',
    'Cho trẻ 2-6 tuổi, đạm mềm nhỏ tự nhiên dễ tiêu hóa, hỗ trợ đề kháng đường ruột.',
    'Sữa bột tách béo, lactose, dầu thực vật, GOS, DHA, vitamin C/D, kẽm, selen.'],
];

export async function seedIfEmpty() {
  const { rows } = await query('SELECT COUNT(*) AS c FROM products');
  if (Number(rows[0].c) > 0) return;
  const ts = now();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const p of PRODUCTS) {
      await client.query(
        `INSERT INTO products (name, brand, age_range, price, stock, origin, description, ingredients, image_url, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL, $9, $10)`,
        [...p, ts, ts]
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  console.log(`[seed] inserted ${PRODUCTS.length} sample products`);
}
