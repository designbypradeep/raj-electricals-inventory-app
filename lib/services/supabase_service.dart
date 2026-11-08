import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/supabase_models.dart' as supabase_models;
import '../models/sales_purchase_models.dart';

class SupabaseService {
  static late SupabaseClient _client;
  static supabase_models.BusinessProfile? _currentBusinessProfile;
  static String? _defaultBusinessId; // Optional fallback for public/guest mode

  static SupabaseClient get supabase => _client;
  static SupabaseClient get client => _client;

  static supabase_models.BusinessProfile? get cachedBusinessProfile =>
      _currentBusinessProfile;

  // Method to set business context explicitly (for Shop App runtime resolution)
  static Future<void> setBusinessContext(
    Map<String, dynamic> profileMap,
  ) async {
    if (profileMap.isNotEmpty) {
      _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
        profileMap,
      );
      _defaultBusinessId = _currentBusinessProfile!.id;
      // Persist for offline access
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'cached_business_profile',
          jsonEncode(profileMap),
        );
      } catch (e) {
        if (kDebugMode) print('Failed to cache business profile: $e');
      }
    }
  }

  static Future<bool> loadBusinessContextFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cached_business_profile');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final profileMap = jsonDecode(jsonStr);
        _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
          profileMap,
        );
        _defaultBusinessId = _currentBusinessProfile!.id;
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('Failed to load cached business profile: $e');
    }
    return false;
  }

  static void setDefaultBusinessId(String businessId) {
    _defaultBusinessId = businessId;
  }

  // =====================
  // Session Management (RPC)
  // =====================
  static Future<List<Map<String, dynamic>>> getMySessions() async {
    try {
      final response = await _client.rpc('get_my_sessions');
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('Error fetching sessions: $e');
      return [];
    }
  }

  static Future<void> revokeSession(String sessionId) async {
    await _client.rpc(
      'revoke_my_session',
      params: {'target_session_id': sessionId},
    );
  }

  // =====================
  // Shop Access by Slug
  // =====================
  static Future<Map<String, dynamic>?> getBusinessBySlug(String slug) async {
    try {
      final response = await _client.rpc(
        'get_public_business_by_slug_secure',
        params: {'p_slug': slug},
      );
      if (response == null) return null;
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      if (kDebugMode) print('Error resolving slug: $e');
      return null;
    }
  }

  // =====================
  // Shop V2 (Pagination)
  // =====================
  static Future<Map<String, dynamic>> getShopProductsV2({
    required int page,
    int limit = 24,
    String? search,
    String? category,
    double? minPrice,
    double? maxPrice,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = _defaultBusinessId ?? _currentBusinessProfile?.id;
    if (businessId == null) return {'products': [], 'total': 0};

    try {
      final response = await _client.rpc(
        'get_public_products_v2',
        params: {
          'p_business_id': businessId,
          'p_limit': limit,
          'p_offset': (page - 1) * limit,
          'p_search': search,
          'p_category': category == 'all' ? null : category,
          'p_min_price': minPrice,
          'p_max_price': maxPrice,
        },
      );

      // Parse response
      final List<dynamic> raw = (response as List?) ?? [];
      final List<Map<String, dynamic>> products = raw.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        // Normalize keys for UI compatibility
        map['active_product_id'] = map['id']; // preserve original id if needed
        map['name'] = map['product_name'] ?? map['name'];
        map['price'] = (map['selling_price'] as num?)?.toDouble() ?? 0.0;
        map['mrp'] = (map['mrp'] as num?)?.toDouble() ?? 0.0;
        map['stock'] = map['current_stock'] ?? 0;
        // Image handling: RPC returns product_image_url and images JSON
        final img = map['product_image_url'];
        map['image'] = img;
        map['image_url'] = img;

        // Parse 'images' JSON
        // It comes as List<dynamic> of Maps {image_url, position}
        final rawImages = map['images'];
        List<String> imageList = [];

        if (rawImages is List) {
          imageList = rawImages
              .map((e) => (e['image_url'] as String?) ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }

        // Ensure main image is in the list (fallback logic)
        if (imageList.isEmpty && img != null && (img as String).isNotEmpty) {
          imageList.add(img);
        }

        map['images'] = imageList; // UI expects List<String>
        return map;
      }).toList();

      final int totalCount = products.isNotEmpty
          ? (products[0]['full_count'] as int? ?? 0)
          : 0;

      return {'products': _processVariants(products), 'total': totalCount};
    } catch (e) {
      if (kDebugMode) print('Error fetching shop V2: $e');
      return {'products': [], 'total': 0};
    }
  }

  // =====================
  // Shop V2 Filters (Smart Search)
  // =====================
  static Future<Map<String, List<String>>> getShopFilters() async {
    await getCurrentBusinessProfile();
    final businessId = _defaultBusinessId ?? _currentBusinessProfile?.id;
    if (businessId == null) return {'categories': [], 'brands': []};

    try {
      // 1. Fetch Categories
      final catRows = await _client
          .from('products')
          .select('category')
          .eq('business_id', businessId)
          .eq('status', 'active'); // Only active products

      final categories =
          (catRows as List)
              .map((e) => (e['category'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toSet() // Distinct
              .toList()
            ..sort();

      // 2. Fetch Brands
      final brandRows = await _client
          .from('products')
          .select('brand')
          .eq('business_id', businessId)
          .eq('status', 'active');

      final brands =
          (brandRows as List)
              .map((e) => (e['brand'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toSet() // Distinct
              .toList()
            ..sort();

      return {'categories': categories, 'brands': brands};
    } catch (e) {
      if (kDebugMode) print('Error fetching shop filters: $e');
      return {'categories': [], 'brands': []};
    }
  }

  // =====================
  // Single Product Fetch (Fallback for disconnected variants)
  // =====================
  static Future<Map<String, dynamic>?> getShopProductById(int id) async {
    try {
      await getCurrentBusinessProfile();
      final businessId = _defaultBusinessId ?? _currentBusinessProfile?.id;
      if (businessId == null) return null;

      final response = await _client
          .from('products')
          .select('*, images:product_images(image_url, position)')
          .eq('id', id)
          .eq('business_id', businessId)
          .maybeSingle();

      if (response == null) return null;

      final map = Map<String, dynamic>.from(response);
      // Normalize
      map['active_product_id'] = map['id'];
      map['name'] = map['product_name'] ?? map['name'];
      map['price'] = (map['selling_price'] as num?)?.toDouble() ?? 0.0;
      map['mrp'] = (map['mrp'] as num?)?.toDouble() ?? 0.0;
      map['stock'] = map['current_stock'] ?? 0;

      final img = map['product_image_url'];
      map['image'] = img;
      map['image_url'] = img;

      final rawImages = map['images'];
      List<String> imageList = [];
      if (rawImages is List) {
        imageList = rawImages
            .map((e) => (e['image_url'] as String?) ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (imageList.isEmpty && img != null && (img as String).isNotEmpty) {
        imageList.add(img);
      }
      map['images'] = imageList;

      return map;
    } catch (e) {
      if (kDebugMode) print('Error fetching product by ID: $e');
      return null;
    }
  }

  // =====================
  // Variant Logic (Ported from Web)
  // =====================
  static final List<String> _colorKeywords = [
    'White',
    'Black',
    'Red',
    'Blue',
    'Green',
    'Yellow',
    'Orange',
    'Brown',
    'Grey',
    'Gray',
    'Silver',
    'Gold',
    'Pink',
    'Purple',
    'Transparent',
    'Clear',
    'Beige',
    'Cream',
    'Ivory',
    'Multicolor',
    // Lighting specific
    'Warm White',
    'Cool White',
    'Daylight',
    'RGB',
    'Multi',
    'Warm',
    'Cool',
    'Day Light',
    'Standard',
  ];

  static Map<String, dynamic> _getBaseName(String name) {
    String? detectedColor;
    String baseName = name;
    for (final color in _colorKeywords) {
      final regex = RegExp(
        '\\b${color.toLowerCase()}\\b',
        caseSensitive: false,
      );
      if (regex.hasMatch(name)) {
        detectedColor = color;
        baseName = baseName.replaceAll(regex, '');
        break; // Only first match
      }
    }
    // Cleanup
    baseName = baseName
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '');
    baseName = baseName.replaceAllMapped(
      RegExp(r'(\d+(\.\d+)?)\s*[wW]\b', caseSensitive: false),
      (match) => '${match.group(1)} W',
    );
    baseName = baseName.replaceAll(RegExp(r'\s+'), ' ').trim();
    return {'baseName': baseName, 'detectedColor': detectedColor};
  }

  static List<Map<String, dynamic>> _processVariants(
    List<Map<String, dynamic>> rawProducts,
  ) {
    final Map<String, List<Map<String, dynamic>>> groups = {};

    // 1. Group
    for (var p in rawProducts) {
      final bn = _getBaseName(p['name'] ?? '');
      final baseName = bn['baseName'];
      final detectedColor = bn['detectedColor'];
      final brand = (p['brand'] ?? '').toString().trim();

      final groupKey = '${brand.toLowerCase()}::$baseName'.toLowerCase();

      p['_groupKey'] = groupKey;
      p['_detectedColor'] = detectedColor;

      groups.putIfAbsent(groupKey, () => []).add(p);
    }

    // 2. Process
    return rawProducts.map((p) {
      final groupKey = p['_groupKey'];
      final group = groups[groupKey] ?? [];

      List<Map<String, dynamic>> variants = [];
      if (group.length > 1) {
        variants = group
            .map(
              (v) => {
                'id': v['id'],
                'color': v['_detectedColor'] ?? 'Standard',
                'slug': v['id'],
                'image': (v['images'] as List?)?.isNotEmpty == true
                    ? v['images'][0]
                    : null,
              },
            )
            .toList();

        // Sort by color
        variants.sort(
          (a, b) => (a['color'] as String).compareTo(b['color'] as String),
        );
      }

      p.remove('_groupKey');
      p['detected_color'] = p['_detectedColor'];
      p.remove('_detectedColor');

      p['variants'] = variants;
      return p;
    }).toList();
  }

  // =====================
  // System Health: Stock reconciliation (preview and apply)
  // =====================
  static Future<List<Map<String, dynamic>>> healthStockReconcilePreview({
    bool includeAllMismatches = false,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    // Load products base
    final productsRows = await _client
        .from('products')
        .select(
          'id, name, current_stock, items_per_wholesale_unit, unit_type_wholesale',
        )
        .eq('business_id', businessId);
    final products = <int, Map<String, dynamic>>{};
    for (final r in (productsRows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      products[(m['id'] as num).toInt()] = m;
    }

    // Sum purchased units (with wholesale conversion) scoped to business
    final purchItems = await _client
        .from('purchase_items')
        .select('product_id, quantity, unit, purchases!inner(business_id)')
        .eq('purchases.business_id', businessId);
    final purchased = <int, int>{};
    for (final r in (purchItems as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final pid = (m['product_id'] as num?)?.toInt();
      final qty = (m['quantity'] as num?)?.toInt() ?? 0;
      if (pid == null) continue;
      final prod = products[pid];
      if (prod == null) continue;
      final ipwu = (prod['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
      final uwh = (prod['unit_type_wholesale'] ?? '').toString().toLowerCase();
      final unit = (m['unit'] ?? '').toString().toLowerCase();
      final add = (unit.isNotEmpty && uwh.isNotEmpty && unit == uwh && ipwu > 0)
          ? qty * ipwu
          : qty;
      purchased[pid] = (purchased[pid] ?? 0) + add;
    }

    // Sum sold units (sales_items assumed in single units) scoped to business
    final salesItems = await _client
        .from('sales_items')
        .select('product_id, quantity, sales!inner(business_id)')
        .eq('sales.business_id', businessId);
    final sold = <int, int>{};
    for (final r in (salesItems as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final pid = (m['product_id'] as num?)?.toInt();
      final qty = (m['quantity'] as num?)?.toInt() ?? 0;
      if (pid == null) continue;
      sold[pid] = (sold[pid] ?? 0) + qty;
    }

    // Build discrepancies
    final results = <Map<String, dynamic>>[];
    products.forEach((pid, prod) {
      final current = (prod['current_stock'] as num?)?.toInt() ?? 0;
      final exp = (purchased[pid] ?? 0) - (sold[pid] ?? 0);
      final diff = exp - current;
      final row = {
        'id': pid,
        'name': prod['name'],
        'current_stock': current,
        'expected_units': exp,
        'diff': diff,
        'items_per_wholesale_unit': (prod['items_per_wholesale_unit'] as num?)
            ?.toInt(),
        'unit_type_wholesale': prod['unit_type_wholesale'],
        'should_fix_simple': (current == 0 && exp > 0),
      };
      if (includeAllMismatches) {
        if (diff != 0) results.add(row);
      } else {
        if (row['should_fix_simple'] == true) results.add(row);
      }
    });

    // Sort by diff desc
    results.sort(
      (a, b) =>
          ((b['diff'] as num).toInt()).compareTo((a['diff'] as num).toInt()),
    );
    return results;
  }

  static Future<int> healthStockReconcileApply({
    List<int>? productIds,
    bool onlyZeroToExpected = true,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final preview = await healthStockReconcilePreview(
      includeAllMismatches: !onlyZeroToExpected,
    );
    final targets = <Map<String, dynamic>>[];
    for (final r in preview) {
      if (productIds != null &&
          productIds.isNotEmpty &&
          !productIds.contains(r['id'])) {
        continue;
      }
      if (onlyZeroToExpected) {
        if (r['should_fix_simple'] == true) targets.add(r);
      } else {
        if ((r['diff'] as num).toInt() != 0) targets.add(r);
      }
    }

    int updated = 0;
    for (final chunk in _chunkList(targets, 100)) {
      final ids = chunk.map<int>((e) => (e['id'] as int)).toList();
      final byId = {
        for (final e in chunk) (e['id'] as int): (e['expected_units'] as int),
      };
      // Postgrest doesn't support per-row different values in a single update; update sequentially per id
      for (final id in ids) {
        try {
          await _client
              .from('products')
              .update({'current_stock': byId[id]})
              .eq('id', id)
              .eq('business_id', businessId);
          updated++;
        } catch (_) {}
      }
    }
    return updated;
  }

  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }

  static Future<void> updateSaleStatus({
    required int saleId,
    required String status,
    String? verifiedBy,
    String? verificationNotes,
  }) async {
    // Legacy support or direct updates are replaced by RPCs for Shop Orders
    final businessId = _currentBusinessProfile?.id;
    final userId = _client.auth.currentUser?.id;

    if (status.toLowerCase() == 'verified') {
      if (businessId == null || userId == null) {
        throw Exception('Business ID or User ID missing for verification');
      }
      await _client.rpc(
        'verify_shop_order',
        params: {
          'p_order_id': saleId,
          'p_business_id': businessId,
          'p_verified_by': userId,
        },
      );
    } else if (status.toLowerCase() == 'rejected') {
      await _client.rpc('reject_shop_order', params: {'p_order_id': saleId});
      // No longer deleting proof images; they are preserved for audit.
    } else {
      throw Exception('Unsupported status update: $status');
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingSalesWithProof({
    int limit = 50,
    String? createdBefore,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      var query = _client
          .from('shop_orders')
          .select(
            '*, shop_order_items(quantity, price_per_unit, products(name, product_images(image_url)))',
          )
          .eq('business_id', businessId)
          .eq('status', 'payment_pending'); // Explicitly only pending

      if (createdBefore != null && createdBefore.isNotEmpty) {
        query = query.lt('created_at', createdBefore);
      }
      final resp = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return (resp as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getShopOrderHistory({
    int limit = 20,
    String? createdBefore,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      var query = _client
          .from('shop_orders')
          .select(
            '*, shop_order_items(quantity, price_per_unit, products(name, product_images(image_url)))',
          )
          .eq('business_id', businessId)
          .neq('status', 'payment_pending'); // Everything NOT pending

      if (createdBefore != null && createdBefore.isNotEmpty) {
        query = query.lt('created_at', createdBefore);
      }
      final resp = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return (resp as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) print('History fetch error: $e');
      return [];
    }
  }

  // Aggregate: sales count for customers (by customer_name on sales)
  static Future<Map<String, int>> getSalesCountsForCustomers(
    List<String> customerNames,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null || customerNames.isEmpty) return {};

    final rows = await _client
        .from('sales')
        .select('customer_name')
        .eq('business_id', businessId)
        .inFilter('customer_name', customerNames);

    final counts = <String, int>{};
    for (final r in (rows as List)) {
      final name = ((r as Map)['customer_name'] ?? '').toString();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  // Aggregate: total_amount for suppliers (sum of purchases total_amount)
  static Future<Map<String, double>> getPurchaseTotalsForSuppliers(
    List<String> supplierNames,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null || supplierNames.isEmpty) return {};

    final rows = await _client
        .from('purchases')
        .select('dealer_name, total_amount')
        .eq('business_id', businessId)
        .inFilter('dealer_name', supplierNames);

    final totals = <String, double>{};
    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final name = (m['dealer_name'] ?? '').toString();
      if (name.isEmpty) continue;
      final amt = (m['total_amount'] as num?)?.toDouble() ?? 0.0;
      totals[name] = (totals[name] ?? 0.0) + amt;
    }
    return totals;
  }

  // Delete a purchase only if it has no purchase_items. Returns true if deleted.
  static Future<bool> deleteEmptyPurchase(int purchaseId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business selected');
    }

    // Check for any items under this purchase
    final List items = await _client
        .from('purchase_items')
        .select('id')
        .eq('purchase_id', purchaseId)
        .limit(1);
    if (items.isNotEmpty) {
      return false; // not empty, do not delete
    }

    // Safe to delete header
    await _client
        .from('purchases')
        .delete()
        .eq('id', purchaseId)
        .eq('business_id', businessId);
    return true;
  }

  // Delete a purchase and its items, rolling back stock quantities safely.
  // Returns true on success. This assumes purchase added stock previously.
  static Future<bool> deletePurchaseSafely(int purchaseId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business selected');
    }

    try {
      // Load items with related product details needed for stock math
      final List items = await _client
          .from('purchase_items')
          .select(
            'id, product_id, quantity, unit, price_per_unit, products(id, current_stock, unit_type_single, unit_type_wholesale, items_per_wholesale_unit)',
          )
          .eq('purchase_id', purchaseId);

      // Roll back stock for each product
      for (final r in items) {
        final m = Map<String, dynamic>.from(r as Map);
        final prod = Map<String, dynamic>.from(
          (m['products'] as Map?) ?? const <String, dynamic>{},
        );
        final int? productId = (m['product_id'] as num?)?.toInt();
        if (productId == null) continue;
        final int currentStock = (prod['current_stock'] as num?)?.toInt() ?? 0;
        final String? unit = m['unit']?.toString();
        final String? unitWholesale = prod['unit_type_wholesale']?.toString();
        final int itemsPerWholesale =
            (prod['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
        final int qty = (m['quantity'] as num?)?.toInt() ?? 0;

        bool isWholesale = false;
        if (unit != null && unitWholesale != null) {
          isWholesale =
              unit.trim().toLowerCase() == unitWholesale.trim().toLowerCase();
        }
        // If unit is single or null, treat as singles
        final int delta = isWholesale ? qty * itemsPerWholesale : qty;
        int newStock = currentStock - delta;
        if (newStock < 0) newStock = 0;

        await _client
            .from('products')
            .update({'current_stock': newStock})
            .eq('id', productId)
            .eq('business_id', businessId);
      }

      // Delete items then header
      await _client
          .from('purchase_items')
          .delete()
          .eq('purchase_id', purchaseId);

      await _client
          .from('purchases')
          .delete()
          .eq('id', purchaseId)
          .eq('business_id', businessId);

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('deletePurchaseSafely failed for #$purchaseId: $e');
      }
      return false;
    }
  }

  // Fix incomplete products (missing name) by deleting them if no history, or resetting stock if history exists.
  static Future<int> healthFixIncompleteProducts() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    // Find products with missing name or empty name
    final rows = await _client
        .from('products')
        .select('id')
        .eq('business_id', businessId)
        .or('name.is.null,name.eq.""');

    int fixed = 0;
    for (final r in rows as List) {
      final id = (r as Map)['id'] as int;

      // Check for dependencies
      final hasPurch = await _client
          .from('purchase_items')
          .select('id')
          .eq('product_id', id)
          .limit(1);
      final hasSales = await _client
          .from('sales_items')
          .select('id')
          .eq('product_id', id)
          .limit(1);

      if (hasPurch.isEmpty && hasSales.isEmpty) {
        // Safe to delete
        await _client.from('products').delete().eq('id', id);
        fixed++;
      } else {
        // Has history, just reset stock to 0 to fix negative stock issues
        await _client
            .from('products')
            .update({'current_stock': 0})
            .eq('id', id);
        fixed++;
      }
    }
    return fixed;
  }

  /// Import a full backup (phase 1): restores products and product_images.
  ///Safety checks:
  /// - Requires a current business; metadata.business_id must match current business_id
  /// Returns counts and optional details (in dryRun):
  /// {inserted_products, updated_products, images_set, ..., details}
  static Future<Map<String, dynamic>> importFullBackup(
    Map<String, dynamic> backup, {
    bool replaceImages = true,
    bool dryRun = false,
    bool importProducts = true,
    bool importPurchases = true,
    bool importSales = true,
    bool importReturns = true,
    bool importReplacements = true,
    bool importItemRequests = true,
    String replacementConflictStrategy = 'skip', // 'skip' | 'suffix'
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final meta = Map<String, dynamic>.from((backup['metadata'] as Map?) ?? {});
    final backupBusinessId = meta['business_id']?.toString();
    if (backupBusinessId != null && backupBusinessId != businessId) {
      throw Exception('Backup belongs to a different business.');
    }

    final List<dynamic> productsJson =
        (backup['products'] as List?) ?? const [];
    final List<dynamic> productImagesJson =
        (backup['product_images'] as List?) ?? const [];

    // Preload existing products for merge by name|brand|size_or_spec
    final existingRows = await _client
        .from('products')
        .select('id, name, brand, size_or_spec')
        .eq('business_id', businessId);

    String keyOf(Map m) {
      String n = (m['name'] ?? '').toString().trim().toLowerCase();
      String b = (m['brand'] ?? '').toString().trim().toLowerCase();
      String s = (m['size_or_spec'] ?? '').toString().trim().toLowerCase();
      return '$n|$b|$s';
    }

    final Map<String, int> keyToId = {};
    for (final r in existingRows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      keyToId[keyOf(m)] = (m['id'] as num).toInt();
    }

    // Map old product ID (from backup) -> new/current product ID
    final Map<int, int> productIdMap = {};
    int inserted = 0;
    int updated = 0;
    // Dry-run details
    final List<String> productsInsertedNames = [];
    final List<String> productsUpdatedNames = [];

    // Insert or update products in chunks
    const chunk = 200;
    // For dry-run, we'll simulate new IDs as negative numbers
    int simulatedIdCursor = -1;

    if (importProducts) {
      for (int i = 0; i < productsJson.length; i += chunk) {
        final batch = productsJson.sublist(
          i,
          i + chunk > productsJson.length ? productsJson.length : i + chunk,
        );

        final rowsToInsert = <Map<String, dynamic>>[];
        final originalsForInsert =
            <Map<String, dynamic>>[]; // keep to map IDs back
        final updates = <Map<String, dynamic>>[]; // {id, data, orig}

        for (final p in batch) {
          final m = Map<String, dynamic>.from(p as Map);
          final oldId = (m['id'] as num?)?.toInt();
          final data = {
            'business_id': businessId,
            'name': m['name'],
            'brand': m['brand'],
            'category': m['category'],
            'size_or_spec': m['size_or_spec'],
            'unit_type_single': m['unit_type_single'],
            'unit_type_wholesale': m['unit_type_wholesale'],
            'items_per_wholesale_unit': m['items_per_wholesale_unit'],
            'selling_price': m['selling_price'],
            'purchase_price': m['purchase_price'],
            'product_image_url': m['product_image_url'],
            'status': m['status'] ?? 'active',
            'selling_price': m['selling_price'],
            'purchase_price': m['purchase_price'],
            'product_image_url': m['product_image_url'],
            'status': m['status'] ?? 'active',
            'item_code': m['item_code'], // NEW
            'created_at': DateTime.now().toIso8601String(),
          };
          final key = keyOf(m);
          final existingId = keyToId[key];
          if (existingId != null) {
            updates.add({'id': existingId, 'data': data, 'orig': m});
            if (oldId != null) productIdMap[oldId] = existingId;
            if (dryRun && productsUpdatedNames.length < 25) {
              final name = (m['name'] ?? '').toString();
              final brand = (m['brand'] ?? '').toString();
              final spec = (m['size_or_spec'] ?? '').toString();
              productsUpdatedNames.add('$name • $brand • $spec');
            }
          } else {
            rowsToInsert.add(data);
            originalsForInsert.add(m);
            if (dryRun && productsInsertedNames.length < 25) {
              final name = (m['name'] ?? '').toString();
              final brand = (m['brand'] ?? '').toString();
              final spec = (m['size_or_spec'] ?? '').toString();
              productsInsertedNames.add('$name • $brand • $spec');
            }
          }
        }

        if (rowsToInsert.isNotEmpty) {
          if (dryRun) {
            inserted += rowsToInsert.length;
            // Simulate ID mapping for originals
            for (int idx = 0; idx < originalsForInsert.length; idx++) {
              final orig = originalsForInsert[idx];
              final oldId = (orig['id'] as num?)?.toInt();
              if (oldId != null) {
                final newId = simulatedIdCursor--;
                productIdMap[oldId] = newId;
                keyToId[keyOf(orig)] = newId;
              }
            }
          } else {
            final resp = await _client
                .from('products')
                .insert(rowsToInsert)
                .select('id, name, brand, size_or_spec');
            inserted += resp.length;
            for (
              int idx = 0;
              idx < resp.length && idx < originalsForInsert.length;
              idx++
            ) {
              final insertedRow = Map<String, dynamic>.from(resp[idx] as Map);
              final newId = (insertedRow['id'] as num).toInt();
              final orig = originalsForInsert[idx];
              final oldId = (orig['id'] as num?)?.toInt();
              if (oldId != null) productIdMap[oldId] = newId;
              keyToId[keyOf(insertedRow)] = newId;
            }
          }
        }

        for (final u in updates) {
          final id = (u['id'] as int);
          final data = Map<String, dynamic>.from(u['data'] as Map);
          if (!dryRun) {
            await _client
                .from('products')
                .update(data)
                .eq('id', id)
                .eq('business_id', businessId);
          }
          updated += 1;
        }
      }
    } else {
      // No product import: still attempt to map old product IDs to existing ones by key
      for (final p in productsJson) {
        final m = Map<String, dynamic>.from(p as Map);
        final oldId = (m['id'] as num?)?.toInt();
        if (oldId == null) continue;
        final key = keyOf(m);
        final existingId = keyToId[key];
        if (existingId != null) productIdMap[oldId] = existingId;
      }
    }

    int imagesSet = 0;
    if (replaceImages && productImagesJson.isNotEmpty) {
      // Build oldProductId -> urls list in order
      final Map<int, List<Map<String, dynamic>>> imagesByOldId = {};
      for (final r in productImagesJson) {
        final m = Map<String, dynamic>.from(r as Map);
        final pid = (m['product_id'] as num?)?.toInt();
        final url = (m['image_url'] as String?)?.trim();
        if (pid == null || url == null || url.isEmpty) continue;
        imagesByOldId.putIfAbsent(pid, () => []).add(m);
      }
      for (final entry in imagesByOldId.entries) {
        final oldId = entry.key;
        final newId = productIdMap[oldId];
        if (newId == null) continue;
        entry.value.sort(
          (a, b) => ((a['position'] as num?) ?? 0).compareTo(
            ((b['position'] as num?) ?? 0),
          ),
        );
        final urls = entry.value
            .map((m) => (m['image_url'] as String?)?.trim())
            .whereType<String>()
            .toList();
        if (dryRun) {
          // Assume success if mapping exists
          imagesSet += 1;
        } else {
          final ok = await setProductImageUrls(newId, urls);
          if (ok) imagesSet += 1;
        }
      }
    }

    // Phase 2: restore purchases + items, sales + items (ID remapping)
    final Map<int, int> purchaseIdMap = {};
    final Map<int, int> saleIdMap = {};
    int purchasesInserted = 0;
    int purchaseItemsInserted = 0;
    int skippedPurchaseItems = 0;
    final List<String> skippedPurchaseItemsExamples = [];
    int salesInserted = 0;
    int salesItemsInserted = 0;
    int skippedSalesItems = 0;
    final List<String> skippedSalesItemsExamples = [];

    Map<String, dynamic> copyIf(Map<String, dynamic> src, List<String> keys) {
      final out = <String, dynamic>{};
      for (final k in keys) {
        if (src.containsKey(k) && src[k] != null) out[k] = src[k];
      }
      return out;
    }

    // Purchases
    final List<dynamic> purchasesJson =
        (backup['purchases'] as List?) ?? const [];
    if (importPurchases)
      for (int i = 0; i < purchasesJson.length; i += 200) {
        final batch = purchasesJson.sublist(
          i,
          i + 200 > purchasesJson.length ? purchasesJson.length : i + 200,
        );
        final rows = <Map<String, dynamic>>[];
        final oldIds = <int>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldId = (m['id'] as num?)?.toInt();
          if (oldId == null) continue;
          final data = <String, dynamic>{
            'business_id': businessId,
            ...copyIf(m, [
              'dealer_name',
              'supplier_name',
              'supplier_phone',
              'supplier_email',
              'bill_number',
              'total_amount',
              'discount_amount',
              'tax_amount',
              'payment_method',
              'status',
              'purchase_date',
              'created_at',
            ]),
          };
          rows.add(data);
          oldIds.add(oldId);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            purchasesInserted += rows.length;
            for (final oldId in oldIds) {
              purchaseIdMap[oldId] = simulatedIdCursor--;
            }
          } else {
            final resp = await _client
                .from('purchases')
                .insert(rows)
                .select('id');
            purchasesInserted += resp.length;
            for (int j = 0; j < resp.length && j < oldIds.length; j++) {
              purchaseIdMap[oldIds[j]] = (resp[j]['id'] as num).toInt();
            }
          }
        }
      }

    // Purchase items
    final List<dynamic> purchaseItemsJson =
        (backup['purchase_items'] as List?) ?? const [];
    if (importPurchases)
      for (int i = 0; i < purchaseItemsJson.length; i += 300) {
        final batch = purchaseItemsJson.sublist(
          i,
          i + 300 > purchaseItemsJson.length ? purchasesJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldPid = (m['purchase_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newPid = oldPid != null ? purchaseIdMap[oldPid] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newPid == null || newProdId == null) {
            if (dryRun) {
              skippedPurchaseItems += 1;
              if (skippedPurchaseItemsExamples.length < 10) {
                skippedPurchaseItemsExamples.add(
                  'purchase_id:$oldPid product_id:$oldProdId',
                );
              }
            }
            continue;
          }
          rows.add({
            'purchase_id': newPid,
            'product_id': newProdId,
            ...copyIf(m, ['quantity', 'price_per_unit', 'unit']),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            purchaseItemsInserted += rows.length;
          } else {
            final resp = await _client
                .from('purchase_items')
                .insert(rows)
                .select('id');
            purchaseItemsInserted += resp.length;
          }
        }
      }

    // Sales
    final List<dynamic> salesJson = (backup['sales'] as List?) ?? const [];
    if (importSales)
      for (int i = 0; i < salesJson.length; i += 200) {
        final batch = salesJson.sublist(
          i,
          i + 200 > salesJson.length ? salesJson.length : i + 200,
        );
        final rows = <Map<String, dynamic>>[];
        final oldIds = <int>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldId = (m['id'] as num?)?.toInt();
          if (oldId == null) continue;
          rows.add({
            'business_id': businessId,
            ...copyIf(m, [
              'customer_name',
              'customer_phone',
              'transaction_id',
              'total_amount',
              'discount',
              'payment_method',
              'status',
              'created_at',
            ]),
          });
          oldIds.add(oldId);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            salesInserted += rows.length;
            for (final oldId in oldIds) {
              saleIdMap[oldId] = simulatedIdCursor--;
            }
          } else {
            final resp = await _client.from('sales').insert(rows).select('id');
            salesInserted += resp.length;
            for (int j = 0; j < resp.length && j < oldIds.length; j++) {
              saleIdMap[oldIds[j]] = (resp[j]['id'] as num).toInt();
            }
          }
        }
      }

    // Sales items
    final List<dynamic> salesItemsJson =
        (backup['sales_items'] as List?) ?? const [];
    if (importSales)
      for (int i = 0; i < salesItemsJson.length; i += 300) {
        final batch = salesItemsJson.sublist(
          i,
          i + 300 > salesItemsJson.length ? salesItemsJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldSid = (m['sale_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newSid = oldSid != null ? saleIdMap[oldSid] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newSid == null || newProdId == null) {
            if (dryRun) {
              skippedSalesItems += 1;
              if (skippedSalesItemsExamples.length < 10) {
                skippedSalesItemsExamples.add(
                  'sale_id:$oldSid product_id:$oldProdId',
                );
              }
            }
            continue;
          }
          rows.add({
            'sale_id': newSid,
            'product_id': newProdId,
            ...copyIf(m, ['quantity', 'price_per_unit', 'unit']),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            salesItemsInserted += rows.length;
          } else {
            final resp = await _client
                .from('sales_items')
                .insert(rows)
                .select('id');
            salesItemsInserted += resp.length;
          }
        }
      }

    // Returns (headers)
    final Map<int, int> returnIdMap = {};
    int returnsInserted = 0;
    final List<dynamic> returnsJson = (backup['returns'] as List?) ?? const [];
    if (importReturns)
      for (int i = 0; i < returnsJson.length; i += 200) {
        final batch = returnsJson.sublist(
          i,
          i + 200 > returnsJson.length ? returnsJson.length : i + 200,
        );
        final rows = <Map<String, dynamic>>[];
        final oldIds = <int>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldId = (m['id'] as num?)?.toInt();
          if (oldId == null) continue;
          final oldSaleId = (m['original_sale_id'] as num?)?.toInt();
          final newSaleId = oldSaleId != null ? saleIdMap[oldSaleId] : null;
          final data = <String, dynamic>{
            'business_id': businessId,
            if (newSaleId != null) 'original_sale_id': newSaleId,
            ...copyIf(m, [
              'return_number',
              'customer_name',
              'customer_phone',
              'total_return_amount',
              'refund_method',
              'status',
              'notes',
              'return_date',
              'created_at',
            ]),
          };
          rows.add(data);
          oldIds.add(oldId);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            returnsInserted += rows.length;
            for (final oldId in oldIds) {
              returnIdMap[oldId] = simulatedIdCursor--;
            }
          } else {
            final resp = await _client
                .from('returns')
                .insert(rows)
                .select('id');
            returnsInserted += resp.length;
            for (int j = 0; j < resp.length && j < oldIds.length; j++) {
              returnIdMap[oldIds[j]] = (resp[j]['id'] as num).toInt();
            }
          }
        }
      }

    // Return items
    int returnItemsInserted = 0;
    int skippedReturnItems = 0;
    final List<String> skippedReturnItemsExamples = [];
    final List<dynamic> returnItemsJson =
        (backup['return_items'] as List?) ?? const [];
    if (importReturns)
      for (int i = 0; i < returnItemsJson.length; i += 300) {
        final batch = returnItemsJson.sublist(
          i,
          i + 300 > returnItemsJson.length ? returnItemsJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldRid = (m['return_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newRid = oldRid != null ? returnIdMap[oldRid] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newRid == null || newProdId == null) {
            if (dryRun) {
              skippedReturnItems += 1;
              if (skippedReturnItemsExamples.length < 10) {
                skippedReturnItemsExamples.add(
                  'return_id:$oldRid product_id:$oldProdId',
                );
              }
            }
            continue;
          }
          rows.add({
            'return_id': newRid,
            'product_id': newProdId,
            ...copyIf(m, [
              'quantity_returned',
              'original_price_per_unit',
              'return_reason',
              'item_condition',
              'restock_eligible',
            ]),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            returnItemsInserted += rows.length;
          } else {
            final resp = await _client
                .from('return_items')
                .insert(rows)
                .select('id');
            returnItemsInserted += resp.length;
          }
        }
      }

    // Replacements (headers)
    final Map<int, int> replacementIdMap = {};
    int replacementsInserted = 0;
    final List<dynamic> replacementsJson =
        (backup['replacements'] as List?) ?? const [];
    // Preload existing replacements by unique replacement_number to avoid conflicts
    final List<dynamic> existingReps = await _client
        .from('replacements')
        .select('id, replacement_number')
        .eq('business_id', businessId);
    final Map<String, int> repNoToId = {};
    for (final r in existingReps) {
      final m = Map<String, dynamic>.from(r as Map);
      final no = m['replacement_number']?.toString();
      final id = (m['id'] as num?)?.toInt();
      if (no != null && id != null) repNoToId[no] = id;
    }
    // Details capture
    int replacementsExistingMapped = 0;
    final List<String> replacementsExistingExamples = [];
    int replacementsDedupedInBatch = 0;
    final List<String> replacementsDedupedExamples = [];
    int replacementsSuffixedCreated = 0;
    final List<String> replacementsSuffixedExamples = [];

    if (importReplacements)
      for (int i = 0; i < replacementsJson.length; i += 200) {
        final batch = replacementsJson.sublist(
          i,
          i + 200 > replacementsJson.length ? replacementsJson.length : i + 200,
        );
        final rows = <Map<String, dynamic>>[];
        final oldIds = <int>[];
        final Set<String> batchSeenRepNos = {};
        final Map<String, int> primaryOldIdByRepNo = {};
        final Map<int, int> duplicateToPrimaryOldId = {};
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldId = (m['id'] as num?)?.toInt();
          if (oldId == null) continue;
          final repNo = m['replacement_number']?.toString();
          String? overrideRepNo;
          // If a replacement with the same number already exists, map and skip insert
          if (repNo != null && repNoToId.containsKey(repNo)) {
            if (replacementConflictStrategy == 'suffix') {
              // generate a unique suffixed number
              String base = repNo;
              String candidate = base;
              int idx = 1;
              while (repNoToId.containsKey(candidate) ||
                  batchSeenRepNos.contains(candidate)) {
                candidate = '$base-$idx';
                idx++;
              }
              overrideRepNo = candidate;
              if (dryRun) {
                replacementsSuffixedCreated += 1;
                if (replacementsSuffixedExamples.length < 10) {
                  replacementsSuffixedExamples.add('$base -> $candidate');
                }
              }
            } else {
              replacementIdMap[oldId] = repNoToId[repNo]!;
              if (dryRun) {
                replacementsExistingMapped += 1;
                if (replacementsExistingExamples.length < 10) {
                  replacementsExistingExamples.add(repNo);
                }
              }
              continue;
            }
          }
          // Deduplicate within the batch to avoid violating unique constraint
          if (repNo != null) {
            if (batchSeenRepNos.contains(repNo)) {
              final primaryOld = primaryOldIdByRepNo[repNo];
              if (primaryOld != null) {
                duplicateToPrimaryOldId[oldId] = primaryOld;
              }
              if (dryRun) {
                replacementsDedupedInBatch += 1;
                if (replacementsDedupedExamples.length < 10) {
                  replacementsDedupedExamples.add(repNo);
                }
              }
              continue; // don't include duplicate in insert rows
            } else {
              batchSeenRepNos.add(repNo);
              primaryOldIdByRepNo[repNo] = oldId;
            }
          }
          final oldSaleId = (m['original_sale_id'] as num?)?.toInt();
          final newSaleId = oldSaleId != null ? saleIdMap[oldSaleId] : null;
          final data = <String, dynamic>{
            'business_id': businessId,
            if (newSaleId != null) 'original_sale_id': newSaleId,
            ...copyIf(m, [
              'replacement_number',
              'customer_name',
              'customer_phone',
              'replacement_date',
              'reason',
              'price_difference',
              'payment_method',
              'status',
              'notes',
              'created_at',
            ]),
          };
          if (overrideRepNo != null) {
            data['replacement_number'] = overrideRepNo;
            batchSeenRepNos.add(overrideRepNo);
          }
          rows.add(data);
          oldIds.add(oldId);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            replacementsInserted += rows.length;
            for (final oldId in oldIds) {
              replacementIdMap[oldId] = simulatedIdCursor--;
            }
            // Map duplicates to the same simulated ID as their primary
            duplicateToPrimaryOldId.forEach((dupOld, primaryOld) {
              final mapped = replacementIdMap[primaryOld];
              if (mapped != null) replacementIdMap[dupOld] = mapped;
            });
          } else {
            final resp = await _client
                .from('replacements')
                .insert(rows)
                .select('id, replacement_number');
            replacementsInserted += resp.length;
            for (int j = 0; j < resp.length && j < oldIds.length; j++) {
              final insertedRow = Map<String, dynamic>.from(resp[j] as Map);
              final newId = (insertedRow['id'] as num).toInt();
              final no = insertedRow['replacement_number']?.toString();
              replacementIdMap[oldIds[j]] = newId;
              if (no != null) repNoToId[no] = newId;
            }
            // Apply mapping for duplicates to their primary's new ID
            duplicateToPrimaryOldId.forEach((dupOld, primaryOld) {
              final mapped = replacementIdMap[primaryOld];
              if (mapped != null) replacementIdMap[dupOld] = mapped;
            });
          }
        }
      }

    // Replacement items OUT
    int replacementItemsOutInserted = 0;
    final List<dynamic> repItemsOutJson =
        (backup['replacement_items_out'] as List?) ?? const [];
    if (importReplacements)
      for (int i = 0; i < repItemsOutJson.length; i += 300) {
        final batch = repItemsOutJson.sublist(
          i,
          i + 300 > repItemsOutJson.length ? repItemsOutJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldRepId = (m['replacement_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newRepId = oldRepId != null ? replacementIdMap[oldRepId] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newRepId == null || newProdId == null) continue;
          rows.add({
            'replacement_id': newRepId,
            'product_id': newProdId,
            ...copyIf(m, [
              'quantity_returned',
              'original_price_per_unit',
              'item_condition',
            ]),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            replacementItemsOutInserted += rows.length;
          } else {
            final resp = await _client
                .from('replacement_items_out')
                .insert(rows)
                .select('id');
            replacementItemsOutInserted += resp.length;
          }
        }
      }

    // Replacement items IN
    int replacementItemsInInserted = 0;
    final List<dynamic> repItemsInJson =
        (backup['replacement_items_in'] as List?) ?? const [];
    if (importReplacements)
      for (int i = 0; i < repItemsInJson.length; i += 300) {
        final batch = repItemsInJson.sublist(
          i,
          i + 300 > repItemsInJson.length ? repItemsInJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldRepId = (m['replacement_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newRepId = oldRepId != null ? replacementIdMap[oldRepId] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newRepId == null || newProdId == null) continue;
          rows.add({
            'replacement_id': newRepId,
            'product_id': newProdId,
            ...copyIf(m, ['quantity_given']),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            replacementItemsInInserted += rows.length;
          } else {
            final resp = await _client
                .from('replacement_items_in')
                .insert(rows)
                .select('id');
            replacementItemsInInserted += resp.length;
          }
        }
      }

    // Replacement stock movements (historical logs only)
    int replacementMovementsInserted = 0;
    final List<dynamic> repMovementsJson =
        (backup['replacement_stock_movements'] as List?) ?? const [];
    if (importReplacements)
      for (int i = 0; i < repMovementsJson.length; i += 300) {
        final batch = repMovementsJson.sublist(
          i,
          i + 300 > repMovementsJson.length ? repMovementsJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldRepId = (m['replacement_id'] as num?)?.toInt();
          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newRepId = oldRepId != null ? replacementIdMap[oldRepId] : null;
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;
          if (newRepId == null || newProdId == null) continue;
          rows.add({
            'replacement_id': newRepId,
            'product_id': newProdId,
            ...copyIf(m, ['movement_type', 'quantity', 'created_at']),
          });
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            replacementMovementsInserted += rows.length;
          } else {
            final resp = await _client
                .from('replacement_stock_movements')
                .insert(rows)
                .select('id');
            replacementMovementsInserted += resp.length;
          }
        }
      }

    // Item requests (headers) + request_items
    final Map<int, int> itemRequestIdMap = {};
    int itemRequestsInserted = 0;
    final List<dynamic> itemRequestsJson =
        (backup['item_requests'] as List?) ?? const [];
    if (importItemRequests)
      for (int i = 0; i < itemRequestsJson.length; i += 200) {
        final batch = itemRequestsJson.sublist(
          i,
          i + 200 > itemRequestsJson.length ? itemRequestsJson.length : i + 200,
        );
        final rows = <Map<String, dynamic>>[];
        final oldIds = <int>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldId = (m['id'] as num?)?.toInt();
          if (oldId == null) continue;
          rows.add({
            'business_id': businessId,
            ...copyIf(m, [
              'dealer_name',
              'dealer_phone',
              'notes',
              'created_at',
            ]),
          });
          oldIds.add(oldId);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            itemRequestsInserted += rows.length;
            for (final oldId in oldIds) {
              itemRequestIdMap[oldId] = simulatedIdCursor--;
            }
          } else {
            final resp = await _client
                .from('item_requests')
                .insert(rows)
                .select('id');
            itemRequestsInserted += resp.length;
            for (int j = 0; j < resp.length && j < oldIds.length; j++) {
              itemRequestIdMap[oldIds[j]] = (resp[j]['id'] as num).toInt();
            }
          }
        }
      }

    // Request items (child rows)
    int requestItemsInserted = 0;
    int requestItemsMissingProduct = 0;
    final List<String> requestItemsMissingExamples = [];
    final List<dynamic> requestItemsJson =
        (backup['request_items'] as List?) ?? const [];
    if (importItemRequests)
      for (int i = 0; i < requestItemsJson.length; i += 300) {
        final batch = requestItemsJson.sublist(
          i,
          i + 300 > requestItemsJson.length ? requestItemsJson.length : i + 300,
        );
        final rows = <Map<String, dynamic>>[];
        for (final r in batch) {
          final m = Map<String, dynamic>.from(r as Map);
          final oldReqId = (m['request_id'] as num?)?.toInt();
          final newReqId = oldReqId != null ? itemRequestIdMap[oldReqId] : null;
          if (newReqId == null) continue;

          final oldProdId = (m['product_id'] as num?)?.toInt();
          final newProdId = oldProdId != null ? productIdMap[oldProdId] : null;

          final data = <String, dynamic>{
            'request_id': newReqId,
            // include product_id only if we have mapping; otherwise skip to avoid FK errors
            if (newProdId != null) 'product_id': newProdId,
          };
          if (dryRun && newProdId == null) {
            requestItemsMissingProduct += 1;
            if (requestItemsMissingExamples.length < 10) {
              requestItemsMissingExamples.add(
                'request_id:$oldReqId product_id:$oldProdId',
              );
            }
          }
          // Copy any other known fields if present
          for (final k in m.keys) {
            if (k == 'id' ||
                k == 'business_id' ||
                k == 'request_id' ||
                k == 'product_id') {
              continue;
            }
            final v = m[k];
            if (v != null) data[k] = v;
          }
          rows.add(data);
        }
        if (rows.isNotEmpty) {
          if (dryRun) {
            requestItemsInserted += rows.length;
          } else {
            final resp = await _client
                .from('request_items')
                .insert(rows)
                .select('id');
            requestItemsInserted += resp.length;
          }
        }
      }

    // Build details (primarily for dry-run UI)
    final details = {
      'products_inserted_names': productsInsertedNames,
      'products_updated_names': productsUpdatedNames,
      'skipped_purchase_items': {
        'count': skippedPurchaseItems,
        'examples': skippedPurchaseItemsExamples,
      },
      'skipped_sales_items': {
        'count': skippedSalesItems,
        'examples': skippedSalesItemsExamples,
      },
      'skipped_return_items': {
        'count': skippedReturnItems,
        'examples': skippedReturnItemsExamples,
      },
      'replacements_existing_mapped': {
        'count': replacementsExistingMapped,
        'examples': replacementsExistingExamples,
      },
      'replacements_deduped_in_batch': {
        'count': replacementsDedupedInBatch,
        'examples': replacementsDedupedExamples,
      },
      'replacements_suffixed_created': {
        'count': replacementsSuffixedCreated,
        'examples': replacementsSuffixedExamples,
      },
      'request_items_missing_product': {
        'count': requestItemsMissingProduct,
        'examples': requestItemsMissingExamples,
      },
    };

    return {
      'inserted_products': inserted,
      'updated_products': updated,
      'images_set': imagesSet,
      'purchases_inserted': purchasesInserted,
      'purchase_items_inserted': purchaseItemsInserted,
      'sales_inserted': salesInserted,
      'sales_items_inserted': salesItemsInserted,
      'returns_inserted': returnsInserted,
      'return_items_inserted': returnItemsInserted,
      'replacements_inserted': replacementsInserted,
      'replacement_items_out_inserted': replacementItemsOutInserted,
      'replacement_items_in_inserted': replacementItemsInInserted,
      'replacement_movements_inserted': replacementMovementsInserted,
      'item_requests_inserted': itemRequestsInserted,
      'request_items_inserted': requestItemsInserted,
      'request_items_missing_product': requestItemsMissingProduct,
      'details': details,
    };
  }

  // =====================
  // Delete all data for current business
  // =====================
  static Future<bool> deleteBusinessData() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;

    try {
      // Replacements related (child tables first)
      try {
        final repIds = await _client
            .from('replacements')
            .select('id')
            .eq('business_id', businessId);
        final ids = (repIds as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          await _client
              .from('replacement_stock_movements')
              .delete()
              .inFilter('replacement_id', ids);
          await _client
              .from('replacement_items_in')
              .delete()
              .inFilter('replacement_id', ids);
          await _client
              .from('replacement_items_out')
              .delete()
              .inFilter('replacement_id', ids);
        }
      } catch (_) {}
      try {
        await _client
            .from('replacements')
            .delete()
            .eq('business_id', businessId);
      } catch (_) {}

      // Returns
      try {
        final retIds = await _client
            .from('returns')
            .select('id')
            .eq('business_id', businessId);
        final ids = (retIds as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          await _client
              .from('return_items')
              .delete()
              .inFilter('return_id', ids);
        }
      } catch (_) {}
      try {
        await _client.from('returns').delete().eq('business_id', businessId);
      } catch (_) {}

      // Sales
      try {
        final saleIds = await _client
            .from('sales')
            .select('id')
            .eq('business_id', businessId);
        final ids = (saleIds as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          await _client.from('sales_items').delete().inFilter('sale_id', ids);
        }
      } catch (_) {}
      try {
        await _client.from('sales').delete().eq('business_id', businessId);
      } catch (_) {}

      // Purchases
      try {
        final purIds = await _client
            .from('purchases')
            .select('id')
            .eq('business_id', businessId);
        final ids = (purIds as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          await _client
              .from('purchase_items')
              .delete()
              .inFilter('purchase_id', ids);
        }
      } catch (_) {}
      try {
        await _client
            .from('purchase_items')
            .delete()
            .eq('business_id', businessId);
      } catch (_) {}
      try {
        await _client.from('purchases').delete().eq('business_id', businessId);
      } catch (_) {}

      // Requests
      try {
        await _client
            .from('item_requests')
            .delete()
            .eq('business_id', businessId);
      } catch (_) {}

      // Product images
      try {
        final prodIds = await _client
            .from('products')
            .select('id')
            .eq('business_id', businessId);
        final ids = (prodIds as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          await _client
              .from('product_images')
              .delete()
              .inFilter('product_id', ids);
        }
      } catch (_) {}

      // Products
      try {
        await _client.from('products').delete().eq('business_id', businessId);
      } catch (_) {}

      // Finally, business profile
      try {
        await _client.from('business_profiles').delete().eq('id', businessId);
      } catch (_) {}

      _currentBusinessProfile = null;
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('deleteBusinessData error: $e');
      }
      return false;
    }
  }

  // =====================
  // Full Backup Export (same-business)
  // =====================

  /// Export full backup for current business_id. Includes:
  /// business_profiles (current), products, product_images, sales, sales_items,
  /// purchases, purchase_items, returns, return_items, replacements,
  /// replacement_items_out, replacement_items_in, replacement_stock_movements,
  /// item_requests. Returns a JSON map with metadata and a manifest of counts.
  static Future<Map<String, dynamic>> exportFullBackup() async {
    final profile = await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (profile == null || businessId == null) {
      throw Exception('No business selected');
    }

    try {
      // Business profile (single)
      final businessRow = await _client
          .from('business_profiles')
          .select()
          .eq('id', businessId)
          .maybeSingle();

      // Products
      final products =
          await _client
                  .from('products')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final productIds = products
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();

      // Product images
      List<dynamic> productImages = const [];
      if (productIds.isNotEmpty) {
        productImages =
            await _client
                    .from('product_images')
                    .select()
                    .inFilter('product_id', productIds)
                    .order('product_id', ascending: true)
                    .order('position', ascending: true)
                as List<dynamic>;
      }

      // Sales and items
      final sales =
          await _client
                  .from('sales')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final saleIds = sales
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();
      List<dynamic> salesItems = const [];
      if (saleIds.isNotEmpty) {
        salesItems =
            await _client
                    .from('sales_items')
                    .select()
                    .inFilter('sale_id', saleIds)
                    .order('sale_id', ascending: true)
                as List<dynamic>;
      }

      // Purchases and items
      final purchases =
          await _client
                  .from('purchases')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final purchaseIds = purchases
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();
      List<dynamic> purchaseItems = const [];
      if (purchaseIds.isNotEmpty) {
        purchaseItems =
            await _client
                    .from('purchase_items')
                    .select()
                    .inFilter('purchase_id', purchaseIds)
                    .order('purchase_id', ascending: true)
                as List<dynamic>;
      }

      // Returns and items
      final returns =
          await _client
                  .from('returns')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final returnIds = returns
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();
      List<dynamic> returnItems = const [];
      if (returnIds.isNotEmpty) {
        returnItems =
            await _client
                    .from('return_items')
                    .select()
                    .inFilter('return_id', returnIds)
                    .order('return_id', ascending: true)
                as List<dynamic>;
      }

      // Replacements and related
      final replacements =
          await _client
                  .from('replacements')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final replacementIds = replacements
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();
      List<dynamic> replacementItemsOut = const [];
      List<dynamic> replacementItemsIn = const [];
      List<dynamic> replacementStockMovements = const [];
      if (replacementIds.isNotEmpty) {
        replacementItemsOut =
            await _client
                    .from('replacement_items_out')
                    .select()
                    .inFilter('replacement_id', replacementIds)
                    .order('replacement_id', ascending: true)
                as List<dynamic>;
        replacementItemsIn =
            await _client
                    .from('replacement_items_in')
                    .select()
                    .inFilter('replacement_id', replacementIds)
                    .order('replacement_id', ascending: true)
                as List<dynamic>;
        replacementStockMovements =
            await _client
                    .from('replacement_stock_movements')
                    .select()
                    .inFilter('replacement_id', replacementIds)
                    .order('replacement_id', ascending: true)
                as List<dynamic>;
      }

      // Item requests
      final itemRequests =
          await _client
                  .from('item_requests')
                  .select()
                  .eq('business_id', businessId)
                  .order('created_at', ascending: true)
              as List<dynamic>;
      final requestIds = itemRequests
          .map((e) => (e as Map)['id'])
          .whereType<int>()
          .toList();
      List<dynamic> requestItems = const [];
      if (requestIds.isNotEmpty) {
        requestItems =
            await _client
                    .from('request_items')
                    .select()
                    .inFilter('request_id', requestIds)
                    .order('request_id', ascending: true)
                as List<dynamic>;
      }

      final manifest = {
        'business_id': businessId,
        'exported_at': DateTime.now().toIso8601String(),
        'counts': {
          'products': products.length,
          'product_images': productImages.length,
          'sales': sales.length,
          'sales_items': salesItems.length,
          'purchases': purchases.length,
          'purchase_items': purchaseItems.length,
          'returns': returns.length,
          'return_items': returnItems.length,
          'replacements': replacements.length,
          'replacement_items_out': replacementItemsOut.length,
          'replacement_items_in': replacementItemsIn.length,
          'replacement_stock_movements': replacementStockMovements.length,
          'item_requests': itemRequests.length,
          'request_items': requestItems.length,
        },
      };

      return {
        'metadata': {
          'type': 'full_backup',
          'version': 1,
          'exported_at': manifest['exported_at'],
          'business_id': businessId,
          'owner_user_id': profile.userId,
        },
        'manifest': manifest,
        'business_profile': businessRow,
        'products': products,
        'product_images': productImages,
        'sales': sales,
        'sales_items': salesItems,
        'purchases': purchases,
        'purchase_items': purchaseItems,
        'returns': returns,
        'return_items': returnItems,
        'replacements': replacements,
        'replacement_items_out': replacementItemsOut,
        'replacement_items_in': replacementItemsIn,
        'replacement_stock_movements': replacementStockMovements,
        'item_requests': itemRequests,
        'request_items': requestItems,
      };
    } catch (e) {
      if (kDebugMode) {
        print('exportFullBackup error: $e');
      }
      rethrow;
    }
  }

  // =====================
  // Catalog With Business Export/Import (same-business partial restore)
  // =====================

  /// Export catalog including business_id and product IDs. Useful for same-business
  /// partial restore or migration. Includes image_urls array per product.
  static Future<Map<String, dynamic>> exportCatalogWithBusiness() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business ID found');

    try {
      const cols =
          'id, business_id, name, brand, category, size_or_spec, unit_type_single, unit_type_wholesale, items_per_wholesale_unit, selling_price, purchase_price, product_image_url, status, created_at';
      final rows = await _client
          .from('products')
          .select(cols)
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .order('created_at', ascending: true);

      final ids = <int>[];
      for (final r in rows as List) {
        final id = (r as Map)['id'] as int?;
        if (id != null) ids.add(id);
      }

      Map<int, List<String>> urlsByProduct = {};
      try {
        urlsByProduct = await getProductImageUrlsForProducts(ids);
      } catch (_) {}

      final products = <Map<String, dynamic>>[];
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final pid = m['id'] as int?;
        final imageUrls = pid != null
            ? (urlsByProduct[pid] ?? const <String>[])
            : const <String>[];
        products.add({...m, 'image_urls': imageUrls});
      }

      return {
        'metadata': {
          'type': 'catalog_with_business',
          'version': 1,
          'exported_at': DateTime.now().toIso8601String(),
          'business_id': businessId,
        },
        'products': products,
      };
    } catch (e) {
      if (kDebugMode) {
        print('exportCatalogWithBusiness error: $e');
      }
      rethrow;
    }
  }

  /// Import catalog that includes business-bound products. Supports conflict merging.
  /// conflictMode: 'insert_new' | 'merge_name_brand_spec'
  /// replaceImages: if true, will replace product_images with provided image_urls
  static Future<Map<String, int>> importCatalogWithBusiness(
    Map<String, dynamic> json, {
    String conflictMode = 'merge_name_brand_spec',
    bool replaceImages = true,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business ID found');

    final list = (json['products'] as List?) ?? const [];
    if (list.isEmpty) return {'inserted': 0, 'updated': 0};

    // Preload existing products for fast matching
    List<dynamic> existingRows = [];
    try {
      existingRows = await _client
          .from('products')
          .select('id, name, brand, size_or_spec')
          .eq('business_id', businessId);
    } catch (_) {}
    final Map<String, int> keyToId = {};
    String keyOf(Map m) {
      String n = (m['name'] ?? '').toString().trim().toLowerCase();
      String b = (m['brand'] ?? '').toString().trim().toLowerCase();
      String s = (m['size_or_spec'] ?? '').toString().trim().toLowerCase();
      return '$n|$b|$s';
    }

    for (final r in existingRows) {
      final m = Map<String, dynamic>.from(r as Map);
      keyToId[keyOf(m)] = (m['id'] as num).toInt();
    }

    int inserted = 0;
    int updated = 0;

    // Process in chunks to minimize payload sizes
    const chunk = 200;
    for (int i = 0; i < list.length; i += chunk) {
      final batch = list.sublist(
        i,
        i + chunk > list.length ? list.length : i + chunk,
      );

      // Prepare inserts and updates
      final rowsToInsert = <Map<String, dynamic>>[];
      final updates = <Map<String, dynamic>>[]; // {id, data, image_urls}

      for (final p in batch) {
        final m = Map<String, dynamic>.from(p as Map);
        final List<dynamic> imgDyn = (m['image_urls'] as List?) ?? const [];
        final imageUrls = imgDyn
            .map((e) => (e as String?)?.trim())
            .whereType<String>()
            .toList();
        final data = {
          'business_id': businessId,
          'name': m['name'],
          'brand': m['brand'],
          'category': m['category'],
          'size_or_spec': m['size_or_spec'],
          'unit_type_single': m['unit_type_single'],
          'unit_type_wholesale': m['unit_type_wholesale'],
          'items_per_wholesale_unit': m['items_per_wholesale_unit'],
          'selling_price': m['selling_price'],
          'purchase_price': m['purchase_price'],
          'product_image_url': imageUrls.isNotEmpty
              ? imageUrls.first
              : m['product_image_url'],
          'status': m['status'] ?? 'active',
          'created_at': DateTime.now().toIso8601String(),
        };

        if (conflictMode == 'insert_new') {
          rowsToInsert.add(data);
          continue;
        }

        // merge_name_brand_spec
        final key = keyOf(m);
        final existingId = keyToId[key];
        if (existingId != null) {
          updates.add({
            'id': existingId,
            'data': data,
            'image_urls': imageUrls,
          });
        } else {
          rowsToInsert.add(data);
        }
      }

      // Perform inserts
      if (rowsToInsert.isNotEmpty) {
        try {
          final resp = await _client
              .from('products')
              .insert(rowsToInsert)
              .select('id, name, brand, size_or_spec');
          inserted += resp.length;
          // update key map for any further batches
          for (final r in resp) {
            final mm = Map<String, dynamic>.from(r as Map);
            keyToId[keyOf(mm)] = (mm['id'] as num).toInt();
          }
        } catch (e) {
          if (kDebugMode) {
            print('importCatalogWithBusiness insert error: $e');
          }
          rethrow;
        }
      }

      // Perform updates
      for (final u in updates) {
        try {
          final id = (u['id'] as int);
          final data = Map<String, dynamic>.from(u['data'] as Map);
          await _client
              .from('products')
              .update(data)
              .eq('id', id)
              .eq('business_id', businessId);
          updated += 1;
        } catch (_) {}
      }

      // Handle images for updates and inserts
      if (replaceImages) {
        // For updates, set images
        for (final u in updates) {
          try {
            final id = (u['id'] as int);
            final urls = (u['image_urls'] as List<String>);
            if (urls.isNotEmpty) {
              await setProductImageUrls(id, urls);
            }
          } catch (_) {}
        }
        // For newly inserted, we don't have mapping from rowsToInsert to IDs with images
        // because we didn’t carry the image lists alongside. If needed, we could re-scan by key.
      }
    }

    return {'inserted': inserted, 'updated': updated};
  }

  // =====================
  // Business Info Export/Import (owner-guarded)
  // =====================

  /// Export business information (branding, contact, preferences) for current business.
  /// Includes minimal metadata for ownership checks.
  static Future<Map<String, dynamic>> exportBusinessInfo() async {
    final profile = await getCurrentBusinessProfile();
    if (profile == null) {
      throw Exception('No business profile to export');
    }

    try {
      final row = await _client
          .from('business_profiles')
          .select(
            'id, business_name, business_type, description, address, city, state, country, postal_code, phone, email, website, gst_number, pan_number, logo_url, currency, timezone, user_id, upi_vpa, upi_payee_name, created_at, updated_at',
          )
          .eq('id', profile.id)
          .single();

      final info = Map<String, dynamic>.from(row as Map);
      return {
        'metadata': {
          'type': 'business_info',
          'version': 1,
          'exported_at': DateTime.now().toIso8601String(),
          'business_id': profile.id,
          'owner_user_id': profile.userId,
        },
        'business': info,
      };
    } catch (e) {
      if (kDebugMode) {
        print('exportBusinessInfo error: $e');
      }
      rethrow;
    }
  }

  /// Import business information.
  /// - If current user already has a business, only allow updating when they are the owner of that business.
  /// - If current user has no business yet, create a new business bound to current user using imported fields.
  static Future<bool> importBusinessInfo(Map<String, dynamic> json) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }

    final data = Map<String, dynamic>.from((json['business'] as Map?) ?? {});
    if (data.isEmpty) throw Exception('Invalid business info JSON');

    // Sanitize payload: only allow specific fields to be written
    final allowed = <String, dynamic>{
      'business_name': data['business_name'],
      'business_type': data['business_type'],
      'description': data['description'],
      'address': data['address'],
      'city': data['city'],
      'state': data['state'],
      'country': data['country'],
      'postal_code': data['postal_code'],
      'phone': data['phone'],
      'email': data['email'],
      'website': data['website'],
      'gst_number': data['gst_number'],
      'pan_number': data['pan_number'],
      'logo_url': data['logo_url'],
      'currency': data['currency'],
      'timezone': data['timezone'],
      'upi_vpa': data['upi_vpa'],
      'upi_payee_name': data['upi_payee_name'],
      'updated_at': DateTime.now().toIso8601String(),
    };

    final existing = await getCurrentBusinessProfile();
    if (existing == null) {
      // Create new business bound to current user
      final insertData = {
        ...allowed,
        'user_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      };
      try {
        await _client.from('business_profiles').insert(insertData);
        // refresh cached current profile if any
        await getCurrentBusinessProfile();
        return true;
      } catch (e) {
        if (kDebugMode) {
          print('importBusinessInfo insert error: $e');
        }
        rethrow;
      }
    }

    // Existing business for this user: ensure ownership
    if (existing.userId != user.id) {
      throw Exception('You are not the owner of the current business.');
    }

    try {
      await _client
          .from('business_profiles')
          .update(allowed)
          .eq('id', existing.id)
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('importBusinessInfo update error: $e');
      }
      rethrow;
    }
  }
  // =====================
  // Catalog Template Export/Import (cross-business sharing)
  // =====================

  /// Export a business-agnostic catalog template.
  /// Strips business_id and primary keys; includes a minimal product shape
  /// and image_urls for portability.
  static Future<Map<String, dynamic>> exportCatalogTemplate() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    try {
      // Fetch basic product fields for portability
      const cols =
          'id, name, brand, category, size_or_spec, unit_type_single, unit_type_wholesale, items_per_wholesale_unit, selling_price, purchase_price, product_image_url, created_at';
      final rows = await _client
          .from('products')
          .select(cols)
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .order('created_at', ascending: true);

      final products = <Map<String, dynamic>>[];
      final ids = <int>[];
      for (final r in rows as List) {
        final map = Map<String, dynamic>.from(r as Map);
        final id = map['id'] as int?;
        if (id != null) ids.add(id);
      }

      Map<int, List<String>> urlsByProduct = {};
      try {
        urlsByProduct = await getProductImageUrlsForProducts(ids);
      } catch (_) {}

      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final pid = m['id'] as int?;
        final imageUrls = pid != null
            ? (urlsByProduct[pid] ?? const <String>[])
            : const <String>[];
        products.add({
          'name': m['name'],
          'brand': m['brand'],
          'category': m['category'],
          'size_or_spec': m['size_or_spec'],
          'unit_type_single': m['unit_type_single'],
          'unit_type_wholesale': m['unit_type_wholesale'],
          'items_per_wholesale_unit': m['items_per_wholesale_unit'],
          'selling_price': m['selling_price'],
          'purchase_price': m['purchase_price'],
          'image_urls': imageUrls,
        });
      }

      return {
        'metadata': {
          'type': 'catalog_template',
          'version': 1,
          'exported_at': DateTime.now().toIso8601String(),
        },
        'products': products,
      };
    } catch (e) {
      if (kDebugMode) {
        print('exportCatalogTemplate error: $e');
      }
      rethrow;
    }
  }

  /// Import a catalog template into the current business.
  /// conflictMode currently supports only 'insert_new'. Future: 'merge_sku', 'merge_name_brand_spec'.
  /// Returns number of products inserted.
  static Future<int> importCatalogTemplate(
    Map<String, dynamic> templateJson, {
    String conflictMode = 'insert_new',
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    final list = (templateJson['products'] as List?) ?? const [];
    if (list.isEmpty) return 0;

    int inserted = 0;
    // Batch in chunks to avoid payload limits
    const chunk = 200;
    for (int i = 0; i < list.length; i += chunk) {
      final batch = list.sublist(
        i,
        i + chunk > list.length ? list.length : i + chunk,
      );
      final rows = <Map<String, dynamic>>[];
      for (final p in batch) {
        final m = Map<String, dynamic>.from(p as Map);
        final List<dynamic> imageUrlsDyn =
            (m['image_urls'] as List?) ?? const [];
        final List<String> imageUrls = imageUrlsDyn
            .map((e) => (e as String?)?.trim())
            .whereType<String>()
            .toList();
        rows.add({
          'business_id': businessId,
          'name': m['name'],
          'brand': m['brand'],
          'category': m['category'],
          'size_or_spec': m['size_or_spec'],
          'unit_type_single': m['unit_type_single'],
          'unit_type_wholesale': m['unit_type_wholesale'],
          'items_per_wholesale_unit': m['items_per_wholesale_unit'],
          'selling_price': m['selling_price'],
          'purchase_price': m['purchase_price'],
          'product_image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
          'created_at': DateTime.now().toIso8601String(),
          'status': 'active',
        });
      }

      try {
        final resp = await _client.from('products').insert(rows).select('id');
        inserted += resp.length;
      } catch (e) {
        if (kDebugMode) {
          print('importCatalogTemplate batch error: $e');
        }
        rethrow;
      }
    }

    return inserted;
  }

  // Update replacement status
  static Future<bool> updateReplacementStatus({
    required int replacementId,
    required String status, // 'pending' | 'completed' | 'cancelled'
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;
    try {
      await _client
          .from('replacements')
          .update({'status': status})
          .eq('id', replacementId)
          .eq('business_id', businessId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating replacement status: $e');
      }
      return false;
    }
  }

  // Delete a replacement and its child rows
  static Future<bool> deleteReplacement(int replacementId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;
    try {
      // 1) Reverse stock adjustments using movement logs (preferred)
      List<dynamic> movements = const [];
      try {
        final res = await _client
            .from('replacement_stock_movements')
            .select('product_id, movement_type, quantity')
            .eq('replacement_id', replacementId);
        movements = res;
      } catch (_) {}

      if (movements.isNotEmpty) {
        for (final m in movements) {
          try {
            final int productId = (m['product_id'] as num).toInt();
            final String type = (m['movement_type'] as String?) ?? '';
            final int qty = ((m['quantity'] as num?) ?? 0).toInt();
            if (qty == 0) continue;

            final existing = await _client
                .from('products')
                .select('current_stock')
                .eq('id', productId)
                .eq('business_id', businessId)
                .maybeSingle();
            if (existing != null) {
              final num current = (existing['current_stock'] as num?) ?? 0;
              // Reverse: if movement was 'in' (we added), now subtract; if 'out' (we removed), now add
              final num newStock = type == 'in' ? current - qty : current + qty;
              await _client
                  .from('products')
                  .update({'current_stock': newStock})
                  .eq('id', productId)
                  .eq('business_id', businessId);
            }
          } catch (_) {}
        }
      } else {
        // 2) Fallback if no movement logs: derive reversals from items tables (assume quantities are in pieces)
        try {
          final outItems = await _client
              .from('replacement_items_out')
              .select('product_id, quantity_returned, item_condition')
              .eq('replacement_id', replacementId);
          for (final it in outItems) {
            try {
              final int productId = (it['product_id'] as num).toInt();
              final int qty = ((it['quantity_returned'] as num?) ?? 0).toInt();
              final String? cond = (it['item_condition'] as String?)
                  ?.toLowerCase();
              // If item was defective/damaged we didn't add stock earlier, so skip subtracting now
              if (cond == 'defective' || cond == 'damaged') continue;
              if (qty == 0) continue;
              final existing = await _client
                  .from('products')
                  .select('current_stock')
                  .eq('id', productId)
                  .eq('business_id', businessId)
                  .maybeSingle();
              if (existing != null) {
                final num current = (existing['current_stock'] as num?) ?? 0;
                // Out items had previously increased stock; now subtract
                final num newStock = current - qty;
                await _client
                    .from('products')
                    .update({'current_stock': newStock})
                    .eq('id', productId)
                    .eq('business_id', businessId);
              }
            } catch (_) {}
          }

          final inItems = await _client
              .from('replacement_items_in')
              .select('product_id, quantity_given')
              .eq('replacement_id', replacementId);
          for (final it in inItems) {
            try {
              final int productId = (it['product_id'] as num).toInt();
              final int qty = ((it['quantity_given'] as num?) ?? 0).toInt();
              if (qty == 0) continue;
              final existing = await _client
                  .from('products')
                  .select('current_stock')
                  .eq('id', productId)
                  .eq('business_id', businessId)
                  .maybeSingle();
              if (existing != null) {
                final num current = (existing['current_stock'] as num?) ?? 0;
                // In items had previously decreased stock; now add back
                final num newStock = current + qty;
                await _client
                    .from('products')
                    .update({'current_stock': newStock})
                    .eq('id', productId)
                    .eq('business_id', businessId);
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      // 3) Delete children (ignore errors to be resilient)
      try {
        await _client
            .from('replacement_items_out')
            .delete()
            .eq('replacement_id', replacementId);
      } catch (_) {}
      try {
        await _client
            .from('replacement_items_in')
            .delete()
            .eq('replacement_id', replacementId);
      } catch (_) {}
      try {
        await _client
            .from('replacement_stock_movements')
            .delete()
            .eq('replacement_id', replacementId);
      } catch (_) {}

      // 4) Delete header
      await _client
          .from('replacements')
          .delete()
          .eq('id', replacementId)
          .eq('business_id', businessId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting replacement $replacementId: $e');
      }
      return false;
    }
  }

  /// Fetch all products for the current business, including archived and deleted.
  /// Useful for integrity checks like duplicate detection where soft-deleted
  /// rows should still be considered and possibly purged.
  Future<List<supabase_models.Product>>
  getAllProductsIncludingDeletedArchived() async {
    try {
      final businessId = getCurrentBusinessId();
      if (businessId == null) return [];
      final response = await _client
          .from('products')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting all products (any status): $e');
      }
      return [];
    }
  }

  // Image URL helpers (product_images table)
  static Future<List<String>> getProductImageUrls(int productId) async {
    try {
      final rows = await _client
          .from('product_images')
          .select('image_url, position, created_at')
          .eq('product_id', productId)
          .order('position', ascending: true)
          .order('created_at', ascending: true);
      final urls = <String>[];
      for (final r in rows as List) {
        final u = (r['image_url'] as String?)?.trim();
        if (u != null && u.isNotEmpty) urls.add(u);
      }
      return urls;
    } catch (e) {
      if (kDebugMode) {
        print('getProductImageUrls($productId) error: $e');
      }
      return [];
    }
  }

  static Future<Map<int, List<String>>> getProductImageUrlsForProducts(
    List<int> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('product_images')
          .select('product_id, image_url, position, created_at')
          .inFilter('product_id', productIds)
          .order('position', ascending: true)
          .order('created_at', ascending: true);
      final map = <int, List<String>>{};
      for (final r in rows as List) {
        final pid = r['product_id'] as int?;
        final url = (r['image_url'] as String?)?.trim();
        if (pid == null || url == null || url.isEmpty) continue;
        map.putIfAbsent(pid, () => []).add(url);
      }
      return map;
    } catch (e) {
      if (kDebugMode) {
        print('getProductImageUrlsForProducts error: $e');
      }
      return {};
    }
  }

  static Future<bool> setProductImageUrls(
    int productId,
    List<String> urls,
  ) async {
    try {
      // Normalize list
      final clean = urls
          .map((e) => e.trim())
          .where((u) => u.startsWith('http://') || u.startsWith('https://'))
          .toList();

      // Replace existing rows
      await _client.from('product_images').delete().eq('product_id', productId);
      if (clean.isNotEmpty) {
        final rows = <Map<String, dynamic>>[];
        for (int i = 0; i < clean.length; i++) {
          rows.add({
            'product_id': productId,
            'image_url': clean[i],
            'position': i,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        await _client.from('product_images').insert(rows);
      }

      // Update cover image on products
      try {
        await _client
            .from('products')
            .update({
              'product_image_url': clean.isNotEmpty ? clean.first : null,
            })
            .eq('id', productId);
      } catch (_) {}

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('setProductImageUrls($productId) error: $e');
      }
      return false;
    }
  }

  /// Fetch a sale with its items and related product names by sale ID.
  /// Returns a map with keys: id, customer_name, customer_phone, transaction_id,
  /// total_amount, discount, payment_method, created_at, sales_items (list of maps with
  /// product_id, quantity, price_per_unit, products(name)). Returns null if not found.
  static Future<Map<String, dynamic>?> getSaleWithItemsById(int saleId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      final resp = await _client
          .from('sales')
          .select(
            'id, business_id, customer_name, customer_phone, transaction_id, total_amount, discount, payment_method, created_at, status, sales_items(id, product_id, quantity, price_per_unit, products(id, name))',
          )
          .eq('id', saleId)
          .eq('business_id', businessId)
          .maybeSingle();
      if (resp == null) return null;
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching sale $saleId: $e');
      }
      return null;
    }
  }

  /// Securely fetch receipt for public shop users via RPC
  static Future<Map<String, dynamic>?> getShopReceipt(int saleId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      final resp = await _client.rpc(
        'get_shop_receipt',
        params: {'p_sale_id': saleId, 'p_business_id': businessId},
      );
      if (resp == null) return null;
      return Map<String, dynamic>.from(resp as Map);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching shop receipt $saleId: $e');
      }
      return null;
    }
  }

  /// Search products by name/brand/category with pagination-friendly limit.
  /// Avoids Postgrest `.or()` by doing multiple queries and merging results.
  static Future<List<supabase_models.Product>> searchProductsQuick(
    String query, {
    int limit = 20,
    bool onlyInStock = false,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final q = query.trim();
      final tokens = q
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      final selectCols =
          'id, name, brand, business_id, category, description, current_stock, product_image_url, purchase_price, selling_price, size_or_spec, status, unit_type_single, unit_type_wholesale, items_per_wholesale_unit, created_at, item_code';

      Future<List<dynamic>> run({
        required String column,
        required String token,
      }) async {
        var req = _client
            .from('products')
            .select(selectCols)
            .eq('business_id', businessId)
            .ilike(column, '%$token%');
        if (onlyInStock) {
          req = req.filter('current_stock', 'gt', 0);
        }
        // Fetch a slightly larger pool; we'll filter client-side for multi-keyword
        return await req.limit(limit * 2);
      }

      if (q.isEmpty) {
        var req = _client
            .from('products')
            .select(selectCols)
            .eq('business_id', businessId);
        if (onlyInStock) {
          req = req.filter('current_stock', 'gt', 0);
        }
        final data = await req
            .order('created_at', ascending: false)
            .limit(limit);
        return (data as List)
            .map(
              (e) => supabase_models.Product.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }

      // Build a pool using the first token across searchable columns,
      // then filter in Dart to ensure all tokens are present in any order.
      final firstToken = tokens.isNotEmpty ? tokens.first : q.toLowerCase();
      final pool = <int, supabase_models.Product>{};
      for (final col in [
        'name',
        'brand',
        'category',
        'size_or_spec',
        'item_code',
      ]) {
        try {
          final data = await run(column: col, token: firstToken);
          for (final row in data) {
            final map = Map<String, dynamic>.from(row as Map);
            final prod = supabase_models.Product.fromJson(map);
            if (prod.id != null && !pool.containsKey(prod.id)) {
              pool[prod.id!] = prod;
              if (pool.length >= (limit * 3)) break; // cap pool size
            }
          }
        } catch (_) {
          // ignore partial failures and continue
        }
      }

      // If pool is still small, as a fallback also try description
      if (pool.length < limit) {
        try {
          final data = await run(column: 'description', token: firstToken);
          for (final row in data) {
            final map = Map<String, dynamic>.from(row as Map);
            final prod = supabase_models.Product.fromJson(map);
            if (prod.id != null && !pool.containsKey(prod.id)) {
              pool[prod.id!] = prod;
            }
          }
        } catch (_) {}
      }

      // Multi-keyword AND filtering on a combined field string
      final filtered = pool.values.where((p) {
        final hay = [
          p.brand ?? '',
          p.name,
          p.category ?? '',
          p.sizeOrSpec ?? '',
          p.itemCode ?? '',
          p.description ?? '',
        ].join(' ').toLowerCase();
        return tokens.every((t) => hay.contains(t));
      }).toList();

      // Preserve insertion order; return up to limit
      return filtered.take(limit).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error searching products: $e');
      }
      return [];
    }
  }

  /// Get distinct product names for suggestions.
  static Future<List<String>> getDistinctProductNames(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final q = query.trim();
      final response = await _client
          .from('products')
          .select('name')
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .ilike('name', '%$q%')
          .order('name')
          .limit(20);

      final names = <String>{};
      for (final row in response as List) {
        final name = (row['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
      final list = names.toList();
      list.sort();
      return list;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting distinct product names: $e');
      }
      return [];
    }
  }

  /// Get distinct product brands for suggestions.
  static Future<List<String>> getDistinctProductBrands(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final q = query.trim();
      final response = await _client
          .from('products')
          .select('brand')
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .ilike('brand', '%$q%')
          .order('brand')
          .limit(20);

      final brands = <String>{};
      for (final row in response as List) {
        final brand = (row['brand'] as String?)?.trim();
        if (brand != null && brand.isNotEmpty) {
          brands.add(brand);
        }
      }
      final list = brands.toList();
      list.sort();
      return list;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting distinct product brands: $e');
      }
      return [];
    }
  }

  /// Get distinct product size/specs for suggestions.
  static Future<List<String>> getDistinctProductSizeSpecs(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final q = query.trim();
      final response = await _client
          .from('products')
          .select('size_or_spec')
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .ilike('size_or_spec', '%$q%')
          .order('size_or_spec')
          .limit(20);

      final specs = <String>{};
      for (final row in response as List) {
        final spec = (row['size_or_spec'] as String?)?.trim();
        if (spec != null && spec.isNotEmpty) {
          specs.add(spec);
        }
      }
      final list = specs.toList();
      list.sort();
      return list;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting distinct product size/specs: $e');
      }
      return [];
    }
  }

  // Create a return with items and optional restock adjustments
  // Unit-aware stock update: if item has 'unit' equal to product.unit_type_wholesale,
  // we multiply quantity_returned by items_per_wholesale_unit for stock changes and logs.
  static Future<int?> createReturnWithItems({
    required int originalSaleId,
    required String customerName,
    String? customerPhone,
    DateTime? returnDate,
    String? refundMethod, // 'cash' | 'upi' | 'card' | etc.
    String? notes,
    String status = 'completed',
    required List<Map<String, dynamic>> items,
    // item: { original_sale_item_id?, product_id, quantity_returned, original_price_per_unit, return_reason?, item_condition?, restock_eligible? }
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    if (items.isEmpty) {
      throw Exception('At least one return item is required');
    }

    // Compute total return amount
    final double totalReturnAmount = items.fold<double>(
      0.0,
      (sum, it) =>
          sum +
          ((it['quantity_returned'] as num).toDouble() *
              (it['original_price_per_unit'] as num).toDouble()),
    );

    try {
      final String retNo = 'RET-${DateTime.now().millisecondsSinceEpoch}';
      final insertData = <String, dynamic>{
        'business_id': businessId,
        'original_sale_id': originalSaleId,
        'return_number': retNo,
        'customer_name': customerName,
        if (customerPhone != null && customerPhone.isNotEmpty)
          'customer_phone': customerPhone,
        'total_return_amount': totalReturnAmount,
        if (refundMethod != null && refundMethod.isNotEmpty)
          'refund_method': refundMethod,
        'status': status,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (returnDate != null) 'return_date': returnDate.toIso8601String(),
      };

      final ret = await _client
          .from('returns')
          .insert(insertData)
          .select('id')
          .single();
      final int returnId = ret['id'] as int;

      // Insert return items
      final itemRows = items.map((it) {
        return {
          'return_id': returnId,
          if (it['original_sale_item_id'] != null)
            'original_sale_item_id': it['original_sale_item_id'],
          'product_id': it['product_id'],
          'quantity_returned': it['quantity_returned'],
          'original_price_per_unit': it['original_price_per_unit'],
          if (it['return_reason'] != null) 'return_reason': it['return_reason'],
          if (it['item_condition'] != null)
            'item_condition': it['item_condition'],
          if (it['restock_eligible'] != null)
            'restock_eligible': it['restock_eligible'],
        };
      }).toList();

      await _client.from('return_items').insert(itemRows);

      // Apply stock adjustments for restock-eligible items and log them
      for (final it in items) {
        final bool restock = (it['restock_eligible'] as bool?) ?? true;
        if (!restock) continue;

        final int productId = it['product_id'] as int;
        final int qtyEntered = (it['quantity_returned'] as num).toInt();
        int qtyPieces = qtyEntered;
        try {
          // Unit-aware conversion
          final meta = await _client
              .from('products')
              .select('items_per_wholesale_unit, unit_type_wholesale')
              .eq('id', productId)
              .single();
          final String? itemUnit = it['unit'] as String?;
          final String? wholesale = meta['unit_type_wholesale'] as String?;
          final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
          if (itemUnit != null && wholesale != null && itemUnit == wholesale) {
            qtyPieces = qtyEntered * perUnit;
          }
        } catch (_) {}

        // Fetch current stock
        final existing = await _client
            .from('products')
            .select('current_stock')
            .eq('id', productId)
            .eq('business_id', businessId)
            .maybeSingle();
        if (existing != null) {
          final num current = (existing['current_stock'] as num?) ?? 0;
          final num newStock = current + qtyPieces;
          await _client
              .from('products')
              .update({'current_stock': newStock})
              .eq('id', productId)
              .eq('business_id', businessId);

          // Log to return_stock_adjustments
          try {
            await _client.from('return_stock_adjustments').insert({
              'return_id': returnId,
              'product_id': productId,
              'quantity_added': qtyPieces,
              'reason': 'restock',
            });
          } catch (_) {}
        }
      }

      return returnId;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating return: $e');
      }
      rethrow;
    }
  }

  static Future<int?> createItemRequest({
    String? dealerName,
    String? dealerPhone,
    String? notes,
    required List<Map<String, dynamic>>
    items, // {product_id, quantity, expected_price, notes}
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('Not signed in. Please login to save requests.');
    }

    if (items.isEmpty) return null;

    try {
      final insertData = <String, dynamic>{
        'business_id': businessId,
        'created_at': DateTime.now().toIso8601String(),
      };
      // Only include optional fields if your table supports them
      if (dealerName != null && dealerName.isNotEmpty) {
        insertData['dealer_name'] = dealerName;
      }
      if (dealerPhone != null && dealerPhone.isNotEmpty) {
        insertData['dealer_phone'] = dealerPhone;
      }
      if (notes != null && notes.isNotEmpty) {
        insertData['notes'] = notes;
      }

      final req = await _client
          .from('item_requests')
          .insert(insertData)
          .select('id')
          .single();

      final reqId = req['id'] as int;

      final rows = items.map(
        (it) => {
          'request_id': reqId,
          'product_id': it['product_id'],
          'quantity': it['quantity'],
          'expected_price': it['expected_price'] ?? it['expectedPrice'],
          if (it['notes'] != null) 'notes': it['notes'],
        },
      );
      await _client.from('request_items').insert(rows.toList());

      return reqId;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating item request: $e');
      }
      rethrow;
    }
  }

  // =====================
  // Requests (item_requests) helpers to match Svelte actions
  // =====================
  static Future<List<Map<String, dynamic>>> getItemRequests() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final response = await _client
          .from('item_requests')
          .select(
            'id, created_at, request_items(id, request_id, product_id, quantity, expected_price, notes, products(id, name, brand, category, current_stock, selling_price, product_image_url))',
          )
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      return (response as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching item requests: $e');
      }
      return [];
    }
  }

  static Future<bool> deleteRequest(int requestId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;
    try {
      // Delete items first
      await _client.from('request_items').delete().eq('request_id', requestId);

      // Then delete the request header
      await _client
          .from('item_requests')
          .delete()
          .eq('id', requestId)
          .eq('business_id', businessId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting request $requestId: $e');
      }
      return false;
    }
  }

  static Future<bool> deleteRequestItem(int itemId) async {
    try {
      await _client.from('request_items').delete().eq('id', itemId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting request item $itemId: $e');
      }
      return false;
    }
  }

  static Future<bool> clearAllRequests() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;

    try {
      // 1) Get all request IDs for this business
      final reqIdsResp = await _client
          .from('item_requests')
          .select('id')
          .eq('business_id', businessId);
      final ids = (reqIdsResp as List).map((e) => (e['id'] as int)).toList();

      if (ids.isEmpty) return true; // nothing to clear

      // 2) Delete request_items linked to those ids
      await _client
          .from('request_items')
          .delete()
          .filter('request_id', 'in', '(${ids.join(',')})');

      // 3) Delete the requests themselves
      await _client
          .from('item_requests')
          .delete()
          .filter('id', 'in', '(${ids.join(',')})')
          .eq('business_id', businessId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing all requests: $e');
      }
      return false;
    }
  }

  // Update an existing sale and its items with stock adjustments (sales reduce stock)
  static Future<bool> updateSaleWithItems({
    required int saleId,
    required String customerName,
    String? customerPhone,
    required DateTime createdAt,
    required List<Map<String, dynamic>>
    items, // {id?, product_id, quantity, price_per_unit}
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    try {
      // Fetch existing items
      final existingResp = await _client
          .from('sales')
          .select(
            'id, business_id, sales_items(id, product_id, quantity, price_per_unit)',
          )
          .eq('id', saleId)
          .single();

      final existingItems = List<Map<String, dynamic>>.from(
        (existingResp['sales_items'] as List?) ?? const [],
      );
      final Map<int, Map<String, dynamic>> existingById = {
        for (final it in existingItems)
          if (it['id'] != null)
            (it['id'] as int): Map<String, dynamic>.from(it),
      };

      final double newTotal = items.fold<double>(
        0.0,
        (sum, it) =>
            sum +
            ((it['quantity'] as num).toDouble() *
                (it['price_per_unit'] as num).toDouble()),
      );

      // Update sale header
      await _client
          .from('sales')
          .update({
            'customer_name': customerName,
            'customer_phone': customerPhone,
            'created_at': createdAt.toIso8601String(),
            'total_amount': newTotal,
          })
          .eq('id', saleId)
          .eq('business_id', businessId);

      // Upsert items and adjust stock (sales decrease stock)
      final Set<int> seenExistingIds = <int>{};
      for (final it in items) {
        final int productId = it['product_id'] as int;
        final int newQty = (it['quantity'] as num).toInt();
        final double newPrice = (it['price_per_unit'] as num).toDouble();
        final int? id = it['id'] as int?;

        if (id != null && existingById.containsKey(id)) {
          final old = existingById[id]!;
          final int oldQty = (old['quantity'] as num?)?.toInt() ?? 0;
          final int delta = newQty - oldQty; // positive means more sold

          await _client
              .from('sales_items')
              .update({'quantity': newQty, 'price_per_unit': newPrice})
              .eq('id', id);

          if (delta != 0) {
            final existing = await _client
                .from('products')
                .select('current_stock')
                .eq('id', productId)
                .eq('business_id', businessId)
                .maybeSingle();
            if (existing != null) {
              final num current = (existing['current_stock'] as num?) ?? 0;
              // Sales: reduce by delta (increase back if delta negative)
              final newStock = delta > 0 ? current - delta : current + (-delta);
              await _client
                  .from('products')
                  .update({'current_stock': newStock})
                  .eq('id', productId)
                  .eq('business_id', businessId);
            }
          }
          seenExistingIds.add(id);
        } else {
          // New item: insert and reduce stock by newQty
          await _client.from('sales_items').insert({
            'sale_id': saleId,
            'product_id': productId,
            'quantity': newQty,
            'price_per_unit': newPrice,
          });

          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final newStock = current - newQty;
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
          }
        }
      }

      // Delete removed items: restore stock by old quantity
      for (final old in existingItems) {
        final int? oldId = old['id'] as int?;
        if (oldId != null && !seenExistingIds.contains(oldId)) {
          final int productId = old['product_id'] as int;
          final int oldQty = (old['quantity'] as num?)?.toInt() ?? 0;

          await _client.from('sales_items').delete().eq('id', oldId);

          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final newStock = current + oldQty; // restore
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
          }
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating sale $saleId: $e');
      }
      return false;
    }
  }

  // Use stored procedure to delete sale and restock
  static Future<bool> deleteSaleAndRestock(int saleId) async {
    try {
      await _client.rpc(
        'delete_sale_and_restock',
        params: {'sale_id_to_delete': saleId},
      );
      // If no exception, consider success
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting sale $saleId: $e');
      }
      return false;
    }
  }

  static Future<Map<String, int>> bulkDeleteSales(List<int> saleIds) async {
    int success = 0;
    int failed = 0;
    for (final id in saleIds) {
      final ok = await deleteSaleAndRestock(id);
      if (ok) {
        success++;
      } else {
        failed++;
      }
    }
    return {'success': success, 'failed': failed};
  }

  // Update an existing purchase and its items with stock adjustments
  static Future<bool> updatePurchaseWithItems({
    required int purchaseId,
    required String dealerName,
    String? billNumber,
    required DateTime createdAt,
    required List<Map<String, dynamic>>
    items, // {id?, product_id, quantity, price_per_unit}
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    try {
      // 1) Fetch existing items to compute stock deltas
      final existingResp = await _client
          .from('purchases')
          .select(
            'id, business_id, purchase_items(id, product_id, quantity, price_per_unit, unit)',
          )
          .eq('id', purchaseId)
          .single();

      final existingItems = List<Map<String, dynamic>>.from(
        (existingResp['purchase_items'] as List?) ?? const [],
      );

      // Build maps for quick lookup
      final Map<int, Map<String, dynamic>> existingById = {
        for (final it in existingItems)
          if (it['id'] != null)
            (it['id'] as int): Map<String, dynamic>.from(it),
      };

      // 2) Update purchase header (dealer, bill, date, total)
      final double newTotal = items.fold<double>(
        0.0,
        (sum, it) =>
            sum +
            ((it['quantity'] as num).toDouble() *
                (it['price_per_unit'] as num).toDouble()),
      );

      await _client
          .from('purchases')
          .update({
            'dealer_name': dealerName,
            'bill_number': billNumber,
            'created_at': createdAt.toIso8601String(),
            'total_amount': newTotal,
          })
          .eq('id', purchaseId)
          .eq('business_id', businessId);

      // 3) Upsert items and adjust stock by delta
      final Set<int> seenExistingIds = <int>{};

      for (final it in items) {
        final int productId = it['product_id'] as int;
        final int newQty = (it['quantity'] as num).toInt();
        final double newPrice = (it['price_per_unit'] as num).toDouble();
        final String? newUnit = it['unit'] as String?;
        final int? id = it['id'] as int?;

        if (id != null && existingById.containsKey(id)) {
          // Update existing item
          final old = existingById[id]!;
          final int oldQty = (old['quantity'] as num?)?.toInt() ?? 0;
          final String? oldUnit = old['unit'] as String?;

          // Convert both old and new to single units for accurate stock delta
          int oldSingle = oldQty;
          int newSingle = newQty;
          try {
            final meta = await _client
                .from('products')
                .select('items_per_wholesale_unit, unit_type_wholesale')
                .eq('id', productId)
                .single();
            final String? wholesale = meta['unit_type_wholesale'] as String?;
            final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
            if (oldUnit != null && wholesale != null && oldUnit == wholesale) {
              oldSingle = oldQty * perUnit;
            }
            if (newUnit != null && wholesale != null && newUnit == wholesale) {
              newSingle = newQty * perUnit;
            }
          } catch (_) {}

          final int delta = newSingle - oldSingle;

          final Map<String, dynamic> updatePayload = {
            'quantity': newQty,
            'price_per_unit': newPrice,
          };
          if (newUnit != null) updatePayload['unit'] = newUnit;
          await _client
              .from('purchase_items')
              .update(updatePayload)
              .eq('id', id);

          if (delta != 0) {
            // Adjust stock by delta
            final existing = await _client
                .from('products')
                .select('current_stock')
                .eq('id', productId)
                .eq('business_id', businessId)
                .maybeSingle();
            if (existing != null) {
              final num current = (existing['current_stock'] as num?) ?? 0;
              final newStock = current + delta;
              await _client
                  .from('products')
                  .update({'current_stock': newStock})
                  .eq('id', productId)
                  .eq('business_id', businessId);
            }
          }

          seenExistingIds.add(id);
        } else {
          // Insert new item and add to stock
          await _client
              .from('purchase_items')
              .insert({
                'purchase_id': purchaseId,
                'product_id': productId,
                'quantity': newQty,
                'price_per_unit': newPrice,
                if (newUnit != null) 'unit': newUnit,
              })
              .select('id')
              .single();

          // Increase stock by converted new quantity
          int inc = newQty;
          try {
            final meta = await _client
                .from('products')
                .select('items_per_wholesale_unit, unit_type_wholesale')
                .eq('id', productId)
                .single();
            final String? wholesale = meta['unit_type_wholesale'] as String?;
            final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
            if (newUnit != null && wholesale != null && newUnit == wholesale) {
              inc = newQty * perUnit;
            }
          } catch (_) {}

          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final newStock = current + inc;
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
          }
        }
      }

      // 4) Delete removed items and reduce stock
      for (final old in existingItems) {
        final int? oldId = old['id'] as int?;
        if (oldId != null && !seenExistingIds.contains(oldId)) {
          final int productId = old['product_id'] as int;
          final int oldQty = (old['quantity'] as num?)?.toInt() ?? 0;
          final String? oldUnit = old['unit'] as String?;

          await _client.from('purchase_items').delete().eq('id', oldId);

          // Reduce stock by converted old quantity
          int dec = oldQty;
          try {
            final meta = await _client
                .from('products')
                .select('items_per_wholesale_unit, unit_type_wholesale')
                .eq('id', productId)
                .single();
            final String? wholesale = meta['unit_type_wholesale'] as String?;
            final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
            if (oldUnit != null && wholesale != null && oldUnit == wholesale) {
              dec = oldQty * perUnit;
            }
          } catch (_) {}

          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final newStock = current - dec;
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
          }
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating purchase $purchaseId: $e');
      }
      return false;
    }
  }

  // Initialize Supabase (call this in main.dart)
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: kDebugMode,
    );
    _client = Supabase.instance.client;
  }

  // Create a sale with items (used by Shop direct checkout)
  static Future<int?> createSaleWithItems({
    String? customerName,
    String? customerPhone,
    String? transactionId,
    DateTime? createdAt,
    String paymentMethod = 'upi',
    required double totalAmount,
    double? discountAmount,
    double? taxAmount,
    required List<Map<String, dynamic>>
    items, // {product_id, quantity, price_per_unit, unit?}
    double? amountPaid,
    bool useAdvance = false,
    String? status,
    String? paymentProofUrl,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('Not signed in. Please login to record sales.');
    }

    int? createdSaleId;
    try {
      // Pre-validate items and stock availability (with unit conversion if provided)
      if (items.isEmpty) {
        throw Exception('At least one sale item is required');
      }
      if (totalAmount <= 0) {
        throw Exception('Invalid sale total amount');
      }

      // Handle Public Shop Orders (Anonymous) OR Pending Authentication Sales via Secure RPC
      final user = _client.auth.currentUser;
      // If we have a proof or explicit pending status, we MUST go through the shop_orders flow
      // so it appears in the Verification Page.
      final isPendingFlow =
          (status == 'pending' || status == 'payment_pending') ||
          (paymentProofUrl != null && paymentProofUrl.isNotEmpty);

      if (user == null || isPendingFlow) {
        // Use NEW secure RPC with validation, rate limiting, and server-side pricing
        // Note: price_per_unit is NOT sent - server uses selling_price from products table
        final rpcParams = {
          'p_business_id': businessId,
          'p_customer_name': customerName ?? 'Walk-in Customer',
          'p_customer_phone': customerPhone,
          'p_items': items
              .map(
                (item) => {
                  'product_id': item['product_id'],
                  'quantity': item['quantity'],
                  // price_per_unit intentionally omitted - server enforces selling_price
                },
              )
              .toList(),
          'p_payment_method': paymentMethod,
          'p_transaction_id': transactionId,
          'p_payment_proof_url': paymentProofUrl,
          'p_client_identifier':
              customerPhone ?? 'anonymous', // For rate limiting
        };

        final rpcResp = await _client.rpc(
          'submit_shop_order_secure',
          params: rpcParams,
        );

        // Handle JSONB response from secure RPC
        final response = Map<String, dynamic>.from(rpcResp as Map);
        if (response['success'] == true) {
          return (response['order_id'] as num).toInt();
        } else {
          // Handle specific error codes
          final errorCode = response['error'] ?? 'UNKNOWN_ERROR';
          final message = response['message'] ?? 'Order submission failed';

          if (errorCode == 'RATE_LIMIT_EXCEEDED') {
            throw Exception('Too many orders. Please wait a few minutes.');
          } else if (errorCode == 'INSUFFICIENT_STOCK') {
            final productName = response['product_name'] ?? 'Product';
            final available = response['available'] ?? 0;
            throw Exception('$productName: Only $available in stock');
          } else {
            throw Exception(message);
          }
        }
      }

      for (final it in items) {
        final int pid = (it['product_id'] as num).toInt();
        final int qty = (it['quantity'] as num).toInt();
        final double ppu = (it['price_per_unit'] as num).toDouble();

        // ... standard validation for authenticated users which follows ...
        if (pid <= 0 || qty <= 0 || ppu < 0) {
          throw Exception('Invalid sale item data');
        }

        final product = await _client
            .from('products')
            .select(
              'current_stock, items_per_wholesale_unit, unit_type_wholesale, name',
            )
            .eq('id', pid)
            .maybeSingle();

        if (product == null) {
          throw Exception('Product with ID $pid not found');
        }

        // Calculate required stock based on optional unit
        num requiredStock = qty;
        final String? unit = it['unit'] as String?;
        final String? wholesaleUnit = product['unit_type_wholesale'] as String?;
        final int itemsPerUnit =
            (product['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
        if (unit != null && wholesaleUnit != null && unit == wholesaleUnit) {
          requiredStock = qty * itemsPerUnit;
        }

        final num currentStock = (product['current_stock'] as num?) ?? 0;
        if (currentStock < requiredStock) {
          final pname = product['name'];
          throw Exception(
            'Insufficient stock for $pname. Available: $currentStock, Required: $requiredStock',
          );
        }
      }

      // 1) Create sale
      final saleResp = await _client
          .from('sales')
          .insert({
            'business_id': businessId,
            'customer_name': customerName ?? 'Walk-in Customer',
            if (customerPhone != null && customerPhone.isNotEmpty)
              'customer_phone': customerPhone,
            'total_amount': totalAmount,
            if (discountAmount != null) 'discount': discountAmount,
            'payment_method': paymentMethod,
            if (transactionId != null && transactionId.isNotEmpty)
              'transaction_id': transactionId,
            // Set created_at for consistent reporting (no sale_date column present)
            'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
          })
          .select('id')
          .single();

      final saleId = (saleResp['id'] as num).toInt();
      createdSaleId = saleId;

      // 2) Insert sale items
      if (items.isNotEmpty) {
        final toInsert = items.map(
          (it) => {
            'sale_id': saleId,
            'product_id': it['product_id'],
            'quantity': it['quantity'],
            'price_per_unit': it['price_per_unit'],
          },
        );
        await _client.from('sales_items').insert(toInsert.toList());
      }

      // 3) Decrement stock for each product using RPC (handles concurrency)
      for (final it in items) {
        final int pid = (it['product_id'] as num).toInt();
        int qty = (it['quantity'] as num).toInt();
        // Convert by unit if provided and matches wholesale unit
        try {
          final product = await _client
              .from('products')
              .select('items_per_wholesale_unit, unit_type_wholesale')
              .eq('id', pid)
              .single();
          final String? unit = it['unit'] as String?;
          final String? wholesaleUnit =
              product['unit_type_wholesale'] as String?;
          final int itemsPerUnit =
              (product['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
          if (unit != null && wholesaleUnit != null && unit == wholesaleUnit) {
            qty = qty * itemsPerUnit;
          }
        } catch (_) {
          // If metadata fetch fails, proceed with raw qty
        }

        try {
          await _client.rpc(
            'decrement_stock',
            params: {'p_product_id': pid, 'p_quantity': qty},
          );
        } catch (_) {
          try {
            final existing = await _client
                .from('products')
                .select('current_stock')
                .eq('id', pid)
                .eq('business_id', businessId)
                .maybeSingle();
            if (existing != null) {
              final num curr = (existing['current_stock'] as num?) ?? 0;
              await _client
                  .from('products')
                  .update({'current_stock': curr - qty})
                  .eq('id', pid)
                  .eq('business_id', businessId);
            }
          } catch (e) {
            debugPrint('[createSaleWithItems] Stock decrement fallback failed for $pid: $e');
          }
        }
      }

      // 3b) Best-effort update of optional fields if columns exist
      if ((status != null && status.isNotEmpty) ||
          (paymentProofUrl != null && paymentProofUrl.isNotEmpty)) {
        try {
          final Map<String, dynamic> extra = {};
          if (status != null && status.isNotEmpty) extra['status'] = status;
          if (paymentProofUrl != null && paymentProofUrl.isNotEmpty) {
            extra['payment_proof_url'] = paymentProofUrl;
          }
          if (extra.isNotEmpty) {
            await _client
                .from('sales')
                .update(extra)
                .eq('id', saleId)
                .eq('business_id', businessId);
          }
        } catch (_) {}
      }

      // 4) Handle customer due and optional advance application
      final String cust = (customerName ?? '').trim();
      if (cust.isNotEmpty && cust.toLowerCase() != 'walk-in customer') {
        double paid = amountPaid ?? totalAmount;
        if (paid < 0) paid = 0;
        if (paid > totalAmount) paid = totalAmount;
        double due = totalAmount - paid;

        if (useAdvance && due > 0) {
          try {
            final adv = await getCustomerAdvanceBalances([cust]);
            final available = adv[cust] ?? 0.0;
            final toApply = available > 0
                ? (available >= due ? due : available)
                : 0.0;
            if (toApply > 0) {
              await applyCustomerAdvance(
                customerName: cust,
                amount: toApply,
                refTable: 'sales',
                refId: saleId,
              );
              due -= toApply;
            }
          } catch (_) {}
        }

        if (due > 0) {
          try {
            final row = await _client
                .from('customers')
                .select('id, outstanding_balance')
                .eq('business_id', businessId)
                .eq('name', cust)
                .maybeSingle();
            if (row != null) {
              final cid = (row['id'] as num).toInt();
              final current =
                  (row['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
              await _client
                  .from('customers')
                  .update({'outstanding_balance': current + due})
                  .eq('id', cid)
                  .eq('business_id', businessId);
            }
          } catch (_) {}
        }
      }

      return saleId;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating sale with items: $e');
      }
      // Best-effort rollback if sale/items were created
      if (createdSaleId != null) {
        try {
          await _client
              .from('sales_items')
              .delete()
              .eq('sale_id', createdSaleId);
        } catch (_) {}
        try {
          await _client.from('sales').delete().eq('id', createdSaleId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  // Search returns by return_number or customer_name to import into replacements
  static Future<List<Map<String, dynamic>>> searchReturns(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      var req = _client
          .from('returns')
          .select(
            'id, return_number, customer_name, created_at, sales(id, customer_name), return_items(*)',
          )
          .eq('business_id', businessId);

      final q = query.trim();
      final asInt = int.tryParse(q);
      if (asInt != null) {
        // match by exact id or numeric return_number
        req = req.or('id.eq.$asInt,return_number.eq.$asInt');
      } else if (q.isNotEmpty) {
        req = req.or('customer_name.ilike.%$q%,return_number.ilike.%$q%');
      }

      final response = await req
          .order('created_at', ascending: false)
          .limit(20);
      return (response as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error searching returns: $e');
      }
      return [];
    }
  }

  // Fetch a single return by ID with joined sales and return_items
  static Future<Map<String, dynamic>?> getReturnById(int id) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      final response = await _client
          .from('returns')
          .select(
            '*, sales(id, customer_name, created_at, sales_items(*, products(*))), return_items(*, products(*))',
          )
          .eq('business_id', businessId)
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching return by id: $e');
      }
      return null;
    }
  }

  // Search sales for processing replacements
  static Future<List<Map<String, dynamic>>> searchSales(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final intId = int.tryParse(query.trim());
      var req = _client
          .from('sales')
          .select(
            'id, customer_name, total_amount, created_at, sales_items(*, products(*))',
          )
          .eq('business_id', businessId);

      if (intId != null) {
        req = req.eq('id', intId);
      } else {
        req = req.ilike('customer_name', '%${query.trim()}%');
      }

      final response = await req
          .order('created_at', ascending: false)
          .limit(20);
      return (response as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error searching sales: $e');
      }
      return [];
    }
  }

  // Search products for replacement items
  static Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final q = query.trim();
      const selectCols =
          'id, name, brand, business_id, category, description, current_stock, product_image_url, purchase_price, selling_price, size_or_spec, status, unit_type_single, unit_type_wholesale, items_per_wholesale_unit, created_at';

      Future<List<dynamic>> run(String column) async {
        return await _client
            .from('products')
            .select(selectCols)
            .eq('business_id', businessId)
            .neq('status', 'deleted')
            .ilike(column, '%$q%')
            .order('name')
            .limit(20);
      }

      final Map<int, Map<String, dynamic>> unique = {};
      for (final col in ['name', 'brand', 'category']) {
        try {
          final data = await run(col);
          for (final row in data) {
            final map = Map<String, dynamic>.from(row as Map);
            final id = map['id'] as int?;
            if (id != null && !unique.containsKey(id)) {
              unique[id] = map;
              if (unique.length >= 20) break;
            }
          }
          if (unique.length >= 20) break;
        } catch (_) {}
      }
      return unique.values.toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error searching products: $e');
      }
      return [];
    }
  }

  // Create a replacement with items in/out
  // Unit-aware stock updates and movement logs for both OUT (returned by customer)
  // and IN (given to customer) directions using items_per_wholesale_unit when unit matches wholesale unit.
  static Future<void> createReplacement({
    required int originalSaleId,
    required String customerName,
    String? customerPhone,
    String? replacementReason, // legacy param name
    String? reason, // new schema field
    String? notes,
    DateTime? replacementDate,
    String? paymentMethod,
    String? replacementNumber,
    double? priceDifference, // new schema field
    double? amountDifference, // legacy param name
    required List<Map<String, dynamic>> itemsOut,
    required List<Map<String, dynamic>> itemsIn,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    try {
      final double diff = priceDifference ?? amountDifference ?? 0.0;
      // If any returned item is defective/damaged, we will not charge customer (set diff to 0)
      final bool anyDefective = itemsOut.any((it) {
        final c = (it['item_condition'] as String?)?.toLowerCase();
        return c == 'defective' || c == 'damaged';
      });
      final double finalDiff = anyDefective ? 0.0 : diff;
      final String? finalReason = (reason != null && reason.isNotEmpty)
          ? reason
          : replacementReason;
      final String replNo =
          replacementNumber ?? 'RPL-${DateTime.now().millisecondsSinceEpoch}';

      final insertData = <String, dynamic>{
        'business_id': businessId,
        'original_sale_id': originalSaleId,
        'replacement_number': replNo,
        'customer_name': customerName,
        if (customerPhone != null && customerPhone.isNotEmpty)
          'customer_phone': customerPhone,
        if (replacementDate != null)
          'replacement_date': replacementDate.toIso8601String(),
        if (finalReason != null && finalReason.isNotEmpty)
          'reason': finalReason,
        'price_difference': finalDiff,
        if (paymentMethod != null && paymentMethod.isNotEmpty)
          'payment_method': paymentMethod,
        'status': 'pending',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      final rep = await _client
          .from('replacements')
          .insert(insertData)
          .select()
          .single();

      final repId = rep['id'] as int;

      if (itemsOut.isNotEmpty) {
        final outRows = itemsOut.map(
          (it) => {
            'replacement_id': repId,
            'product_id': it['product_id'],
            'quantity_returned': it['quantity_returned'],
            'original_price_per_unit': it['price_per_unit'],
            'item_condition': it['item_condition'] ?? 'good',
            if (it['original_sale_item_id'] != null)
              'original_sale_item_id': it['original_sale_item_id'],
          },
        );
        await _client.from('replacement_items_out').insert(outRows.toList());

        // Increase stock for returned items and log movement
        // Minimal change: skip restocking when item is defective/damaged or explicitly marked non-restockable
        for (final it in itemsOut) {
          final String? cond = (it['item_condition'] as String?)?.toLowerCase();
          final bool explicitRestock =
              (it['restock_eligible'] as bool?) ?? true;
          final bool restockAllowed =
              explicitRestock && cond != 'defective' && cond != 'damaged';
          if (!restockAllowed) {
            // Do not modify sellable stock for defective/damaged returns
            // We also skip creating a movement log to keep deletion reversal consistent
            continue;
          }
          final int productId = it['product_id'] as int;
          final int qtyEntered = (it['quantity_returned'] as num).toInt();
          int qtyPieces = qtyEntered;
          try {
            final meta = await _client
                .from('products')
                .select('items_per_wholesale_unit, unit_type_wholesale')
                .eq('id', productId)
                .single();
            final String? itemUnit = it['unit'] as String?;
            final String? wholesale = meta['unit_type_wholesale'] as String?;
            final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
            if (itemUnit != null &&
                wholesale != null &&
                itemUnit == wholesale) {
              qtyPieces = qtyEntered * perUnit;
            }
          } catch (_) {}
          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final num newStock = current + qtyPieces;
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
            // Log movement: IN
            try {
              await _client.from('replacement_stock_movements').insert({
                'replacement_id': repId,
                'product_id': productId,
                'movement_type': 'in',
                'quantity': qtyPieces,
                'reason': 'returned_by_customer',
              });
            } catch (_) {}
          }
        }
      }

      if (itemsIn.isNotEmpty) {
        final inRows = itemsIn.map(
          (it) => {
            'replacement_id': repId,
            'product_id': it['product_id'],
            'quantity_given': it['quantity_given'],
            'price_per_unit': it['price_per_unit'],
          },
        );
        await _client.from('replacement_items_in').insert(inRows.toList());

        // Decrease stock for given items and log movement
        for (final it in itemsIn) {
          final int productId = it['product_id'] as int;
          final int qtyEntered = (it['quantity_given'] as num).toInt();
          int qtyPieces = qtyEntered;
          try {
            final meta = await _client
                .from('products')
                .select('items_per_wholesale_unit, unit_type_wholesale')
                .eq('id', productId)
                .single();
            final String? itemUnit = it['unit'] as String?;
            final String? wholesale = meta['unit_type_wholesale'] as String?;
            final int perUnit =
              (meta['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
            if (itemUnit != null &&
                wholesale != null &&
                itemUnit == wholesale) {
              qtyPieces = qtyEntered * perUnit;
            }
          } catch (_) {}
          final existing = await _client
              .from('products')
              .select('current_stock')
              .eq('id', productId)
              .eq('business_id', businessId)
              .maybeSingle();
          if (existing != null) {
            final num current = (existing['current_stock'] as num?) ?? 0;
            final num newStock = current - qtyPieces;
            await _client
                .from('products')
                .update({'current_stock': newStock})
                .eq('id', productId)
                .eq('business_id', businessId);
            // Log movement: OUT
            try {
              await _client.from('replacement_stock_movements').insert({
                'replacement_id': repId,
                'product_id': productId,
                'movement_type': 'out',
                'quantity': qtyPieces,
                'reason': 'given_to_customer',
              });
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating replacement: $e');
      }
      rethrow;
    }
  }

  // Archived products helpers
  static Future<List<supabase_models.Product>> getArchivedProducts() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final response = await _client
          .from('products')
          .select()
          .eq('business_id', businessId)
          .eq('status', 'archived')
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching archived products: $e');
      }
      return [];
    }
  }

  static Future<bool> restoreProductById(int productId) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;
    try {
      await _client
          .from('products')
          .update({'status': 'active'})
          .eq('id', productId)
          .eq('business_id', businessId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error restoring product $productId: $e');
      }
      return false;
    }
  }

  static Future<bool> permanentlyDeleteProductById(int productId) async {
    try {
      await deleteProductById(productId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Replacements methods (raw maps for flexible UI mapping)
  static Future<List<Map<String, dynamic>>> getReplacements() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      if (kDebugMode) {
        print('No business ID found for fetching replacements');
      }
      return [];
    }

    try {
      final response = await _client
          .from('replacements')
          .select(
            '*, sales!inner(id, customer_name, created_at), replacement_items_out(*, products(*)), replacement_items_in(*, products(*))',
          )
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      return (response as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching replacements: $e');
      }
      return [];
    }
  }

  // Returns methods (raw maps for flexible UI mapping)
  static Future<List<Map<String, dynamic>>> getReturns() async {
    // Ensure business profile is loaded
    await getCurrentBusinessProfile();

    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      if (kDebugMode) {
        print('No business ID found for fetching returns');
      }
      return [];
    }

    try {
      final response = await _client
          .from('returns')
          .select(
            '*, sales:sales!returns_original_sale_id_fkey(id, customer_name, created_at), return_items(*, products(*))',
          )
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      return (response as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching returns: $e');
      }
      return [];
    }
  }

  // Get current user
  static User? get currentUser => _client.auth.currentUser;

  // Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  // Get business profile for current user
  static Future<supabase_models.BusinessProfile?>
  getCurrentBusinessProfile() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        // Unauthenticated/public shop mode: try default business ID
        if (_defaultBusinessId != null && _defaultBusinessId!.isNotEmpty) {
          try {
            // Use RPC for secure public access (returns only public columns)
            // Note: get_public_business_profile was replaced with public_business_info view
            final response = await _client
                .from('public_business_info')
                .select()
                .eq('id', _defaultBusinessId!)
                .maybeSingle();

            // maybeSingle returns Map? directly, not a List
            if (response != null) {
              _currentBusinessProfile =
                  supabase_models.BusinessProfile.fromJson(
                    Map<String, dynamic>.from(response),
                  );
              return _currentBusinessProfile;
            }
          } catch (_) {}
        }
        return null;
      }

      // First try to get business profile by current user ID
      var response = await _client
          .from('business_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
          response,
        );
        return _currentBusinessProfile;
      }

      // If no business profile found, check if there's one with the same email
      // This handles the case where user signed up in SvelteKit and now using Flutter
      if (user.email != null) {
        final profilesResponse = await _client
            .from('profiles')
            .select('id')
            .eq('email', user.email!)
            .neq('id', user.id);

        if (profilesResponse.isNotEmpty) {
          // Found existing profile with same email, try to get business profile
          final existingUserId = profilesResponse.first['id'];
          final businessResponse = await _client
              .from('business_profiles')
              .select()
              .eq('user_id', existingUserId)
              .maybeSingle();

          if (businessResponse != null) {
            final businessId = businessResponse['id'];

            // Update the business profile to use current user ID
            await _client
                .from('business_profiles')
                .update({'user_id': user.id})
                .eq('user_id', existingUserId);

            // Also migrate any existing categories and products to the new business profile
            // (Categories and products are already linked by business_id, so they should work automatically)

            _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
              businessResponse,
            );

            return _currentBusinessProfile;
          }
        }
      }

      // New fallback: if profiles has business_id for current user, use it
      try {
        final prof = await _client
            .from('profiles')
            .select('business_id')
            .eq('id', user.id)
            .maybeSingle();
        final bid = prof != null ? prof['business_id'] as String? : null;
        if (bid != null && bid.isNotEmpty) {
          final byId = await _client
              .from('business_profiles')
              .select()
              .eq('id', bid)
              .maybeSingle();
          if (byId != null) {
            _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
              byId,
            );
            return _currentBusinessProfile;
          }
        }
      } catch (_) {}

      // Fallback for unauthenticated/public shop mode using default business ID
      if (_currentBusinessProfile == null &&
          _defaultBusinessId != null &&
          _defaultBusinessId!.isNotEmpty) {
        try {
          final byId = await _client
              .from('business_profiles')
              .select()
              .eq('id', _defaultBusinessId!)
              .maybeSingle();
          if (byId != null) {
            _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
              byId,
            );
            return _currentBusinessProfile;
          }
        } catch (_) {}
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting business profile: $e');
      }
      return null;
    }
  }

  // Verify OTP and sign in
  static Future<Map<String, dynamic>> verifyOTP(
    String email,
    String token,
  ) async {
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: token,
      );

      if (response.user != null) {
        return {
          'success': true,
          'message': 'Successfully signed in!',
          'user': response.user,
        };
      } else {
        return {
          'success': false,
          'message': 'Invalid verification code. Please try again.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Verification failed: ${e.toString()}',
      };
    }
  }

  // Sign out user
  static Future<void> signOut() async {
    await _client.auth.signOut();
    _currentBusinessProfile = null;
  }

  // Update user profile
  static Future<Map<String, dynamic>> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      // Upsert profile data
      await _client.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': fullName,
        'phone': phone,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return {'success': true, 'message': 'Profile updated successfully!'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update profile: ${e.toString()}',
      };
    }
  }

  // Alias for getCurrentBusinessProfile for consistency
  static Future<supabase_models.BusinessProfile?> getBusinessProfile() async {
    return getCurrentBusinessProfile();
  }

  // Create business profile
  static Future<supabase_models.BusinessProfile?> createBusinessProfile(
    Map<String, dynamic> profileData,
  ) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Add user_id to profile data
      final dataWithUserId = {...profileData, 'user_id': user.id};

      final response = await _client
          .from('business_profiles')
          .insert(dataWithUserId)
          .select()
          .single();

      // Update current business profile
      _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
        response,
      );
      return _currentBusinessProfile;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating business profile: $e');
      }
      throw Exception('Failed to create business profile: $e');
    }
  }

  // Update business profile
  static Future<supabase_models.BusinessProfile?> updateBusinessProfile(
    Map<String, dynamic> profileData,
  ) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .from('business_profiles')
          .update(profileData)
          .eq('user_id', user.id)
          .select()
          .single();

      // Update current business profile
      _currentBusinessProfile = supabase_models.BusinessProfile.fromJson(
        response,
      );
      return _currentBusinessProfile;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating business profile: $e');
      }
      throw Exception('Failed to update business profile: $e');
    }
  }

  // Get current business ID (for scoping data)
  static String? getCurrentBusinessId() {
    if (_currentBusinessProfile?.id != null) {
      return _currentBusinessProfile!.id;
    }

    // Try to get from current user if business profile is null
    final user = _client.auth.currentUser;
    if (user?.userMetadata?['business_id'] != null) {
      return user!.userMetadata!['business_id'] as String;
    }

    // Fallback to default business ID for public browsing
    if (_defaultBusinessId != null && _defaultBusinessId!.isNotEmpty) {
      return _defaultBusinessId;
    }

    return null;
  }

  // Sign in with email and password
  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign up with email and password
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  // Send OTP for passwordless authentication
  static Future<void> sendOTP(String email) async {
    await _client.auth.signInWithOtp(email: email);
  }

  // Sign in with Google (OAuth)
  static Future<bool> signInWithGoogle({String? redirectTo}) async {
    try {
      final isShop = appFlavor == 'shop' ||
          const String.fromEnvironment('APP_TYPE') == 'shop';
      final callback = redirectTo ??
          (isShop
              ? 'io.supabase.rajinventory://shop-login-callback'
              : 'io.supabase.rajinventory://login-callback');
      return await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: callback,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error initiating Google sign in: $e');
      }
      rethrow;
    }
  }

  static String? _lastHandledAuthCode;

  // Handle OAuth callback URL if received via deep link
  static Future<AuthSessionUrlResponse?> handleAuthCallbackUrl(Uri uri) async {
    try {
      final code = uri.queryParameters['code'];
      if (code != null && code == _lastHandledAuthCode) {
        if (kDebugMode) {
          print('[Supabase] Auth code already being handled, skipping duplicate.');
        }
        return null;
      }
      if (code != null) {
        _lastHandledAuthCode = code;
      }
      final response = await _client.auth.getSessionFromUrl(uri);
      if (kDebugMode) {
        print('[Supabase] Successfully obtained session from URL: ${response.session.user.email}');
      }
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('Error handling auth callback URL: $e');
      }
      return null;
    }
  }

  // Auth State Stream
  static Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  // Create Storefront Order (shop_orders + shop_order_items)
  static Future<Map<String, dynamic>?> createShopOrder({
    required String businessId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? paymentMethod,
    String? transactionId,
    String? paymentProofUrl,
    required double totalAmount,
    String? notes,
    int? saleId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final token = 'trk_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      final orderRes = await _client
          .from('shop_orders')
          .insert({
            'business_id': businessId,
            if (customerId != null) 'customer_id': customerId,
            if (customerName != null) 'customer_name': customerName,
            if (customerPhone != null) 'customer_phone': customerPhone,
            'payment_method': paymentMethod ?? 'upi',
            if (transactionId != null) 'transaction_id': transactionId,
            if (paymentProofUrl != null) 'payment_proof_url': paymentProofUrl,
            'total_amount': totalAmount,
            'status': 'payment_pending',
            'tracking_token': token,
            if (notes != null) 'notes': notes,
            if (saleId != null) 'sale_id': saleId,
          })
          .select()
          .single();

      final orderId = (orderRes['id'] as num).toInt();

      if (items.isNotEmpty) {
        final orderItems = items.map((it) => {
          'order_id': orderId,
          'product_id': it['product_id'],
          'quantity': it['quantity'],
          'price_per_unit': it['price_per_unit'],
          if (it['unit'] != null) 'unit': it['unit'],
        }).toList();

        await _client.from('shop_order_items').insert(orderItems);
      }

      return Map<String, dynamic>.from(orderRes);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating shop order: $e');
      }
      return null;
    }
  }

  // Get Storefront Orders for Customer
  static Future<List<Map<String, dynamic>>> getShopOrdersForCustomer({
    required String customerId,
    required String businessId,
  }) async {
    try {
      final res = await _client
          .from('shop_orders')
          .select('*, shop_order_items(*, products(*))')
          .eq('business_id', businessId)
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      return (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching customer shop orders: $e');
      }
      return [];
    }
  }

  // Track Order by Token or ID
  static Future<Map<String, dynamic>?> trackShopOrder({
    required String query,
    required String businessId,
  }) async {
    try {
      final trimmed = query.trim();
      final idNum = int.tryParse(trimmed);

      var req = _client
          .from('shop_orders')
          .select('*, shop_order_items(*, products(*))');
      if (businessId.isNotEmpty) {
        req = req.eq('business_id', businessId);
      }

      dynamic res;
      if (idNum != null) {
        res = await req.or('tracking_token.eq.$trimmed,id.eq.$idNum,sale_id.eq.$idNum').limit(1).maybeSingle();
      } else {
        res = await req.eq('tracking_token', trimmed).limit(1).maybeSingle();
      }

      if (res != null) {
        return Map<String, dynamic>.from(res);
      }

      // Fallback: check sales table by ID or transaction_id
      try {
        var saleReq = _client.from('sales').select('*, sale_items(*, products(*))');
        if (businessId.isNotEmpty) {
          saleReq = saleReq.eq('business_id', businessId);
        }
        dynamic saleRes;
        if (idNum != null) {
          saleRes = await saleReq.eq('id', idNum).limit(1).maybeSingle();
        } else {
          saleRes = await saleReq.eq('transaction_id', trimmed).limit(1).maybeSingle();
        }
        if (saleRes != null) {
          final items = (saleRes['sale_items'] as List? ?? []).map((si) => {
            'product_name': si['products']?['name'] ?? 'Product',
            'quantity': si['quantity'] ?? 1,
            'unit_price': (si['price_per_unit'] ?? si['unit_price'] ?? 0.0) as num,
            'total_price': (si['total_price'] ?? 0.0) as num,
          }).toList();
          return {
            'id': saleRes['id'],
            'tracking_token': saleRes['transaction_id'] ?? 'SALE-${saleRes['id']}',
            'status': saleRes['status'] ?? 'completed',
            'total_amount': saleRes['total_amount'] ?? saleRes['final_amount'] ?? 0.0,
            'created_at': saleRes['sale_date'] ?? saleRes['created_at'],
            'customer_name': saleRes['customer_name'] ?? 'Customer',
            'customer_phone': saleRes['customer_phone'],
            'payment_method': saleRes['payment_method'],
            'shop_order_items': items,
          };
        }
      } catch (_) {}

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error tracking shop order: $e');
      }
      return null;
    }
  }

  // Create or get business profile
  static Future<supabase_models.BusinessProfile?> getOrCreateBusinessProfile({
    required String businessName,
    String? businessType,
    String? description,
  }) async {
    if (!isAuthenticated) return null;

    try {
      // Try to get existing business profile
      final existing = await _client
          .from('business_profiles')
          .select()
          .eq('user_id', currentUser!.id)
          .maybeSingle();

      if (existing != null) {
        return supabase_models.BusinessProfile.fromJson(existing);
      }

      // Create new business profile
      final response = await _client
          .from('business_profiles')
          .insert({
            'business_name': businessName,
            'business_type': businessType,
            'description': description,
            'user_id': currentUser!.id,
            'currency': 'INR',
            'timezone': 'Asia/Kolkata',
          })
          .select()
          .single();

      return supabase_models.BusinessProfile.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating/getting business profile: $e');
      }
      return null;
    }
  }

  // Products CRUD operations
  static Future<List<supabase_models.Product>> getProducts() async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      dynamic response;
      if (currentUser == null) {
        // Public/Shop mode: use secure RPC (returns public_products view, no purchase_price)
        response = await _client.rpc(
          'get_public_products_for_business',
          params: {'p_business_id': businessId},
        );
      } else {
        // Authenticated mode: use standard table access
        response = await _client
            .from('products')
            .select()
            .eq('business_id', businessId)
            .neq('status', 'deleted')
            .neq('status', 'archived');
      }

      return (response as List)
          .map<supabase_models.Product>(
            (json) => supabase_models.Product.fromJson(json),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting products: $e');
      }
      return [];
    }
  }

  static Future<supabase_models.Product?> getProduct(int id) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      final response = await _client
          .from('products')
          .select()
          .eq('id', id)
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .single();

      return supabase_models.Product.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting product: $e');
      }
      return null;
    }
  }

  // Subscription & Quotas
  static Future<supabase_models.SubscriptionInfo> getSubscriptionInfo([
    String? businessId,
  ]) async {
    final bId = businessId ?? getCurrentBusinessId();
    if (bId == null) {
      return const supabase_models.SubscriptionInfo(status: 'ACTIVE');
    }

    try {
      final profile =
          _currentBusinessProfile ?? await getCurrentBusinessProfile();

      // Check business_subscriptions
      dynamic subsRes;
      try {
        subsRes = await _client
            .from('business_subscriptions')
            .select()
            .eq('business_id', bId)
            .order('created_at', ascending: false);
      } catch (_) {}

      final subsList = (subsRes as List?) ?? [];
      Map<String, dynamic>? activeSub;
      for (final s in subsList) {
        final st = (s['status'] as String? ?? '').toLowerCase();
        if (['active', 'trialing', 'past_due', 'cancelled'].contains(st)) {
          activeSub = Map<String, dynamic>.from(s as Map);
          break;
        }
      }
      if (activeSub == null && subsList.isNotEmpty) {
        activeSub = Map<String, dynamic>.from(subsList.first as Map);
      }

      String? planId = activeSub != null
          ? activeSub['plan_id']?.toString()
          : profile?.planId;
      String subStatus = activeSub != null
          ? (activeSub['status']?.toString().toUpperCase() ?? 'TRIAL')
          : (profile?.status?.toUpperCase() ?? 'TRIAL');

      // Check if trial has expired based on trialEnd
      final trialEnd = profile?.trialEnd;
      if (subStatus == 'TRIAL' || subStatus == 'TRIALING') {
        if (trialEnd != null && trialEnd.isBefore(DateTime.now())) {
          subStatus = 'EXPIRED';
        }
      }

      Map<String, dynamic>? planData;
      if (planId != null) {
        try {
          final pRes = await _client
              .from('subscription_plans')
              .select()
              .eq('id', planId)
              .maybeSingle();
          if (pRes != null) {
            planData = Map<String, dynamic>.from(pRes as Map);
          }
        } catch (_) {}
      }

      final planName =
          planData?['display_name'] as String? ??
          (planId != null ? 'Inventoza Plan' : 'Trial Plan');
      final planMaxProducts = planData?['max_products'] as int?;
      final planMaxUsers = planData?['max_users'] as int?;
      final planMaxImages = planData?['max_storage_images'] as int?;

      Map<String, dynamic> features = {};
      final rawFeatures = planData?['features'];
      if (rawFeatures is Map) {
        features = Map<String, dynamic>.from(rawFeatures);
      }

      int? resolveLimit(int? override, int? planLimit) {
        if (planLimit == null) return override;
        if (override == null) return planLimit;
        return override > planLimit ? override : planLimit;
      }

      final effectiveMaxProducts = resolveLimit(
        profile?.maxProducts,
        planMaxProducts,
      );
      final effectiveMaxUsers = resolveLimit(profile?.maxUsers, planMaxUsers);
      final effectiveMaxImages = resolveLimit(
        profile?.maxStorageImages,
        planMaxImages,
      );

      final renewsAt = activeSub?['renews_at'] != null
          ? DateTime.tryParse(activeSub!['renews_at'])
          : null;
      final expiresAt = activeSub?['expires_at'] != null
          ? DateTime.tryParse(activeSub!['expires_at'])
          : null;

      final isTrial = subStatus == 'TRIAL' || subStatus == 'TRIALING';
      int? daysRemaining;
      if (isTrial && trialEnd != null) {
        final diff = trialEnd.difference(DateTime.now()).inDays;
        daysRemaining = diff < 0 ? 0 : diff;
      }

      return supabase_models.SubscriptionInfo(
        planId: planId,
        planName: planName,
        status: subStatus,
        maxProducts: effectiveMaxProducts,
        maxUsers: effectiveMaxUsers,
        maxStorageImages: effectiveMaxImages,
        features: features,
        trialEnd: trialEnd,
        renewsAt: renewsAt,
        expiresAt: expiresAt,
        isTrial: isTrial,
        daysRemaining: daysRemaining,
      );
    } catch (e) {
      if (kDebugMode) print('Error getting subscription info: $e');
      return const supabase_models.SubscriptionInfo(status: 'ACTIVE');
    }
  }

  static Future<supabase_models.QuotaCheckResult> checkProductQuota([
    String? businessId,
  ]) async {
    final bId = businessId ?? getCurrentBusinessId();
    if (bId == null) {
      return const supabase_models.QuotaCheckResult(
        allowed: false,
        message: 'No business selected',
      );
    }

    try {
      final subInfo = await getSubscriptionInfo(bId);
      if (!subInfo.isWritable) {
        return supabase_models.QuotaCheckResult(
          allowed: false,
          message: subInfo.isSuspended
              ? 'Your account has been suspended. Please contact support.'
              : 'Your trial or subscription has expired. Please upgrade to continue.',
          currentCount: 0,
          maxAllowed: subInfo.maxProducts,
        );
      }

      final res = await _client
          .from('products')
          .select('id')
          .eq('business_id', bId)
          .neq('status', 'archived');
      final count = (res as List).length;

      if (subInfo.maxProducts != null && count >= subInfo.maxProducts!) {
        return supabase_models.QuotaCheckResult(
          allowed: false,
          message:
              'Product limit reached ($count/${subInfo.maxProducts}). Please upgrade your plan on Inventoza web to add more products.',
          currentCount: count,
          maxAllowed: subInfo.maxProducts,
        );
      }

      return supabase_models.QuotaCheckResult(
        allowed: true,
        currentCount: count,
        maxAllowed: subInfo.maxProducts,
      );
    } catch (e) {
      if (kDebugMode) print('Quota check error: $e');
      return const supabase_models.QuotaCheckResult(allowed: true);
    }
  }

  static Future<supabase_models.Product?> createProduct({
    required String name,
    String? brand,
    required String category,
    String? sizeSpec,
    String? description,
    required double sellingPrice,
    String? unitTypeSingle = 'Piece',
    String? unitTypeWholesale,
    int? itemsPerWholesaleUnit = 1,
    List<String>? localImagePaths, // Local image paths (not stored in Supabase)
    String? itemCode, // NEW
  }) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business selected. Please log in again.');
    }

    try {
      // Decide cover image URL (first http/https reference)
      String? coverImageUrl;
      if (localImagePaths != null && localImagePaths.isNotEmpty) {
        coverImageUrl = localImagePaths.firstWhere(
          (p) => p.startsWith('http'),
          orElse: () => '',
        );
        if (coverImageUrl.isEmpty) coverImageUrl = null;
      }

      final response = await _client
          .from('products')
          .insert({
            'name': name,
            'brand': brand,
            'business_id': businessId,
            'category': category,
            'description': description,
            'size_or_spec': sizeSpec,
            'selling_price': sellingPrice,
            'unit_type_single': unitTypeSingle,
            'unit_type_wholesale': unitTypeWholesale,
            'items_per_wholesale_unit': itemsPerWholesaleUnit,
            'item_code': itemCode,
            if (coverImageUrl != null) 'product_image_url': coverImageUrl,
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final product = supabase_models.Product.fromJson(response);

      // Best-effort: persist full image list if column exists
      try {
        final httpUrls = (localImagePaths ?? [])
            .where((p) => p.startsWith('http'))
            .toList();
        if (httpUrls.isNotEmpty && product.id != null) {
          await _client
              .from('products')
              .update({'product_images': httpUrls})
              .eq('id', product.id!);
        }
      } catch (_) {
        // ignore if column doesn't exist
      }

      return product;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating product: $e');
      }
      if (e is PostgrestException) {
        throw Exception(e.message);
      }
      rethrow;
    }
  }

  static Future<supabase_models.Product?> updateProduct({
    required int id,
    String? name,
    String? brand,
    String? category,
    String? description,
    String? sizeOrSpec,
    int? currentStock,
    double? purchasePrice,
    double? sellingPrice,
    String? unitTypeSingle,
    String? unitTypeWholesale,
    int? itemsPerWholesaleUnit,
    List<String>? localImagePaths,
    String? itemCode,
  }) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      final updateData = <String, dynamic>{};

      if (name != null) updateData['name'] = name;
      if (brand != null) updateData['brand'] = brand;
      if (category != null) updateData['category'] = category;
      if (description != null) updateData['description'] = description;
      if (sizeOrSpec != null) updateData['size_or_spec'] = sizeOrSpec;
      if (currentStock != null) updateData['current_stock'] = currentStock;
      if (purchasePrice != null) updateData['purchase_price'] = purchasePrice;
      if (sellingPrice != null) updateData['selling_price'] = sellingPrice;
      if (unitTypeSingle != null) {
        updateData['unit_type_single'] = unitTypeSingle;
      }
      if (unitTypeWholesale != null) {
        updateData['unit_type_wholesale'] = unitTypeWholesale;
      }
      if (itemsPerWholesaleUnit != null) {
        updateData['items_per_wholesale_unit'] = itemsPerWholesaleUnit;
      }

      // If new images provided, take first http/https as cover
      if (localImagePaths != null && localImagePaths.isNotEmpty) {
        final cover = localImagePaths.firstWhere(
          (p) => p.startsWith('http'),
          orElse: () => '',
        );
        if (cover.isNotEmpty) {
          updateData['product_image_url'] = cover;
        }
      }

      final response = await _client
          .from('products')
          .update(updateData)
          .eq('id', id)
          .eq('business_id', businessId)
          .select()
          .single();

      // Best-effort: persist full image list (multiple URLs)
      try {
        final httpUrls = (localImagePaths ?? [])
            .where((p) => p.startsWith('http'))
            .toList();
        if (httpUrls.isNotEmpty) {
          await _client
              .from('products')
              .update({'product_images': httpUrls})
              .eq('id', id)
              .eq('business_id', businessId);
        }
      } catch (_) {
        // ignore if column doesn't exist
      }

      return supabase_models.Product.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating product: $e');
      }
      return null;
    }
  }

  static Future<bool> deleteProduct(int id) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return false;

    try {
      // Soft delete - set status to deleted
      await _client
          .from('products')
          .update({'status': 'deleted'})
          .eq('id', id)
          .eq('business_id', businessId);

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting product: $e');
      }
      return false;
    }
  }

  // Categories
  static Future<List<supabase_models.Category>> getCategories() async {
    // Ensure we have a business profile loaded
    if (_currentBusinessProfile == null) {
      await getCurrentBusinessProfile();
    }

    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      if (kDebugMode) {
        print('No business ID found for getting categories');
      }
      return [];
    }

    try {
      if (kDebugMode) {
        print('Getting categories for business ID: $businessId');
      }
      final response = await _client
          .from('categories')
          .select()
          .eq('business_id', businessId)
          .order('name');

      if (kDebugMode) {
        print('Categories response: $response');
      }
      return response
          .map<supabase_models.Category>(
            (json) => supabase_models.Category.fromJson(json),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting categories: $e');
      }
      return [];
    }
  }

  static Future<supabase_models.Category?> createCategory({
    required String name,
  }) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return null;

    try {
      if (kDebugMode) {
        print('Creating category with business ID: $businessId');
      }

      // Check if category already exists first
      final existingCategories = await getCategories();
      final existingCategory = existingCategories
          .where((cat) => cat.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;

      if (existingCategory != null) {
        if (kDebugMode) {
          print(
            'Category already exists, returning existing: ${existingCategory.name}',
          );
        }
        return existingCategory;
      }

      final response = await _client
          .from('categories')
          .insert({'name': name, 'business_id': businessId})
          .select()
          .single();

      return supabase_models.Category.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating category: $e');
      }
      return null;
    }
  }

  // Get unique category names from products (fallback if categories table is empty)
  static Future<List<String>> getProductCategories() async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) return [];

    try {
      final response = await _client
          .from('products')
          .select('category')
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .not('category', 'is', null);

      final categories = <String>{};
      for (final row in response) {
        final category = row['category'] as String?;
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }

      return categories.toList()..sort();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting product categories: $e');
      }
      return [];
    }
  }

  // Update product - using the existing method signature
  static Future<supabase_models.Product?> updateProductById({
    required int productId,
    required String name,
    String? brand,
    String? category,
    String? description,
    String? sizeOrSpec,
    int? currentStock,
    double? purchasePrice,
    double? sellingPrice,
    String? unitTypeSingle,
    String? unitTypeWholesale,
    int? itemsPerWholesaleUnit,
  }) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception(
        'No business profile found. Please set up business information first.',
      );
    }

    try {
      final updateData = <String, dynamic>{
        'name': name,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (brand != null) updateData['brand'] = brand;
      if (category != null) updateData['category'] = category;
      if (description != null) updateData['description'] = description;
      if (sizeOrSpec != null) updateData['size_or_spec'] = sizeOrSpec;
      if (currentStock != null) updateData['current_stock'] = currentStock;
      if (purchasePrice != null) updateData['purchase_price'] = purchasePrice;
      if (sellingPrice != null) updateData['selling_price'] = sellingPrice;
      if (unitTypeSingle != null) {
        updateData['unit_type_single'] = unitTypeSingle;
      }
      if (unitTypeWholesale != null) {
        updateData['unit_type_wholesale'] = unitTypeWholesale;
      }
      if (itemsPerWholesaleUnit != null) {
        updateData['items_per_wholesale_unit'] = itemsPerWholesaleUnit;
      }

      final response = await _client
          .from('products')
          .update(updateData)
          .eq('id', productId)
          .eq('business_id', businessId)
          .select()
          .single();

      return supabase_models.Product.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating product: $e');
      }
      throw Exception('Failed to update product: $e');
    }
  }

  // Delete product
  static Future<void> deleteProductById(int productId) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception(
        'No business profile found. Please set up business information first.',
      );
    }

    try {
      await _client
          .from('products')
          .delete()
          .eq('id', productId)
          .eq('business_id', businessId);
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting product: $e');
      }
      throw Exception('Failed to delete product: $e');
    }
  }

  // Bulk delete products
  static Future<void> bulkDeleteProducts(List<int> productIds) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception(
        'No business profile found. Please set up business information first.',
      );
    }

    try {
      for (final productId in productIds) {
        await _client
            .from('products')
            .delete()
            .eq('id', productId)
            .eq('business_id', businessId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error bulk deleting products: $e');
      }
      throw Exception('Failed to delete products: $e');
    }
  }

  // Real-time subscriptions
  static Future<void> subscribeToProducts({
    required void Function(List<Map<String, dynamic>>) onData,
  }) async {
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    _client
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .listen(onData);
  }

  // Sales methods
  static Future<List<Sale>> getSales() async {
    // Ensure business profile is loaded
    await getCurrentBusinessProfile();

    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      if (kDebugMode) {
        print('No business ID found for fetching sales');
      }
      return [];
    }

    try {
      final List<Sale> allSales = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('sales')
            .select('*, sales_items(*, products(*))')
            .eq('business_id', businessId)
            .order('created_at', ascending: false)
            .range(from, from + pageSize - 1);

        final list = (response as List)
            .map((json) => Sale.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        allSales.addAll(list);

        if (list.length < pageSize) break;
        from += pageSize;
      }

      return allSales;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching sales: $e');
      }
      return [];
    }
  }

  // Purchase methods
  static Future<List<Purchase>> getPurchases() async {
    // Ensure business profile is loaded
    await getCurrentBusinessProfile();

    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      if (kDebugMode) {
        print('No business ID found for fetching purchases');
      }
      return [];
    }

    try {
      final List<Purchase> allPurchases = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final response = await _client
            .from('purchases')
            .select('*, purchase_items(*, products(*))')
            .eq('business_id', businessId)
            .order('created_at', ascending: false)
            .range(from, from + pageSize - 1);

        final list = (response as List)
            .map((json) => Purchase.fromJson(json))
            .toList();
        allPurchases.addAll(list);

        if (list.length < pageSize) break;
        from += pageSize;
      }

      return allPurchases;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching purchases: $e');
      }
      return [];
    }
  }

  // Create a new purchase with items
  static Future<Purchase> createPurchase({
    required String dealerName,
    String? billNumber,
    DateTime? purchaseDate,
    required List<Map<String, dynamic>> purchaseItems,
    double paidAmount = 0.0,
  }) async {
    await getCurrentBusinessProfile();

    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business ID found');
    }

    try {
      // Compute total amount from items (qty * price_per_unit using entered unit)
      final double totalAmount = purchaseItems.fold<double>(
        0.0,
        (sum, it) =>
            sum +
            ((it['quantity'] as num).toDouble() *
                (it['price_per_unit'] as num).toDouble()),
      );

      // Create the purchase record - matching provided schema
      final purchaseData = {
        'business_id': businessId,
        'dealer_name': dealerName,
        'bill_number': billNumber,
        'total_amount': totalAmount,
      };

      // Add custom date if provided (SvelteKit pattern)
      if (purchaseDate != null) {
        purchaseData['created_at'] = purchaseDate.toIso8601String();
      }

      final purchaseResponse = await _client
          .from('purchases')
          .insert(purchaseData)
          .select()
          .single();

      final purchaseId = purchaseResponse['id'] as int;

      // Process each purchase item with smart unit conversion (SvelteKit logic)
      for (final item in purchaseItems) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        final unit = item['unit'] as String;
        final pricePerUnit = item['price_per_unit'] as double;

        // Get the full product details for unit conversion
        final productResponse = await _client
            .from('products')
            .select(
              'items_per_wholesale_unit, unit_type_single, unit_type_wholesale, current_stock',
            )
            .eq('id', productId)
            .single();

        final product = productResponse;

        // Calculate quantity to add with unit conversion (SvelteKit logic)
        int quantityToAdd = quantity;
        if (unit == product['unit_type_wholesale']) {
          final itemsPerUnit =
              (product['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;
          quantityToAdd = quantity * itemsPerUnit;
        }

        // Update stock using the calculated quantity
        final num currentStock = (product['current_stock'] as num?) ?? 0;
        final num newStock = currentStock + quantityToAdd;

        await _client
            .from('products')
            .update({'current_stock': newStock})
            .eq('id', productId);

        // Save the purchase item record with original quantity and unit
        await _client.from('purchase_items').insert({
          'purchase_id': purchaseId,
          'product_id': productId,
          'quantity': quantity, // Original quantity as entered
          'unit': unit, // Save the unit type used
          'price_per_unit': pricePerUnit,
        });
      }

      // Ledger entry: Record Purchase as 'credit' (Liability)
      try {
        await _client.from('supplier_ledger').insert({
          'business_id': businessId,
          'supplier_name': dealerName,
          'entry_type': 'purchase', // Explicit type for Purchase (Liability)
          'amount': totalAmount,
          'ref_table': 'purchases',
          'ref_id': purchaseId,
        });
      } catch (e) {
        if (kDebugMode) {
          print('Error creating ledger entry: $e');
        }
        // Proceeding anyway as purchase is valid
      }

      // Ledger entry: Record Payment (Asset) if amount paid > 0
      if (paidAmount > 0) {
        try {
          await _client.from('supplier_ledger').insert({
            'business_id': businessId,
            'supplier_name': dealerName,
            'entry_type': 'payment',
            'amount': paidAmount,
            'ref_table': 'purchases',
            'ref_id': purchaseId,
            'notes': 'Payment for Purchase #$purchaseId',
          });
        } catch (e) {
          if (kDebugMode) {
            print('Error creating payment ledger entry: $e');
          }
        }
      }

      // Fetch and return the complete purchase with items
      final completeResponse = await _client
          .from('purchases')
          .select('*, purchase_items(*, products(*))')
          .eq('id', purchaseId)
          .single();

      return Purchase.fromJson(completeResponse);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating purchase: $e');
      }
      throw Exception('Failed to create purchase: $e');
    }
  }

  // Health Check Methods
  Future<List<supabase_models.Product>> getProductsWithNegativeStock() async {
    try {
      final response = await _client
          .from('products')
          .select()
          .lt('current_stock', 0);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting products with negative stock: $e');
      }
      return [];
    }
  }

  Future<List<supabase_models.Product>> getIncompleteProducts() async {
    try {
      final response = await _client
          .from('products')
          .select()
          .or('name.is.null,unit_type_single.is.null');

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting incomplete products: $e');
      }
      return [];
    }
  }

  Future<List<supabase_models.Product>> getProductsWithStock() async {
    try {
      final response = await _client
          .from('products')
          .select()
          .gt('current_stock', 0);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting products with stock: $e');
      }
      return [];
    }
  }

  Future<bool> productHasPurchaseHistory(int productId) async {
    try {
      final response = await _client
          .from('purchase_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);

      return (response as List).isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking purchase history for product $productId: $e');
      }
      return false;
    }
  }

  Future<List<supabase_models.Product>> getAllProducts() async {
    try {
      final businessId = getCurrentBusinessId();
      if (businessId == null) return [];
      final response = await _client
          .from('products')
          .select()
          .eq('business_id', businessId)
          .neq('status', 'deleted')
          .neq('status', 'archived')
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting all products: $e');
      }
      return [];
    }
  }

  Future<List<supabase_models.Product>> getProductsCreatedAfter(
    DateTime date,
  ) async {
    try {
      final response = await _client
          .from('products')
          .select()
          .gte('created_at', date.toIso8601String())
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => supabase_models.Product.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting products created after $date: $e');
      }
      return [];
    }
  }

  // Health Check Fix Actions
  Future<bool> correctProductStock(int productId) async {
    try {
      // Get product details - will throw if not found
      await _client.from('products').select().eq('id', productId).single();

      // Check for purchase history
      final purchaseItems = await _client
          .from('purchase_items')
          .select('quantity')
          .eq('product_id', productId);

      // Check for sales history
      final salesItems = await _client
          .from('sales_items')
          .select('quantity')
          .eq('product_id', productId);

      final hasPurchaseHistory = (purchaseItems as List).isNotEmpty;
      final hasSalesHistory = (salesItems as List).isNotEmpty;

      if (hasPurchaseHistory) {
        // Calculate correct stock from purchase/sales history
        final totalPurchased = (purchaseItems as List).fold<int>(
          0,
          (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
        );
        final totalSold = (salesItems as List).fold<int>(
          0,
          (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
        );

        final correctStock = totalPurchased - totalSold;

        await _client
            .from('products')
            .update({'current_stock': correctStock})
            .eq('id', productId);
      } else if (hasSalesHistory) {
        // Set stock to total sold to prevent negative stock
        final totalSold = (salesItems as List).fold<int>(
          0,
          (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
        );

        await _client
            .from('products')
            .update({'current_stock': totalSold})
            .eq('id', productId);
      } else {
        // No history, safe to reset to 0
        await _client
            .from('products')
            .update({'current_stock': 0})
            .eq('id', productId);
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error correcting stock for product $productId: $e');
      }
      return false;
    }
  }

  Future<bool> deleteProductSafely(int productId) async {
    try {
      // Check for related records
      final purchaseItems = await _client
          .from('purchase_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);

      final salesItems = await _client
          .from('sales_items')
          .select('id')
          .eq('product_id', productId)
          .limit(1);

      final hasPurchaseItems = (purchaseItems as List).isNotEmpty;
      final hasSalesItems = (salesItems as List).isNotEmpty;

      if (hasPurchaseItems || hasSalesItems) {
        // Cannot hard-delete: archive the product and reset stock
        await _client
            .from('products')
            .update({'current_stock': 0, 'status': 'archived'})
            .eq('id', productId);
      } else {
        // Safe to delete
        await _client.from('products').delete().eq('id', productId);
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting product $productId: $e');
      }
      return false;
    }
  }

  Future<int> resetAllSuspiciousStock() async {
    try {
      final productsWithStock = await getProductsWithStock();
      int resetCount = 0;

      for (final product in productsWithStock) {
        final productId = product.id;
        if (productId != null) {
          final hasPurchases = await productHasPurchaseHistory(productId);
          if (!hasPurchases) {
            await _client
                .from('products')
                .update({'current_stock': 0})
                .eq('id', productId);
            resetCount++;
          }
        }
      }

      return resetCount;
    } catch (e) {
      if (kDebugMode) {
        print('Error resetting suspicious stock: $e');
      }
      return 0;
    }
  }

  Future<int> fixAllNegativeStock() async {
    try {
      final negativeStockProducts = await getProductsWithNegativeStock();
      int fixedCount = 0;

      for (final product in negativeStockProducts) {
        final productId = product.id;
        if (productId != null) {
          final success = await correctProductStock(productId);
          if (success) {
            fixedCount++;
          }
        }
      }
      return fixedCount;
    } catch (e) {
      if (kDebugMode) {
        print('Error fixing negative stock: $e');
      }
      return 0;
    }
  }

  // =====================
  // System Health: Duplicate detection and fixes
  // =====================
  static Future<Map<String, dynamic>> healthDetectDuplicates() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final result = <String, dynamic>{
      'products': {'count': 0, 'examples': <String>[]},
      'purchases': {'count': 0, 'examples': <String>[]},
      'returns': {'count': 0, 'examples': <String>[]},
      'replacements': {'count': 0, 'examples': <String>[]},
    };

    String prodKey(Map m) =>
        '${(m['name'] ?? '').toString().trim().toLowerCase()}|'
        '${(m['brand'] ?? '').toString().trim().toLowerCase()}|'
        '${(m['size_or_spec'] ?? '').toString().trim().toLowerCase()}';

    // Products
    final products = await _client
        .from('products')
        .select('id, name, brand, size_or_spec')
        .eq('business_id', businessId);
    final Map<String, List<int>> prodGroups = {};
    for (final r in products as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['id'] as num).toInt();
      (prodGroups[prodKey(m)] ??= []).add(id);
    }
    int prodDup = 0;
    final prodExamples = <String>[];
    prodGroups.forEach((k, ids) {
      if (ids.length > 1) {
        prodDup += (ids.length - 1);
        if (prodExamples.length < 10) prodExamples.add('$k -> ${ids.length}');
      }
    });
    result['products'] = {'count': prodDup, 'examples': prodExamples};

    // Purchases by bill_number
    final purchases = await _client
        .from('purchases')
        .select('id, bill_number')
        .eq('business_id', businessId);
    final Map<String, List<int>> purchGroups = {};
    for (final r in purchases as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['id'] as num).toInt();
      final bn = (m['bill_number'] ?? '').toString().trim();
      if (bn.isEmpty) continue;
      (purchGroups[bn] ??= []).add(id);
    }
    int purchDup = 0;
    final purchExamples = <String>[];
    purchGroups.forEach((bn, ids) {
      if (ids.length > 1) {
        purchDup += (ids.length - 1);
        if (purchExamples.length < 10) {
          purchExamples.add('$bn -> ${ids.length}');
        }
      }
    });
    result['purchases'] = {'count': purchDup, 'examples': purchExamples};

    // Returns by return_number
    final returns = await _client
        .from('returns')
        .select('id, return_number')
        .eq('business_id', businessId);
    final Map<String, List<int>> retGroups = {};
    for (final r in returns as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['id'] as num).toInt();
      final rn = (m['return_number'] ?? '').toString().trim();
      if (rn.isEmpty) continue;
      (retGroups[rn] ??= []).add(id);
    }
    int retDup = 0;
    final retExamples = <String>[];
    retGroups.forEach((rn, ids) {
      if (ids.length > 1) {
        retDup += (ids.length - 1);
        if (retExamples.length < 10) retExamples.add('$rn -> ${ids.length}');
      }
    });
    result['returns'] = {'count': retDup, 'examples': retExamples};

    // Replacements by replacement_number
    final replacements = await _client
        .from('replacements')
        .select('id, replacement_number')
        .eq('business_id', businessId);
    final Map<String, List<int>> repGroups = {};
    for (final r in replacements as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['id'] as num).toInt();
      final no = (m['replacement_number'] ?? '').toString().trim();
      if (no.isEmpty) continue;
      (repGroups[no] ??= []).add(id);
    }
    int repDup = 0;
    final repExamples = <String>[];
    repGroups.forEach((no, ids) {
      if (ids.length > 1) {
        repDup += (ids.length - 1);
        if (repExamples.length < 10) repExamples.add('$no -> ${ids.length}');
      }
    });
    result['replacements'] = {'count': repDup, 'examples': repExamples};

    return result;
  }

  static Future<Map<String, dynamic>> healthFixDuplicates({
    bool fixProducts = true,
    bool fixPurchases = true,
    bool fixReturns = true,
    bool fixReplacements = true,
    bool dryRun = true,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final changes = {
      'products_merged': 0,
      'purchases_merged': 0,
      'returns_merged': 0,
      'replacements_merged': 0,
      'details': <String, dynamic>{},
    };

    String prodKey(Map m) =>
        '${(m['name'] ?? '').toString().trim().toLowerCase()}|'
        '${(m['brand'] ?? '').toString().trim().toLowerCase()}|'
        '${(m['size_or_spec'] ?? '').toString().trim().toLowerCase()}';

    // Merge Products
    if (fixProducts) {
      final rows = await _client
          .from('products')
          .select('id, name, brand, size_or_spec')
          .eq('business_id', businessId);
      final Map<String, List<int>> groups = {};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        (groups[prodKey(m)] ??= []).add((m['id'] as num).toInt());
      }
      int merged = 0;
      final examples = <String>[];
      for (final e in groups.entries) {
        if (e.value.length <= 1) continue;
        e.value.sort();
        final primary = e.value.first;
        final dupIds = e.value.skip(1).toList();
        if (!dryRun) {
          await _client
              .from('purchase_items')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('sales_items')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('return_items')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('replacement_items_out')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('replacement_items_in')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('product_images')
              .update({'product_id': primary})
              .inFilter('product_id', dupIds);
          await _client
              .from('products')
              .delete()
              .inFilter('id', dupIds)
              .eq('business_id', businessId);
        }
        merged += dupIds.length;
        if (examples.length < 10) {
          examples.add(
            '${e.key} -> kept:$primary, removed:${dupIds.join(',')}',
          );
        }
      }
      changes['products_merged'] = merged;
      (changes['details'] as Map)['products'] = {
        'count': merged,
        'examples': examples,
      };
    }

    // Merge Purchases by bill_number
    if (fixPurchases) {
      final rows = await _client
          .from('purchases')
          .select('id, bill_number')
          .eq('business_id', businessId);
      final Map<String, List<int>> groups = {};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final bn = (m['bill_number'] ?? '').toString().trim();
        if (bn.isEmpty) continue;
        (groups[bn] ??= []).add((m['id'] as num).toInt());
      }
      int merged = 0;
      final examples = <String>[];
      for (final e in groups.entries) {
        if (e.value.length <= 1) continue;
        e.value.sort();
        final primary = e.value.first;
        final dupIds = e.value.skip(1).toList();
        if (!dryRun) {
          await _client
              .from('purchase_items')
              .update({'purchase_id': primary})
              .inFilter('purchase_id', dupIds);
          await _client
              .from('purchases')
              .delete()
              .inFilter('id', dupIds)
              .eq('business_id', businessId);
        }
        merged += dupIds.length;
        if (examples.length < 10) {
          examples.add(
            '${e.key} -> kept:$primary, removed:${dupIds.join(',')}',
          );
        }
      }
      changes['purchases_merged'] = merged;
      (changes['details'] as Map)['purchases'] = {
        'count': merged,
        'examples': examples,
      };
    }

    // Merge Returns by return_number
    if (fixReturns) {
      final rows = await _client
          .from('returns')
          .select('id, return_number')
          .eq('business_id', businessId);
      final Map<String, List<int>> groups = {};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final rn = (m['return_number'] ?? '').toString().trim();
        if (rn.isEmpty) continue;
        (groups[rn] ??= []).add((m['id'] as num).toInt());
      }
      int merged = 0;
      final examples = <String>[];
      for (final e in groups.entries) {
        if (e.value.length <= 1) continue;
        e.value.sort();
        final primary = e.value.first;
        final dupIds = e.value.skip(1).toList();
        if (!dryRun) {
          await _client
              .from('return_items')
              .update({'return_id': primary})
              .inFilter('return_id', dupIds);
          await _client
              .from('returns')
              .delete()
              .inFilter('id', dupIds)
              .eq('business_id', businessId);
        }
        merged += dupIds.length;
        if (examples.length < 10) {
          examples.add(
            '${e.key} -> kept:$primary, removed:${dupIds.join(',')}',
          );
        }
      }
      changes['returns_merged'] = merged;
      (changes['details'] as Map)['returns'] = {
        'count': merged,
        'examples': examples,
      };
    }

    // Merge Replacements by replacement_number
    if (fixReplacements) {
      final rows = await _client
          .from('replacements')
          .select('id, replacement_number')
          .eq('business_id', businessId);
      final Map<String, List<int>> groups = {};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final no = (m['replacement_number'] ?? '').toString().trim();
        if (no.isEmpty) continue;
        (groups[no] ??= []).add((m['id'] as num).toInt());
      }
      int merged = 0;
      final examples = <String>[];
      for (final e in groups.entries) {
        if (e.value.length <= 1) continue;
        e.value.sort();
        final primary = e.value.first;
        final dupIds = e.value.skip(1).toList();
        if (!dryRun) {
          await _client
              .from('replacement_items_out')
              .update({'replacement_id': primary})
              .inFilter('replacement_id', dupIds);
          await _client
              .from('replacement_items_in')
              .update({'replacement_id': primary})
              .inFilter('replacement_id', dupIds);
          await _client
              .from('replacement_stock_movements')
              .update({'replacement_id': primary})
              .inFilter('replacement_id', dupIds);
          await _client
              .from('replacements')
              .delete()
              .inFilter('id', dupIds)
              .eq('business_id', businessId);
        }
        merged += dupIds.length;
        if (examples.length < 10) {
          examples.add(
            '${e.key} -> kept:$primary, removed:${dupIds.join(',')}',
          );
        }
      }
      changes['replacements_merged'] = merged;
      (changes['details'] as Map)['replacements'] = {
        'count': merged,
        'examples': examples,
      };
    }

    return changes;
  }

  // =====================
  // Supplier Returns + Ledger
  // =====================

  static Future<Map<String, dynamic>> createPurchaseReturn({
    required String supplierName,
    int? originalPurchaseId,
    required DateTime returnDate,
    required String refundType, // 'credit' | 'cash'
    required List<PurchaseReturnItemInput> items,
    String? notes,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) {
      throw Exception('No business selected');
    }

    if (items.isEmpty) {
      throw Exception('Return must have at least one item');
    }

    // Prepare items for RPC (Requires fetching product names and converting units to singles)
    final List<Map<String, dynamic>> rpcItems = [];

    // Optimize: Fetch all products involved once
    // (For now, linear fetch is acceptable as return items are usually few)
    for (final it in items) {
      // 1. Fetch Product Details
      String productName = 'Unknown Product';
      int itemsPerWholesale = 1;
      bool isWholesale = false;

      try {
        final prod = await _client
            .from('products')
            .select(
              'name, unit_type_single, unit_type_wholesale, items_per_wholesale_unit',
            )
            .eq('id', it.productId)
            .single();

        productName = prod['name'] as String? ?? 'Unknown Product';
        final String? unitWhole = prod['unit_type_wholesale'] as String?;
        itemsPerWholesale =
            (prod['items_per_wholesale_unit'] as num?)?.toInt() ?? 1;

        if (it.unit != null && unitWhole != null) {
          isWholesale =
              it.unit!.trim().toLowerCase() == unitWhole.trim().toLowerCase();
        }
      } catch (_) {
        // Fallback if product deleted or fetch fails
      }

      // 2. Convert to Standard Units (Pieces) for Stock Accuracy
      // RPC logic: stock = stock - quantity.
      // If user returns 1 Box (10 pcs), we must send 10 to RPC.
      final int qtyPieces = isWholesale
          ? (it.quantity * itemsPerWholesale)
          : it.quantity;
      final double pricePerPiece = isWholesale
          ? (it.pricePerUnit / itemsPerWholesale)
          : it.pricePerUnit;

      rpcItems.add({
        'productId': it.productId,
        'productName': productName,
        'quantity': qtyPieces,
        'pricePerUnit': pricePerPiece,
      });
    }

    try {
      // 3. Call RPC
      final response = await _client.rpc(
        'process_supplier_return',
        params: {
          'p_business_id': businessId,
          'p_supplier_name': supplierName,
          'p_return_date': returnDate.toIso8601String(),
          'p_refund_type': refundType == 'cash' ? 'cash' : 'credit',
          'p_items': rpcItems,
        },
      );

      final returnId = (response as num).toInt();

      // Calculate total for return value (legacy support)
      final double totalAmount = rpcItems.fold<double>(
        0.0,
        (sum, it) =>
            sum + ((it['quantity'] as int) * (it['pricePerUnit'] as double)),
      );

      return {'id': returnId, 'total_amount': totalAmount};
    } catch (e) {
      if (kDebugMode) {
        print('Error processing supplier return: $e');
      }
      rethrow;
    }
  }

  static Future<double> getSupplierCreditBalance(String supplierName) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final rows = await _client
        .from('supplier_ledger')
        .select('entry_type, amount')
        .eq('business_id', businessId)
        .eq('supplier_name', supplierName);

    double credits = 0, debits = 0;
    for (final r in rows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final type = (m['entry_type'] as String?)?.toLowerCase() ?? '';
      final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;

      // Liability View (Standardized with Web App):
      // Positive (+) = Money We Owe (Liability) -> Purchase
      // Negative (-) = Money We Have/Paid (Asset) -> Return, Payment

      if (type == 'purchase' || type == 'credit') {
        // 'purchase': New Standard Liability
        // 'credit': Legacy Liability (if any) or Manual Credit
        credits += amt;
      } else if (type == 'debit' ||
          type == 'return' ||
          type == 'payment' ||
          type == 'apply' ||
          type == 'refund') {
        // 'debit': New Standard Asset (Return)
        // 'return': Semantic alias
        // 'payment': Semantic alias
        debits += amt;
      }
    }
    // Result: Net Liability (How much we owe)
    return credits - debits;
  }

  static Future<void> addSupplierPayment({
    required String supplierName,
    required double amount,
    required DateTime date,
    String? notes,
  }) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client.from('supplier_ledger').insert({
      'business_id': businessId,
      'supplier_name': supplierName,
      'entry_type': 'payment',
      'amount': amount,
      'created_at': date.toIso8601String(),
      'notes': notes,
    });
  }

  static Future<bool> applySupplierCredit({
    required String supplierName,
    required double amount,
    String? refTable, // e.g., 'purchases'
    int? refId,
  }) async {
    if (amount <= 0) return false;
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client.from('supplier_ledger').insert({
      'business_id': businessId,
      'supplier_name': supplierName,
      'entry_type': 'apply',
      'amount': amount,
      if (refTable != null) 'ref_table': refTable,
      if (refId != null) 'ref_id': refId,
    });
    return true;
  }

  static Future<List<SupplierLedgerEntry>> getSupplierLedger(
    String supplierName,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final rows = await _client
        .from('supplier_ledger')
        .select()
        .eq('business_id', businessId)
        .eq('supplier_name', supplierName)
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (e) =>
              SupplierLedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // ==================== Customer Ledger ====================

  static Future<bool> recordCustomerAdvance({
    required String customerName,
    required double amount,
    String? refTable,
    int? refId,
  }) async {
    if (amount <= 0) return false;
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client.from('customer_ledger').insert({
      'business_id': businessId,
      'customer_name': customerName,
      'entry_type': 'advance',
      'amount': amount,
      if (refTable != null) 'ref_table': refTable,
      if (refId != null) 'ref_id': refId,
    });
    return true;
  }

  static Future<bool> applyCustomerAdvance({
    required String customerName,
    required double amount,
    String? refTable,
    int? refId,
  }) async {
    if (amount <= 0) return false;
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client.from('customer_ledger').insert({
      'business_id': businessId,
      'customer_name': customerName,
      'entry_type': 'apply',
      'amount': amount,
      if (refTable != null) 'ref_table': refTable,
      if (refId != null) 'ref_id': refId,
    });
    return true;
  }

  /// Refund advance to customer (withdraw as cash)
  static Future<bool> refundCustomerAdvance({
    required String customerName,
    required double amount,
  }) async {
    if (amount <= 0) return false;
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    // Verify customer has enough advance balance
    final balances = await getCustomerAdvanceBalances([customerName]);
    final available = balances[customerName] ?? 0.0;
    if (amount > available) {
      throw Exception(
        'Cannot refund more than available advance (₹${available.toStringAsFixed(2)})',
      );
    }

    await _client.from('customer_ledger').insert({
      'business_id': businessId,
      'customer_name': customerName,
      'entry_type': 'refund',
      'amount': amount,
    });
    return true;
  }

  static Future<bool> recordCustomerPayment({
    required String customerName,
    required double amount,
  }) async {
    if (amount <= 0) return false;
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final row = await _client
        .from('customers')
        .select('id, outstanding_balance')
        .eq('business_id', businessId)
        .eq('name', customerName)
        .maybeSingle();

    if (row == null) return false;
    final id = (row['id'] as num).toInt();
    final current = (row['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
    final next = (current - amount) < 0 ? 0.0 : (current - amount);

    await _client
        .from('customers')
        .update({'outstanding_balance': next})
        .eq('id', id)
        .eq('business_id', businessId);

    await _client.from('customer_ledger').insert({
      'business_id': businessId,
      'customer_name': customerName,
      'entry_type': 'payment',
      'amount': amount,
    });
    return true;
  }

  static Future<List<CustomerLedgerEntry>> getCustomerLedger(
    String customerName,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final rows = await _client
        .from('customer_ledger')
        .select()
        .eq('business_id', businessId)
        .eq('customer_name', customerName)
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (e) =>
              CustomerLedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  static Future<Map<String, double>> getCustomerAdvanceBalances(
    List<String> customerNames,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null || customerNames.isEmpty) return {};

    final rows = await _client
        .from('customer_ledger')
        .select('customer_name, entry_type, amount')
        .eq('business_id', businessId)
        .inFilter('customer_name', customerNames);

    final totals = <String, double>{};
    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final name = (m['customer_name'] ?? '').toString();
      final type = (m['entry_type'] ?? '').toString();
      final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;
      if (name.isEmpty || amt <= 0) continue;
      double sign = 0;
      if (type == 'advance') sign = 1;
      if (type == 'apply' || type == 'refund') sign = -1;
      if (sign != 0) totals[name] = (totals[name] ?? 0.0) + sign * amt;
    }
    return totals;
  }

  // ==================== Suppliers Management ====================

  static Future<List<supabase_models.Supplier>> getSuppliers() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final rows = await _client
        .from('suppliers')
        .select()
        .eq('business_id', businessId)
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (e) => supabase_models.Supplier.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  static Future<List<supabase_models.Supplier>> searchSuppliers(
    String query,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    if (query.isEmpty) return getSuppliers();

    final rows = await _client
        .from('suppliers')
        .select()
        .eq('business_id', businessId)
        .ilike('name', '%$query%')
        .order('name', ascending: true)
        .limit(10);

    return (rows as List)
        .map(
          (e) => supabase_models.Supplier.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  static Future<supabase_models.Supplier> getSupplierById(int id) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final row = await _client
        .from('suppliers')
        .select()
        .eq('business_id', businessId)
        .eq('id', id)
        .single();

    return supabase_models.Supplier.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  static Future<int> createSupplier(supabase_models.Supplier supplier) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final data = supplier.toJson();
    data['business_id'] = businessId;
    data.remove('id');
    data.remove('created_at');
    data.remove('updated_at');

    final result = await _client.from('suppliers').insert(data).select('id');

    return (result as List).first['id'] as int;
  }

  static Future<void> updateSupplier(supabase_models.Supplier supplier) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    if (supplier.id == null) {
      throw Exception('Supplier ID is required for update');
    }

    final data = supplier.toJson();
    data['business_id'] = businessId;
    data.remove('id');
    data.remove('created_at');
    data.remove('updated_at');

    await _client
        .from('suppliers')
        .update(data)
        .eq('id', supplier.id!)
        .eq('business_id', businessId);
  }

  static Future<void> deleteSupplier(int id) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client
        .from('suppliers')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  // ==================== Customers Management ====================

  // Aggregate: purchases count for suppliers (by dealer_name)
  static Future<Map<String, int>> getPurchaseCountsForSuppliers(
    List<String> supplierNames,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null || supplierNames.isEmpty) return {};

    final rows = await _client
        .from('purchases')
        .select('dealer_name')
        .eq('business_id', businessId)
        .inFilter('dealer_name', supplierNames);

    final counts = <String, int>{};
    for (final r in (rows as List)) {
      final name = ((r as Map)['dealer_name'] ?? '').toString();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  static Future<List<supabase_models.Customer>> getCustomers() async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final rows = await _client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .order('name', ascending: true);

    final list = (rows as List)
        .map(
          (e) => supabase_models.Customer.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();

    // Filter out generic walk-in customers from listings
    return list.where((c) {
      final n = c.name.trim().toLowerCase();
      return n != 'walk-in' && n != 'walk-in customer';
    }).toList();
  }

  static Future<List<supabase_models.Customer>> searchCustomers(
    String query,
  ) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    if (query.isEmpty) return getCustomers();

    final rows = await _client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .or('name.ilike.%$query%,phone.ilike.%$query%')
        .order('name', ascending: true)
        .limit(10);

    final list = (rows as List)
        .map(
          (e) => supabase_models.Customer.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    return list.where((c) {
      final n = c.name.trim().toLowerCase();
      return n != 'walk-in' && n != 'walk-in customer';
    }).toList();
  }

  static Future<supabase_models.Customer> getCustomerById(int id) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final row = await _client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .eq('id', id)
        .single();

    return supabase_models.Customer.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  static Future<int> createCustomer(supabase_models.Customer customer) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    final data = customer.toJson();
    data['business_id'] = businessId;
    data.remove('id');
    data.remove('created_at');
    data.remove('updated_at');

    final result = await _client.from('customers').insert(data).select('id');

    return (result as List).first['id'] as int;
  }

  static Future<void> updateCustomer(supabase_models.Customer customer) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    if (customer.id == null) {
      throw Exception('Customer ID is required for update');
    }

    final data = customer.toJson();
    data['business_id'] = businessId;
    data.remove('id');
    data.remove('created_at');
    data.remove('updated_at');

    await _client
        .from('customers')
        .update(data)
        .eq('id', customer.id!)
        .eq('business_id', businessId);
  }

  static Future<void> deleteCustomer(int id) async {
    await getCurrentBusinessProfile();
    final businessId = getCurrentBusinessId();
    if (businessId == null) throw Exception('No business selected');

    await _client
        .from('customers')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }
}
