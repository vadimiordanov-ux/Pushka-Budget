import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../data/db/database.dart';
import 'common.dart';

/// Transaction row + directional swipe — port of txRow() + attachSwipe():
///   swipe right ≥72px → edit (sheet), reveal ✏️ over accent gradient
///   swipe left  ≥72px → delete (undo toast), row slides out −100%
///   translation clamped to ±104px, haptic tick at the 72px threshold,
///   haptic select on commit. Internal rows at 45% opacity, split children
///   indented with ↳ and a smaller tile.
class TxRow extends StatefulWidget {
  final Transaction tx;
  final Category? cat;
  final Color? catColor;
  final String title;
  final String sub;
  final String amountText;
  final bool income;
  final (String key, String letter)? owner;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TxRow(
      {super.key,
      required this.tx,
      required this.cat,
      required this.catColor,
      required this.title,
      required this.sub,
      required this.amountText,
      required this.income,
      required this.owner,
      required this.onTap,
      required this.onEdit,
      required this.onDelete});

  @override
  State<TxRow> createState() => _TxRowState();
}

class _TxRowState extends State<TxRow> with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _buzzed = false;
  bool _leaving = false;

  static const _threshold = 72.0;
  static const _max = 104.0;

  void _onUpdate(DragUpdateDetails d) {
    setState(() => _dx = (_dx + d.delta.dx).clamp(-_max, _max));
    final over = _dx.abs() >= _threshold;
    if (over && !_buzzed) {
      haptic();
      _buzzed = true;
    } else if (!over) {
      _buzzed = false;
    }
  }

  void _onEnd(DragEndDetails d) {
    if (_dx <= -_threshold) {
      haptic(HapticKind.select);
      setState(() => _leaving = true); // slide out then delete
      Future.delayed(const Duration(milliseconds: 150), widget.onDelete);
    } else if (_dx >= _threshold) {
      haptic(HapticKind.select);
      setState(() => _dx = 0);
      widget.onEdit();
    } else {
      setState(() => _dx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tk(context);
    final child = widget.tx.parentId != null;
    final showLeft = _dx > 6; // edit reveal
    final showRight = _dx < -6; // delete reveal

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(children: [
        // reveal gradients (.tx-wrap::before/::after)
        Positioned.fill(
          child: Row(children: [
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: showLeft ? 1 : 0,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                    t.accent.withValues(alpha: .32),
                    t.accent.withValues(alpha: 0)
                  ])),
                  child: const Text('✏️', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: showRight ? 1 : 0,
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                    t.expense.withValues(alpha: 0),
                    t.expense.withValues(alpha: .34)
                  ])),
                  child: const Text('🗑', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ]),
        ),
        GestureDetector(
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: () => setState(() => _dx = 0),
          child: AnimatedSlide(
            duration: Duration(milliseconds: _leaving ? 220 : (_dx == 0 ? 200 : 0)),
            curve: Curves.easeOut,
            offset: _leaving
                ? const Offset(-1, 0)
                : Offset(0, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _leaving ? 0 : (widget.tx.internal ? .45 : 1),
              child: Transform.translate(
                offset: Offset(_dx, 0),
                child: Press(
                  onTap: widget.onTap,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.fromLTRB(child ? 30 : 8, 10, 8, 10),
                    child: Row(children: [
                      EmTile(
                        widget.cat?.emoji ??
                            (widget.tx.internal
                                ? '⇄'
                                : widget.tx.amount > 0
                                    ? '↓'
                                    : '❔'),
                        color: widget.catColor,
                        size: child ? 30 : 40,
                        fontSize: child ? 14 : 18,
                        radius: child ? 10 : 14,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(
                                  child: Text(widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: t.ink)),
                                ),
                                if (widget.owner != null)
                                  OwnerBadge(widget.owner!.$1, widget.owner!.$2),
                              ]),
                              if (widget.sub.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(widget.sub,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: t.ink2, fontSize: 12)),
                                ),
                            ]),
                      ),
                      const SizedBox(width: 10),
                      Text(widget.amountText,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: widget.income ? t.income : t.ink)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
