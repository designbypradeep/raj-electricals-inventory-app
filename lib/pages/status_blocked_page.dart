import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class StatusBlockedPage extends StatelessWidget {
  final String status;

  const StatusBlockedPage({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    String message = 'Access Restricted';
    IconData icon = Icons.lock;
    Color color = Colors.grey;

    if (status == 'PENDING') {
      message =
          'Your account is currently PENDING approval.\nPlease wait for an administrator to activate your account.';
      icon = Icons.hourglass_empty;
      color = Colors.orange;
    } else if (status == 'SUSPENDED') {
      message =
          'Your account has been SUSPENDED.\nPlease contact support for assistance.';
      icon = Icons.block;
      color = Colors.red;
    } else if (status == 'EXPIRED') {
      message = 'Your trial has EXPIRED.\nPlease upgrade to continue.';
      icon = Icons.timelapse;
      color = Colors.redAccent;
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 24),
              Text(
                'Status: $status',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () async {
                  await SupabaseService.signOut();
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
