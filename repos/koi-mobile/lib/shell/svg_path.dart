import 'dart:ui';

/// Minimal SVG path-data parser, enough to draw the web nav icons from their
/// exact path strings (no SVG package is on the approved list).
///
/// Supports M/m, L/l, H/h, V/v, C/c, A/a and Z/z, the commands used
/// by the web nav and chat icons. Throws [FormatException] on anything
/// else so an unsupported icon fails loudly instead of drawing wrong.
Path parseSvgPath(String d) {
  final tokens = RegExp(
    // Numbers first (so an exponent "e" stays inside its number), then any
    // letter, so unsupported commands reach the `default:` throw below.
    r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|[A-Za-z]',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd.isEmpty) {
      throw FormatException('Path data must start with a command', d);
    }
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Further coordinate pairs after a moveto are implicit linetos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'H':
        x = next() + (rel ? x : 0);
        path.lineTo(x, y);
      case 'V':
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'C':
        final x1 = next() + (rel ? x : 0), y1 = next() + (rel ? y : 0);
        final x2 = next() + (rel ? x : 0), y2 = next() + (rel ? y : 0);
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final largeArc = next() != 0, sweep = next() != 0;
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep, // SVG sweep-flag 1 = clockwise in y-down space
        );
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        throw FormatException('Unsupported SVG path command "$cmd"', d);
    }
  }
  return path;
}

/// SVG `<polyline points="...">` as an open path.
Path parseSvgPolyline(String points) {
  final n = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)')
      .allMatches(points)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  if (n.length < 4 || n.length.isOdd) {
    throw FormatException('Bad polyline points', points);
  }
  final path = Path()..moveTo(n[0], n[1]);
  for (var j = 2; j < n.length; j += 2) {
    path.lineTo(n[j], n[j + 1]);
  }
  return path;
}
