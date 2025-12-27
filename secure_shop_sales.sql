-- Secure Shop Order Submission RPC
-- Allows anonymous Shop users to place orders safely for a specific business.

CREATE OR REPLACE FUNCTION public.submit_shop_order(
    p_business_id UUID,
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_total_amount NUMERIC,
    p_payment_method TEXT,
    p_items JSONB, -- Array of objects: [{"product_id": 123, "quantity": 2, "price_per_unit": 100}]
    p_transaction_id TEXT DEFAULT NULL,
    p_payment_proof_url TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sale_id BIGINT;
    v_item JSONB;
    v_product_id BIGINT;
    v_quantity INT;
    v_price NUMERIC;
BEGIN
    -- 1. Insert Sale Record
    INSERT INTO public.sales (
        business_id,
        customer_name,
        customer_phone,
        total_amount,
        payment_method,
        transaction_id,
        payment_proof_url,
        created_at,
        status -- Default to 'pending' or 'completed' based on payment proof? Let's use 'pending' for check.
    ) VALUES (
        p_business_id,
        COALESCE(p_customer_name, 'Walk-in Customer'),
        p_customer_phone,
        p_total_amount,
        p_payment_method,
        p_transaction_id,
        p_payment_proof_url,
        NOW(),
        'pending' 
    ) RETURNING id INTO v_sale_id;

    -- 2. Process Items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::BIGINT;
        v_quantity := (v_item->>'quantity')::INT;
        v_price := (v_item->>'price_per_unit')::NUMERIC;

        -- Insert Sale Item
        INSERT INTO public.sales_items (sale_id, product_id, quantity, price_per_unit)
        VALUES (v_sale_id, v_product_id, v_quantity, v_price);

        -- Decrement Stock (Simple decrement)
        UPDATE public.products
        SET current_stock = current_stock - v_quantity
        WHERE id = v_product_id;
    END LOOP;

    RETURN v_sale_id;
END;
$$;

-- Grant execute permission to anon (public) users
GRANT EXECUTE ON FUNCTION public.submit_shop_order(UUID, TEXT, TEXT, NUMERIC, TEXT, JSONB, TEXT, TEXT) TO anon, authenticated, service_role;
