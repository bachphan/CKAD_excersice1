// Giỏ hàng phía client (localStorage) — chỉ cần đăng nhập lúc checkout.
// Giá lưu ở đây chỉ để HIỂN THỊ; giá thật do product-service chốt lúc checkout.
const CART_KEY = 'bm_cart';
const MAX_QTY = 100;

export function getCart() {
  try {
    const items = JSON.parse(localStorage.getItem(CART_KEY));
    return Array.isArray(items) ? items : [];
  } catch {
    return [];
  }
}

function save(items) {
  localStorage.setItem(CART_KEY, JSON.stringify(items));
  window.dispatchEvent(new Event('cart-change'));
}

export function addToCart(product, qty = 1) {
  const items = getCart();
  const line = items.find((i) => i.productId === product.id);
  if (line) line.qty = Math.min(MAX_QTY, line.qty + qty);
  else items.push({ productId: product.id, name: product.name, brand: product.brand, price: product.price, qty: Math.min(MAX_QTY, qty) });
  save(items);
}

export function updateQty(productId, qty) {
  let items = getCart();
  if (qty <= 0) {
    items = items.filter((i) => i.productId !== productId);
  } else {
    const line = items.find((i) => i.productId === productId);
    if (line) line.qty = Math.min(MAX_QTY, qty);
  }
  save(items);
}

export function removeFromCart(productId) {
  save(getCart().filter((i) => i.productId !== productId));
}

export function clearCart() {
  save([]);
}

export function cartCount() {
  return getCart().reduce((s, i) => s + i.qty, 0);
}

export function cartTotal() {
  return getCart().reduce((s, i) => s + i.price * i.qty, 0);
}
