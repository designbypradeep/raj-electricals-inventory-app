-- ============================================================================
-- SECURITY MIGRATIONS FOR RAJ ELECTRICALS INVENTORY
-- ============================================================================
-- Created: 2025-12-29
-- Purpose: Fix identified security vulnerabilities
-- 
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard → SQL Editor
-- 2. Paste this entire file
-- 3. Execute (F5 or click Run)
-- 4. Verify no errors in output
-- ============================================================================

-- ============================================================================
-- SECTION 1: FIX DATA TYPE INCONSISTENCIES
-- ============================================================================

-- Fix supplier_ledger.business_id from TEXT to UUID
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'supplier_ledger' 
        AND column_name = 'business_id' 
        AND data_type = 'text'
    ) THEN
        ALTER TABLE supplier_ledger 
        ALTER COLUMN business_id TYPE uuid USING business_id::uuid;
        RAISE NOTICE 'Fixed supplier_ledger.business_id to UUID';
    ELSE
        RAISE NOTICE 'supplier_ledger.business_id already correct or does not exist';
    END IF;
END $$;

-- Fix purchase_returns.business_id from TEXT to UUID
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'purchase_returns' 
        AND column_name = 'business_id' 
        AND data_type = 'text'
    ) THEN
        ALTER TABLE purchase_returns 
        ALTER COLUMN business_id TYPE uuid USING business_id::uuid;
        RAISE NOTICE 'Fixed purchase_returns.business_id to UUID';
    ELSE
        RAISE NOTICE 'purchase_returns.business_id already correct or does not exist';
    END IF;
END $$;

-- ============================================================================
-- SECTION 2: RATE LIMITING TABLE
-- ============================================================================

-- Create rate limit tracking table
CREATE TABLE IF NOT EXISTS shop_order_rate_limits (
    id BIGSERIAL PRIMARY KEY,
    client_identifier TEXT NOT NULL, -- IP or device fingerprint
    business_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient rate limit checks
CREATE INDEX IF NOT EXISTS idx_rate_limits_lookup 
ON shop_order_rate_limits(client_identifier, business_id, created_at);

-- Auto-cleanup old entries (older than 24 hours)
CREATE OR REPLACE FUNCTION cleanup_old_rate_limits()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM shop_order_rate_limits 
    WHERE created_at < NOW() - INTERVAL '24 hours';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to run cleanup on insert
DROP TRIGGER IF EXISTS rate_limit_cleanup_trigger ON shop_order_rate_limits;
CREATE TRIGGER rate_limit_cleanup_trigger
    AFTER INSERT ON shop_order_rate_limits
    FOR EACH STATEMENT
    EXECUTE FUNCTION cleanup_old_rate_limits();

-- Grant anon permission to insert (for rate tracking)
GRANT INSERT ON shop_order_rate_limits TO anon, authenticated;
GRANT USAGE ON SEQUENCE shop_order_rate_limits_id_seq TO anon, authenticated;

-- ============================================================================
-- SECTION 3: SECURE SHOP ORDER RPC WITH VALIDATION + RATE LIMITING
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_shop_order_secure(
    p_business_id UUID,
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_items JSONB, -- Array of objects: [{"product_id": 123, "quantity": 2}]
    p_payment_method TEXT DEFAULT 'upi',
    p_transaction_id TEXT DEFAULT NULL,
    p_payment_proof_url TEXT DEFAULT NULL,
    p_client_identifier TEXT DEFAULT 'unknown' -- For rate limiting
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_id BIGINT;
    v_item JSONB;
    v_product_id BIGINT;
    v_quantity INT;
    v_price NUMERIC;
    v_product_record RECORD;
    v_total_amount NUMERIC := 0;
    v_rate_count INT;
    v_max_orders_per_hour INT := 10;
BEGIN
    -- ===========================================
    -- VALIDATION 1: Rate Limiting
    -- ===========================================
    SELECT COUNT(*) INTO v_rate_count
    FROM shop_order_rate_limits
    WHERE client_identifier = p_client_identifier
    AND business_id = p_business_id
    AND created_at > NOW() - INTERVAL '1 hour';
    
    IF v_rate_count >= v_max_orders_per_hour THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'RATE_LIMIT_EXCEEDED',
            'message', 'Too many orders. Please wait before placing another order.'
        );
    END IF;
    
    -- Record this attempt for rate limiting
    INSERT INTO shop_order_rate_limits (client_identifier, business_id)
    VALUES (p_client_identifier, p_business_id);
    
    -- ===========================================
    -- VALIDATION 2: Business exists and is active
    -- ===========================================
    IF NOT EXISTS (
        SELECT 1 FROM business_profiles 
        WHERE id = p_business_id AND is_active = true
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_BUSINESS',
            'message', 'Business not found or inactive.'
        );
    END IF;
    
    -- ===========================================
    -- VALIDATION 3: Items array is not empty
    -- ===========================================
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'EMPTY_ORDER',
            'message', 'Order must contain at least one item.'
        );
    END IF;
    
    -- ===========================================
    -- VALIDATION 4: Validate each item
    -- ===========================================
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::BIGINT;
        v_quantity := (v_item->>'quantity')::INT;
        
        -- Check quantity is positive
        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_QUANTITY',
                'message', 'Quantity must be a positive number.',
                'product_id', v_product_id
            );
        END IF;
        
        -- Check product exists and belongs to this business
        SELECT id, name, selling_price, current_stock, status
        INTO v_product_record
        FROM products
        WHERE id = v_product_id 
        AND business_id = p_business_id
        AND status = 'active';
        
        IF v_product_record IS NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PRODUCT_NOT_FOUND',
                'message', 'Product not found or not available.',
                'product_id', v_product_id
            );
        END IF;
        
        -- Check stock availability (optional - can be removed for reservation-only)
        IF v_product_record.current_stock < v_quantity THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INSUFFICIENT_STOCK',
                'message', 'Not enough stock available.',
                'product_id', v_product_id,
                'product_name', v_product_record.name,
                'available', v_product_record.current_stock,
                'requested', v_quantity
            );
        END IF;
        
        -- Calculate total using SERVER-SIDE price (ignore client price)
        v_total_amount := v_total_amount + (v_product_record.selling_price * v_quantity);
    END LOOP;
    
    -- ===========================================
    -- INSERT: Create shop order (NOT sales - pending verification)
    -- ===========================================
    INSERT INTO shop_orders (
        business_id,
        customer_name,
        customer_phone,
        total_amount,
        payment_method,
        transaction_id,
        payment_proof_url,
        status,
        created_at
    ) VALUES (
        p_business_id,
        COALESCE(p_customer_name, 'Walk-in Customer'),
        p_customer_phone,
        v_total_amount,
        p_payment_method,
        p_transaction_id,
        p_payment_proof_url,
        'payment_pending',
        NOW()
    ) RETURNING id INTO v_order_id;
    
    -- ===========================================
    -- INSERT: Order items with SERVER-SIDE pricing
    -- ===========================================
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::BIGINT;
        v_quantity := (v_item->>'quantity')::INT;
        
        -- Get server-side price
        SELECT selling_price INTO v_price
        FROM products WHERE id = v_product_id;
        
        INSERT INTO shop_order_items (order_id, product_id, quantity, price_per_unit)
        VALUES (v_order_id, v_product_id, v_quantity, v_price);
    END LOOP;
    
    -- NOTE: Stock is NOT decremented here. It will be decremented
    -- only when the order is verified via verify_shop_order RPC.
    
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'total_amount', v_total_amount,
        'status', 'payment_pending',
        'message', 'Order placed successfully. Awaiting payment verification.'
    );
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', 'INTERNAL_ERROR',
        'message', 'An unexpected error occurred. Please try again.'
    );
END;
$$;

-- Grant execute permission to anon users
GRANT EXECUTE ON FUNCTION public.submit_shop_order_secure(
    UUID, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, TEXT
) TO anon, authenticated, service_role;

-- ============================================================================
-- SECTION 4: SECURE PUBLIC VIEWS (HIDE SENSITIVE DATA)
-- ============================================================================

-- View for public business info (excludes PII)
CREATE OR REPLACE VIEW public_business_info AS
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
    -- EXCLUDED: phone, email, gst_number, pan_number, upi_vpa
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

-- Grant public read access to the view
GRANT SELECT ON public_business_info TO anon, authenticated;

-- View for public products (excludes purchase_price/margins)
CREATE OR REPLACE VIEW public_products AS
SELECT 
    p.id,
    p.business_id,
    p.name,
    p.brand,
    p.category,
    p.size_or_spec,
    p.selling_price,
    -- EXCLUDED: purchase_price (margin info)
    p.current_stock,
    p.unit_type_single,
    p.unit_type_wholesale,
    p.items_per_wholesale_unit,
    p.product_image_url,
    p.description,
    p.status,
    p.created_at
FROM products p
WHERE p.status = 'active';

-- Grant public read access to the view
GRANT SELECT ON public_products TO anon, authenticated;

-- ============================================================================
-- SECTION 5: RPC TO GET PUBLIC BUSINESS BY SLUG (USES SECURE VIEW)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_public_business_by_slug_secure(p_slug TEXT)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER -- Uses caller's permissions, not owner's
STABLE
AS $$
    SELECT to_jsonb(pbi.*)
    FROM public_business_info pbi
    WHERE pbi.slug = p_slug
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_business_by_slug_secure(TEXT) 
TO anon, authenticated, service_role;

-- ============================================================================
-- SECTION 6: RPC TO GET PUBLIC PRODUCTS FOR BUSINESS (USES SECURE VIEW)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_public_products_for_business(p_business_id UUID)
RETURNS SETOF public_products
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
    SELECT * FROM public_products
    WHERE business_id = p_business_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_products_for_business(UUID) 
TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICATION QUERIES (Run these to verify migration success)
-- ============================================================================

-- Check data types are fixed
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_name IN ('supplier_ledger', 'purchase_returns') 
-- AND column_name = 'business_id';

-- Check new functions exist
-- SELECT routine_name FROM information_schema.routines 
-- WHERE routine_schema = 'public' 
-- AND routine_name IN ('submit_shop_order_secure', 'get_public_business_by_slug_secure', 'get_public_products_for_business');

-- Check new views exist
-- SELECT table_name FROM information_schema.views 
-- WHERE table_schema = 'public' 
-- AND table_name IN ('public_business_info', 'public_products');

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
