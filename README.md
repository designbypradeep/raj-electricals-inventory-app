# Raj Electricals Inventory App

A comprehensive Flutter inventory management application for electrical goods business with Supabase backend.

## Features

- 📦 **Product Management**: Add, edit, archive products with multiple images
- 💰 **Sales & Purchases**: Record sales and purchases with detailed tracking
- 📊 **Reports & Analytics**: Dashboard with charts, profit/loss analysis
- 🔄 **Returns & Replacements**: Handle customer returns and product replacements
- 🤝 **Suppliers Management**: Track suppliers/dealers with contact info, advances, and credits
- 👥 **Customers Management**: Manage customers with debt tracking
- 💳 **Supplier Credit System**: Credit notes for returns, apply credits to future purchases
- 📱 **Shop Mode**: Customer-facing storefront with UPI payment
- 🔐 **Authentication**: Secure login with biometric support
- 🌙 **Dark Mode**: Full theme support

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Supabase account
- Android Studio / VS Code with Flutter extensions

## Supabase Setup

### 1. Create Tables

Run the following SQL scripts in your Supabase SQL editor:

#### Suppliers Table
```sql
CREATE TABLE IF NOT EXISTS suppliers (
  id BIGSERIAL PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES business_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  contact_number TEXT,
  physical_address TEXT,
  map_location TEXT,
  advance_pay NUMERIC(10, 2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suppliers_business_id ON suppliers(business_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(name);

ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their business suppliers"
  ON suppliers FOR SELECT
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can insert suppliers for their business"
  ON suppliers FOR INSERT
  WITH CHECK (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can update their business suppliers"
  ON suppliers FOR UPDATE
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can delete their business suppliers"
  ON suppliers FOR DELETE
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE OR REPLACE FUNCTION update_suppliers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER suppliers_updated_at_trigger
  BEFORE UPDATE ON suppliers
  FOR EACH ROW
  EXECUTE FUNCTION update_suppliers_updated_at();
```

#### Customers Table
```sql
CREATE TABLE IF NOT EXISTS customers (
  id BIGSERIAL PRIMARY KEY,
  business_id BIGINT NOT NULL REFERENCES business_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  outstanding_balance NUMERIC(10, 2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_business_id ON customers(business_id);
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their business customers"
  ON customers FOR SELECT
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can insert customers for their business"
  ON customers FOR INSERT
  WITH CHECK (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can update their business customers"
  ON customers FOR UPDATE
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can delete their business customers"
  ON customers FOR DELETE
  USING (business_id IN (
    SELECT business_id FROM business_users WHERE user_id = auth.uid()
  ));

CREATE OR REPLACE FUNCTION update_customers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER customers_updated_at_trigger
  BEFORE UPDATE ON customers
  FOR EACH ROW
  EXECUTE FUNCTION update_customers_updated_at();
```

### 2. Configure Environment

Create a `.env` file in the project root (if not using hardcoded values):

```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/designbypradeep/raj-electricals-inventory-app.git
   cd raj-electricals-inventory-app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── models/              # Data models
│   ├── supabase_models.dart
│   └── sales_purchase_models.dart
├── pages/               # UI pages
│   ├── dashboard_page.dart
│   ├── suppliers_page.dart
│   ├── customers_page.dart
│   ├── purchase_page.dart
│   ├── sales_page.dart
│   └── ...
├── services/            # Business logic
│   ├── supabase_service.dart
│   ├── accounting_service.dart
│   └── ...
├── widgets/             # Reusable widgets
│   ├── page_header.dart
│   └── ...
└── theme/               # Theme configuration
    ├── ui_tokens.dart
    └── status_colors.dart
```

## Key Features Implementation

### Supplier Auto-Suggest
- Purchase page now includes autocomplete for supplier names
- Quick add supplier button for on-the-fly additions
- Fetches from `suppliers` table

### Customer Management
- Track customer debts and outstanding balances
- Search by name, phone, or email
- View total debt statistics

### Supplier Credit System
- Create credit notes from returns
- Apply credits to future purchases
- Track credit balance per supplier via `supplier_ledger` table

## Git Commands

### Initial Setup (Already Done)
```bash
git init
git add .
git commit -m "Initial commit: Raj Electricals Inventory App"
git remote add origin https://github.com/designbypradeep/raj-electricals-inventory-app.git
git push -u origin main
```

### Update After New Features
```bash
# Stage all changes
git add .

# Commit with descriptive message
git commit -m "feat: add suppliers and customers management with auto-suggest"

# Push to GitHub
git push
```

### Common Git Operations
```bash
# Check status
git status

# View changes
git diff

# Create new branch
git checkout -b feature/your-feature-name

# Switch branches
git checkout main

# Pull latest changes
git pull

# View commit history
git log --oneline
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is proprietary software for Raj Electricals.

## Support

For support, contact: pradeepsupergalaxy12+github@gmail.com
