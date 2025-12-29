# Security Analysis & Implementation

**Last Updated:** December 29, 2025  
**Status:** ✅ All Fixes Implemented

---

## Executive Summary

| Category | Count | Status |
|----------|-------|--------|
| 🔴 Critical | 2 fixed | ✅ Done |
| 🟠 High | 3 fixed | ✅ Done |
| 🟡 Medium | 4 fixed | ✅ Done |
| 🟢 Low | 3 | ℹ️ Acceptable |

---

## Architecture

```
┌─────────────────┐          ┌─────────────────┐
│   Admin App     │          │    Shop App     │
│ (Authenticated) │          │  (Anonymous)    │
└────────┬────────┘          └────────┬────────┘
         │                            │
         │ login/OTP                  │ QR/Deep Link
         ▼                            ▼
    ┌────────────────────────────────────────┐
    │           Supabase Backend             │
    ├────────────────────────────────────────┤
    │  ✅ submit_shop_order_secure (NEW)     │
    │  ✅ get_public_business_by_slug_secure │
    │  ✅ get_public_products_for_business   │
    │  ✅ public_business_info view          │
    │  ✅ public_products view               │
    └────────────────────────────────────────┘
```

---

## What Was Fixed

### Flutter App

| File | Change |
|------|--------|
| `app.dart` | Uses `get_public_business_by_slug_secure` |
| `welcome_page.dart` | Uses `get_public_business_by_slug_secure` |
| `supabase_service.dart` | Uses `get_public_products_for_business` |
| `supabase_service.dart` | Queries `public_business_info` view |

### SvelteKit App (`src/routes/shop/+page.server.ts`)
| Change | Details |
|--------|---------|
| **Business Profile** | Uses `public_business_info` View (hides sensitive columns like PAN) |
| **Products** | Uses `get_public_products_for_business` RPC (hides purchase_price) |
| **Order Submission** | Uses `submit_shop_order_secure` RPC (server-side pricing, rate limited) |
| **Cleanup** | Deleted `/api/debug-profit` and `/api/test-db` (RLS bypasses) |

---

## Security Principles (For Future Devs)

### 1. No Client-Side Trust
*   **Old Way:** Client calculated total price → **Vulnerable** (User could send ₹1 total).
*   **New Way:** Client sends `product_id` + `quantity`. Server calculates total using database price.

### 2. Views vs Tables
*   **Tables:** Restricted by RLS. Good for authenticated users, hard for anonymous public access without leaking data.
*   **Views:** We use `public_business_info` and `public_products` views to explicitly whitelist columns.
    *   *Why?* It's safer to have a View that physically cannot return `purchase_price` than to rely on an RLS policy that might be accidentally turned off.

### 3. Immediate vs Deferred Stock
*   **Old Way:** Stock decremented immediately on order → **Vulnerable** (Stock drain attack).
*   **New Way:** Stock is checked but NOT decremented until secure RPC validation passes. (Inventory is decremented in `submit_shop_order_secure` only *after* validation).

### 4. Rate Limiting
*   Public RPCs (`submit_shop_order_secure`) now enforce rate limits (e.g., 3 orders per minute per IP) to prevent spam.

### SQL Files Deprecated

| File | Status |
|------|--------|
| `secure_shop_sales.sql` | Replaced with deprecation notice |
| `secure_shop_access.sql` | Replaced with deprecation notice |
| `enable_public_shop_access.sql` | Replaced with deprecation notice |

---

## SQL Files to Run

> [!IMPORTANT]
> Run these in **Supabase Dashboard → SQL Editor** in order:

### 1. `fix_public_view.sql`
Updates the public view to include fields needed for shop functionality:
- `upi_vpa` - Payments
- `phone` - Customer support
- `email` - Contact/receipts
- `gst_number` - Legal requirement

### 2. `security_cleanup.sql`
Removes old vulnerable functions:
- `submit_shop_order` (immediate stock decrement)
- `get_public_business_profile` (exposed PII)
- `get_public_products` (exposed purchase_price)
- Old `USING(true)` RLS policies

---

## Data Exposure Matrix

| Column | Public View | Reason |
|--------|-------------|--------|
| `business_name` | ✅ | Shop branding |
| `logo_url` | ✅ | Shop branding |
| `upi_vpa` | ✅ | Payment QR |
| `phone` | ✅ | Customer support |
| `email` | ✅ | Receipts (editable) |
| `gst_number` | ✅ | Legal requirement |
| `pan_number` | ❌ | Sensitive tax info |
| `purchase_price` | ❌ | Business margins |

---

## Testing Checklist

After running the SQL files, verify:

- [ ] Shop app loads via QR/slug
- [ ] Business logo and name display
- [ ] Products load (without purchase_price)
- [ ] UPI payment QR works
- [ ] Orders submit successfully
- [ ] Admin can verify orders

## ℹ️ Note on Supabase Dashboard Badges

You may see an **"UNRESTRICTED"** badge next to `public_business_info` and `public_products` views in the Table Editor.

**This is Normal and Safe.**
- These are **Views**, not Tables.
- They are "Unrestricted" because they don't use Row Level Security (RLS) policies.
- Instead, **the View itself IS the security policy**:
  - It hardcodes exactly which columns are visible (hiding PII/margins).
  - It hardcodes the row filter (`WHERE is_active = true`).
- Access is safe because `anon` users only have permission to SELECT from these Views, not the underlying Tables.

