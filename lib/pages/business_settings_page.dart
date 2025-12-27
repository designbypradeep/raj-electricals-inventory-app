import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../models/supabase_models.dart';
import '../services/theme_controller.dart';
import 'package:local_auth/local_auth.dart';
import '../services/security_service.dart';
import '../theme/ui_tokens.dart';

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _gstNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _upiVpaController = TextEditingController();

  // App-managed static UPI VPA (no Supabase dependency)
  final String _staticUpiVpa = 'pradeepsupergalaxy12@okicici';

  String? _selectedBusinessType;
  String? _selectedState;
  File? _logoFile;
  String? _logoUrl;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  // Brand color drafts for live preview (null = use defaults)
  Color? _primaryDraft;
  Color? _secondaryDraft;

  // Biometric security setting
  final LocalAuthentication _localAuth = LocalAuthentication();
  final SecurityService _securityService = SecurityService();
  bool _biometricSupported = false;
  bool _requireBiometric = false;
  bool _loadingBiometric = true;
  bool _hasBiometricsEnrolled = false;
  List<BiometricType> _availableBiometrics = const [];

  final List<String> _businessTypes = [
    'Retail Store',
    'Wholesale Business',
    'Manufacturing',
    'Service Provider',
    'Trading Company',
    'Electronics Store',
    'Hardware Store',
    'Grocery Store',
    'Pharmacy',
    'Textile Business',
    'Automobile Parts',
    'Construction Materials',
    'Other',
  ];

  final List<String> _indianStates = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Andaman and Nicobar Islands',
    'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi',
    'Jammu and Kashmir',
    'Ladakh',
    'Lakshadweep',
    'Puducherry',
  ];

  // Slug Logic
  final TextEditingController _slugController = TextEditingController();
  final RegExp _slugRegex = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  String? _loadedSlug;
  final bool _validatingSlug = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessProfile();
    // Initialize drafts from saved custom colors
    final tc = ThemeController.instance;
    _primaryDraft = tc.savedPrimary;
    _secondaryDraft = tc.savedSecondary;
    _initBiometricSetting();
  }

  // UPI VPA validation is no longer required here since it is app-managed

  // ===================== Shop Access Section =====================
  Widget _buildShopAccessSection() {
    final slug = _loadedSlug;
    final hasSlug = slug != null && slug.isNotEmpty;
    // Using the custom scheme as defined in AndroidManifest/Runner
    final shopLink = hasSlug ? 'myshop://store/$slug' : 'Not set';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Shop Access', Icons.storefront),
            const SizedBox(height: 24),

            if (!hasSlug)
              Center(
                child: Column(
                  children: [
                    const Text('No Shop Code set.'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _editSlug,
                      child: const Text('Create Shop Code'),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  // Shop Code Display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SHOP CODE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              slug,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _editSlug,
                          tooltip: 'Edit Shop Code',
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: slug));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Shop Code copied')),
                            );
                          },
                          tooltip: 'Copy Code',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR & Link Row
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmall = constraints.maxWidth < 500;
                      return Flex(
                        direction: isSmall ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: isSmall
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          // QR Code
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: QrImageView(
                              data: 'myshop://store/$slug',
                              version: QrVersions.auto,
                              size: 140.0,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          if (isSmall)
                            const SizedBox(height: 24)
                          else
                            const SizedBox(width: 24),

                          // Link Actions
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Share this link with customers:',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          shopLink,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: shopLink),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Link copied'),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.copy, size: 18),
                                        label: const Text('Copy Link'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Share.share(
                                            'Check out my shop: $shopLink',
                                          );
                                        },
                                        icon: const Icon(Icons.share, size: 18),
                                        label: const Text('Share'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ===================== Brand Colors (Live Preview) =====================
  Widget _buildBrandColorsSection() {
    final tc = ThemeController.instance;
    final effectivePrimary =
        _primaryDraft ?? tc.savedPrimary ?? const Color(0xFFC1441E);
    final effectiveSecondary =
        _secondaryDraft ?? tc.savedSecondary ?? const Color(0xFF118AB2);

    final primaryPalette = <Color>[
      const Color(0xFFC1441E), // Terracotta (default)
      const Color(0xFFE07B39), // Terracotta variant
      const Color(0xFFDB4437), // Red
      const Color(0xFF8E44AD), // Purple
      const Color(0xFF1D4ED8), // Blue
      const Color(0xFF16A34A), // Green
      const Color(0xFFF59E0B), // Amber
    ];

    final secondaryPalette = <Color>[
      const Color(0xFF118AB2), // Blue (default)
      const Color(0xFF5EC2E8), // Light blue (dark-mode default)
      const Color(0xFF10B981), // Emerald
      const Color(0xFF6366F1), // Indigo
      const Color(0xFFEC4899), // Pink
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF14B8A6), // Teal
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Brand Colors', Icons.palette),
            const SizedBox(height: 16),

            // Preview Strip
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 480;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges row (wrap to avoid overflow)
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _buildColorBadge(
                              'Primary',
                              effectivePrimary,
                              onTap: () => _onPickPrimary(effectivePrimary),
                            ),
                            _buildColorBadge(
                              'Secondary',
                              effectiveSecondary,
                              onTap: () => _onPickSecondary(effectiveSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Buttons wrap (stack or sit side-by-side as space allows)
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: effectivePrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    UITokens.radius,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('Primary Action'),
                            ),
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: effectiveSecondary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    UITokens.radius,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('Secondary'),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                  // Wide layout
                  return Row(
                    children: [
                      _buildColorBadge(
                        'Primary',
                        effectivePrimary,
                        onTap: () => _onPickPrimary(effectivePrimary),
                      ),
                      const SizedBox(width: 12),
                      _buildColorBadge(
                        'Secondary',
                        effectiveSecondary,
                        onTap: () => _onPickSecondary(effectiveSecondary),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: effectivePrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              UITokens.radius,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Primary Action'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: effectiveSecondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              UITokens.radius,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Secondary'),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 20),
            Text(
              'Primary Color',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _buildPaletteRow(
              primaryPalette,
              _primaryDraft ??
                  ThemeController.instance.savedPrimary ??
                  const Color(0xFFC1441E),
              isPrimary: true,
            ),

            const SizedBox(height: 20),
            Text(
              'Secondary Color',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _buildPaletteRow(
              secondaryPalette,
              _secondaryDraft ??
                  ThemeController.instance.savedSecondary ??
                  const Color(0xFF118AB2),
              isPrimary: false,
            ),

            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 480;
                if (isNarrow) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: [
                      OutlinedButton(
                        onPressed: _onPreviewCancel,
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: _onResetDefaults,
                        child: const Text('Reset to Defaults'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _onPreviewSave,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              UITokens.radius,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    OutlinedButton(
                      onPressed: _onPreviewCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _onResetDefaults,
                      child: const Text('Reset to Defaults'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _onPreviewSave,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(UITokens.radius),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaletteRow(
    List<Color> palette,
    Color selected, {
    required bool isPrimary,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in palette)
          GestureDetector(
            onTap: () =>
                isPrimary ? _onPickPrimary(color) : _onPickSecondary(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(UITokens.radius),
                border: Border.all(
                  color: color.value == selected.value
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).dividerColor,
                  width: color.value == selected.value ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).shadowColor.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildColorBadge(String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPickPrimary(Color color) {
    _primaryDraft = color;
    ThemeController.instance.previewColors(
      primary: _primaryDraft,
      secondary: _secondaryDraft,
    );
    setState(() {});
  }

  void _onPickSecondary(Color color) {
    _secondaryDraft = color;
    ThemeController.instance.previewColors(
      primary: _primaryDraft,
      secondary: _secondaryDraft,
    );
    setState(() {});
  }

  Future<void> _onPreviewSave() async {
    await ThemeController.instance.saveColors(
      primary: _primaryDraft,
      secondary: _secondaryDraft,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Brand colors saved.'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _onPreviewCancel() {
    final tc = ThemeController.instance;
    _primaryDraft = tc.savedPrimary;
    _secondaryDraft = tc.savedSecondary;
    tc.clearPreview();
    setState(() {});
  }

  Future<void> _onResetDefaults() async {
    await ThemeController.instance.resetToDefaults();
    _primaryDraft = null;
    _secondaryDraft = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Brand colors reset to defaults.'),
        backgroundColor: Theme.of(context).colorScheme.secondary,
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _gstNumberController.dispose();
    _panNumberController.dispose();
    _upiVpaController.dispose();
    super.dispose();
  }

  Future<void> _loadBusinessProfile() async {
    setState(() {});

    try {
      final businessProfile = await SupabaseService.getBusinessProfile();

      if (businessProfile != null && mounted) {
        setState(() {
          _businessNameController.text = businessProfile.businessName ?? '';
          _selectedBusinessType = businessProfile.businessType;
          _descriptionController.text = businessProfile.description ?? '';
          _phoneController.text = businessProfile.phone ?? '';
          _emailController.text = businessProfile.email ?? '';
          _websiteController.text = businessProfile.website ?? '';
          _addressController.text = businessProfile.address ?? '';
          _cityController.text = businessProfile.city ?? '';
          _selectedState = businessProfile.state;
          _postalCodeController.text = businessProfile.postalCode ?? '';
          _gstNumberController.text = businessProfile.gstNumber ?? '';
          _panNumberController.text = businessProfile.panNumber ?? '';
          _logoUrl = businessProfile.logoUrl;
          _loadedSlug = businessProfile.slug;
          _upiVpaController.text = _staticUpiVpa;
        });
      }
    } catch (e) {
      _showError('Failed to load business profile: $e');
    } finally {
      setState(() {});
    }
  }

  Future<void> _editSlug() async {
    _slugController.text = _loadedSlug ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Shop Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This code is used for your shop link and QR code.\n'
              'Changing it will invalidate old links.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _slugController,
              decoration: const InputDecoration(
                labelText: 'Shop Code',
                hintText: 'e.g. raj-electricals',
                border: OutlineInputBorder(),
                prefixText: 'myshop://store/',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _slugController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _loadedSlug) {
      if (!_slugRegex.hasMatch(result)) {
        _showError(
          'Invalid Shop Code. Use lowercase letters, numbers, and hyphens only.',
        );
        return;
      }

      setState(() {
        _isSaving = true;
      });

      try {
        final currentProfile = await SupabaseService.getBusinessProfile();
        if (currentProfile != null) {
          // Check uniqueness (handled by DB constraint, but nice to check first if possible,
          // but for now relying on DB error or success)
          await SupabaseService.updateBusinessProfile({'slug': result});

          setState(() {
            _loadedSlug = result;
            _successMessage = 'Shop Code updated successfully!';
          });

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _successMessage = null);
          });
        }
      } catch (e) {
        if (e.toString().contains('unique constraint')) {
          _showError('This Shop Code is already taken. Please choose another.');
        } else {
          _showError('Failed to update Shop Code: $e');
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickLogo() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        final File file = File(image.path);
        final int fileSize = await file.length();

        if (fileSize > 2 * 1024 * 1024) {
          // 2MB limit
          _showError('Logo file size must be less than 2MB');
          return;
        }

        setState(() {
          _logoFile = file;
          _errorMessage = null;
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoUrl = null;
    });
  }

  String _formatPhoneNumber(String value) {
    String digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('91') && digits.length > 2) {
      digits = '+91 ${digits.substring(2)}';
    } else if (value.startsWith('+91')) {
      digits = '+91 ${digits.substring(2)}';
    } else if (digits.length == 10) {
      digits = '+91 $digits';
    } else if (digits.length > 10 && !value.startsWith('+91')) {
      digits = '+91 ${digits.substring(digits.length - 10)}';
    }

    return digits;
  }

  bool _validateForm() {
    if (_businessNameController.text.trim().isEmpty) {
      _showError('Business name is required');
      return false;
    }

    final email = _emailController.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showError('Please enter a valid email address');
      return false;
    }

    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^\+91\s\d{10}$').hasMatch(phone)) {
      _showError(
        'Please enter a valid Indian phone number (+91 followed by 10 digits)',
      );
      return false;
    }

    final website = _websiteController.text.trim();
    if (website.isNotEmpty && !RegExp(r'^https?://.+').hasMatch(website)) {
      _showError('Website URL must start with http:// or https://');
      return false;
    }

    final gst = _gstNumberController.text.trim();
    if (gst.isNotEmpty &&
        !RegExp(
          r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
        ).hasMatch(gst)) {
      _showError('Please enter a valid GST number (15 characters)');
      return false;
    }

    final pan = _panNumberController.text.trim();
    if (pan.isNotEmpty &&
        !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(pan)) {
      _showError('Please enter a valid PAN number (10 characters)');
      return false;
    }

    // UPI VPA is managed by the app; no validation here

    return true;
  }

  Future<void> _saveBusinessProfile() async {
    if (!_validateForm()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Create business profile data
      final profileData = {
        'business_name': _businessNameController.text.trim(),
        'business_type': _selectedBusinessType,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'website': _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'state': _selectedState,
        'postal_code': _postalCodeController.text.trim().isEmpty
            ? null
            : _postalCodeController.text.trim(),
        'gst_number': _gstNumberController.text.trim().isEmpty
            ? null
            : _gstNumberController.text.trim().toUpperCase(),
        'pan_number': _panNumberController.text.trim().isEmpty
            ? null
            : _panNumberController.text.trim().toUpperCase(),
        'logo_url': _logoUrl,
      };

      // Check if business profile exists
      final existingProfile = await SupabaseService.getBusinessProfile();

      BusinessProfile? result;
      if (existingProfile != null) {
        // Update existing profile
        result = await SupabaseService.updateBusinessProfile(profileData);
      } else {
        // Create new profile
        result = await SupabaseService.createBusinessProfile(profileData);
      }

      if (result != null && mounted) {
        setState(() {
          _successMessage = existingProfile != null
              ? 'Business profile updated successfully!'
              : 'Business profile created successfully!';
        });

        // Clear success message after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      } else {
        _showError('Failed to save business profile. Please try again.');
      }
    } catch (e) {
      _showError('Failed to save business profile: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Business Settings',
                description: 'Configure your business information and branding',
                icon: '🏢',
                showBackButton: true,
                onBackPressed: () => Navigator.pop(context),
                stats: [
                  PageHeaderStat(
                    label: 'Profile Status',
                    value: 'Complete',
                    description: 'Business profile is fully configured',
                  ),
                  PageHeaderStat(
                    label: 'Last Updated',
                    value: 'Today',
                    description: 'Profile was last modified today',
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 16,
                  vertical: MediaQuery.of(context).size.width < 480 ? 12 : 16,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.shadow.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Error Message
                          if (_errorMessage != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Error',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Success Message
                          if (_successMessage != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Success',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _successMessage!,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Business Identity Section
                          _buildSectionHeader(
                            'Business Identity',
                            Icons.business,
                          ),
                          const SizedBox(height: 24),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth > 768;

                              if (isDesktop) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          _buildTextField(
                                            controller: _businessNameController,
                                            label: 'Business Name *',
                                            hint: 'Enter your business name',
                                            required: true,
                                          ),
                                          const SizedBox(height: 24),
                                          _buildDropdown(
                                            label: 'Business Type',
                                            value: _selectedBusinessType,
                                            items: _businessTypes,
                                            onChanged: (value) {
                                              setState(() {
                                                _selectedBusinessType = value;
                                              });
                                              _clearError();
                                            },
                                          ),
                                          const SizedBox(height: 24),
                                          _buildTextField(
                                            controller: _descriptionController,
                                            label: 'Business Description',
                                            hint:
                                                'Brief description of your business',
                                            maxLines: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 32),
                                    SizedBox(
                                      width: 200,
                                      child: _buildLogoSection(),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    _buildTextField(
                                      controller: _businessNameController,
                                      label: 'Business Name *',
                                      hint: 'Enter your business name',
                                      required: true,
                                    ),
                                    const SizedBox(height: 24),
                                    _buildDropdown(
                                      label: 'Business Type',
                                      value: _selectedBusinessType,
                                      items: _businessTypes,
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedBusinessType = value;
                                        });
                                        _clearError();
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    _buildLogoSection(),
                                    const SizedBox(height: 24),
                                    _buildTextField(
                                      controller: _descriptionController,
                                      label: 'Business Description',
                                      hint:
                                          'Brief description of your business',
                                      maxLines: 4,
                                    ),
                                  ],
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 40),

                          // Shop Access Section
                          _buildShopAccessSection(),

                          const SizedBox(height: 40),

                          // Brand Colors Section (Live Preview)
                          _buildBrandColorsSection(),

                          const SizedBox(height: 40),

                          // Security Section (Biometric Lock)
                          _buildSecuritySection(),

                          const SizedBox(height: 40),

                          // Contact Information Section
                          _buildSectionHeader(
                            'Contact Information',
                            Icons.phone,
                          ),
                          const SizedBox(height: 24),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth > 768;

                              if (isDesktop) {
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: _buildPhoneField()),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          child: _buildTextField(
                                            controller: _emailController,
                                            label: 'Email Address',
                                            hint: 'business@example.com',
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            prefixIcon: Icons.email,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    _buildTextField(
                                      controller: _websiteController,
                                      label: 'Website',
                                      hint: 'https://www.example.com',
                                      keyboardType: TextInputType.url,
                                      prefixIcon: Icons.language,
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    _buildPhoneField(),
                                    const SizedBox(height: 24),
                                    _buildTextField(
                                      controller: _emailController,
                                      label: 'Email Address',
                                      hint: 'business@example.com',
                                      keyboardType: TextInputType.emailAddress,
                                      prefixIcon: Icons.email,
                                    ),
                                    const SizedBox(height: 24),
                                    _buildTextField(
                                      controller: _websiteController,
                                      label: 'Website',
                                      hint: 'https://www.example.com',
                                      keyboardType: TextInputType.url,
                                      prefixIcon: Icons.language,
                                    ),
                                  ],
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 40),

                          // Business Address Section
                          _buildSectionHeader(
                            'Business Address',
                            Icons.location_on,
                          ),
                          const SizedBox(height: 24),

                          _buildTextField(
                            controller: _addressController,
                            label: 'Street Address',
                            hint: 'Enter your business address',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 24),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth > 768;

                              if (isDesktop) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _cityController,
                                        label: 'City',
                                        hint: 'Enter city',
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: _buildDropdown(
                                        label: 'State',
                                        value: _selectedState,
                                        items: _indianStates,
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedState = value;
                                          });
                                          _clearError();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _postalCodeController,
                                        label: 'Postal Code',
                                        hint: 'Enter postal code',
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    _buildTextField(
                                      controller: _cityController,
                                      label: 'City',
                                      hint: 'Enter city',
                                    ),
                                    const SizedBox(height: 24),
                                    _buildDropdown(
                                      label: 'State',
                                      value: _selectedState,
                                      items: _indianStates,
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedState = value;
                                        });
                                        _clearError();
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    _buildTextField(
                                      controller: _postalCodeController,
                                      label: 'Postal Code',
                                      hint: 'Enter postal code',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ],
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 40),

                          // Tax Information Section
                          _buildSectionHeader(
                            'Tax Information',
                            Icons.receipt_long,
                          ),
                          const SizedBox(height: 24),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth > 768;

                              if (isDesktop) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildTextField(
                                            controller: _gstNumberController,
                                            label: 'GST Number',
                                            hint: '22AAAAA0000A1Z5',
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            maxLength: 15,
                                            prefixIcon: Icons.credit_card,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '15-character GST identification number (optional)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildTextField(
                                            controller: _panNumberController,
                                            label: 'PAN Number',
                                            hint: 'ABCDE1234F',
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            maxLength: 10,
                                            prefixIcon: Icons.description,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '10-character PAN number (optional)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildTextField(
                                          controller: _gstNumberController,
                                          label: 'GST Number',
                                          hint: '22AAAAA0000A1Z5',
                                          textCapitalization:
                                              TextCapitalization.characters,
                                          maxLength: 15,
                                          prefixIcon: Icons.credit_card,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '15-character GST identification number (optional)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildTextField(
                                          controller: _panNumberController,
                                          label: 'PAN Number',
                                          hint: 'ABCDE1234F',
                                          textCapitalization:
                                              TextCapitalization.characters,
                                          maxLength: 10,
                                          prefixIcon: Icons.description,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '10-character PAN number (optional)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 40),

                          // Payments (UPI)
                          _buildSectionHeader(
                            'Payments (UPI)',
                            Icons.currency_rupee,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'UPI VPA is managed by the app and cannot be edited here.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _upiVpaController,
                            readOnly: true,
                            enableInteractiveSelection: false,
                            showCursor: false,
                            decoration: InputDecoration(
                              labelText: 'UPI VPA',
                              hintText: 'your-vpa@bank',
                              prefixIcon: const Icon(Icons.currency_rupee),
                              suffixIcon: const Icon(Icons.lock_outline),
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Current VPA is set to $_staticUpiVpa. Contact admin to change.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Save Button
                          Container(
                            padding: const EdgeInsets.only(top: 24),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : _saveBusinessProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isSaving
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onPrimary,
                                                  ),
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Saving Changes...',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.save, size: 20),
                                          SizedBox(width: 12),
                                          Text(
                                            'Update Business Profile',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 16),
            height: 1,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    int maxLines = 1,
    int? maxLength,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    IconData? prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(
                prefixIcon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: (_) => _clearError(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            counterText: '',
          ),
          validator: required
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '$label is required';
                  }
                  return null;
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            onChanged: onChanged,
            isExpanded: true,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            hint: Text(
              'Select $label',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.phone,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(width: 8),
            Text(
              'Phone Number',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          onChanged: (value) {
            final formatted = _formatPhoneNumber(value);
            if (formatted != value) {
              _phoneController.value = TextEditingValue(
                text: formatted,
                selection: TextSelection.collapsed(offset: formatted.length),
              );
            }
            _clearError();
          },
          decoration: InputDecoration(
            hintText: '+91 98765 43210',
            hintStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.only(left: 12, right: 8),
              child: const Text('🇮🇳', style: TextStyle(fontSize: 20)),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business Logo',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),

        // Logo Preview
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: _logoFile != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _logoFile!,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _removeLogo,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onError,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : _logoUrl != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _logoUrl!,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.image,
                            size: 40,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _removeLogo,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onError,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Icon(
                    Icons.upload,
                    size: 40,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
        ),
        const SizedBox(height: 12),

        // Upload Button
        SizedBox(
          width: 120,
          child: OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload, size: 16),
            label: Text(
              _logoFile != null || _logoUrl != null ? 'Change' : 'Upload',
              style: const TextStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Max 2MB • JPG, PNG, GIF',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ===================== Security (Biometric Lock) =====================
  Future<void> _initBiometricSetting() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();
      final enrolled = canCheck && available.isNotEmpty;
      final enabled = await _securityService.getRequireBiometric();
      if (!mounted) return;
      setState(() {
        _biometricSupported = supported;
        _hasBiometricsEnrolled = enrolled;
        _availableBiometrics = available;
        _requireBiometric = enabled && supported && enrolled;
        _loadingBiometric = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricSupported = false;
        _hasBiometricsEnrolled = false;
        _availableBiometrics = const [];
        _requireBiometric = false;
        _loadingBiometric = false;
      });
    }
  }

  Widget _buildSecuritySection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Security', Icons.lock),
            const SizedBox(height: 12),
            Text(
              'Add an extra layer of security. When enabled, you\'ll be asked to authenticate with your phone\'s biometrics every time the app opens or resumes (after login).',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SwitchListTile.adaptive(
                value: _requireBiometric,
                onChanged: _loadingBiometric
                    ? null
                    : (_biometricSupported ? _onToggleRequireBiometric : null),
                title: const Text('Require biometric on app open'),
                subtitle: Text(
                  _loadingBiometric
                      ? 'Checking device capability...'
                      : (!_biometricSupported
                            ? 'Biometrics not supported on this device'
                            : (!_hasBiometricsEnrolled
                                  ? 'No biometrics enrolled. Set up fingerprint/Face unlock in Settings'
                                  : 'Supported and enrolled${_availableBiometrics.isNotEmpty ? ' (${_availableBiometrics.map((e) => e.name).join(', ')})' : ''}')),
                ),
                secondary: Icon(
                  Icons.fingerprint,
                  color: _biometricSupported
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onToggleRequireBiometric(bool value) async {
    if (value) {
      if (!_biometricSupported) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Biometric not supported on this device.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      if (!_hasBiometricsEnrolled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No biometrics enrolled. Please enable Fingerprint/Face unlock in device settings.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      try {
        final didAuth = await LocalAuthentication().authenticate(
          localizedReason: 'Enable biometric lock',
          options: const AuthenticationOptions(
            stickyAuth: false,
            biometricOnly: true,
            useErrorDialogs: true,
          ),
        );
        if (didAuth) {
          await _securityService.setRequireBiometric(true);
          if (!mounted) return;
          setState(() => _requireBiometric = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Biometric lock enabled.'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Authentication failed or was cancelled.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } catch (_) {
        // Ignore, keep disabled
      }
    } else {
      await _securityService.setRequireBiometric(false);
      if (!mounted) return;
      setState(() => _requireBiometric = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Biometric lock disabled.'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    }
  }
}
