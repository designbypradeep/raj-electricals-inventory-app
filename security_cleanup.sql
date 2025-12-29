-- ============================================================================
-- SECURITY CLEANUP - ✅ RAN SUCCESSFULLY
-- ============================================================================
-- Executed: 2025-12-29
-- Status: All vulnerable functions and policies removed
-- ============================================================================

-- ============================================================================
-- SECTION 1: DROP VULNERABLE FUNCTIONS
-- ============================================================================

-- Old shop order RPC (inserts into sales, decrements stock immediately)
DROP FUNCTION IF EXISTS public.submit_shop_order(UUID, TEXT, TEXT, NUMERIC, TEXT, JSONB, TEXT, TEXT);

-- Old business profile RPC (returns all columns including PII)
DROP FUNCTION IF EXISTS public.get_public_business_profile(UUID);

-- Old products RPC (returns all columns including purchase_price)
DROP FUNCTION IF EXISTS public.get_public_products(UUID);

-- Old default shop ID function (returns first business found)
DROP FUNCTION IF EXISTS public.get_default_shop_id();

-- Old product images RPC
DROP FUNCTION IF EXISTS public.get_public_product_images(BIGINT[]);

-- Old slug RPC (if exists alongside secure version)
DROP FUNCTION IF EXISTS public.get_public_business_by_slug(TEXT);

-- ============================================================================
-- SECTION 2: DROP OVERLY PERMISSIVE RLS POLICIES
-- ============================================================================

-- These exposed ALL data with USING(true)
DROP POLICY IF EXISTS "Public can view business profiles" ON business_profiles;
DROP POLICY IF EXISTS "Public can view products" ON products;
DROP POLICY IF EXISTS "Public can view product images" ON product_images;

-- ============================================================================
-- SECTION 3: VERIFY SECURE REPLACEMENTS EXIST
-- ============================================================================

-- Run these SELECT queries to verify secure functions exist:
-- SELECT routine_name FROM information_schema.routines 
-- WHERE routine_schema = 'public' 
-- AND routine_name IN (
--   'submit_shop_order_secure',
--   'get_public_business_by_slug_secure', 
--   'get_public_products_for_business'
-- );

-- Verify secure views exist:
-- SELECT table_name FROM information_schema.views 
-- WHERE table_schema = 'public' 
-- AND table_name IN ('public_business_info', 'public_products');

-- ============================================================================
-- DONE!
-- ============================================================================
-- After running this, your database will only have the secure functions:
-- - submit_shop_order_secure (rate limited, server-side pricing)
-- - get_public_business_by_slug_secure (uses public_business_info view)
-- - get_public_products_for_business (uses public_products view)
-- ============================================================================
