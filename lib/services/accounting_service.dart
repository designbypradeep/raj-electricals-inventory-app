import 'package:flutter/material.dart';
import '../models/sales_purchase_models.dart' as models;
import '../models/supabase_models.dart' as supa;

class AccountingService {
  AccountingService._();

  /// Result of FIFO computation for a period
  static FifoSummary computeFifoSummary({
    required List<models.Sale> allSales,
    required List<models.Purchase> allPurchases,
    required List<supa.Product> products,
    required DateTimeRange period,
  }) {
    // Sort all sales chronologically up to the end of the period to correctly consume lots
    final salesUpToEnd =
        allSales.where((s) {
          final d = s.createdAt ?? s.saleDate;
          if (d == null) return false;
          return !d.isAfter(period.end);
        }).toList()..sort((a, b) {
          final ad = a.createdAt ?? a.saleDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? b.saleDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

    // Build lots from purchases up to the period end (beginning inventory + in-period purchases)
    final purchasesUpToEnd = allPurchases.where((p) {
      final d = p.purchaseDate ?? p.createdAt;
      if (d == null) return false;
      return !d.isAfter(period.end);
    }).toList();

    final lots = _buildLotsByProduct(purchasesUpToEnd, products);
    final avgCostByProduct = _buildHistoricalAvgCost(
      purchasesUpToEnd,
      products,
    );

    final Map<int, supa.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };

    double totalCogs = 0.0;
    double totalRevenue = 0.0;
    int unitsSold = 0;
    double totalInternalCost = 0.0;

    for (final sale in salesUpToEnd) {
      final d = sale.createdAt ?? sale.saleDate;
      final inPeriod = d != null && !d.isBefore(period.start) && !d.isAfter(period.end);

      final cust = (sale.customerName ?? '').trim().toLowerCase();
      final isInternal =
          cust == 'self consumption' ||
          cust == 'internal testing' ||
          cust == 'internal use';
      final saleRevenue = isInternal ? 0.0 : sale.totalAmount;

      if (sale.salesItems.isEmpty) {
        if (!isInternal && inPeriod) {
          totalRevenue += saleRevenue;
        }
        continue;
      }

      double saleCogs = 0.0;
      int saleUnits = 0;
      for (final item in sale.salesItems) {
        // Normalize to pieces
        int qty = item.quantity;
        final pid = item.productId;
        final meta = prodMap[pid];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (item.unit != null &&
              wholesale != null &&
              item.unit!.trim().toLowerCase() == wholesale.trim().toLowerCase() &&
              per > 0) {
            qty = item.quantity * per;
          }
        }

        if (inPeriod) {
          saleUnits += qty;
        }

        // Consume lots FIFO for COGS
        lots.putIfAbsent(pid, () => []);
        while (qty > 0) {
          final lot = _firstLotWithQty(lots[pid]!);
          if (lot == null) {
            // Fallback: historical average cost up to period end; if unavailable, use product.purchasePrice
            final avg =
                avgCostByProduct[pid] ??
                (prodMap[pid]?.purchasePrice ?? 0).toDouble();
            if (inPeriod) {
              saleCogs += avg * qty;
            }
            qty = 0;
            break;
          }
          final used = qty < lot.remainingQty ? qty : lot.remainingQty;
          if (inPeriod) {
            saleCogs += lot.unitCost * used;
          }
          lot.remainingQty -= used;
          qty -= used;
        }
      }

      if (inPeriod) {
        if (isInternal) {
          totalInternalCost += saleCogs;
        } else {
          totalRevenue += saleRevenue;
          totalCogs += saleCogs;
          unitsSold += saleUnits;
        }
      }
    }

    // Average values (defensive)
    final avgSell = unitsSold > 0 ? totalRevenue / unitsSold : 0.0;
    final avgCost = unitsSold > 0 ? totalCogs / unitsSold : 0.0;

    return FifoSummary(
      revenue: totalRevenue,
      cogs: totalCogs,
      grossProfit: totalRevenue - totalCogs,
      unitsSold: unitsSold,
      avgSellPrice: avgSell,
      avgCostPrice: avgCost,
      internalConsumptionCost: totalInternalCost,
    );
  }

  // Net summary aligned with Dashboard: netRevenue and netProfit for a period
  // Applies adjustments for Returns (refund), Replacements (price_difference),
  // warranty loss approximation, and return profit reversal.
  static NetSummary computeNetSummary({
    required List<models.Sale> allSales,
    required List<models.Purchase> allPurchases,
    required List<supa.Product> products,
    required List<Map<String, dynamic>> replacements,
    required List<Map<String, dynamic>> returnsList,
    required DateTimeRange period,
  }) {
    final DateTime start = period.start;
    final DateTime end = period.end;

    final fifo = computeFifoSummary(
      allSales: allSales,
      allPurchases: allPurchases,
      products: products,
      period: period,
    );

    final double totalSalesRevenue = fifo.revenue;

    final purchasesUpToEnd = allPurchases.where((p) {
      final d = p.purchaseDate ?? p.createdAt;
      if (d == null) return false;
      return !d.isAfter(end);
    }).toList();

    final lots = _buildLotsByProduct(purchasesUpToEnd, products);

    final Map<int, supa.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };

    double totalRefund = 0.0;
    double returnsProfitReversal = 0.0;
    double warrantyLossTotal = 0.0;

    for (final r in returnsList) {
      final createdAt = r['created_at'] as String?;
      final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
      if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;

      final List items = (r['return_items'] as List?) ?? const [];
      for (final it in items) {
        final double qty =
            ((it['quantity_returned'] ?? it['quantity']) as num?)?.toDouble() ??
            0.0;
        final double sp =
            ((it['original_price_per_unit'] ??
                        it['price_per_unit'] ??
                        it['price'])
                    as num?)
                ?.toDouble() ??
            0.0;
        final int pid =
            (it['product_id'] as num?)?.toInt() ??
            (((it['products'] as Map<String, dynamic>?)?['id'] as num?)
                    ?.toInt() ??
                0);
        final double cp = _fallbackAvgCostForProduct(pid, lots, prodMap);
        totalRefund += qty * sp;
        returnsProfitReversal += (sp - cp) * qty;

        final cond = (it['item_condition'] as String?)?.toLowerCase();
        final restockEligible = it['restock_eligible'];
        if (cond == 'defective' ||
            cond == 'damaged' ||
            cond == 'warranty_claim' ||
            restockEligible == false) {
          warrantyLossTotal += cp * qty;
        }
      }
    }

    double totalPriceDiff = 0.0;
    for (final rep in replacements) {
      final createdAt = rep['created_at'] as String?;
      final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
      if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;

      totalPriceDiff += (rep['price_difference'] as num?)?.toDouble() ?? 0.0;

      final List ins = (rep['replacement_items_in'] as List?) ?? const [];
      final List outs = (rep['replacement_items_out'] as List?) ?? const [];

      double costGiven = 0.0;
      for (final it in ins) {
        final double qty = ((it['quantity_given'] as num?) ?? 0).toDouble();
        final int pid =
            (it['product_id'] as num?)?.toInt() ??
            (((it['products'] as Map<String, dynamic>?)?['id'] as num?)
                    ?.toInt() ??
                0);
        final double cp = _fallbackAvgCostForProduct(pid, lots, prodMap);
        costGiven += qty * cp;
      }

      double costReturnedRestockable = 0.0;
      for (final it in outs) {
        final cond = (it['item_condition'] as String?)?.toLowerCase();
        final restockEligible = it['restock_eligible'];
        if (cond == 'defective' ||
            cond == 'damaged' ||
            cond == 'warranty_claim' ||
            restockEligible == false) {
          continue;
        }
        final double qty = ((it['quantity_returned'] as num?) ?? 0).toDouble();
        final int pid =
            (it['product_id'] as num?)?.toInt() ??
            (((it['products'] as Map<String, dynamic>?)?['id'] as num?)
                    ?.toInt() ??
                0);
        final double cp = _fallbackAvgCostForProduct(pid, lots, prodMap);
        costReturnedRestockable += qty * cp;
      }

      final loss = costGiven - costReturnedRestockable;
      if (loss > 0) warrantyLossTotal += loss;
    }

    final double netRevenue = totalSalesRevenue - totalRefund + totalPriceDiff;
    final double netProfit =
        fifo.grossProfit -
        returnsProfitReversal -
        warrantyLossTotal +
        totalPriceDiff;

    return NetSummary(
      grossRevenue: totalSalesRevenue,
      fifoGrossProfit: fifo.grossProfit,
      netRevenue: netRevenue,
      netProfit: netProfit,
      refunds: totalRefund,
      priceDifference: totalPriceDiff,
      warrantyLoss: warrantyLossTotal,
      returnsProfitReversal: returnsProfitReversal,
      internalConsumptionCost: fifo.internalConsumptionCost,
    );
  }

  // ---- Internal helpers (FIFO lots) ----

  static Map<int, List<_Lot>> _buildLotsByProduct(
    List<models.Purchase> purchases,
    List<supa.Product> products,
  ) {
    final Map<int, List<_Lot>> lots = {};
    final Map<int, supa.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };
    for (final p in purchases) {
      final date =
          p.purchaseDate ??
          p.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      for (final item in p.purchaseItems) {
        final pid = item.productId;
        if (pid == 0) continue;
        lots.putIfAbsent(pid, () => []);
        int qtyPieces = item.quantity;
        double costPerPiece = item.pricePerUnit;
        final meta = prodMap[pid];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (item.unit != null &&
              wholesale != null &&
              item.unit!.trim().toLowerCase() == wholesale.trim().toLowerCase() &&
              per > 0) {
            qtyPieces = item.quantity * per;
            costPerPiece = item.pricePerUnit / per;
          }
        }
        lots[pid]!.add(
          _Lot(remainingQty: qtyPieces, unitCost: costPerPiece, date: date),
        );
      }
    }
    for (final entry in lots.entries) {
      entry.value.sort((a, b) => a.date.compareTo(b.date));
    }
    return lots;
  }

  // Average cost per product from all purchases up to the period end
  static Map<int, double> _buildHistoricalAvgCost(
    List<models.Purchase> purchases,
    List<supa.Product> products,
  ) {
    final Map<int, supa.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };
    final Map<int, double> totals = {};
    final Map<int, int> qtys = {};
    for (final p in purchases) {
      for (final item in p.purchaseItems) {
        final pid = item.productId;
        if (pid == 0) continue;
        int qtyPieces = item.quantity;
        double costPerPiece = item.pricePerUnit;
        final meta = prodMap[pid];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (item.unit != null &&
              wholesale != null &&
              item.unit!.trim().toLowerCase() == wholesale.trim().toLowerCase() &&
              per > 0) {
            qtyPieces = item.quantity * per;
            costPerPiece = item.pricePerUnit / per;
          }
        }
        totals[pid] = (totals[pid] ?? 0) + costPerPiece * qtyPieces;
        qtys[pid] = (qtys[pid] ?? 0) + qtyPieces;
      }
    }
    final Map<int, double> avg = {};
    for (final entry in totals.entries) {
      final pid = entry.key;
      final q = (qtys[pid] ?? 0);
      if (q > 0) avg[pid] = entry.value / q;
    }
    return avg;
  }

  static _Lot? _firstLotWithQty(List<_Lot> list) {
    for (final l in list) {
      if (l.remainingQty > 0) return l;
    }
    return null;
  }

  // Fallback mean unit cost for a product using available lots or product.purchasePrice
  static double _fallbackAvgCostForProduct(
    int productId,
    Map<int, List<_Lot>> lots,
    Map<int, supa.Product> prodMap,
  ) {
    final batches = lots[productId];
    if (batches != null && batches.isNotEmpty) {
      double totalCost = 0.0;
      int totalQty = 0;
      for (final b in batches) {
        totalCost += b.unitCost * b.remainingQty;
        totalQty += b.remainingQty;
      }
      if (totalQty > 0) return totalCost / totalQty;
    }
    return (prodMap[productId]?.purchasePrice ?? 0).toDouble();
  }

  // Profit attribution breakdown by product/category/payment method/customer, per period
  static ProfitBreakdown computeProfitBreakdown({
    required List<models.Sale> allSales,
    required List<models.Purchase> allPurchases,
    required List<supa.Product> products,
    required DateTimeRange period,
  }) {
    final start = period.start;
    final end = period.end;
    final sales =
        allSales.where((s) {
          final d = s.createdAt ?? s.saleDate;
          if (d == null) return false;
          return !d.isBefore(start) && !d.isAfter(end);
        }).toList()..sort((a, b) {
          final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

    final purchasesUpToEnd = allPurchases.where((p) {
      final d = p.purchaseDate ?? p.createdAt;
      if (d == null) return false;
      return !d.isAfter(end);
    }).toList();

    final lots = _buildLotsByProduct(purchasesUpToEnd, products);
    final avgCostByProduct = _buildHistoricalAvgCost(
      purchasesUpToEnd,
      products,
    );
    final Map<int, supa.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };

    final Map<int, double> productProfit = {};
    final Map<String, double> categoryProfit = {};
    final Map<String, double> paymentProfit = {};
    final Map<String, double> customerProfit = {};
    double discountsGiven = 0.0;

    for (final sale in sales) {
      if (sale.salesItems.isEmpty) continue;

      final double saleDiscount = sale.discountAmount ?? 0.0;
      discountsGiven += saleDiscount;

      double totalLineRevenue = 0.0;
      final List<_LineCtx> lines = [];
      for (final it in sale.salesItems) {
        int qty = it.quantity;
        final meta = prodMap[it.productId];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (it.unit != null &&
              wholesale != null &&
              it.unit!.trim().toLowerCase() == wholesale.trim().toLowerCase() &&
              per > 0) {
            qty = it.quantity * per;
          }
        }
        final revenue = it.pricePerUnit * qty;
        totalLineRevenue += revenue;
        lines.add(
          _LineCtx(
            pid: it.productId,
            qty: qty,
            unitPrice: it.pricePerUnit,
            rawRevenue: revenue,
          ),
        );
      }

      final double discountRatio = totalLineRevenue > 0
          ? (saleDiscount / totalLineRevenue)
          : 0.0;

      double saleProfit = 0.0;
      for (final ln in lines) {
        lots.putIfAbsent(ln.pid, () => []);
        int remaining = ln.qty;
        double itemCogs = 0.0;
        while (remaining > 0) {
          final lot = _firstLotWithQty(lots[ln.pid]!);
          if (lot == null) {
            final avg =
                avgCostByProduct[ln.pid] ??
                (prodMap[ln.pid]?.purchasePrice ?? 0).toDouble();
            itemCogs += avg * remaining;
            remaining = 0;
            break;
          }
          final used = remaining < lot.remainingQty
              ? remaining
              : lot.remainingQty;
          itemCogs += lot.unitCost * used;
          lot.remainingQty -= used;
          remaining -= used;
        }
        final netRevenue = ln.rawRevenue * (1 - discountRatio);
        final profit = netRevenue - itemCogs;
        saleProfit += profit;

        productProfit[ln.pid] = (productProfit[ln.pid] ?? 0) + profit;
        final cat = (prodMap[ln.pid]?.category ?? 'Uncategorized');
        categoryProfit[cat] = (categoryProfit[cat] ?? 0) + profit;
      }

      paymentProfit[sale.paymentMethod] =
          (paymentProfit[sale.paymentMethod] ?? 0) + saleProfit;
      final cust = sale.customerName?.isNotEmpty == true
          ? sale.customerName!
          : 'Walk-in Customer';
      customerProfit[cust] = (customerProfit[cust] ?? 0) + saleProfit;
    }

    return ProfitBreakdown(
      productProfit: productProfit,
      categoryProfit: categoryProfit,
      paymentMethodProfit: paymentProfit,
      customerProfit: customerProfit,
      discountsGiven: discountsGiven,
    );
  }

  // Summarize product-level impacts for the financial report
  static ProductImpacts computeProductImpacts({
    required List<models.Sale> allSales,
    required List<models.Purchase> allPurchases,
    required List<supa.Product> products,
    required List<Map<String, dynamic>> replacements,
    required List<Map<String, dynamic>> returnsList,
    required DateTimeRange period,
  }) {
    final pb = computeProfitBreakdown(
      allSales: allSales,
      allPurchases: allPurchases,
      products: products,
      period: period,
    );

    // 1) Products with losses (negative profit)
    final Map<int, double> lossProfitByProduct = {};
    pb.productProfit.forEach((pid, val) {
      if (val < 0) lossProfitByProduct[pid] = val; // keep negative sign
    });

    // 2) Returns: refund amount by product
    final start = period.start;
    final end = period.end;
    final Map<int, double> returnsRefundByProduct = {};
    for (final r in returnsList) {
      final createdAt = r['created_at'] as String?;
      final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
      if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;
      final List items = (r['return_items'] as List?) ?? const [];
      for (final it in items) {
        final int pid =
            (it['product_id'] as num?)?.toInt() ??
            (((it['products'] as Map<String, dynamic>?)?['id'] as num?)
                    ?.toInt() ??
                0);
        if (pid == 0) continue;
        final double qty =
            ((it['quantity_returned'] ?? it['quantity']) as num?)?.toDouble() ??
            0.0;
        final double sp =
            ((it['original_price_per_unit'] ??
                        it['price_per_unit'] ??
                        it['price'])
                    as num?)
                ?.toDouble() ??
            0.0;
        returnsRefundByProduct[pid] =
            (returnsRefundByProduct[pid] ?? 0) + qty * sp;
      }
    }

    // 3) Replacement price difference allocation by product (proportional to outgoing item qty)
    final Map<int, double> priceDiffByProduct = {};
    for (final rep in replacements) {
      final createdAt = rep['created_at'] as String?;
      final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
      if (dt == null || dt.isBefore(start) || dt.isAfter(end)) continue;
      final double diff = (rep['price_difference'] as num?)?.toDouble() ?? 0.0;
      if (diff == 0) continue;
      final List outs = (rep['replacement_items_out'] as List?) ?? const [];
      final List ins = (rep['replacement_items_in'] as List?) ?? const [];
      List allocList = outs.isNotEmpty ? outs : ins;
      double totalQty = 0.0;
      for (final it in allocList) {
        totalQty +=
            ((it['quantity_returned'] ??
                        it['quantity_given'] ??
                        it['quantity'] ??
                        0)
                    as num)
                .toDouble();
      }
      if (totalQty <= 0) continue;
      for (final it in allocList) {
        final int pid =
            (it['product_id'] as num?)?.toInt() ??
            (((it['products'] as Map<String, dynamic>?)?['id'] as num?)
                    ?.toInt() ??
                0);
        if (pid == 0) continue;
        final double q =
            ((it['quantity_returned'] ??
                        it['quantity_given'] ??
                        it['quantity'] ??
                        0)
                    as num)
                .toDouble();
        final double share = diff * (q / totalQty);
        priceDiffByProduct[pid] = (priceDiffByProduct[pid] ?? 0) + share;
      }
    }

    return ProductImpacts(
      lossProfitByProduct: lossProfitByProduct,
      returnsRefundByProduct: returnsRefundByProduct,
      priceDifferenceByProduct: priceDiffByProduct,
    );
  }
}

class FifoSummary {
  final double revenue;
  final double cogs;
  final double grossProfit;
  final int unitsSold;
  final double avgSellPrice;
  final double avgCostPrice;
  final double internalConsumptionCost;
  const FifoSummary({
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    this.unitsSold = 0,
    this.avgSellPrice = 0.0,
    this.avgCostPrice = 0.0,
    this.internalConsumptionCost = 0.0,
  });
}

class NetSummary {
  final double grossRevenue;
  final double fifoGrossProfit;
  final double netRevenue;
  final double netProfit;
  final double refunds;
  final double priceDifference;
  final double warrantyLoss;
  final double returnsProfitReversal;
  final double internalConsumptionCost;

  const NetSummary({
    required this.grossRevenue,
    required this.fifoGrossProfit,
    required this.netRevenue,
    required this.netProfit,
    this.refunds = 0.0,
    this.priceDifference = 0.0,
    this.warrantyLoss = 0.0,
    this.returnsProfitReversal = 0.0,
    this.internalConsumptionCost = 0.0,
  });
}

class ProfitBreakdown {
  final Map<int, double> productProfit;
  final Map<String, double> categoryProfit;
  final Map<String, double> paymentMethodProfit;
  final Map<String, double> customerProfit;
  final double discountsGiven;

  const ProfitBreakdown({
    required this.productProfit,
    required this.categoryProfit,
    required this.paymentMethodProfit,
    required this.customerProfit,
    required this.discountsGiven,
  });
}

class ProductImpacts {
  final Map<int, double> lossProfitByProduct; // negative values indicate loss
  final Map<int, double> returnsRefundByProduct; // refund amounts per product
  final Map<int, double>
  priceDifferenceByProduct; // allocated replacement price difference per product

  const ProductImpacts({
    required this.lossProfitByProduct,
    required this.returnsRefundByProduct,
    required this.priceDifferenceByProduct,
  });
}

extension _SafeGetStr on Map<String, double> {
  void addStr(String key, double value) {
    this[key] = (this[key] ?? 0) + value;
  }
}

extension _SafeGetInt on Map<int, double> {
  void addInt(int key, double value) {
    this[key] = (this[key] ?? 0) + value;
  }
}

extension _NumX on num {
  double get d => toDouble();
}

class _LineCtx {
  final int pid;
  final int qty;
  final double unitPrice;
  final double rawRevenue;
  const _LineCtx({
    required this.pid,
    required this.qty,
    required this.unitPrice,
    required this.rawRevenue,
  });
}

class _Lot {
  int remainingQty;
  final double unitCost;
  final DateTime date;
  _Lot({
    required this.remainingQty,
    required this.unitCost,
    required this.date,
  });
  _Lot clone() =>
      _Lot(remainingQty: remainingQty, unitCost: unitCost, date: date);
}
