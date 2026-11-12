import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../widgets/page_header.dart';

const Color _emerald = Color(0xFF10B981);

class TeamManagementPage extends StatefulWidget {
  const TeamManagementPage({super.key});

  @override
  State<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends State<TeamManagementPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _teamData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService.client.rpc('get_business_staff_members');
      if (mounted) {
        setState(() {
          _teamData = res is Map ? Map<String, dynamic>.from(res) : null;
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

  Future<void> _addStaff(String name, String phone, String email, String role) async {
    try {
      final res = await SupabaseService.client.rpc('add_business_staff', params: {
        'p_full_name': name.trim().isEmpty ? null : name.trim(),
        'p_phone': phone.trim().isEmpty ? null : phone.trim(),
        'p_email': email.trim().isEmpty ? null : email.trim(),
        'p_role': role,
      });

      if (mounted) {
        final msg = (res is Map && res['message'] != null)
            ? res['message'].toString()
            : 'Staff member added successfully.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
        _loadTeam();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add staff: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeStaff({String? userId, String? inviteId, String? name}) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Staff Member'),
        content: Text('Are you sure you want to revoke access for ${name ?? "this member"}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.client.rpc('remove_business_staff', params: {
        if (userId != null) 'p_user_id': userId,
        if (inviteId != null) 'p_invite_id': inviteId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff member removed.'), backgroundColor: Colors.orange),
        );
        _loadTeam();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateRole(String userId, String newRole) async {
    try {
      await SupabaseService.client.rpc('update_business_staff_role', params: {
        'p_user_id': userId,
        'p_role': newRole,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to $newRole.'), backgroundColor: Colors.green),
        );
        _loadTeam();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update role: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddStaffModal() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'cashier';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Staff Member',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Staff Full Name',
                        hintText: 'e.g. Rahul Sharma',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (for App Login)',
                        hintText: 'e.g. staff@gmail.com',
                        prefixIcon: Icon(Icons.mail_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Phone (Optional / Contact)',
                        hintText: 'e.g. 9876543210',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Assign Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => selectedRole = 'cashier'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              decoration: BoxDecoration(
                                color: selectedRole == 'cashier'
                                    ? _emerald.withValues(alpha: 0.15)
                                    : Theme.of(ctx).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedRole == 'cashier' ? _emerald : Colors.grey.shade400,
                                  width: selectedRole == 'cashier' ? 2 : 1,
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Text('Cashier', style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(height: 2),
                                  Text('POS Billing only', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => selectedRole = 'manager'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              decoration: BoxDecoration(
                                color: selectedRole == 'manager'
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : Theme.of(ctx).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedRole == 'manager' ? Colors.blue : Colors.grey.shade400,
                                  width: selectedRole == 'manager' ? 2 : 1,
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Text('Manager', style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(height: 2),
                                  Text('Stock & Operations', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedRole == 'cashier'
                                  ? 'Cashier access: POS Billing, Orders & Sales History, Customer returns, and Replacements. Inventory costs, purchases, reports, and settings are hidden.'
                                  : 'Manager access: Inventory, Catalog, Purchases, Suppliers, Stock Requests, and Reports. Business settings, Billing plans, and Team management are hidden.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(ctx).textTheme.bodySmall?.color,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          final email = emailCtrl.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid email address for staff app login.')),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _addStaff(
                            nameCtrl.text,
                            phoneCtrl.text,
                            emailCtrl.text,
                            selectedRole,
                          );
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Confirm & Add Staff', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Team & Staff',
                description: 'Manage staff accounts, assign roles, and monitor team seats',
                icon: '👥',
                showBackButton: true,
                backLabel: 'Dashboard',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Team & Staff',
                      icon: '👥',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(label: 'Seats Used', value: '...', description: 'Loading team'),
                  PageHeaderStat(label: 'Available', value: '...', description: 'Fetching quota'),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Team & Staff',
                description: 'Manage staff accounts, assign roles, and monitor team seats',
                icon: '👥',
                showBackButton: true,
                backLabel: 'Dashboard',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                ],
                stats: [
                  PageHeaderStat(label: 'Status', value: 'Error', description: 'Failed to load'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_errorMessage', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadTeam,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final owner = _teamData?['owner'] as Map<String, dynamic>?;
    final members = (_teamData?['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final invites = (_teamData?['invitations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final int maxUsers = (_teamData?['max_users'] as num?)?.toInt() ?? 3;
    final int usedUsers = (_teamData?['used_users'] as num?)?.toInt() ?? (1 + members.length + invites.length);
    final bool isLimitReached = usedUsers >= maxUsers;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadTeam,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              PageHeader(
                title: 'Team & Staff',
                description: 'Manage staff accounts, assign roles, and monitor team seats',
                icon: '👥',
                showBackButton: true,
                backLabel: 'Dashboard',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Team & Staff',
                      icon: '👥',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Seats Used',
                    value: '$usedUsers / $maxUsers',
                    description: 'Active team members',
                  ),
                  PageHeaderStat(
                    label: 'Available',
                    value: isLimitReached ? 'Full' : '${maxUsers - usedUsers}',
                    description: isLimitReached ? 'Quota reached' : 'Free seats',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Add Staff',
                    shortLabel: 'Add',
                    icon: Icons.person_add,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: isLimitReached ? null : _showAddStaffModal,
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width < 480 ? 14 : 20,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quota Card with Progress Bar
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).shadowColor.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.people_alt_rounded,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Team Member Quota',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$usedUsers of $maxUsers seats used',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).textTheme.bodySmall?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isLimitReached
                                          ? Colors.orange.withValues(alpha: 0.15)
                                          : _emerald.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isLimitReached
                                            ? Colors.orange.withValues(alpha: 0.3)
                                            : _emerald.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      isLimitReached
                                          ? 'Plan Limit Reached'
                                          : '${maxUsers - usedUsers} Available',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isLimitReached ? Colors.orange : _emerald,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: maxUsers > 0
                                      ? (usedUsers / maxUsers).clamp(0.0, 1.0)
                                      : 0,
                                  minHeight: 8,
                                  backgroundColor: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isLimitReached ? Colors.orange : _emerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Store Owner Section
                        Text(
                          'STORE OWNER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (owner != null)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).shadowColor.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.amber.shade400, Colors.amber.shade700],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.workspace_premium, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        owner['full_name'] ?? 'Store Owner',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        owner['email'] ?? owner['phone'] ?? 'Primary Account',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).textTheme.bodySmall?.color,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, size: 12, color: Colors.amber),
                                      SizedBox(width: 4),
                                      Text(
                                        'OWNER',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.amber,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 22),

                        // Active Staff Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ACTIVE STAFF MEMBERS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${members.length}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Empty State
                        if (members.isEmpty && invites.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.group_add_rounded,
                                    size: 36,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Staff Members Added Yet',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Invite cashiers for front-desk billing or managers to handle inventory & purchases.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: isLimitReached ? null : _showAddStaffModal,
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Staff Member'),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Active Members List
                        ...members.map((m) {
                          final isManager = m['role'] == 'manager';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (isManager ? Colors.blue : _emerald).withValues(alpha: 0.25),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).shadowColor.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: (isManager ? Colors.blue : _emerald).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isManager ? Icons.manage_accounts : Icons.point_of_sale,
                                    color: isManager ? Colors.blue : _emerald,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m['full_name'] ?? 'Staff',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        m['email'] ?? m['phone'] ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).textTheme.bodySmall?.color,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isManager ? Colors.blue : _emerald).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isManager ? 'Manager' : 'Cashier (POS)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isManager ? Colors.blue : _emerald,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (val) {
                                    if (val == 'remove') {
                                      _removeStaff(userId: m['id'], name: m['full_name']);
                                    } else if (val == 'make_cashier') {
                                      _updateRole(m['id'], 'cashier');
                                    } else if (val == 'make_manager') {
                                      _updateRole(m['id'], 'manager');
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    if (isManager)
                                      const PopupMenuItem(
                                        value: 'make_cashier',
                                        child: Row(
                                          children: [
                                            Icon(Icons.point_of_sale, size: 16),
                                            SizedBox(width: 8),
                                            Text('Switch to Cashier (POS)'),
                                          ],
                                        ),
                                      )
                                    else
                                      const PopupMenuItem(
                                        value: 'make_manager',
                                        child: Row(
                                          children: [
                                            Icon(Icons.manage_accounts, size: 16),
                                            SizedBox(width: 8),
                                            Text('Promote to Manager'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_remove_outlined, size: 16, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Remove Access', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),

                        // Pending Invites Section
                        if (invites.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'PENDING INVITATIONS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${invites.length}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...invites.map((inv) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.mail_outline, color: Colors.orange, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          inv['full_name'] ?? 'Invited Staff',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${inv['email'] ?? inv['phone']} • Role: ${inv['role']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).textTheme.bodySmall?.color,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _removeStaff(inviteId: inv['id'], name: inv['full_name']),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.red, fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 40),
                      ],
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
}

