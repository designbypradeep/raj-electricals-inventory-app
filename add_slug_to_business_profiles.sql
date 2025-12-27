-- Migration: Add Slug and Branding to Business Profiles
-- Purpose: Enable runtime resolution of shops via unique slugs.

-- 1. Add Columns
ALTER TABLE public.business_profiles
ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS primary_color VARCHAR(10),
ADD COLUMN IF NOT EXISTS secondary_color VARCHAR(10),
ADD COLUMN IF NOT EXISTS footer_text TEXT;

-- 2. Backfill Slugs for existing businesses (Simple sanitization)
-- Takes business_name, lowercases, replaces spaces with dashes, removes special chars.
-- Note: This might conflict if two businesses have same name, but fine for initial migration.
UPDATE public.business_profiles
SET slug = trim(BOTH '-' FROM lower(regexp_replace(business_name, '[^a-zA-Z0-9]+', '-', 'g')))
WHERE slug IS NULL;

-- 3. Create Public RPC to resolve Slug -> ID
CREATE OR REPLACE FUNCTION public.get_public_business_by_slug(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile JSONB;
BEGIN
    SELECT to_jsonb(bp.*)
    INTO v_profile
    FROM public.business_profiles bp
    WHERE bp.slug = p_slug
      AND bp.is_active = true
    LIMIT 1;

    -- Return null if not found (let client handle it)
    RETURN v_profile;
END;
$$;

-- 4. Grant access to Anon users
GRANT EXECUTE ON FUNCTION public.get_public_business_by_slug(TEXT) TO anon, authenticated, service_role;

-- 5. Enable Public Read on business_profiles via RLS/RPC?
-- We already have specific RPCs for access. This new RPC handles the initial lookup.
-- No change needed to table RLS if we stick to RPCs.
