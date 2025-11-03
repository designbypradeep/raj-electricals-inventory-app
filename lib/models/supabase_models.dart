// Supabase database models matching the existing schema
import 'dart:convert';

class Product {
  final int? id;
  final String name;
  final String? brand;
  final String businessId;
  final String? category;
  final String? description;
  final int currentStock;
  final String? productImageUrl;
  final List<String>?
  productImages; // multiple image URLs (stored as JSON in DB)
  final double? purchasePrice;
  final double? sellingPrice;
  final String? sizeOrSpec;
  final String? status;
  final String? unitTypeSingle;
  final String? unitTypeWholesale;
  final int? itemsPerWholesaleUnit;
  final DateTime? createdAt;

  // Local image paths (not stored in Supabase)
  final List<String>? localImagePaths;

  Product({
    this.id,
    required this.name,
    this.brand,
    required this.businessId,
    this.category,
    this.description,
    this.currentStock = 0,
    this.productImageUrl,
    this.productImages,
    this.purchasePrice,
    this.sellingPrice,
    this.sizeOrSpec,
    this.status,
    this.unitTypeSingle = 'Piece',
    this.unitTypeWholesale,
    this.itemsPerWholesaleUnit = 1,
    this.createdAt,
    this.localImagePaths,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    List<String>? parseImages(dynamic v) {
      if (v == null) return null;
      try {
        if (v is List) {
          return v.map((e) => e.toString()).toList();
        }
        if (v is String) {
          // text column storing JSON array
          final decoded = jsonDecode(v);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        }
      } catch (_) {}
      return null;
    }

    return Product(
      id: json['id'] as int?,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      businessId: json['business_id'] as String,
      category: json['category'] as String?,
      description: json['description'] as String?,
      currentStock: json['current_stock'] as int? ?? 0,
      productImageUrl: json['product_image_url'] as String?,
      productImages: parseImages(json['product_images']),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble(),
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      sizeOrSpec: json['size_or_spec'] as String?,
      status: json['status'] as String?,
      unitTypeSingle: json['unit_type_single'] as String? ?? 'Piece',
      unitTypeWholesale: json['unit_type_wholesale'] as String?,
      itemsPerWholesaleUnit: json['items_per_wholesale_unit'] as int? ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'brand': brand,
      'business_id': businessId,
      'category': category,
      'description': description,
      'current_stock': currentStock,
      'product_image_url': productImageUrl,
      if (productImages != null) 'product_images': productImages,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'size_or_spec': sizeOrSpec,
      'status': status,
      'unit_type_single': unitTypeSingle,
      'unit_type_wholesale': unitTypeWholesale,
      'items_per_wholesale_unit': itemsPerWholesaleUnit,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  Product copyWith({
    int? id,
    String? name,
    String? brand,
    String? businessId,
    String? category,
    String? description,
    int? currentStock,
    String? productImageUrl,
    List<String>? productImages,
    double? purchasePrice,
    double? sellingPrice,
    String? sizeOrSpec,
    String? status,
    String? unitTypeSingle,
    String? unitTypeWholesale,
    int? itemsPerWholesaleUnit,
    DateTime? createdAt,
    List<String>? localImagePaths,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      businessId: businessId ?? this.businessId,
      category: category ?? this.category,
      description: description ?? this.description,
      currentStock: currentStock ?? this.currentStock,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      productImages: productImages ?? this.productImages,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      sizeOrSpec: sizeOrSpec ?? this.sizeOrSpec,
      status: status ?? this.status,
      unitTypeSingle: unitTypeSingle ?? this.unitTypeSingle,
      unitTypeWholesale: unitTypeWholesale ?? this.unitTypeWholesale,
      itemsPerWholesaleUnit:
          itemsPerWholesaleUnit ?? this.itemsPerWholesaleUnit,
      createdAt: createdAt ?? this.createdAt,
      localImagePaths: localImagePaths ?? this.localImagePaths,
    );
  }
}

class Category {
  final int? id;
  final String name;
  final String businessId;

  Category({this.id, required this.name, required this.businessId});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int?,
      name: json['name'] as String,
      businessId: json['business_id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {if (id != null) 'id': id, 'name': name, 'business_id': businessId};
  }
}

class BusinessProfile {
  final String id;
  final String businessName;
  final String? businessType;
  final String? description;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final String? phone;
  final String? email;
  final String? website;
  final String? gstNumber;
  final String? panNumber;
  final String? logoUrl;
  final String? currency;
  final String? timezone;
  final String userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Payment settings
  final String? upiVpa;
  final String? upiPayeeName;

  BusinessProfile({
    required this.id,
    required this.businessName,
    this.businessType,
    this.description,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.phone,
    this.email,
    this.website,
    this.gstNumber,
    this.panNumber,
    this.logoUrl,
    this.currency,
    this.timezone,
    required this.userId,
    this.createdAt,
    this.updatedAt,
    this.upiVpa,
    this.upiPayeeName,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id'] as String,
      businessName: json['business_name'] as String,
      businessType: json['business_type'] as String?,
      description: json['description'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      website: json['website'] as String?,
      gstNumber: json['gst_number'] as String?,
      panNumber: json['pan_number'] as String?,
      logoUrl: json['logo_url'] as String?,
      currency: json['currency'] as String?,
      timezone: json['timezone'] as String?,
      userId: json['user_id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      upiVpa: json['upi_vpa'] as String?,
      upiPayeeName: json['upi_payee_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_name': businessName,
      'business_type': businessType,
      'description': description,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'postal_code': postalCode,
      'phone': phone,
      'email': email,
      'website': website,
      'gst_number': gstNumber,
      'pan_number': panNumber,
      'logo_url': logoUrl,
      'currency': currency,
      'timezone': timezone,
      'user_id': userId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (upiVpa != null) 'upi_vpa': upiVpa,
      if (upiPayeeName != null) 'upi_payee_name': upiPayeeName,
    };
  }
}

class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'phone': phone,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

class Supplier {
  final int? id;
  final String businessId;
  final String name;
  final String? contactNumber;
  final String? physicalAddress;
  final String? mapLocation;
  final double advancePay;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Supplier({
    this.id,
    required this.businessId,
    required this.name,
    this.contactNumber,
    this.physicalAddress,
    this.mapLocation,
    this.advancePay = 0.0,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as int?,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      contactNumber: json['contact_number'] as String?,
      physicalAddress: json['physical_address'] as String?,
      mapLocation: json['map_location'] as String?,
      advancePay: (json['advance_pay'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'name': name,
      'contact_number': contactNumber,
      'physical_address': physicalAddress,
      'map_location': mapLocation,
      'advance_pay': advancePay,
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

class Customer {
  final int? id;
  final String businessId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double outstandingBalance;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Customer({
    this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.outstandingBalance = 0.0,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int?,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      outstandingBalance:
          (json['outstanding_balance'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'outstanding_balance': outstandingBalance,
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
