-- Cập nhật image_url cho các sản phẩm mẫu theo brand.
UPDATE products SET image_url = '/images/nan.png'      WHERE brand = 'Nestlé';
UPDATE products SET image_url = '/images/aptamil.png'  WHERE brand = 'Aptamil';
UPDATE products SET image_url = '/images/similac.png'  WHERE brand = 'Abbott';
UPDATE products SET image_url = '/images/enfamil.png'  WHERE brand = 'Mead Johnson';
UPDATE products SET image_url = '/images/meiji.png'    WHERE brand = 'Meiji';
UPDATE products SET image_url = '/images/vinamilk.png' WHERE brand = 'Vinamilk';
UPDATE products SET image_url = '/images/friso.png'    WHERE brand = 'FrieslandCampina';
