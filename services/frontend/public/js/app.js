import { api, getUser, setSession, clearSession } from './api.js';
import * as cart from './store.js';

const app = document.getElementById('app');
const nav = document.getElementById('main-nav');

// ---------- helpers ----------

const AGE_LABELS = {
  '0-6m': '0–6 tháng',
  '6-12m': '6–12 tháng',
  '1-3y': '1–3 tuổi',
  '3-6y': '3–6 tuổi',
  '6y+': 'Trên 6 tuổi',
};

const STATUS_LABELS = {
  confirmed: 'Đã xác nhận',
  shipping: 'Đang giao',
  completed: 'Hoàn thành',
  cancelled: 'Đã hủy',
};

const PAYMENT_LABELS = { cod: 'Thanh toán khi nhận hàng (COD)', bank_transfer: 'Chuyển khoản (giả lập)' };

const fmtVnd = (n) => new Intl.NumberFormat('vi-VN').format(n) + ' ₫';
const fmtDate = (iso) => new Date(iso).toLocaleString('vi-VN');

// Escape mọi dữ liệu động trước khi nhét vào innerHTML — chống XSS.
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function toast(message, type = 'info') {
  const root = document.getElementById('toast-root');
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = message;
  root.appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

// Ô ảnh sản phẩm: nếu không có imageUrl thì vẽ tile màu theo thương hiệu.
function productImage(p, cls = '') {
  if (p.imageUrl) return `<img class="p-img ${cls}" src="${esc(p.imageUrl)}" alt="${esc(p.name)}" loading="lazy" />`;
  let hash = 0;
  for (const ch of p.brand) hash = (hash * 31 + ch.codePointAt(0)) % 360;
  return `<div class="p-img p-img-tile ${cls}" style="background:hsl(${hash} 70% 88%);color:hsl(${hash} 45% 35%)">${esc(p.brand)}</div>`;
}

function spinner() {
  return '<div class="spinner">Đang tải…</div>';
}

function requireLoginRedirect(nextHash) {
  sessionStorage.setItem('bm_after_login', nextHash);
  toast('Vui lòng đăng nhập để tiếp tục', 'info');
  location.hash = '#/login';
}

// ---------- header/nav ----------

function renderNav() {
  const user = getUser();
  const count = cart.cartCount();
  nav.innerHTML = `
    <a href="#/">Sản phẩm</a>
    <a href="#/cart" class="cart-link">Giỏ hàng${count ? ` <span class="badge">${count}</span>` : ''}</a>
    ${user ? `<a href="#/orders">Đơn hàng</a>` : ''}
    ${user?.role === 'admin' ? `<a href="#/admin" class="admin-link">Quản trị</a>` : ''}
    ${user
      ? `<a href="#/account" title="${esc(user.email)}">👤 ${esc(user.fullName.split(' ').pop())}</a>
         <button id="btn-logout" class="btn btn-ghost btn-sm">Đăng xuất</button>`
      : `<a href="#/login" class="btn btn-sm btn-primary">Đăng nhập</a>`}
  `;
  document.getElementById('btn-logout')?.addEventListener('click', () => {
    clearSession();
    toast('Đã đăng xuất');
    location.hash = '#/';
  });
}

window.addEventListener('session-change', renderNav);
window.addEventListener('cart-change', renderNav);

// ---------- catalog ----------

const catalogState = { q: '', ageRange: '', brand: '', minPrice: '', maxPrice: '', sort: 'newest', page: 1 };
let metaCache = null;

async function renderCatalog() {
  app.innerHTML = spinner();
  if (!metaCache) {
    try { metaCache = await api('/api/meta'); } catch { metaCache = { ageRanges: Object.keys(AGE_LABELS), brands: [] }; }
  }
  const s = catalogState;
  const params = new URLSearchParams({ page: s.page, limit: 12, sort: s.sort });
  for (const k of ['q', 'ageRange', 'brand', 'minPrice', 'maxPrice']) if (s[k]) params.set(k, s[k]);

  let data;
  try {
    data = await api(`/api/products?${params}`);
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
    return;
  }

  app.innerHTML = `
    <div class="catalog-layout">
      <aside class="filters card">
        <h3>Bộ lọc</h3>
        <form id="filter-form">
          <label>Tìm kiếm
            <input name="q" type="search" placeholder="Tên sữa, thương hiệu…" value="${esc(s.q)}" />
          </label>
          <label>Độ tuổi
            <select name="ageRange">
              <option value="">Tất cả</option>
              ${metaCache.ageRanges.map((a) => `<option value="${a}" ${s.ageRange === a ? 'selected' : ''}>${AGE_LABELS[a] || a}</option>`).join('')}
            </select>
          </label>
          <label>Thương hiệu
            <select name="brand">
              <option value="">Tất cả</option>
              ${metaCache.brands.map((b) => `<option value="${esc(b)}" ${s.brand === b ? 'selected' : ''}>${esc(b)}</option>`).join('')}
            </select>
          </label>
          <div class="price-row">
            <label>Giá từ<input name="minPrice" type="number" min="0" step="10000" value="${esc(s.minPrice)}" /></label>
            <label>đến<input name="maxPrice" type="number" min="0" step="10000" value="${esc(s.maxPrice)}" /></label>
          </div>
          <label>Sắp xếp
            <select name="sort">
              <option value="newest" ${s.sort === 'newest' ? 'selected' : ''}>Mới nhất</option>
              <option value="price_asc" ${s.sort === 'price_asc' ? 'selected' : ''}>Giá tăng dần</option>
              <option value="price_desc" ${s.sort === 'price_desc' ? 'selected' : ''}>Giá giảm dần</option>
              <option value="name" ${s.sort === 'name' ? 'selected' : ''}>Tên A→Z</option>
            </select>
          </label>
          <button class="btn btn-primary" type="submit">Áp dụng</button>
          <button class="btn btn-ghost" type="button" id="btn-clear-filter">Xóa lọc</button>
        </form>
      </aside>
      <section>
        <p class="result-count">${data.total} sản phẩm</p>
        <div class="product-grid">
          ${data.items.map((p) => `
            <a class="product-card card" href="#/product/${p.id}">
              ${productImage(p)}
              <div class="p-body">
                <span class="p-brand">${esc(p.brand)} · ${AGE_LABELS[p.ageRange] || esc(p.ageRange)}</span>
                <h4>${esc(p.name)}</h4>
                <div class="p-foot">
                  <span class="p-price">${fmtVnd(p.price)}</span>
                  ${p.stock > 0 ? `<span class="stock-ok">Còn hàng</span>` : `<span class="stock-out">Hết hàng</span>`}
                </div>
              </div>
            </a>`).join('') || '<p>Không tìm thấy sản phẩm phù hợp.</p>'}
        </div>
        ${data.totalPages > 1 ? `
          <div class="pagination">
            <button class="btn btn-sm" id="pg-prev" ${data.page <= 1 ? 'disabled' : ''}>‹ Trước</button>
            <span>Trang ${data.page}/${data.totalPages}</span>
            <button class="btn btn-sm" id="pg-next" ${data.page >= data.totalPages ? 'disabled' : ''}>Sau ›</button>
          </div>` : ''}
      </section>
    </div>
  `;

  document.getElementById('filter-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    Object.assign(s, {
      q: f.get('q').trim(), ageRange: f.get('ageRange'), brand: f.get('brand'),
      minPrice: f.get('minPrice'), maxPrice: f.get('maxPrice'), sort: f.get('sort'), page: 1,
    });
    renderCatalog();
  });
  document.getElementById('btn-clear-filter').addEventListener('click', () => {
    Object.assign(s, { q: '', ageRange: '', brand: '', minPrice: '', maxPrice: '', sort: 'newest', page: 1 });
    renderCatalog();
  });
  document.getElementById('pg-prev')?.addEventListener('click', () => { s.page--; renderCatalog(); });
  document.getElementById('pg-next')?.addEventListener('click', () => { s.page++; renderCatalog(); });
}

// ---------- product detail ----------

async function renderProduct(id) {
  app.innerHTML = spinner();
  let p;
  try {
    p = await api(`/api/products/${id}`);
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
    return;
  }
  app.innerHTML = `
    <a href="#/" class="back-link">‹ Quay lại danh sách</a>
    <div class="detail-layout card">
      ${productImage(p, 'p-img-lg')}
      <div class="detail-info">
        <span class="p-brand">${esc(p.brand)} · Xuất xứ: ${esc(p.origin) || 'N/A'}</span>
        <h2>${esc(p.name)}</h2>
        <p class="p-price p-price-lg">${fmtVnd(p.price)}</p>
        <p><strong>Độ tuổi:</strong> ${AGE_LABELS[p.ageRange] || esc(p.ageRange)}</p>
        <p><strong>Tồn kho:</strong> ${p.stock > 0 ? `${p.stock} sản phẩm` : '<span class="stock-out">Hết hàng</span>'}</p>
        <p>${esc(p.description)}</p>
        <h4>Thành phần dinh dưỡng</h4>
        <p class="ingredients">${esc(p.ingredients)}</p>
        ${p.stock > 0 ? `
          <div class="add-row">
            <input id="qty" type="number" min="1" max="${Math.min(100, p.stock)}" value="1" />
            <button class="btn btn-primary" id="btn-add">Thêm vào giỏ</button>
          </div>` : ''}
      </div>
    </div>
  `;
  document.getElementById('btn-add')?.addEventListener('click', () => {
    const qty = Math.max(1, Number(document.getElementById('qty').value) || 1);
    cart.addToCart(p, qty);
    toast(`Đã thêm ${qty} x ${p.name} vào giỏ`, 'success');
  });
}

// ---------- cart ----------

function renderCart() {
  const items = cart.getCart();
  if (items.length === 0) {
    app.innerHTML = `<div class="card center-box"><p>Giỏ hàng đang trống.</p><a class="btn btn-primary" href="#/">Mua sắm ngay</a></div>`;
    return;
  }
  app.innerHTML = `
    <h2>Giỏ hàng</h2>
    <div class="card">
      <table class="table">
        <thead><tr><th>Sản phẩm</th><th>Đơn giá</th><th>Số lượng</th><th>Thành tiền</th><th></th></tr></thead>
        <tbody>
          ${items.map((i) => `
            <tr data-id="${i.productId}">
              <td><a href="#/product/${i.productId}">${esc(i.name)}</a><br /><small>${esc(i.brand)}</small></td>
              <td>${fmtVnd(i.price)}</td>
              <td><input class="qty-input" type="number" min="1" max="100" value="${i.qty}" /></td>
              <td>${fmtVnd(i.price * i.qty)}</td>
              <td><button class="btn btn-ghost btn-sm btn-remove">✕</button></td>
            </tr>`).join('')}
        </tbody>
      </table>
      <div class="cart-foot">
        <strong>Tổng cộng: ${fmtVnd(cart.cartTotal())}</strong>
        <div>
          <small class="muted">Giá cuối cùng được xác nhận lại lúc đặt hàng.</small>
          <a class="btn btn-primary" href="#/checkout">Tiến hành đặt hàng</a>
        </div>
      </div>
    </div>
  `;
  app.querySelectorAll('.qty-input').forEach((input) => {
    input.addEventListener('change', () => {
      const id = Number(input.closest('tr').dataset.id);
      cart.updateQty(id, Number(input.value) || 1);
      renderCart();
    });
  });
  app.querySelectorAll('.btn-remove').forEach((btn) => {
    btn.addEventListener('click', () => {
      cart.removeFromCart(Number(btn.closest('tr').dataset.id));
      renderCart();
    });
  });
}

// ---------- checkout ----------

async function renderCheckout() {
  if (!getUser()) return requireLoginRedirect('#/checkout');
  const items = cart.getCart();
  if (items.length === 0) { location.hash = '#/cart'; return; }

  app.innerHTML = spinner();
  let profile = {};
  try { profile = await api('/api/users/me'); } catch { /* dùng form trống nếu không lấy được */ }

  app.innerHTML = `
    <h2>Đặt hàng</h2>
    <div class="checkout-layout">
      <form id="checkout-form" class="card">
        <h3>Thông tin giao hàng</h3>
        <label>Họ tên người nhận<input name="fullName" required maxlength="100" value="${esc(profile.fullName || '')}" /></label>
        <label>Số điện thoại<input name="phone" required minlength="8" maxlength="20" pattern="[0-9+ .()-]+" value="${esc(profile.phone || '')}" /></label>
        <label>Địa chỉ<textarea name="address" required maxlength="300" rows="3">${esc(profile.address || '')}</textarea></label>
        <h3>Thanh toán (giả lập)</h3>
        <label class="radio"><input type="radio" name="paymentMethod" value="cod" checked /> ${PAYMENT_LABELS.cod}</label>
        <label class="radio"><input type="radio" name="paymentMethod" value="bank_transfer" /> ${PAYMENT_LABELS.bank_transfer}</label>
        <button class="btn btn-primary btn-lg" type="submit" id="btn-place">Đặt hàng — ${fmtVnd(cart.cartTotal())}</button>
      </form>
      <aside class="card order-summary">
        <h3>Đơn hàng</h3>
        ${items.map((i) => `<div class="sum-row"><span>${esc(i.name)} × ${i.qty}</span><span>${fmtVnd(i.price * i.qty)}</span></div>`).join('')}
        <div class="sum-row sum-total"><span>Tổng</span><span>${fmtVnd(cart.cartTotal())}</span></div>
      </aside>
    </div>
  `;

  document.getElementById('checkout-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = document.getElementById('btn-place');
    btn.disabled = true;
    btn.textContent = 'Đang xử lý…';
    const f = new FormData(e.target);
    try {
      const order = await api('/api/orders', {
        method: 'POST',
        body: {
          fullName: f.get('fullName'),
          phone: f.get('phone'),
          address: f.get('address'),
          paymentMethod: f.get('paymentMethod'),
          items: cart.getCart().map((i) => ({ productId: i.productId, quantity: i.qty })),
        },
      });
      cart.clearCart();
      app.innerHTML = `
        <div class="card center-box">
          <h2>🎉 Đặt hàng thành công!</h2>
          <p>Mã đơn hàng: <strong>#${order.id}</strong> — Tổng tiền: <strong>${fmtVnd(order.total)}</strong></p>
          <p>${PAYMENT_LABELS[order.paymentMethod] || ''} · ${STATUS_LABELS[order.status]}</p>
          <div><a class="btn btn-primary" href="#/orders">Xem đơn hàng</a> <a class="btn btn-ghost" href="#/">Tiếp tục mua sắm</a></div>
        </div>`;
    } catch (err) {
      toast(err.message, 'error');
      btn.disabled = false;
      btn.textContent = `Đặt hàng — ${fmtVnd(cart.cartTotal())}`;
    }
  });
}

// ---------- auth pages ----------

function authAfterLogin() {
  const next = sessionStorage.getItem('bm_after_login') || '#/';
  sessionStorage.removeItem('bm_after_login');
  location.hash = next;
}

function renderLogin() {
  app.innerHTML = `
    <form id="login-form" class="card auth-card">
      <h2>Đăng nhập</h2>
      <label>Email<input name="email" type="email" required /></label>
      <label>Mật khẩu<input name="password" type="password" required /></label>
      <button class="btn btn-primary" type="submit">Đăng nhập</button>
      <p>Chưa có tài khoản? <a href="#/register">Đăng ký</a></p>
    </form>
  `;
  document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      const data = await api('/api/auth/login', { method: 'POST', body: { email: f.get('email'), password: f.get('password') } });
      setSession(data.token, data.user);
      toast(`Xin chào ${data.user.fullName}!`, 'success');
      authAfterLogin();
    } catch (err) {
      toast(err.message, 'error');
    }
  });
}

function renderRegister() {
  app.innerHTML = `
    <form id="register-form" class="card auth-card">
      <h2>Đăng ký tài khoản</h2>
      <label>Họ tên<input name="fullName" required maxlength="100" /></label>
      <label>Email<input name="email" type="email" required /></label>
      <label>Mật khẩu (tối thiểu 8 ký tự)<input name="password" type="password" required minlength="8" /></label>
      <button class="btn btn-primary" type="submit">Đăng ký</button>
      <p>Đã có tài khoản? <a href="#/login">Đăng nhập</a></p>
    </form>
  `;
  document.getElementById('register-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      const data = await api('/api/auth/register', {
        method: 'POST',
        body: { fullName: f.get('fullName'), email: f.get('email'), password: f.get('password') },
      });
      setSession(data.token, data.user);
      toast('Đăng ký thành công!', 'success');
      authAfterLogin();
    } catch (err) {
      toast(err.details ? err.details.join('; ') : err.message, 'error');
    }
  });
}

// ---------- order history ----------

function orderCard(o, adminView = false) {
  return `
    <div class="card order-card">
      <div class="order-head">
        <strong>Đơn #${o.id}</strong>
        ${adminView ? `<span class="muted">user #${o.userId}</span>` : ''}
        <span class="muted">${fmtDate(o.createdAt)}</span>
        <span class="status status-${o.status}">${STATUS_LABELS[o.status] || o.status}</span>
      </div>
      <div class="order-items">
        ${o.items.map((i) => `<div class="sum-row"><span>${esc(i.productName)} × ${i.quantity}</span><span>${fmtVnd(i.unitPrice * i.quantity)}</span></div>`).join('')}
      </div>
      <div class="order-foot">
        <small class="muted">${esc(o.shipping.fullName)} · ${esc(o.shipping.phone)} · ${esc(o.shipping.address)}</small>
        <strong>${fmtVnd(o.total)}</strong>
      </div>
      ${adminView ? `
        <div class="order-admin-row" data-id="${o.id}">
          <select class="status-select" ${o.status === 'cancelled' ? 'disabled' : ''}>
            ${['confirmed', 'shipping', 'completed', 'cancelled'].map((st) => `<option value="${st}" ${o.status === st ? 'selected' : ''}>${STATUS_LABELS[st]}</option>`).join('')}
          </select>
        </div>` : ''}
    </div>`;
}

async function renderOrders() {
  if (!getUser()) return requireLoginRedirect('#/orders');
  app.innerHTML = spinner();
  try {
    const data = await api('/api/orders/mine?limit=20');
    app.innerHTML = `
      <h2>Đơn hàng của tôi</h2>
      ${data.items.length ? data.items.map((o) => orderCard(o)).join('') : '<div class="card center-box"><p>Bạn chưa có đơn hàng nào.</p><a class="btn btn-primary" href="#/">Mua sắm ngay</a></div>'}
    `;
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
  }
}

// ---------- account ----------

async function renderAccount() {
  if (!getUser()) return requireLoginRedirect('#/account');
  app.innerHTML = spinner();
  let me;
  try {
    me = await api('/api/users/me');
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
    return;
  }
  app.innerHTML = `
    <form id="account-form" class="card auth-card">
      <h2>Tài khoản của tôi</h2>
      <p class="muted">${esc(me.email)} · vai trò: ${me.role}</p>
      <label>Họ tên<input name="fullName" required maxlength="100" value="${esc(me.fullName)}" /></label>
      <label>Số điện thoại<input name="phone" maxlength="20" pattern="[0-9+ .()-]*" value="${esc(me.phone)}" /></label>
      <label>Địa chỉ mặc định<textarea name="address" maxlength="300" rows="3">${esc(me.address)}</textarea></label>
      <button class="btn btn-primary" type="submit">Lưu thay đổi</button>
    </form>
  `;
  document.getElementById('account-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      const updated = await api('/api/users/me', {
        method: 'PUT',
        body: { fullName: f.get('fullName'), phone: f.get('phone'), address: f.get('address') },
      });
      setSession(localStorage.getItem('bm_token'), updated);
      toast('Đã lưu hồ sơ', 'success');
    } catch (err) {
      toast(err.details ? err.details.join('; ') : err.message, 'error');
    }
  });
}

// ---------- admin: products ----------

const EMPTY_PRODUCT = { id: null, name: '', brand: '', ageRange: '0-6m', price: 0, stock: 0, origin: '', description: '', ingredients: '', imageUrl: '' };

async function renderAdminProducts() {
  const user = getUser();
  if (!user) return requireLoginRedirect('#/admin');
  if (user.role !== 'admin') { app.innerHTML = '<p class="error-box">Bạn không có quyền truy cập trang này.</p>'; return; }

  app.innerHTML = spinner();
  let data;
  try {
    data = await api('/api/products?limit=100&sort=newest');
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
    return;
  }

  app.innerHTML = `
    <div class="admin-head">
      <h2>Quản trị — Sản phẩm</h2>
      <nav class="admin-tabs"><a class="active" href="#/admin">Sản phẩm</a><a href="#/admin/orders">Đơn hàng</a></nav>
    </div>
    <details class="card admin-form-wrap" id="product-form-wrap">
      <summary id="form-title">➕ Thêm sản phẩm mới</summary>
      <form id="product-form">
        <input type="hidden" name="id" />
        <div class="form-grid">
          <label>Tên sản phẩm<input name="name" required maxlength="200" /></label>
          <label>Thương hiệu<input name="brand" required maxlength="100" /></label>
          <label>Độ tuổi
            <select name="ageRange">${Object.entries(AGE_LABELS).map(([v, l]) => `<option value="${v}">${l}</option>`).join('')}</select>
          </label>
          <label>Giá (VND)<input name="price" type="number" required min="0" step="1000" /></label>
          <label>Tồn kho<input name="stock" type="number" required min="0" /></label>
          <label>Xuất xứ<input name="origin" maxlength="100" /></label>
        </div>
        <label>Mô tả<textarea name="description" rows="2" maxlength="5000"></textarea></label>
        <label>Thành phần dinh dưỡng<textarea name="ingredients" rows="2" maxlength="5000"></textarea></label>
        <label>URL ảnh (tùy chọn)<input name="imageUrl" maxlength="500" /></label>
        <div class="form-actions">
          <button class="btn btn-primary" type="submit">Lưu</button>
          <button class="btn btn-ghost" type="button" id="btn-form-reset">Làm mới form</button>
        </div>
      </form>
    </details>
    <div class="card">
      <table class="table admin-table">
        <thead><tr><th>ID</th><th>Sản phẩm</th><th>Độ tuổi</th><th>Giá</th><th>Tồn kho</th><th>Thao tác</th></tr></thead>
        <tbody>
          ${data.items.map((p) => `
            <tr data-id="${p.id}">
              <td>${p.id}</td>
              <td>${esc(p.name)}<br /><small class="muted">${esc(p.brand)}</small></td>
              <td>${AGE_LABELS[p.ageRange] || esc(p.ageRange)}</td>
              <td>${fmtVnd(p.price)}</td>
              <td class="stock-cell">
                <input class="stock-input" type="number" min="0" value="${p.stock}" />
                <button class="btn btn-sm btn-stock" title="Cập nhật tồn kho">💾</button>
              </td>
              <td>
                <button class="btn btn-sm btn-edit">Sửa</button>
                <button class="btn btn-sm btn-danger btn-delete">Xóa</button>
              </td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>
  `;

  const products = new Map(data.items.map((p) => [p.id, p]));
  const form = document.getElementById('product-form');
  const wrap = document.getElementById('product-form-wrap');

  function fillForm(p) {
    document.getElementById('form-title').textContent = p.id ? `✏️ Sửa sản phẩm #${p.id}` : '➕ Thêm sản phẩm mới';
    for (const [k, v] of Object.entries(p)) {
      const field = form.elements[k];
      if (field) field.value = v ?? '';
    }
    wrap.open = true;
  }

  document.getElementById('btn-form-reset').addEventListener('click', () => { form.reset(); fillForm(EMPTY_PRODUCT); });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(form);
    const id = f.get('id');
    const body = {
      name: f.get('name'), brand: f.get('brand'), ageRange: f.get('ageRange'),
      price: Number(f.get('price')), stock: Number(f.get('stock')),
      origin: f.get('origin'), description: f.get('description'), ingredients: f.get('ingredients'),
      imageUrl: f.get('imageUrl') || null,
    };
    try {
      if (id) await api(`/api/products/${id}`, { method: 'PUT', body });
      else await api('/api/products', { method: 'POST', body });
      toast('Đã lưu sản phẩm', 'success');
      metaCache = null; // brand list có thể đã thay đổi
      renderAdminProducts();
    } catch (err) {
      toast(err.details ? err.details.join('; ') : err.message, 'error');
    }
  });

  app.querySelectorAll('.btn-edit').forEach((btn) => btn.addEventListener('click', () => {
    fillForm(products.get(Number(btn.closest('tr').dataset.id)));
    wrap.scrollIntoView({ behavior: 'smooth' });
  }));

  app.querySelectorAll('.btn-delete').forEach((btn) => btn.addEventListener('click', async () => {
    const id = Number(btn.closest('tr').dataset.id);
    if (!confirm(`Xóa sản phẩm #${id}? Hành động này không hoàn tác được.`)) return;
    try {
      await api(`/api/products/${id}`, { method: 'DELETE' });
      toast('Đã xóa sản phẩm', 'success');
      metaCache = null;
      renderAdminProducts();
    } catch (err) {
      toast(err.message, 'error');
    }
  }));

  app.querySelectorAll('.btn-stock').forEach((btn) => btn.addEventListener('click', async () => {
    const tr = btn.closest('tr');
    const id = Number(tr.dataset.id);
    const stock = Number(tr.querySelector('.stock-input').value);
    try {
      await api(`/api/products/${id}/stock`, { method: 'PATCH', body: { stock } });
      toast(`Đã cập nhật tồn kho #${id} = ${stock}`, 'success');
    } catch (err) {
      toast(err.details ? err.details.join('; ') : err.message, 'error');
    }
  }));
}

// ---------- admin: orders ----------

async function renderAdminOrders() {
  const user = getUser();
  if (!user) return requireLoginRedirect('#/admin/orders');
  if (user.role !== 'admin') { app.innerHTML = '<p class="error-box">Bạn không có quyền truy cập trang này.</p>'; return; }

  app.innerHTML = spinner();
  let data;
  try {
    data = await api('/api/orders?limit=50');
  } catch (e) {
    app.innerHTML = `<p class="error-box">${esc(e.message)}</p>`;
    return;
  }
  app.innerHTML = `
    <div class="admin-head">
      <h2>Quản trị — Đơn hàng</h2>
      <nav class="admin-tabs"><a href="#/admin">Sản phẩm</a><a class="active" href="#/admin/orders">Đơn hàng</a></nav>
    </div>
    ${data.items.length ? data.items.map((o) => orderCard(o, true)).join('') : '<div class="card center-box"><p>Chưa có đơn hàng nào.</p></div>'}
  `;
  app.querySelectorAll('.order-admin-row .status-select').forEach((sel) => sel.addEventListener('change', async () => {
    const id = Number(sel.closest('.order-admin-row').dataset.id);
    if (sel.value === 'cancelled' && !confirm(`Hủy đơn #${id}? Tồn kho sẽ được hoàn lại.`)) { renderAdminOrders(); return; }
    try {
      await api(`/api/orders/${id}/status`, { method: 'PATCH', body: { status: sel.value } });
      toast(`Đơn #${id} → ${STATUS_LABELS[sel.value]}`, 'success');
      renderAdminOrders();
    } catch (err) {
      toast(err.message, 'error');
      renderAdminOrders();
    }
  }));
}

// ---------- router ----------

const ROUTES = [
  [/^#?\/?$/, renderCatalog],
  [/^#\/product\/(\d+)$/, (m) => renderProduct(Number(m[1]))],
  [/^#\/cart$/, renderCart],
  [/^#\/checkout$/, renderCheckout],
  [/^#\/login$/, renderLogin],
  [/^#\/register$/, renderRegister],
  [/^#\/orders$/, renderOrders],
  [/^#\/account$/, renderAccount],
  [/^#\/admin$/, renderAdminProducts],
  [/^#\/admin\/orders$/, renderAdminOrders],
];

function route() {
  const hash = location.hash || '#/';
  for (const [pattern, handler] of ROUTES) {
    const m = hash.match(pattern);
    if (m) return handler(m);
  }
  app.innerHTML = '<p class="error-box">Trang không tồn tại. <a href="#/">Về trang chủ</a></p>';
}

window.addEventListener('hashchange', route);
renderNav();
route();
