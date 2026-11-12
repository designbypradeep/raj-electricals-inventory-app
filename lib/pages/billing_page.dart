import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/supabase_models.dart' as supa;
import '../services/supabase_service.dart';
import '../widgets/page_header.dart';
import '../data/app_database.dart';

class BillingPage extends StatefulWidget {
  final AppDatabase? db;
  const BillingPage({super.key, this.db});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  bool _isLoading = true;
  supa.SubscriptionInfo? _subInfo;
  int _productCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBillingData();
  }

  Future<void> _loadBillingData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final info = await SupabaseService.getSubscriptionInfo();
      int count = 0;
      try {
        final products = await SupabaseService.getProducts();
        count = products.length;
      } catch (_) {
        if (widget.db != null) {
          final local = await widget.db!.getAllProducts();
          count = local.length;
        }
      }

      if (mounted) {
        setState(() {
          _subInfo = info;
          _productCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openUpgradeUrl() async {
    final uri = Uri.parse('https://inventoza.com/billing');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _loadBillingData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Billing & Subscription',
                  description: 'Monitor your plan limits, trial status, and usage quotas',
                  icon: '💳',
                  showBackButton: true,
                  wrapInSafeArea: true,
                  breadcrumbs: [
                    PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                    if (MediaQuery.of(context).size.width >= 450)
                      PageHeaderBreadcrumb(
                        label: 'Billing & Plans',
                        icon: '💳',
                        current: true,
                      ),
                  ],
                  stats: [
                    PageHeaderStat(
                      label: 'Active Plan',
                      value: _subInfo?.planName ?? 'Trial',
                      description: _subInfo?.status ?? 'Active',
                    ),
                    PageHeaderStat(
                      label: 'Products Quota',
                      value: '$_productCount / ${_subInfo?.maxProducts ?? 500}',
                      description: 'Catalog items used',
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width < 480 ? 14 : 20,
                    vertical: 16,
                  ),
                  child: _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _errorMessage != null
                          ? _buildErrorState()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCurrentPlanHero(cs, isDark),
                                const SizedBox(height: 20),
                                _buildQuotaGauges(cs, isDark),
                                const SizedBox(height: 20),
                                _buildFeatureChecklist(cs, isDark),
                                const SizedBox(height: 24),
                                _buildUpgradeTiers(cs, isDark),
                                const SizedBox(height: 32),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not load billing details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadBillingData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanHero(ColorScheme cs, bool isDark) {
    final sub = _subInfo;
    final planName = sub?.planName ?? '14-Day Free Trial';
    final isTrial = sub?.isTrial ?? true;
    final daysRemaining = sub?.daysRemaining ?? 14;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withAlpha(isDark ? 40 : 25),
            cs.secondary.withAlpha(isDark ? 30 : 15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withAlpha(60), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withAlpha(isDark ? 30 : 15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withAlpha(77)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stars, size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'CURRENT PLAN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isTrial ? Colors.amber : Colors.green).withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isTrial ? Colors.amber : Colors.green).withAlpha(77),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isTrial ? Colors.amber : Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isTrial ? 'TRIAL ACTIVE' : 'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isTrial ? Colors.amber : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            planName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            isTrial
                ? 'Your trial includes full access to all standard POS & Inventory features.'
                : 'Your business subscription is active and in good standing.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(180),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                isTrial
                    ? '$daysRemaining days remaining in your trial'
                    : 'Renews automatically on monthly cycle',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaGauges(ColorScheme cs, bool isDark) {
    final maxProd = _subInfo?.maxProducts ?? 500;
    final prodPercent = (maxProd > 0) ? (_productCount / maxProd).clamp(0.0, 1.0) : 0.0;
    final maxUsers = _subInfo?.maxUsers ?? 2;
    final maxStorage = _subInfo?.maxStorageImages ?? 100;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                'Resource Quotas & Usage',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProgressRow(
            label: 'Products in Catalog',
            used: _productCount,
            total: maxProd,
            percent: prodPercent,
            cs: cs,
          ),
          const Divider(height: 24),
          _buildProgressRow(
            label: 'Staff User Seats',
            used: 1,
            total: maxUsers,
            percent: (1 / maxUsers).clamp(0.0, 1.0),
            cs: cs,
          ),
          const Divider(height: 24),
          _buildProgressRow(
            label: 'Product Image Storage',
            used: (_productCount * 0.1).round(),
            total: maxStorage,
            percent: ((_productCount * 0.1) / maxStorage).clamp(0.0, 1.0),
            unit: 'MB',
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow({
    required String label,
    required num used,
    required num total,
    required double percent,
    required ColorScheme cs,
    String unit = '',
  }) {
    final isNearLimit = percent >= 0.85;
    final barColor = isNearLimit ? Colors.orange : cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              '$used / $total $unit',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureChecklist(ColorScheme cs, bool isDark) {
    final features = [
      {'title': 'Real-time Stock Tracking & Alerts', 'included': true},
      {'title': 'Point of Sale (POS) Billing & Invoices', 'included': true},
      {'title': 'Customer Storefront & UPI QR Checkout', 'included': true},
      {'title': 'Financial Analytics & Profit Reports', 'included': _subInfo?.hasFeature('reports') ?? true},
      {'title': 'Customer Returns & Replacements Ledger', 'included': _subInfo?.hasFeature('returns') ?? true},
      {'title': 'AI Camera Barcode & Smart Scanner', 'included': _subInfo?.hasFeature('ai') ?? true},
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                'Plan Entitlements',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...features.map((f) {
            final inc = f['included'] as bool;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    inc ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                    size: 18,
                    color: inc ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f['title'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        color: inc
                            ? Theme.of(context).textTheme.bodyMedium?.color
                            : Colors.grey,
                        fontWeight: inc ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUpgradeTiers(ColorScheme cs, bool isDark) {
    final plans = [
      {
        'name': 'Standard',
        'price': '₹499',
        'subtitle': 'For small retail stores',
        'badge': 'STARTER',
        'features': ['500 Products', '2 Staff Members', 'POS & Invoicing', 'UPI Storefront'],
      },
      {
        'name': 'Premium',
        'price': '₹999',
        'subtitle': 'For growing businesses',
        'badge': 'POPULAR',
        'isPopular': true,
        'features': [
          '2,500 Products',
          '5 Staff Members',
          'Advanced Financial Analytics',
          'Customer Returns & Replacements',
          'AI Camera Scanner',
        ],
      },
      {
        'name': 'Enterprise',
        'price': '₹1,999',
        'subtitle': 'For multi-location stores',
        'badge': 'SCALE',
        'features': [
          'Unlimited Products',
          '15 Staff Members',
          'Priority Support',
          'Multi-location Sync',
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.upgrade_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            const Text(
              'Available Subscription Tiers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...plans.map((p) => _buildPlanCard(p, cs, isDark)),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, ColorScheme cs, bool isDark) {
    final isPopular = plan['isPopular'] == true;
    final name = plan['name'] as String;
    final price = plan['price'] as String;
    final subtitle = plan['subtitle'] as String;
    final features = plan['features'] as List<String>;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? cs.primary : Theme.of(context).dividerColor.withAlpha(40),
          width: isPopular ? 2 : 1,
        ),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: cs.primary.withAlpha(26),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(160),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price/mo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  if (isPopular)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'POPULAR',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map(
            (feat) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.check, size: 15, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(feat, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                _openUpgradeUrl();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isPopular ? cs.primary : cs.surfaceContainerHighest,
                foregroundColor: isPopular ? cs.onPrimary : cs.onSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Upgrade to $name',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
