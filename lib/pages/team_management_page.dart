import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

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
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Phone (for App Login)',
                        hintText: 'e.g. 9876543210',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (Optional)',
                        hintText: 'e.g. staff@gmail.com',
                        prefixIcon: Icon(Icons.mail_outline),
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (phoneCtrl.text.trim().isEmpty && emailCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please enter a phone number or email.')),
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
        appBar: AppBar(title: const Text('Team & Staff')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team & Staff')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $_errorMessage'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadTeam, child: const Text('Retry')),
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
      appBar: AppBar(
        title: const Text('Team & Staff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTeam,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: isLimitReached
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddStaffModal,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Staff'),
            ),
      body: RefreshIndicator(
        onRefresh: _loadTeam,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quota Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.people, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Team Member Quota', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('$usedUsers of $maxUsers seats used', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLimitReached ? Colors.orange.withValues(alpha: 0.15) : _emerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isLimitReached ? 'Plan Limit Reached' : '${maxUsers - usedUsers} Available',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isLimitReached ? Colors.orange : _emerald,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Owner Section
            const Text('Store Owner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            if (owner != null)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.workspace_premium, color: Colors.white),
                  ),
                  title: Text(owner['full_name'] ?? 'Store Owner', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(owner['email'] ?? owner['phone'] ?? 'Primary Account'),
                  trailing: const Chip(
                    label: Text('OWNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Color(0x22F59E0B),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Active Staff Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Staff Members', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text('${members.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            if (members.isEmpty && invites.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No staff members added yet.\nTap "+ Add Staff" to assign a cashier.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              ),
            ...members.map((m) {
              final isManager = m['role'] == 'manager';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isManager ? Colors.blue.withValues(alpha: 0.2) : _emerald.withValues(alpha: 0.2),
                    child: Icon(
                      isManager ? Icons.manage_accounts : Icons.point_of_sale,
                      color: isManager ? Colors.blue : _emerald,
                    ),
                  ),
                  title: Text(m['full_name'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${m['phone'] ?? m['email'] ?? ""} • ${isManager ? "Manager" : "Cashier (POS Only)"}'),
                  trailing: PopupMenuButton<String>(
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
                        const PopupMenuItem(value: 'make_cashier', child: Text('Switch to Cashier (POS only)'))
                      else
                        const PopupMenuItem(value: 'make_manager', child: Text('Promote to Manager')),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove Staff Access', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Pending Invites Section
            if (invites.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pending Invitations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                  Text('${invites.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
              const SizedBox(height: 8),
              ...invites.map((inv) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      child: const Icon(Icons.mail_outline, color: Colors.orange),
                    ),
                    title: Text(inv['full_name'] ?? 'Invited Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${inv['phone'] ?? inv['email']} • Assigned as ${inv['role']}'),
                    trailing: TextButton(
                      onPressed: () => _removeStaff(inviteId: inv['id'], name: inv['full_name']),
                      child: const Text('Cancel', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

