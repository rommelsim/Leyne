// Search — placeholder for Task #6. Task #9 wires it to DataStore.search*
// with the Conservative/Ambitious variants and persisted recents from
// legacy SearchSheet.swift.

import 'package:flutter/material.dart';
import '../theme.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Bus, stop, postal code…',
                hintStyle: TextStyle(color: t.dim),
                prefixIcon: Icon(Icons.search, color: t.dim),
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: t.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.line),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Search arrives in Task #9.',
                style: t.sans(14).copyWith(color: t.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
