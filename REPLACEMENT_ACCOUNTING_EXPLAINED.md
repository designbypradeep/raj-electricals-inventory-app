# Retail Exchange & Replacement Accounting Engine

This document defines the mathematical, accounting, and inventory rules governing product returns, exchanges, courtesy discounts, and warranty upgrades in Inventoza across Web and Mobile.

---

## 1. Core Accounting Formula

For any date range $[T_{start}, T_{end}]$:

$$\text{Net Revenue} = \text{Gross Sales Revenue} - \text{Refunds} + \text{Replacement Price Differences}$$

$$\text{Net Profit} = \text{FIFO Gross Profit} - \text{Returns Profit Reversal} - \text{Warranty Loss} + \text{Replacement Price Differences}$$

Where:
- **FIFO Gross Profit**: Realized profit on original sales using First-In-First-Out purchase cost depletion.
- **Refunds**: Direct cash/UPI paybacks issued to customers when items are returned without replacement.
- **Replacement Price Difference**: Extra payment received ($+$) or refund given ($-$) when items of differing prices are exchanged.
- **Warranty Loss**: Physical cost value of defective/damaged items that cannot be restocked, plus any cost differences absorbed by the merchant during courtesy swaps:
  $$\text{Warranty Loss} = \sum (\text{Cost of New Items Given}) - \sum (\text{Cost of Resellable Restocked Items})$$

---

## 2. The 5 Comprehensive Retail Scenarios

---

### Scenario 1: Resellable Exchange with Difference Paid
> **Case**: Customer purchased a ₹10 2-pin plug. Later, customer returns it in original resellable condition and upgrades to a ₹20 3-pin plug, paying the ₹10 difference via Cash or UPI.

#### 1. Inventory Flow
- ₹10 Plug: Condition is **Resellable** $\rightarrow$ Restocked into sellable inventory (`+1 stock`).
- ₹20 Plug: Issued to customer $\rightarrow$ Deducted from sellable inventory (`-1 stock`).

#### 2. Financial Balance
- Original Sale: Paid ₹10 (Gross Revenue = ₹10).
- Replacement: Price Difference = $+₹10$ (Paid via Cash/UPI).
- Net Revenue: ₹10 (original) $+$ ₹10 (diff) = **₹20**.
- Cost of Goods Sold (COGS):
  - ₹10 Plug was restocked (cost returned).
  - ₹20 Plug cost is depleted via FIFO.
- Net Profit: Margin between ₹20 selling price and ₹20 plug purchase cost.

---

### Scenario 2: Courtesy / Waived Difference (Free Upgrade)
> **Case**: Customer wants to exchange their ₹10 plug for a ₹20 plug. The merchant waives the ₹10 difference as customer goodwill.

#### 1. Inventory Flow
- ₹10 Plug: Condition is **Resellable** $\rightarrow$ Restocked (`+1 stock`).
- ₹20 Plug: Issued to customer $\rightarrow$ Deducted (`-1 stock`).

#### 2. Financial Balance
- Waive switch enabled: `waived: true`, `price_difference: 0.0`.
- Net Revenue: Remains **₹10** (customer paid ₹0 extra).
- Accounting Engine Calculation:
  $$\text{Cost Given (₹20 plug)} - \text{Cost Restocked (₹10 plug)} = \text{Cost Difference Absorbed}$$
- Warranty/Courtesy Loss correctly absorbs the difference in unit cost, accurately lowering net profit by the discount given without inflating fictitious revenue.

---

### Scenario 3: Pay Later / Due on Account
> **Case**: Customer exchanges for the ₹20 plug, but will pay the remaining ₹10 later.

#### 1. Workflow
- Settlement method: `Pay Later (Due)`.
- `price_difference = +10.0`, `payment_method = 'due'`, `status = 'Pending'`.
- Printed invoice shows:
  - New Item: ₹20.00
  - Returned Credit: -₹10.00
  - **Amount Paid: ₹0.00**
  - **Balance Due: ₹10.00** (Highlighted in red for merchant collection).

---

### Scenario 4: Second Return of Replacement Item for Full Refund
> **Case**: Customer paid ₹10 initially + ₹10 upgrade for the ₹20 plug, but later returns the ₹20 plug for a full refund of ₹20. Customer returns the plug in resellable condition.

#### 1. Workflow
- In the Return/Replacement screen, items issued from previous replacements for this sale are selectable.
- Customer returns ₹20 plug; selects **no new item**.
- Settlement method: `Refund Cash` or `Refund UPI`.
- `price_difference = -20.0`.

#### 2. Complete Transaction Sequence Balance
| Step | Action | Revenue Impact | Stock Change |
| :--- | :--- | :--- | :--- |
| **Sale** | Bought ₹10 plug | +₹10 | ₹10 plug: -1 |
| **Exchange** | Returned ₹10, took ₹20 | +₹10 | ₹10 plug: +1, ₹20 plug: -1 |
| **Return** | Returned ₹20 for refund | -₹20 | ₹20 plug: +1 |
| **Net Total** | **Customer walked away with ₹0** | **₹0.00** | **All stock net change = 0** |

The entire lifecycle balances cleanly to **₹0.00 revenue and 0 net inventory variance**.

---

### Scenario 5: Defective Item Upgrade (Warranty Write-off)
> **Case**: ₹10 plug was defective. Customer upgrades to a higher-end ₹20 plug and pays the difference.

#### 1. Inventory Flow
- ₹10 Plug: Condition is **Defective (Warranty Loss)** $\rightarrow$ **NOT restocked** into active sellable inventory.
- ₹20 Plug: Issued to customer $\rightarrow$ Deducted (`-1 stock`).

#### 2. Financial Balance
- Defective item cost is written off as physical warranty loss:
  $$\text{Warranty Loss} = \text{Cost of Defective Item}$$
- Customer pays the upgrade price difference: `price_difference = +10.0`.
- Net Profit correctly reflects the upgrade revenue minus the write-off of the damaged unit.

---

## 3. Printed & WhatsApp Invoices

Every replacement produces an A4 printable PDF invoice with:
- Original Sale Reference (`S-XXXXX`)
- Customer Details Card
- Items Returned Table (with *Resellable* or *Defective* badges)
- Items Issued Table
- Financial Math Breakdown (New Total, Credit, Courtesy Discount, Net Difference, Amount Paid, Balance Due)
- UPI QR Code for instant difference collection
- One-click WhatsApp sharing formatted for retail customers.
