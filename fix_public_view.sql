-- ============================================================================
-- PUBLIC BUSINESS VIEW - Required for shop/receipts
-- ============================================================================
-- All fields included are needed for customer-facing features:
-- - UPI VPA: Payments
-- - Phone: Customer support  
-- - GST Number: Legal requirement on invoices
-- - Email: Contact/receipts (business can edit/remove if spam issues)
-- ============================================================================

-- Drop existing view first (required when changing column structure)
DROP VIEW IF EXISTS public_business_info;

CREATE VIEW public_business_info AS
SELECT 
    id,
    business_name,
    business_type,
    logo_url,
    address,
    city,
    state,
    postal_code,
    country,
    upi_vpa,       -- Payments
    phone,         -- Customer support
    email,         -- Contact/receipts (editable by business)
    gst_number,    -- Legal requirement for invoices
    -- EXCLUDED: pan_number (private tax info)
    website,
    description,
    currency,
    timezone,
    slug,
    is_active,
    primary_color,
    secondary_color,
    footer_text,
    created_at
FROM business_profiles
WHERE is_active = true;

GRANT SELECT ON public_business_info TO anon, authenticated;
