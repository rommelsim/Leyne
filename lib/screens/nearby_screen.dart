// Nearby — placeholder for Task #6. Task #7 wires it to geolocator +
// DataStore.updateNearby for ranked live results.

import 'package:flutter/material.dart';
import '../theme.dart';

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Nearby')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location,
                  size: 56, color: t.dim.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('Nearby stops', style: t.sans(17, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Task #7 wires this to your live location and the LTA bus stop dataset.',
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
