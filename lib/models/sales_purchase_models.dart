import 'package:flutter/foundation.dart';

// =====================
// Supplier Returns + Ledger models (top-level)
// =====================

class PurchaseReturnItemInput {
  final int productId;
  final int quantity; // in single units
  final double pricePerUnit;
  final String? unit; // optional wholesale/single label

  const PurchaseReturnItemInput({
    required this.productId,
    required this.quantity,
    required this.pricePerUnit,
    this.unit,
  });
}

class CustomerLedgerEntry {
  final int? id;
  final String businessId;
  final String customerName;
  final String entryType; // 'advance' | 'apply' | 'payment' | 'refund'
  final double amount; // positive
  final String? refTable;
  final int? refId;
  final DateTime? createdAt;

  const CustomerLedgerEntry({
    this.id,
    required this.businessId,
    required this.customerName,
    required this.entryType,
    required this.amount,
    this.refTable,
    this.refId,
    this.createdAt,
  });

  factory CustomerLedgerEntry.fromJson(Map<String, dynamic> json) {
    return CustomerLedgerEntry(
      id: json['id'] as int?,
      businessId: json['business_id'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      entryType: json['entry_type'] as String? ?? 'advance',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      refTable: json['ref_table'] as String?,
      refId: (json['ref_id'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class PurchaseReturnItemModel {
  final int? id;
  final int returnId;
  final int productId;
  final int quantity; // single units
  final double pricePerUnit;
  final String? unit;

  const PurchaseReturnItemModel({
    this.id,
    required this.returnId,
    required this.productId,
    required this.quantity,
    required this.pricePerUnit,
    this.unit,
  });

  factory PurchaseReturnItemModel.fromJson(Map<String, dynamic> json) {
    return PurchaseReturnItemModel(
      id: json['id'] as int?,
      returnId: (json['purchase_return_id'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      pricePerUnit: json['price_per_unit'] != null
          ? (json['price_per_unit'] as num).toDouble()
          : 0.0,
      unit: json['unit'] as String?,
    );
  }
}

class PurchaseReturnModel {
  final int? id;
  final String businessId;
  final String supplierName;
  final int? originalPurchaseId;
  final DateTime returnDate;
  final String refundType; // 'credit' | 'cash'
  final double totalAmount;
  final String? notes;
  final DateTime? createdAt;
  final List<PurchaseReturnItemModel> items;

  const PurchaseReturnModel({
    this.id,
    required this.businessId,
    required this.supplierName,
    this.originalPurchaseId,
    required this.returnDate,
    required this.refundType,
    required this.totalAmount,
    this.notes,
    this.createdAt,
    this.items = const [],
  });

  factory PurchaseReturnModel.fromJson(Map<String, dynamic> json) {
    final items =
        (json['purchase_return_items'] as List?)
            ?.map(
              (e) => PurchaseReturnItemModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList() ??
        const <PurchaseReturnItemModel>[];
    return PurchaseReturnModel(
      id: json['id'] as int?,
      businessId: json['business_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      originalPurchaseId: (json['original_purchase_id'] as num?)?.toInt(),
      returnDate: json['return_date'] != null
          ? DateTime.parse(json['return_date'] as String)
          : DateTime.now(),
      refundType: json['refund_type'] as String? ?? 'credit',
      totalAmount: json['total_amount'] != null
          ? (json['total_amount'] as num).toDouble()
          : 0.0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      items: items,
    );
  }
}

class SupplierLedgerEntry {
  final int? id;
  final String businessId;
  final String supplierName;
  final String entryType; // 'credit' | 'apply' | 'refund'
  final double amount; // positive
  final String? refTable;
  final int? refId;
  final DateTime? createdAt;

  const SupplierLedgerEntry({
    this.id,
    required this.businessId,
    required this.supplierName,
    required this.entryType,
    required this.amount,
    this.refTable,
    this.refId,
    this.createdAt,
  });

  factory SupplierLedgerEntry.fromJson(Map<String, dynamic> json) {
    return SupplierLedgerEntry(
      id: json['id'] as int?,
      businessId: json['business_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      entryType: json['entry_type'] as String? ?? 'credit',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      refTable: json['ref_table'] as String?,
      refId: (json['ref_id'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class Sale {
  final int? id;
  final String businessId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final double totalAmount;
  final double? discountAmount;
  final double? taxAmount;
  final String paymentMethod;
  final String status;
  final DateTime? saleDate;
  final DateTime? createdAt;
  final List<SaleItem> salesItems;

  const Sale({
    this.id,
    required this.businessId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.totalAmount,
    this.discountAmount,
    this.taxAmount,
    required this.paymentMethod,
    this.status = 'completed',
    this.saleDate,
    this.createdAt,
    this.salesItems = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    // Parse nested sales items if present
    List<SaleItem> items = [];
    if (json['sales_items'] != null) {
      items = (json['sales_items'] as List)
          .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Sale(
      id: json['id'] as int?,
      businessId: json['business_id'] as String? ?? '',
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      customerEmail: json['customer_email'] as String?,
      totalAmount: json['total_amount'] != null
          ? (json['total_amount'] as num).toDouble()
          : 0.0,
      // Schema uses 'discount'
      discountAmount: json['discount'] != null
          ? (json['discount'] as num).toDouble()
          : null,
      // No tax column in schema; keep null for compatibility
      taxAmount: null,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'completed',
      // No sale_date in schema; rely on created_at below
      saleDate: null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      salesItems: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'total_amount': totalAmount,
      // Schema uses 'discount'
      'discount': discountAmount,
      'payment_method': paymentMethod,
      // Do not serialize status or sale_date (not in schema)
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final int quantity;
  final double pricePerUnit;
  final String? unit; // optional: 'Piece' or wholesale unit label
  final Product? product;

  const SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.pricePerUnit,
    this.unit,
    this.product,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    Product? prod;
    if (json['products'] != null) {
      final p = json['products'] as Map<String, dynamic>;
      prod = Product(
        id: p['id'] as int?,
        name: p['name'] as String? ?? '',
        brand: p['brand'] as String?,
        currentStock: p['current_stock'] as int? ?? 0,
      );
    }
    return SaleItem(
      id: json['id'] as int?,
      saleId: json['sale_id'] as int? ?? 0,
      productId: json['product_id'] as int? ?? 0,
      quantity: json['quantity'] as int? ?? 0,
      pricePerUnit: json['price_per_unit'] != null
          ? (json['price_per_unit'] as num).toDouble()
          : 0.0,
      unit: json['unit'] as String?,
      product: prod,
    );
  }
}

class PurchaseItem {
  final int? id;
  final int purchaseId;
  final int productId;
  final int quantity;
  final double pricePerUnit;
  final String? unit;
  final Product? product;

  const PurchaseItem({
    this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.pricePerUnit,
    this.unit,
    this.product,
  });

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      print('PurchaseItem.fromJson received data: $json');
    }

    Product? product;
    if (json['products'] != null) {
      // Handle nested product data from Supabase join
      final productData = json['products'] as Map<String, dynamic>;
      product = Product(
        id: productData['id'] as int?,
        name: productData['name'] as String? ?? '',
        brand: productData['brand'] as String?,
        currentStock: productData['current_stock'] as int? ?? 0,
      );
      if (kDebugMode) {
        print('Parsed nested product: ${product.name}');
      }
    } else {
      if (kDebugMode) {
        print('No products data found in PurchaseItem');
      }
    }

    final item = PurchaseItem(
      id: json['id'] as int?,
      purchaseId: json['purchase_id'] as int? ?? 0,
      productId: json['product_id'] as int? ?? 0,
      quantity: json['quantity'] as int? ?? 0,
      pricePerUnit: json['price_per_unit'] != null
          ? (json['price_per_unit'] as num).toDouble()
          : 0.0,
      unit: json['unit'] as String?,
      product: product,
    );

    if (kDebugMode) {
      print(
        'Parsed PurchaseItem: id=${item.id}, productId=${item.productId}, quantity=${item.quantity}, price=${item.pricePerUnit}, hasProduct=${item.product != null}',
      );
    }
    return item;
  }
}

class Product {
  final int? id;
  final String name;
  final String? brand;
  final int currentStock;

  const Product({
    this.id,
    required this.name,
    this.brand,
    required this.currentStock,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      currentStock: json['current_stock'] as int? ?? 0,
    );
  }
}

class Purchase {
  final int? id;
  final String businessId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierEmail;
  final String? billNumber;
  final double totalAmount;
  final double? discountAmount;
  final double? taxAmount;
  final String paymentMethod;
  final String status;
  final DateTime? purchaseDate;
  final DateTime? createdAt;
  final List<PurchaseItem> purchaseItems;

  const Purchase({
    this.id,
    required this.businessId,
    this.supplierName,
    this.supplierPhone,
    this.supplierEmail,
    this.billNumber,
    required this.totalAmount,
    this.discountAmount,
    this.taxAmount,
    required this.paymentMethod,
    this.status = 'completed',
    this.purchaseDate,
    this.createdAt,
    this.purchaseItems = const [],
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    // Debug logging to see what data we're receiving
    if (kDebugMode) {
      print('Purchase.fromJson received data: $json');
    }

    List<PurchaseItem> items = [];
    if (json['purchase_items'] != null) {
      items = (json['purchase_items'] as List)
          .map((item) => PurchaseItem.fromJson(item))
          .toList();
    }

    // Calculate total amount from purchase items if not provided
    double calculatedTotal = 0.0;
    if (json['total_amount'] == null && items.isNotEmpty) {
      calculatedTotal = items.fold(
        0.0,
        (sum, item) => sum + (item.quantity * item.pricePerUnit),
      );
    }

    final purchase = Purchase(
      id: json['id'] as int?,
      businessId: json['business_id'] as String? ?? '',
      supplierName:
          json['dealer_name'] as String? ??
          json['supplier_name'] as String?, // Handle both field names
      supplierPhone: json['supplier_phone'] as String?,
      supplierEmail: json['supplier_email'] as String?,
      billNumber: json['bill_number'] as String?,
      totalAmount: json['total_amount'] != null
          ? (json['total_amount'] as num).toDouble()
          : calculatedTotal,
      discountAmount: json['discount_amount'] != null
          ? (json['discount_amount'] as num).toDouble()
          : null,
      taxAmount: json['tax_amount'] != null
          ? (json['tax_amount'] as num).toDouble()
          : null,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'completed',
      purchaseDate: json['purchase_date'] != null
          ? DateTime.parse(json['purchase_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      purchaseItems: items,
    );

    if (kDebugMode) {
      print(
        'Parsed Purchase: id=${purchase.id}, supplier=${purchase.supplierName}, total=${purchase.totalAmount}, items=${purchase.purchaseItems.length}',
      );
    }
    return purchase;
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'supplier_name': supplierName,
      'supplier_phone': supplierPhone,
      'supplier_email': supplierEmail,
      'bill_number': billNumber,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'payment_method': paymentMethod,
      'status': status,
      if (purchaseDate != null)
        'purchase_date': purchaseDate!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}
