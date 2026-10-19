import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'coach_models.dart';

/// A 32×32 pixel-art cat drawn cell by cell. Shapes are filled first and the
/// dark outline is generated around them, so the sprite stays crisp at any
/// size. [phase] (0–1, looping) drives idle frames: bob, tail, blink, ears,
/// glances and, at night, sleeping with floating Z's.
class PixelCatPainter extends CustomPainter {
  PixelCatPainter({
    required this.mood,
    required this.growth,
    required this.outfit,
    required this.phase,
    required this.sleeping,
  });
  final PetMood mood;
  final double growth, phase;
  final int outfit;
  final bool sleeping;
  static const n = 32;
  static const outline = Color(0xff4a3426);
  static const cream = Color(0xfffff3e2);
  static const ginger = Color(0xfff2a65a);
  static const stripe = Color(0xffd9822f);
  static const pink = Color(0xffffb3b3);
  static const white = Color(0xffffffff);
  static const coin = Color(0xffffcf5a);
  static const coinDark = Color(0xffe0a43a);
  static const eye = Color(0xff2d211a);
  static const tear = Color(0xff7cc4f4);
  static const whisker = Color(0x99806a5a);
  @override
  void paint(Canvas canvas, Size size) {
    // One spare row above keeps the ear outline inside the canvas.
    final cell = math.min(size.width, size.height) / (n + 1) * growth;
    final ox = (size.width - cell * n) / 2;
    final oy = size.height - cell * n;
    // Chunky 2-step animation reads as "pixel" rather than smooth tweening.
    final frame = (phase * 8).floor();
    final bob = sleeping ? (frame % 4 < 2 ? 0 : 1) : (frame.isEven ? 0 : 1);
    final body = <math.Point<int>, Color>{};
    void put(int x, int y, Color c) {
      if (x >= 0 && x < n && y >= 0 && y < n) body[math.Point(x, y)] = c;
    }

    void ellipse(
      double cx,
      double cy,
      double rx,
      double ry,
      Color c, {
      bool Function(int x, int y)? where,
    }) {
      for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
        for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
          final dx = (x + .5 - cx) / rx, dy = (y + .5 - cy) / ry;
          if (dx * dx + dy * dy <= 1 && (where == null || where(x, y))) {
            put(x, y, c);
          }
        }
      }
    }

    void tri(List<math.Point<double>> p, Color c) {
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final px = x + .5, py = y + .5;
          double s(math.Point<double> a, math.Point<double> b) =>
              (px - b.x) * (a.y - b.y) - (a.x - b.x) * (py - b.y);
          final d1 = s(p[0], p[1]), d2 = s(p[1], p[2]), d3 = s(p[2], p[0]);
          final neg = d1 < 0 || d2 < 0 || d3 < 0;
          final pos = d1 > 0 || d2 > 0 || d3 > 0;
          if (!(neg && pos)) put(x, y, c);
        }
      }
    }
    // Tail: three sway positions.

    final sway = sleeping ? 0 : [0, 1, 2, 1][frame % 4];
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final x =
          (22 + t * 6 + math.sin(t * 2.6) * 1.5).round() + (sway * t).round();
      final y = (28 - t * 9).round();
      put(x, y, ginger);
      put(x + 1, y, ginger);
      put(x, y - 1, ginger);
    }
    // Body, belly, feet.
    final by = 25.5 + bob;
    ellipse(16, by, 8, 5.2, cream);
    ellipse(16, by + 1, 4.3, 3, white);
    ellipse(11, 29.8, 3, 1.3, cream);
    ellipse(21, 29.8, 3, 1.3, cream);
    // Ears (right ear twitches now and then).
    final twitch = !sleeping && phase > .62 && phase < .68 ? 1 : 0;
    final hy = bob.toDouble();
    tri([
      math.Point(5, 8 + hy),
      math.Point(6.5, 0.5 + hy),
      math.Point(13, 4.5 + hy),
    ], ginger);
    tri([
      math.Point(27, 8 + hy),
      math.Point(25.5 + twitch, 0.5 + hy + twitch),
      math.Point(19, 4.5 + hy),
    ], ginger);
    tri([
      math.Point(7, 6.5 + hy),
      math.Point(7.5, 3 + hy),
      math.Point(11, 5 + hy),
    ], pink);
    tri([
      math.Point(25, 6.5 + hy),
      math.Point(24.5 + twitch, 3 + hy + twitch),
      math.Point(21, 5 + hy),
    ], pink);
    // Head with a ginger crown.
    final hc = 12.0 + hy;
    ellipse(16, hc, 12, 8.5, cream);
    ellipse(
      16,
      hc,
      12,
      8.5,
      ginger,
      where: (x, y) => y < hc - 2.5 - (x - 16).abs() * .12,
    );
    // Paws hugging a coin.
    ellipse(16, 24.0 + bob, 2.5, 2.5, coin);
    ellipse(12.6, 25.0 + bob, 1.8, 1.4, cream);
    ellipse(19.4, 25.0 + bob, 1.8, 1.4, cream);
    // Scarf outfit.
    if (outfit > 0) {
      final scarf = outfit == 1
          ? const Color(0xff2e8b57)
          : HSVColor.fromAHSV(1, (outfit * 67.0) % 360, .55, .75).toColor();
      for (var x = 9; x <= 23; x++) {
        put(x, 21 + bob, scarf);
      }
      for (var y = 22; y <= 23; y++) {
        put(20, y + bob, scarf);
        put(21, y + bob, scarf);
      }
    }
    // Auto outline: every empty cell touching the sprite becomes outline.
    final lines = <math.Point<int>>{};
    for (final p in body.keys) {
      for (final d in const [
        math.Point(1, 0),
        math.Point(-1, 0),
        math.Point(0, 1),
        math.Point(0, -1),
      ]) {
        final q = math.Point(p.x + d.x, p.y + d.y);
        if (!body.containsKey(q)) lines.add(q);
      }
    }
    final paint = Paint()..isAntiAlias = false;
    void cellAt(int x, int y, Color c) {
      paint.color = c;
      canvas.drawRect(
        Rect.fromLTWH(ox + x * cell, oy + y * cell, cell + .6, cell + .6),
        paint,
      );
    }
    // Shadow.

    for (var x = 8; x <= 24; x++) {
      cellAt(x, 31, const Color(0x1a000000));
    }
    for (final p in lines) {
      if (p.x >= -1 && p.x <= n && p.y >= -1 && p.y < n) cellAt(p.x, p.y, outline);
    }
    body.forEach((p, c) => cellAt(p.x, p.y, c));
    // Features on top.
    final h = bob;
    for (final x in [13, 16, 19]) {
      for (var y = 4; y <= 6; y++) {
        if (x == 16 || y > 4) cellAt(x, y + h, stripe);
      }
    }
    for (final x in [8, 9, 22, 23]) {
      cellAt(x, 15 + h, pink.withValues(alpha: .7));
    }
    for (final side in [-1, 1]) {
      for (var i = 0; i < 3; i++) {
        cellAt(16 + side * (13 + i), 13 + h, whisker);
        cellAt(16 + side * (13 + i), 15 + h + (i == 2 ? 1 : 0), whisker);
      }
    }
    cellAt(15, 14 + h, pink);
    cellAt(16, 14 + h, pink);
    final blink = !sleeping && phase > .9 && phase < .95;
    final glance = sleeping
        ? 0
        : (phase > .3 && phase < .42
              ? -1
              : phase > .5 && phase < .6
              ? 1
              : 0);
    for (final ex in [10, 20]) {
      if (sleeping || blink) {
        // Closed: a little downward curve.
        cellAt(ex, 11 + h, eye);
        cellAt(ex + 1, 12 + h, eye);
        cellAt(ex + 2, 11 + h, eye);
      } else if (mood == PetMood.crying) {
        final left = ex == 10;
        cellAt(ex + (left ? 0 : 2), 10 + h, eye);
        cellAt(ex + 1, 11 + h, eye);
        cellAt(ex + (left ? 0 : 2), 12 + h, eye);
      } else {
        for (var y = 12; y <= 14; y++) {
          for (var x = 0; x <= 1; x++) {
            cellAt(ex + x + glance, y + h, eye);
          }
        }
        cellAt(ex + glance, 10 + h, white);
      }
      if (!sleeping && mood != PetMood.happy) {
        // Brows tilt up toward the middle.
        final inner = ex == 10 ? ex + 2 : ex;
        final outer = ex == 10 ? ex : ex + 2;
        cellAt(outer, 8 + h, eye);
        cellAt(ex + 1, 8 + h, eye);
        cellAt(inner, 7 + h, eye);
      }
    }
    // Mouth.
    if (sleeping) {
      cellAt(15, 16 + h, eye);
      cellAt(16, 16 + h, eye);
    } else if (mood == PetMood.happy) {
      cellAt(13, 16 + h, eye);
      cellAt(14, 17 + h, eye);
      cellAt(15, 16 + h, eye);
      cellAt(16, 16 + h, eye);
      cellAt(17, 17 + h, eye);
      cellAt(18, 16 + h, eye);
    } else if (mood == PetMood.worried) {
      cellAt(14, 17 + h, eye);
      cellAt(15, 16 + h, eye);
      cellAt(16, 17 + h, eye);
      cellAt(17, 16 + h, eye);
      cellAt(27, 4 + h, tear);
      cellAt(27, 5 + h, tear);
      cellAt(26, 5 + h, tear);
    } else {
      cellAt(14, 17 + h, eye);
      cellAt(15, 16 + h, eye);
      cellAt(16, 16 + h, eye);
      cellAt(17, 17 + h, eye);
      final drop = (phase * 7).floor();
      for (final x in [9, 22]) {
        cellAt(x, 13 + h + drop, tear);
        cellAt(x, 14 + h + drop, tear);
      }
    }
    cellAt(16, 24 + bob, coinDark);
    if (sleeping) {
      // Floating Z's that rise and fade.
      final zPaint = Paint()..isAntiAlias = false;
      for (var i = 0; i < 2; i++) {
        final t = (phase + i * .5) % 1;
        final zx = 25 + (t * 3).floor();
        final zy = 6 - (t * 6).floor();
        zPaint.color = const Color(0xff7c8fd6).withValues(alpha: 1 - t);
        for (final p in const [
          [0, 0],
          [1, 0],
          [2, 0],
          [1, 1],
          [0, 2],
          [1, 2],
          [2, 2],
        ]) {
          canvas.drawRect(
            Rect.fromLTWH(
              ox + (zx + p[0]) * cell,
              oy + (zy + p[1]) * cell,
              cell + .6,
              cell + .6,
            ),
            zPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelCatPainter old) =>
      old.phase != phase ||
      old.mood != mood ||
      old.outfit != outfit ||
      old.sleeping != sleeping ||
      old.growth != growth;
}
