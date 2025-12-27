-- Enable public read access for Shop App (Anonymous users)

-- 1. Business Profiles
-- Allow anyone to read business profiles (to find the shop details)
DROP POLICY IF EXISTS "Public can view business profiles" ON business_profiles;
CREATE POLICY "Public can view business profiles" ON business_profiles
  FOR SELECT USING (true);

-- 2. Products
-- Allow anyone to read products
DROP POLICY IF EXISTS "Public can view products" ON products;
CREATE POLICY "Public can view products" ON products
  FOR SELECT USING (true);

-- 3. Product Images
-- Allow anyone to read product images
ALTER TABLE IF EXISTS product_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view product images" ON product_images;
CREATE POLICY "Public can view product images" ON product_images
  FOR SELECT USING (true);
