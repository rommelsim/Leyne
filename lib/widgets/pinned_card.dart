// Compact pinned-stop card on the Home list — two-line rows that fit ~3×
// more info than the legacy chunky card. Each row taps through to the
// service detail; the whole-card tap opens the stop overview.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';
import 'atoms.dart';

class PinnedCard extends StatefulWidget {
  const PinnedCard({
    super.key,
    required this.card,
    required this.isNew,
    required this.onOpen,
    required this.onRename,
    this.hiddenServices = const {},
  });

  final CardModel card;
  final bool isNew;
  final void Function(String? busNo) onOpen;
  final void Function(String newLabel) onRename;
  final Set<String> hiddenServices;

  @override
  State<PinnedCard> createState() => _PinnedCardState();
}

class _PinnedCardState extends State<PinnedCard> {
  Future<void> _showRenameSheet() async {
    final t = context.t;
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) =>
          _RenameSheet(initial: widget.card.label, hint: widget.card.stopName),
    );
    if (v != null && v.isNotEmpty && v != widget.card.label) {
      widget.onRename(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final visible = widget.card.services
        .where((s) => !widget.hiddenServices.contains(s.no))
        .toList();
    final anyArriving = visible.any((s) => s.etaSec <= 60);

    final borderColor = widget.isNew
        ? t.accent
        : (anyArriving ? t.accent.withValues(alpha: 0.4) : t.line);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpen(null),
        onLongPress: _showRenameSheet,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Loading arrivals…',
                    style: t.sans(12, color: t.dim),
                  ),
                )
              else
                for (var i = 0; i < visible.length; i++) ...[
                  if (i == 0) const SizedBox(height: 12) else _rowDivider(t),
                  _serviceRow(t, visible[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(LyneTheme t) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.card.label,
                style: t.sans(16, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _meta(),
                style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.4),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ],
    );
  }

  String _meta() {
    final id = 'STOP ${widget.card.stopCode}';
    if (widget.card.walkMin <= 0) return id;
    return '$id · ${widget.card.walkMin} MIN WALK';
  }

  Widget _rowDivider(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: t.line),
    );
  }

  Widget _serviceRow(LyneTheme t, Service s) {
    final etaMin = (s.etaSec / 60).floor();
    final followingMin = (s.followingSec / 60).floor();
    final big = etaMin <= 0 ? 'Arr' : '$etaMin';
    final unit = etaMin <= 0 ? 'now' : 'min';
    final loadColor = switch (s.load) {
      Load.sea => t.accent,
      Load.sda => t.warn,
      Load.lsd => t.crit,
    };
    final arriving = s.etaSec <= 60;
    final etaColor = arriving ? t.accent : t.fg;

    return InkWell(
      onTap: () => widget.onOpen(s.no),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BusChip(no: s.no, size: ChipSize.sm),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.dest,
                    style: t.sans(14, weight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: loadColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.load.label.toLowerCase(),
                        style: t.mono(10, color: t.dim),
                      ),
                      if (s.wab) ...[
                        const SizedBox(width: 8),
                        Text(
                          'WAB',
                          style: t
                              .mono(10, color: t.dim)
                              .copyWith(letterSpacing: 0.4),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      big,
                      style: t.mono(
                        22,
                        weight: FontWeight.w600,
                        color: etaColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(unit, style: t.mono(11, color: t.dim)),
                  ],
                ),
                if (followingMin > etaMin + 1) ...[
                  const SizedBox(height: 2),
                  Text('then $followingMin', style: t.mono(10, color: t.faint)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial, required this.hint});
  final String initial;
  final String hint;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnimatedPadding(
      duration: LyneMotion.fast,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rename stop', style: t.sans(15, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              autofocus: true,
              style: t.sans(15),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: t.dim),
                isDense: true,
                filled: true,
                fillColor: t.bg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.accent),
                ),
              ),
              onSubmitted: (s) => Navigator.of(context).pop(s.trim()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: t.contrastFg,
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(_ctl.text.trim()),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
