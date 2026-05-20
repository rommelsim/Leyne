// One pinned-stop card on the Home list.
//
// Behavioural parity with legacy PinnedCardView.swift:
//   • Header: editable label (tap to rename), stop name, code, walk-min.
//   • Body: up to 3 service rows, then a "+N more" overflow chip.
//   • Arriving-bus highlight: a green hairline border + soft shadow when
//     any tracked service is ≤ 60s out.
//   • Recently-added: brief accent-tinted border pulse via isNew.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme.dart';
import 'service_row.dart';

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
  bool _editing = false;
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.card.label);
  }

  @override
  void didUpdateWidget(covariant PinnedCard old) {
    super.didUpdateWidget(old);
    if (!_editing && old.card.label != widget.card.label) {
      _ctl.text = widget.card.label;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _commit() {
    setState(() => _editing = false);
    final v = _ctl.text.trim();
    if (v.isEmpty || v == widget.card.label) return;
    widget.onRename(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final visible = widget.card.services
        .where((s) => !widget.hiddenServices.contains(s.no))
        .toList();
    final shown = visible.take(3).toList();
    final overflow = visible.length - shown.length;
    final anyArriving = visible.any((s) => s.etaSec <= 60);

    final highlight = widget.isNew
        ? t.accent
        : (anyArriving ? t.live : t.line);

    return InkWell(
      onTap: () => widget.onOpen(null),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight, width: 1),
          boxShadow: anyArriving
              ? [
                  BoxShadow(
                    color: t.live.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t, anyArriving),
            if (shown.isNotEmpty) ...[
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.line),
                ServiceRow(
                  service: shown[i],
                  onTap: () => widget.onOpen(shown[i].no),
                ),
              ],
              if (overflow > 0) _moreChip(t, overflow),
            ] else
              _emptyBody(t),
          ],
        ),
      ),
    );
  }

  Widget _header(LyneTheme t, bool arriving) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _editing = true);
                  },
                  child: _editing
                      ? TextField(
                          controller: _ctl,
                          autofocus: true,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _commit(),
                          onEditingComplete: _commit,
                          style: t.sans(17, weight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            hintText: widget.card.stopName,
                            hintStyle: TextStyle(color: t.dim),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.card.label,
                                style: t.sans(17, weight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.edit_outlined,
                                size: 14, color: t.dim.withValues(alpha: 0.6)),
                          ],
                        ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('STOP ${widget.card.stopCode}',
                        style: t.mono(10).copyWith(color: t.dim)),
                    if (widget.card.walkMin > 0) ...[
                      const SizedBox(width: 8),
                      Text('·',
                          style: t.mono(10)
                              .copyWith(color: t.dim.withValues(alpha: 0.5))),
                      const SizedBox(width: 8),
                      Text('${widget.card.walkMin} MIN WALK',
                          style: t.mono(10).copyWith(color: t.dim)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (arriving)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.liveBg,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('ARRIVING',
                  style: t.mono(9, weight: FontWeight.w700)
                      .copyWith(color: t.live, letterSpacing: 0.5)),
            ),
        ],
      ),
    );
  }

  Widget _moreChip(LyneTheme t, int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: t.line),
          ),
          child: Text('+$n more',
              style: t.mono(10).copyWith(color: t.dim)),
        ),
      ),
    );
  }

  Widget _emptyBody(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        'Loading arrivals…',
        style: t.sans(12).copyWith(color: t.dim),
      ),
    );
  }
}
