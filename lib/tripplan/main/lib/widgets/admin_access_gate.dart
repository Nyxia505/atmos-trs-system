import 'package:flutter/material.dart';

/// Wraps admin screens (role checks can be added here).
class AdminAccessGate extends StatelessWidget {
  const AdminAccessGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
