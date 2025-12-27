-- Secure Public Access for Shop App via RPC Functions
-- This allows access ONLY to the specific business data requested, preventing data leaks.

-- 1. Function to get the default shop ID (e.g. the first business found)
CREATE OR REPLACE FUNCTION public.get_default_shop_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    found_id UUID;
BEGIN
    SELECT id INTO found_id FROM public.business_profiles LIMIT 1;
    RETURN found_id;
END;
$$;

-- 2. Function to get a public business profile by ID
CREATE OR REPLACE FUNCTION public.get_public_business_profile(target_business_id UUID)
RETURNS SETOF public.business_profiles
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT * FROM public.business_profiles
    WHERE id = target_business_id;
$$;

-- 3. Function to get public products for a business
CREATE OR REPLACE FUNCTION public.get_public_products(target_business_id UUID)
RETURNS SETOF public.products
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT * FROM public.products
    WHERE business_id = target_business_id
    AND status = 'active'; -- Optional: ensure only active products are shown
$$;

-- 4. Grant permissions to anonymous users
GRANT EXECUTE ON FUNCTION public.get_default_shop_id() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_business_profile(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_products(UUID) TO anon, authenticated, service_role;

-- 5. Helper for images (often public buckets need policy, but RPC can return URLs)
-- Product images are URLs in 'products' table mostly, or 'product_images' table.
-- If 'product_images' table is used:
CREATE OR REPLACE FUNCTION public.get_public_product_images(target_product_ids BIGINT[])
RETURNS SETOF public.product_images
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT * FROM public.product_images
    WHERE product_id = ANY(target_product_ids);
$$;

GRANT EXECUTE ON FUNCTION public.get_public_product_images(BIGINT[]) TO anon, authenticated, service_role;
