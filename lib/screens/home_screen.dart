// Home — placeholder for Task #6. Task #7 wires it to DataStore for live
// pinned-stop arrivals matching legacy HomeView.swift.

import 'package:flutter/material.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Leyne')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_bus_filled,
                  size: 56, color: t.dim.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'No pinned stops yet',
                style: t.sans(17, weight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Pin a stop from Nearby or Search to see live arrivals here.',
                textAlign: TextAlign.center,
                style: t.sans(14).copyWith(color: t.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
