// SaveSheet — Material bottom sheet for "Save this stop / Save this service".
// Radio-option card layout, port of ios-native/Leyne/V2/SaveSheet.swift.
//
// Used by SoftStopScreen and SoftBusScreen. Show with showModalBottomSheet:
//
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     shape: const RoundedRectangleBorder(
//       borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
//     ),
//     builder: (_) => SaveSheetBody(
//       title: 'Save this stop',
//       subtitle: '...',
//       options: [...],
//       onSave: (idx) { ... },
//     ),
//   );

import 'package:flutter/material.dart';
import '../../theme.dart';

class SaveOption {
  const SaveOption({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
}

/// Stateful bottom sheet body. Manages radio selection internally; calls
/// [onSave] with the chosen index when the Save button is tapped.
class SaveSheetBody extends StatefulWidget {
  const SaveSheetBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.onSave,
    this.initialSel = 0,
    this.saveLabel = 'Save',
  });
  final String title;
  final String subtitle;
  final List<SaveOption> options;
  final ValueChanged<int> onSave;
  final int initialSel;
  final String saveLabel;

  @override
  State<SaveSheetBody> createState() => _SaveSheetBodyState();
}

class _SaveSheetBodyState extends State<SaveSheetBody> {
  late int _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.initialSel;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: t.faint,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(widget.title,
                style: t.sans(20, weight: FontWeight.w700, color: t.fg)),
            const SizedBox(height: 4),
            Text(widget.subtitle, style: t.sans(13, color: t.dim)),
            const SizedBox(height: 18),
            for (var i = 0; i < widget.options.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _optionCard(widget.options[i], i, t),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.contrast,
                  foregroundColor: t.contrastFg,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => widget.onSave(_sel),
                child: Text(widget.saveLabel,
                    style: t.sans(16, weight: FontWeight.w700,
                        color: t.contrastFg)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionCard(SaveOption opt, int idx, LyneTheme t) {
    final selected = _sel == idx;
    return GestureDetector(
      onTap: () => setState(() => _sel = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? t.soonBg.withValues(alpha: 0.5) : t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.md),
          border: Border.all(
            color: selected ? t.soon.withValues(alpha: 0.6) : t.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? t.soonBg : t.surfaceHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(opt.icon,
                  size: 17, color: selected ? t.soon : t.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opt.title,
                      style:
                          t.sans(15, weight: FontWeight.w600, color: t.fg)),
                  const SizedBox(height: 2),
                  Text(opt.subtitle,
                      style: t.sans(12, color: t.dim), maxLines: 2),
                ],
              ),
            ),
            const SizedBox(width: 8),
            selected
                ? Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color: t.soon, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded,
                        size: 14, color: t.contrastFg),
                  )
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.line, width: 1.5),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
