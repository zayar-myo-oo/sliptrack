import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import 'localized_text.dart';
import 'design.dart';

const _palette = [
  Color(0xff1e4b3a),
  Color(0xff4f9a72),
  Color(0xff8cc6a4),
  Color(0xffe0a64b),
  Color(0xffc8544b),
  Color(0xff9aa69f),
];

Color _color(BuildContext context, int i) =>
    i == 0 ? Palette.accent(context) : _palette[i % _palette.length];

class CategoryChart extends StatelessWidget {
  const CategoryChart({
    required this.amounts,
    required this.currency,
    super.key,
  });
  final Map<String, int> amounts;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final entries = amounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    return Surface(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'By category',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Center(
              child: Semantics(
                label: '${tr(context, 'Expenses')} ${money(total, currency)}',
                child: SizedBox(
                  height: 190,
                  width: 190,
                  child: CustomPaint(
                    painter: _Ring(entries.map((e) => e.value).toList(), [
                      for (var i = 0; i < entries.length; i++)
                        _color(context, i),
                    ], Palette.soft(context)),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LText(
                              'Expenses',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              child: Text(
                                money(total, currency),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Center(child: LText('No confirmed spending yet')),
            for (var i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _color(context, i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(entries[i].key)),
                    Text(
                      '${(entries[i].value * 100 / total).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Palette.muted(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      money(entries[i].value, currency),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.values, this.colors, this.track);
  final List<int> values;
  final List<Color> colors;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(14);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, paint..color = track);
    final total = values.fold<int>(0, (sum, n) => sum + n);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      final gap = values.length == 1 ? 0.0 : math.min(.22, sweep * .4);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        paint..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Ring oldDelegate) => true;
}
