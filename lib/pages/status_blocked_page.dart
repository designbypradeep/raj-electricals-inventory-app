import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class StatusBlockedPage extends StatefulWidget {
  final String status;
  final VoidCallback? onStatusRefreshed;

  const StatusBlockedPage({
    super.key,
    required this.status,
    this.onStatusRefreshed,
  });

  @override
  State<StatusBlockedPage> createState() => _StatusBlockedPageState();
}

class _StatusBlockedPageState extends State<StatusBlockedPage> {
  bool _isChecking = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status.toUpperCase();
  }

  Future<void> _refreshStatus() async {
    setState(() => _isChecking = true);
    try {
      final profile = await SupabaseService.getCurrentBusinessProfile();
      if (profile != null && profile.isWritable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Account is active! Loading dashboard...'),
              backgroundColor: Colors.green,
            ),
          );
        }
        if (widget.onStatusRefreshed != null) {
          widget.onStatusRefreshed!();
        } else if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _currentStatus = (profile?.status ?? _currentStatus).toUpperCase();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account status is still: $_currentStatus'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _openWebUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open browser: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String title = 'Access Restricted';
    String message =
        'Your business account access is currently restricted.';
    IconData icon = Icons.lock_outline;
    Color statusColor = Colors.orange;

    if (_currentStatus == 'PENDING') {
      title = 'Pending Approval';
      message =
          'Your account is currently under administrative review.\nYou will receive full access once approved by an administrator.';
      icon = Icons.hourglass_top_rounded;
      statusColor = const Color(0xFFF59E0B);
    } else if (_currentStatus == 'SUSPENDED') {
      title = 'Account Suspended';
      message =
          'Your business account has been suspended by an administrator.\nThis may occur due to a terms review or billing issue.';
      icon = Icons.block_rounded;
      statusColor = const Color(0xFFEF4444);
    } else if (_currentStatus == 'EXPIRED') {
      title = 'Trial or Plan Expired';
      message =
          'Your trial or subscription period has ended.\nPlease upgrade or renew your plan on the Inventoza web portal.';
      icon = Icons.timelapse_rounded;
      statusColor = const Color(0xFFF43F5E);
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1,
                ),
              ),
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Badge
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(icon, size: 40, color: statusColor),
                    ),
                    const SizedBox(height: 24),

                    // Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _currentStatus,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // Message
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Primary Action: Open Web Portal
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _openWebUrl('https://inventoza.com/billing'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(
                          _currentStatus == 'EXPIRED'
                              ? 'Upgrade Plan on Web'
                              : 'Open Web Portal',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Refresh Status Button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _isChecking ? null : _refreshStatus,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(_isChecking ? 'Checking...' : 'Check Status'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Contact Support Button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton.icon(
                        onPressed: () =>
                            _openWebUrl('https://inventoza.com/contact'),
                        icon: const Icon(Icons.support_agent, size: 18),
                        label: const Text('Contact Inventoza Support'),
                      ),
                    ),
                    const Divider(height: 32),

                    // Sign Out
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          await SupabaseService.signOut();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                        ),
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Sign Out'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
