import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/receipt_service.dart';
import '../models/sales_purchase_models.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Storage helper for guest orders and delivery details on the customer device.
class ShopCustomerStorage {
  static const String _localOrdersKey = 'inventoza_guest_orders';
  static const String _profileNameKey = 'inventoza_customer_name';
  static const String _profilePhoneKey = 'inventoza_customer_phone';
  static const String _profileHouseKey = 'inventoza_customer_house';
  static const String _profileStreetKey = 'inventoza_customer_street';
  static const String _profileLandmarkKey = 'inventoza_customer_landmark';
  static const String _profileCityKey = 'inventoza_customer_city';
  static const String _profileStateKey = 'inventoza_customer_state';
  static const String _profilePincodeKey = 'inventoza_customer_pincode';
  static const String _profileLatitudeKey = 'inventoza_customer_latitude';
  static const String _profileLongitudeKey = 'inventoza_customer_longitude';

  static Future<Map<String, String>> loadSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = SupabaseService.currentUser;
    final meta = user?.userMetadata;
    final googleName = (meta?['full_name'] ?? meta?['name'])?.toString();
    final googleEmail = user?.email;

    final name = prefs.getString(_profileNameKey) ?? googleName ?? '';
    final phone = prefs.getString(_profilePhoneKey) ?? '';
    final house = prefs.getString(_profileHouseKey) ?? '';
    final street = prefs.getString(_profileStreetKey) ?? '';
    final landmark = prefs.getString(_profileLandmarkKey) ?? '';
    final city = prefs.getString(_profileCityKey) ?? '';
    final state = prefs.getString(_profileStateKey) ?? '';
    final pincode = prefs.getString(_profilePincodeKey) ?? '';
    final latitude = prefs.getString(_profileLatitudeKey) ?? '';
    final longitude = prefs.getString(_profileLongitudeKey) ?? '';

    return {
      'name': name,
      'phone': phone,
      'house': house,
      'street': street,
      'landmark': landmark,
      'city': city,
      'state': state,
      'pincode': pincode,
      'latitude': latitude,
      'longitude': longitude,
      'email': googleEmail ?? '',
    };
  }

  static Future<void> saveProfile({
    required String name,
    required String phone,
    String? house,
    String? street,
    String? landmark,
    String? city,
    String? state,
    String? pincode,
    String? latitude,
    String? longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, name.trim());
    await prefs.setString(_profilePhoneKey, phone.trim());
    if (house != null) await prefs.setString(_profileHouseKey, house.trim());
    if (street != null) await prefs.setString(_profileStreetKey, street.trim());
    if (landmark != null) await prefs.setString(_profileLandmarkKey, landmark.trim());
    if (city != null) await prefs.setString(_profileCityKey, city.trim());
    if (state != null) await prefs.setString(_profileStateKey, state.trim());
    if (pincode != null) await prefs.setString(_profilePincodeKey, pincode.trim());
    if (latitude != null) await prefs.setString(_profileLatitudeKey, latitude.trim());
    if (longitude != null) await prefs.setString(_profileLongitudeKey, longitude.trim());
  }

  static Future<List<Map<String, dynamic>>> loadLocalOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localOrdersKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('[ShopCustomerStorage] Error loading local orders: $e');
    }
    return [];
  }

  static Future<void> saveOrderLocally({
    required int orderId,
    required String trackingToken,
    required String customerName,
    String? customerPhone,
    required double totalAmount,
    required String status,
    required String createdAt,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadLocalOrders();
      current.removeWhere(
        (o) => o['id'] == orderId || o['tracking_token'] == trackingToken,
      );
      current.insert(0, {
        'id': orderId,
        'tracking_token': trackingToken,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'total_amount': totalAmount,
        'status': status,
        'created_at': createdAt,
        'items': items,
      });
      if (current.length > 50) current.removeRange(50, current.length);
      await prefs.setString(_localOrdersKey, jsonEncode(current));
    } catch (e) {
      debugPrint('[ShopCustomerStorage] Error saving local order: $e');
    }
  }

  static Future<void> updateLocalOrderStatus(int orderId, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadLocalOrders();
      for (var o in current) {
        if (o['id'] == orderId) {
          o['status'] = newStatus;
          break;
        }
      }
      await prefs.setString(_localOrdersKey, jsonEncode(current));
    } catch (e) {
      debugPrint('[ShopCustomerStorage] Error updating local order status: $e');
    }
  }
}

/// Unified modal sheets and dialogs for customer account, orders, and tracking.
class ShopAccountSheets {
  static void showAccountSheet(
    BuildContext context, {
    required String? businessId,
    required String businessName,
    String? businessPhone,
    String? businessWhatsapp,
    VoidCallback? onStateChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AccountMenuSheet(
        businessId: businessId,
        businessName: businessName,
        businessPhone: businessPhone,
        businessWhatsapp: businessWhatsapp,
        onStateChanged: onStateChanged,
      ),
    );
  }

  static void showTrackOrderSheet(
    BuildContext context, {
    required String? businessId,
    required String businessName,
    String? businessPhone,
    String? businessWhatsapp,
    String? initialQuery,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TrackOrderSheet(
        businessId: businessId,
        businessName: businessName,
        businessPhone: businessPhone,
        businessWhatsapp: businessWhatsapp,
        initialQuery: initialQuery,
      ),
    );
  }

  static void showMyOrdersSheet(
    BuildContext context, {
    required String? businessId,
    required String businessName,
    String? businessPhone,
    String? businessWhatsapp,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MyOrdersSheet(
        businessId: businessId,
        businessName: businessName,
        businessPhone: businessPhone,
        businessWhatsapp: businessWhatsapp,
      ),
    );
  }

  static void showProfileSheet(
    BuildContext context, {
    VoidCallback? onSaved,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProfileSheet(onSaved: onSaved),
    );
  }
}

// -------------------------------------------------------------
// 1. Account Menu Sheet
// -------------------------------------------------------------
class _AccountMenuSheet extends StatefulWidget {
  final String? businessId;
  final String businessName;
  final String? businessPhone;
  final String? businessWhatsapp;
  final VoidCallback? onStateChanged;

  const _AccountMenuSheet({
    required this.businessId,
    required this.businessName,
    this.businessPhone,
    this.businessWhatsapp,
    this.onStateChanged,
  });

  @override
  State<_AccountMenuSheet> createState() => _AccountMenuSheetState();
}

class _AccountMenuSheetState extends State<_AccountMenuSheet> {
  bool _isGoogleSigningIn = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = SupabaseService.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {});
        widget.onStateChanged?.call();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleSigningIn = true);
    try {
      await SupabaseService.signInWithGoogle(redirectTo: 'io.supabase.rajinventory://shop-login-callback');
      if (mounted) {
        widget.onStateChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseService.signOut();
      if (mounted) {
        Navigator.pop(context);
        widget.onStateChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = SupabaseService.currentUser;
    final meta = user?.userMetadata;
    final avatarUrl = meta?['avatar_url'] as String? ?? meta?['picture'] as String?;
    final fullName = (meta?['full_name'] ?? meta?['name']) as String? ?? user?.email?.split('@').first;
    final email = user?.email;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Account & Orders',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // User Card or Google Sign-In Card
          if (user != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  if (avatarUrl != null && avatarUrl.isNotEmpty)
                    CircleAvatar(
                      radius: 26,
                      backgroundImage: NetworkImage(avatarUrl),
                    )
                  else
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: theme.primaryColor,
                      child: Text(
                        (fullName?.isNotEmpty == true ? fullName![0].toUpperCase() : 'U'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName ?? 'Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email ?? '',
                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Logged in via Google',
                                style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to Raj Electricals Store',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in with Google to view order history, track deliveries, and save your delivery details.',
                    style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodySmall?.color),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isGoogleSigningIn ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: theme.cardColor,
                        side: BorderSide(color: theme.dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isGoogleSigningIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/120px-Google_%22G%22_logo.svg.png',
                                  width: 18,
                                  height: 18,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, size: 18, color: Colors.blue),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Sign In with Google',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Menu Options
          _MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'My Orders',
            subtitle: 'Order history, receipts & invoices',
            onTap: () {
              Navigator.pop(context);
              ShopAccountSheets.showMyOrdersSheet(
                context,
                businessId: widget.businessId,
                businessName: widget.businessName,
                businessPhone: widget.businessPhone,
                businessWhatsapp: widget.businessWhatsapp,
              );
            },
          ),
          const SizedBox(height: 8),

          _MenuTile(
            icon: Icons.local_shipping_outlined,
            title: 'Track Order',
            subtitle: 'Live order timeline and progress tracking',
            onTap: () {
              Navigator.pop(context);
              ShopAccountSheets.showTrackOrderSheet(
                context,
                businessId: widget.businessId,
                businessName: widget.businessName,
                businessPhone: widget.businessPhone,
                businessWhatsapp: widget.businessWhatsapp,
              );
            },
          ),
          const SizedBox(height: 8),

          _MenuTile(
            icon: Icons.location_on_outlined,
            title: 'Saved Delivery Details',
            subtitle: 'Manage default name, phone & shipping address',
            onTap: () {
              Navigator.pop(context);
              ShopAccountSheets.showProfileSheet(context, onSaved: widget.onStateChanged);
            },
          ),

          if (user != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18, color: Colors.red),
              label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: theme.primaryColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.dividerColor),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 2. Track Order Sheet
// -------------------------------------------------------------
class _TrackOrderSheet extends StatefulWidget {
  final String? businessId;
  final String businessName;
  final String? businessPhone;
  final String? businessWhatsapp;
  final String? initialQuery;

  const _TrackOrderSheet({
    required this.businessId,
    required this.businessName,
    this.businessPhone,
    this.businessWhatsapp,
    this.initialQuery,
  });

  @override
  State<_TrackOrderSheet> createState() => _TrackOrderSheetState();
}

class _TrackOrderSheetState extends State<_TrackOrderSheet> {
  final TextEditingController _queryCtrl = TextEditingController();
  bool _isSearching = false;
  Map<String, dynamic>? _orderResult;
  String? _errorMessage;
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadRecentOrders();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _queryCtrl.text = widget.initialQuery!.trim();
      _searchOrder(widget.initialQuery!.trim());
    }
  }

  Future<void> _loadRecentOrders() async {
    final list = await ShopCustomerStorage.loadLocalOrders();
    if (mounted) setState(() => _recentOrders = list);
  }

  Future<void> _searchOrder(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _orderResult = null;
    });

    try {
      final bizId = widget.businessId ?? '';
      final res = await SupabaseService.trackShopOrder(query: query.trim(), businessId: bizId);
      if (res != null) {
        if (mounted) setState(() => _orderResult = res);
      } else {
        // Fallback: check if local order exists
        final localMatch = _recentOrders.firstWhere(
          (o) => o['id'].toString() == query.trim() || (o['tracking_token'] ?? '').toString() == query.trim(),
          orElse: () => {},
        );
        if (localMatch.isNotEmpty && mounted) {
          setState(() => _orderResult = localMatch);
        } else if (mounted) {
          setState(() {
            _errorMessage = 'No order found matching "${query.trim()}". Please verify the Order ID or Tracking Token.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to fetch order: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Track Order',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter Order ID (e.g. 1014) or Token',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: _searchOrder,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isSearching ? null : () => _searchOrder(_queryCtrl.text),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSearching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Track'),
              ),
            ],
          ),

          // Recent order chips
          if (_recentOrders.isNotEmpty && _orderResult == null) ...[
            const SizedBox(height: 12),
            Text('Recent orders from this device:', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _recentOrders.take(6).map((o) {
                  final oid = o['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('#$oid • ₹${((o['total_amount'] as num?) ?? 0).toStringAsFixed(0)}'),
                      avatar: const Icon(Icons.history, size: 14),
                      onPressed: () {
                        _queryCtrl.text = oid.toString();
                        _searchOrder(oid.toString());
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: _buildTrackingContent(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingContent(ThemeData theme) {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_orderResult == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.local_shipping_outlined, size: 56, color: theme.disabledColor),
              const SizedBox(height: 12),
              Text(
                'Track any order with Order ID or Token',
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the Order ID from your receipt or check your order history.',
                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final o = _orderResult!;
    final orderId = o['id'] ?? o['sale_id'] ?? 'N/A';
    final token = o['tracking_token'] ?? '';
    final status = (o['status'] ?? 'pending').toString().toLowerCase();
    final total = ((o['total_amount'] as num?) ?? 0.0).toDouble();
    final customerName = o['customer_name'] ?? 'Walk-in Customer';
    final customerPhone = o['customer_phone'];
    final createdAtStr = o['created_at'];
    DateTime? createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
    final dateStr = createdAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt) : '';

    final items = (o['shop_order_items'] as List?) ?? (o['items'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Order Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 6),
              if (dateStr.isNotEmpty)
                Text('Placed on: $dateStr', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
              if (token.isNotEmpty)
                Text('Token: $token', style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('₹${total.toStringAsFixed(2)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: theme.primaryColor)),
                ],
              ),
              if (customerName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Customer: $customerName${customerPhone != null ? " • $customerPhone" : ""}', style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Live Timeline
        Text('Order Status Timeline', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildTimelineWidget(status, dateStr),

        const SizedBox(height: 20),

        // Items List
        if (items.isNotEmpty) ...[
          Text('Items in Order (${items.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
              itemBuilder: (context, idx) {
                final it = items[idx];
                final pName = it['name'] ?? (it['products']?['name']) ?? 'Product Item';
                final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                final price = ((it['price_per_unit'] ?? it['price']) as num?)?.toDouble() ?? 0.0;
                return ListTile(
                  dense: true,
                  title: Text(pName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('Qty: $qty × ₹${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                  trailing: Text('₹${(qty * price).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Store Help Button
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  final phone = widget.businessWhatsapp ?? widget.businessPhone ?? '8076635513';
                  final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                  final msg = Uri.encodeComponent('Hi ${widget.businessName}, I would like an update on my Order #$orderId');
                  launchUrl(Uri.parse('https://wa.me/91$cleanPhone?text=$msg'), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.green),
                label: const Text('Chat with Store', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.green),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final receiptItems = items.map((it) {
                    final pName = it['name'] ?? (it['products']?['name']) ?? 'Product Item';
                    final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                    final price = ((it['price_per_unit'] ?? it['price']) as num?)?.toDouble() ?? 0.0;
                    return ReceiptItem(name: pName, quantity: qty, pricePerUnit: price);
                  }).toList();

                  final receipt = ReceiptData(
                    saleId: orderId.toString(),
                    customerName: customerName,
                    customerPhone: customerPhone,
                    items: receiptItems,
                    subTotal: total,
                    discount: 0,
                    finalTotal: total,
                    paymentMethod: 'UPI',
                    saleDate: createdAt ?? DateTime.now(),
                    status: status,
                  );
                  await ReceiptService.shareReceiptPdf(receipt);
                },
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('View Invoice'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineWidget(String status, String dateStr) {
    if (status == 'cancelled') {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This order was cancelled. If you already made a payment, please contact the store for a refund.',
                style: TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final isConfirmed = status == 'confirmed' || status == 'dispatched' || status == 'delivered' || status == 'completed';
    final isDispatched = status == 'dispatched' || status == 'delivered' || status == 'completed';
    final isDelivered = status == 'delivered' || status == 'completed';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _TimelineStep(
            title: 'Order Placed',
            subtitle: dateStr.isNotEmpty ? dateStr : 'Order registered in system',
            isCompleted: true,
            isCurrent: status == 'payment_pending' || status == 'pending',
          ),
          _TimelineStep(
            title: 'Payment Verification',
            subtitle: isConfirmed ? 'Payment confirmed by store' : 'Verification in progress by merchant',
            isCompleted: isConfirmed,
            isCurrent: status == 'confirmed',
          ),
          _TimelineStep(
            title: 'Dispatched / Prepared',
            subtitle: isDispatched ? 'Package dispatched from store' : 'Preparing order items',
            isCompleted: isDispatched,
            isCurrent: status == 'dispatched',
          ),
          _TimelineStep(
            title: 'Delivered',
            subtitle: isDelivered ? 'Delivered successfully' : 'Pending delivery',
            isCompleted: isDelivered,
            isCurrent: isDelivered,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'confirmed':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade700;
        label = 'Confirmed';
        break;
      case 'dispatched':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purple.shade700;
        label = 'Dispatched';
        break;
      case 'delivered':
      case 'completed':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade700;
        label = 'Delivered';
        break;
      case 'cancelled':
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red.shade700;
        label = 'Cancelled';
        break;
      default:
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange.shade800;
        label = 'Pending Verification';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    this.isCurrent = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = isCompleted ? Colors.green : (isCurrent ? Colors.orange : theme.disabledColor);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step circle and vertical connector line
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green : (isCurrent ? Colors.orange.withValues(alpha: 0.2) : theme.dividerColor.withValues(alpha: 0.3)),
                  shape: BoxShape.circle,
                  border: Border.all(color: activeColor, width: 2),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : (isCurrent
                          ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))
                          : null),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted ? Colors.green : theme.dividerColor.withValues(alpha: 0.3),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Label
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: isCompleted || isCurrent ? theme.textTheme.titleMedium?.color : theme.disabledColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: theme.textTheme.bodySmall?.color),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 3. My Orders Sheet
// -------------------------------------------------------------
class _MyOrdersSheet extends StatefulWidget {
  final String? businessId;
  final String businessName;
  final String? businessPhone;
  final String? businessWhatsapp;

  const _MyOrdersSheet({
    required this.businessId,
    required this.businessName,
    this.businessPhone,
    this.businessWhatsapp,
  });

  @override
  State<_MyOrdersSheet> createState() => _MyOrdersSheetState();
}

class _MyOrdersSheetState extends State<_MyOrdersSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadAllOrders();
  }

  Future<void> _loadAllOrders() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> all = [];
    final user = SupabaseService.currentUser;

    if (user != null && widget.businessId != null) {
      final remote = await SupabaseService.getShopOrdersForCustomer(
        customerId: user.id,
        businessId: widget.businessId!,
      );
      all.addAll(remote);
    }

    // Merge with local device orders
    final local = await ShopCustomerStorage.loadLocalOrders();
    for (var l in local) {
      final exists = all.any((r) => r['id'] == l['id'] || (r['tracking_token'] != null && r['tracking_token'] == l['tracking_token']));
      if (!exists) {
        all.add(l);
      }
    }

    all.sort((a, b) {
      final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
      final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });

    if (mounted) {
      setState(() {
        _orders = all;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Orders',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_bag_outlined, size: 64, color: theme.disabledColor),
                            const SizedBox(height: 12),
                            const Text('No orders yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('Your placed orders and receipts will appear here.', style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAllOrders,
                        child: ListView.separated(
                          itemCount: _orders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final o = _orders[idx];
                            final orderId = o['id'] ?? o['sale_id'] ?? 'N/A';
                            final token = o['tracking_token'] ?? '';
                            final status = (o['status'] ?? 'pending').toString().toLowerCase();
                            final total = ((o['total_amount'] as num?) ?? 0.0).toDouble();
                            final createdAtStr = o['created_at'];
                            DateTime? createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
                            final dateStr = createdAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt) : '';
                            final items = (o['shop_order_items'] as List?) ?? (o['items'] as List?) ?? [];

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      _buildStatusBadge(status),
                                    ],
                                  ),
                                  if (dateStr.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(dateStr, style: TextStyle(fontSize: 11.5, color: theme.textTheme.bodySmall?.color)),
                                    ),
                                  const Divider(height: 16),
                                  Text(
                                    items.isNotEmpty
                                        ? '${items.first['name'] ?? (items.first['products']?['name']) ?? "Item"}${items.length > 1 ? " + ${items.length - 1} more" : ""}'
                                        : 'Ordered items',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Total: ₹${total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.primaryColor)),
                                      Row(
                                        children: [
                                          OutlinedButton(
                                            onPressed: () {
                                              ShopAccountSheets.showTrackOrderSheet(
                                                context,
                                                businessId: widget.businessId,
                                                businessName: widget.businessName,
                                                businessPhone: widget.businessPhone,
                                                businessWhatsapp: widget.businessWhatsapp,
                                                initialQuery: token.isNotEmpty ? token : orderId.toString(),
                                              );
                                            },
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            child: const Text('Track', style: TextStyle(fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.tonal(
                                            onPressed: () async {
                                              final receiptItems = items.map((it) {
                                                final pName = it['name'] ?? (it['products']?['name']) ?? 'Product';
                                                final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                                                final price = ((it['price_per_unit'] ?? it['price']) as num?)?.toDouble() ?? 0.0;
                                                return ReceiptItem(name: pName, quantity: qty, pricePerUnit: price);
                                              }).toList();

                                              final receipt = ReceiptData(
                                                saleId: orderId.toString(),
                                                customerName: o['customer_name'] ?? 'Customer',
                                                customerPhone: o['customer_phone'],
                                                items: receiptItems,
                                                subTotal: total,
                                                discount: 0,
                                                finalTotal: total,
                                                paymentMethod: 'UPI',
                                                saleDate: createdAt ?? DateTime.now(),
                                                status: status,
                                              );
                                              await ReceiptService.shareReceiptPdf(receipt);
                                            },
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            child: const Text('Invoice', style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case 'confirmed':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade700;
        text = 'Confirmed';
        break;
      case 'dispatched':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purple.shade700;
        text = 'Dispatched';
        break;
      case 'delivered':
      case 'completed':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade700;
        text = 'Delivered';
        break;
      case 'cancelled':
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red.shade700;
        text = 'Cancelled';
        break;
      default:
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange.shade800;
        text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );
  }
}

// -------------------------------------------------------------
// 4. Delivery Profile / Address Sheet
// -------------------------------------------------------------
class _ProfileSheet extends StatefulWidget {
  final VoidCallback? onSaved;

  const _ProfileSheet({this.onSaved});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  bool _isSaving = false;
  bool _isDetectingLocation = false;
  String? _latitude;
  String? _longitude;
  String? _locationStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await ShopCustomerStorage.loadSavedProfile();
    if (mounted) {
      setState(() {
        _nameCtrl.text = p['name'] ?? '';
        _phoneCtrl.text = p['phone'] ?? '';
        _houseCtrl.text = p['house'] ?? '';
        _streetCtrl.text = p['street'] ?? '';
        _landmarkCtrl.text = p['landmark'] ?? '';
        _cityCtrl.text = p['city'] ?? '';
        _stateCtrl.text = p['state'] ?? '';
        _pincodeCtrl.text = p['pincode'] ?? '';
        _latitude = p['latitude']?.isNotEmpty == true ? p['latitude'] : null;
        _longitude = p['longitude']?.isNotEmpty == true ? p['longitude'] : null;
      });
    }
  }

  Future<void> _detectLocation() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isDetectingLocation = true;
      _locationStatusMessage = null;
    });

    try {
      // 1. Check & Request Permissions FIRST so the OS prompts the user
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isDetectingLocation = false;
              _locationStatusMessage = 'Location permission was denied.';
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isDetectingLocation = false;
            _locationStatusMessage =
                'Location permission permanently denied in device settings.';
          });
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text(
                'Location permission is permanently disabled for this app. Please enable it in App Settings to use GPS auto-fill.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 2. Check if Location Services (GPS) is turned on
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isDetectingLocation = false;
            _locationStatusMessage =
                'GPS/Location is turned off on your device. Please turn it on.';
          });
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.location_off_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('GPS is Turned Off'),
                ],
              ),
              content: const Text(
                'Device GPS / Location is currently turned off. Please turn it on in settings to auto-fill your delivery address.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openLocationSettings();
                  },
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Turn On Location'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 3. Fetch GPS position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      _latitude = position.latitude.toString();
      _longitude = position.longitude.toString();

      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final streetParts = [
          place.street,
          place.subLocality,
          place.thoroughfare,
        ]
            .where((s) =>
                s != null &&
                s.trim().isNotEmpty &&
                s != place.postalCode &&
                s != place.locality)
            .toSet()
            .toList();

        setState(() {
          if (place.postalCode != null && place.postalCode!.isNotEmpty) {
            _pincodeCtrl.text = place.postalCode!;
          }
          if (streetParts.isNotEmpty) {
            _streetCtrl.text = streetParts.join(', ');
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            _cityCtrl.text = place.locality!;
          } else if (place.subAdministrativeArea != null &&
              place.subAdministrativeArea!.isNotEmpty) {
            _cityCtrl.text = place.subAdministrativeArea!;
          }
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty) {
            _stateCtrl.text = place.administrativeArea!;
          }
          _locationStatusMessage =
              'Auto-filled from GPS. Please check and add your Flat / House number.';
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatusMessage = 'Could not detect location: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await ShopCustomerStorage.saveProfile(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      house: _houseCtrl.text,
      street: _streetCtrl.text,
      landmark: _landmarkCtrl.text,
      city: _cityCtrl.text,
      state: _stateCtrl.text,
      pincode: _pincodeCtrl.text,
      latitude: _latitude,
      longitude: _longitude,
    );
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery details saved successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Delivery Details', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),

            // GPS Location Detection Button
            OutlinedButton.icon(
              onPressed: _isDetectingLocation ? null : _detectLocation,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  width: 1.2,
                ),
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.05),
              ),
              icon: _isDetectingLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.my_location_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
              label: Text(
                _isDetectingLocation ? 'Detecting location from GPS...' : 'Use Current Location (GPS Auto-Fill)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (_locationStatusMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationStatusMessage!,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pin_drop_outlined, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'GPS Pin Captured (Lat: ${double.tryParse(_latitude!)?.toStringAsFixed(4)}, Lng: ${double.tryParse(_longitude!)?.toStringAsFixed(4)})',
                        style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Phone / WhatsApp Number',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _houseCtrl,
                    decoration: InputDecoration(
                      labelText: 'Flat / House No.',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pincodeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: InputDecoration(
                      labelText: 'Pincode',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _streetCtrl,
              decoration: InputDecoration(
                labelText: 'Street / Colony / Area',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _stateCtrl,
                    decoration: InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Delivery Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}


