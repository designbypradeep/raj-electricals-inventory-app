# Replacement Accounting Logic

## Your Scenario (Charger Example)

### Transaction Flow
1. **Original Purchase**: Bought charger at **₹30** (COGS)
2. **Original Sale**: Sold at **₹50** (customer paid)
3. **Initial Gross Profit**: ₹50 - ₹30 = **₹20**
4. **Replacement**: Customer found defect, gave new charger (cost ₹30) without extra payment
5. **Defective Item**: Returned but not restockable (₹0 value)

### Expected Calculation

#### Total COGS
- Original charger: ₹30
- Replacement charger: ₹30
- **Total COGS**: ₹60

#### Total Revenue
- Customer paid once: **₹50**

#### Net Profit/Loss
- Revenue: ₹50
- COGS: ₹60
- **Net Loss**: ₹50 - ₹60 = **-₹10** ✅

---

## How Our Accounting Engine Calculates This

### Step 1: FIFO Gross Profit (from original sale)
```
Revenue from sale: ₹50
COGS (FIFO): ₹30
FIFO Gross Profit: ₹20
```

### Step 2: Replacement Adjustments

#### A. Price Difference
```
price_difference = 0  (customer paid nothing extra)
```

#### B. Warranty Loss Calculation
```dart
costGiven = ₹30  (new charger given to customer)
costReturnedRestockable = ₹0  (defective item, not restockable)
warrantyLoss = ₹30 - ₹0 = ₹30
```

### Step 3: Net Profit Calculation
```
Net Profit = FIFO Gross Profit - Warranty Loss + Price Difference
Net Profit = ₹20 - ₹30 + ₹0
Net Profit = -₹10  ✅ CORRECT!
```

---

## Financial Breakdown Display

### REVENUE CALCULATION
- Gross Sales Revenue: **₹50**
- Less: Refunds: ₹0
- Add: Replacement Price Adj.: ₹0
- **Net Revenue: ₹50**

### PROFIT CALCULATION
- FIFO Gross Profit (Sales): **₹20**
- Less: Return Profit Reversal: ₹0
- Less: Warranty/Replacement Cost: **₹30** ← (Cost of replacement charger given)
- Add: Replacement Price Adj.: ₹0
- **Net Profit/Loss: -₹10** ✅

---

## Key Points

1. **Warranty Loss** captures the cost of replacement items given that aren't recovered
2. **Price Difference** captures extra payment from customer (if any)
3. **FIFO tracks original COGS**, warranty loss tracks replacement COGS
4. **Defective items** returned are not counted as restockable (correctly ignored)

## Data Structure Requirements

### Replacement Record
```json
{
  "price_difference": 0,
  "replacement_items_in": [
    {
      "product_id": 123,
      "quantity_given": 1,
      // System looks up cost: ₹30
    }
  ],
  "replacement_items_out": [
    {
      "product_id": 123,
      "quantity_returned": 1,
      "item_condition": "defective"  // ← Not counted as restockable
    }
  ]
}
```

### Conditions That Are NOT Restockable
- "defective"
- "damaged"

### Conditions That ARE Restockable (reduce loss)
- "good"
- "working"
- Any other condition

---

## Verification

Check the Reports page Financial Breakdown section. It should show:

**REVENUE CALCULATION**
- Gross Sales Revenue: ₹50
- Net Revenue: ₹50

**PROFIT CALCULATION**
- FIFO Gross Profit: ₹20
- Less: Warranty/Replacement Cost: ₹30
- **Net Profit/Loss: -₹10** (displayed in RED if negative)

The debug console will also print these values when you view the Reports page.

---

## Summary

✅ **Accounting logic is CORRECT**
✅ **Tracks both original sale COGS and replacement costs**
✅ **Properly handles defective items (not restockable)**
✅ **Shows accurate net loss of ₹10 for your scenario**
