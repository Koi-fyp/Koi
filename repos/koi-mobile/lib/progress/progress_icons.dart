import 'dart:ui';

import '../shell/svg_path.dart';

/// The `Icon` set in progress/page.tsx (24x24 viewBox, stroke 2, round caps
/// and joins), drawn with StrokeIcon. Path data is copied verbatim;
/// `<circle>`, `<rect>` and `<line>` elements are built as equivalent paths.
abstract final class ProgressIcons {
  static Path _circle(double cx, double cy, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

  static Path _rect(double x, double y, double w, double h, double rx) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx)),
    );

  static Path _line(double x1, double y1, double x2, double y2) =>
      parseSvgPath('M$x1 ${y1}L$x2 $y2');

  static final List<Path> flame = [
    parseSvgPath(
      'M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z',
    ),
  ];

  static final List<Path> chat = [
    parseSvgPath(
      'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z',
    ),
  ];

  static final List<Path> smile = [
    _circle(12, 12, 10),
    parseSvgPath('M8 14s1.5 2 4 2 4-2 4-2'),
    _line(9, 9, 9.01, 9),
    _line(15, 9, 15.01, 9),
  ];

  static final List<Path> lock = [
    _rect(3, 11, 18, 11, 2),
    parseSvgPath('M7 11V7a5 5 0 0 1 10 0v4'),
  ];

  static final List<Path> check = [parseSvgPolyline('20 6 9 17 4 12')];

  static final List<Path> arrow = [
    _line(12, 5, 12, 19),
    parseSvgPolyline('19 12 12 19 5 12'),
  ];

  static final List<Path> sparkles = [
    parseSvgPath(
      'm12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z',
    ),
    parseSvgPath('M5 3v4'),
    parseSvgPath('M19 17v4'),
    parseSvgPath('M3 5h4'),
    parseSvgPath('M17 19h4'),
  ];

  static final List<Path> puzzle = [
    parseSvgPath(
      'M19.439 7.85c-.049.322.059.648.289.878l1.568 1.568c.47.47.706 1.087.706 1.704s-.235 1.233-.706 1.704l-1.611 1.611a.98.98 0 0 1-.837.276c-.47-.07-.802-.48-.968-.925a2.501 2.501 0 1 0-3.214 3.214c.446.166.855.497.925.968a.979.979 0 0 1-.276.837l-1.61 1.61a2.404 2.404 0 0 1-1.705.707 2.402 2.402 0 0 1-1.704-.706l-1.568-1.568a1.026 1.026 0 0 0-.877-.29c-.493.074-.84.504-1.02.968a2.5 2.5 0 1 1-3.237-3.237c.464-.18.894-.527.967-1.02a1.026 1.026 0 0 0-.289-.877l-1.568-1.568A2.402 2.402 0 0 1 1.998 12c0-.617.236-1.234.706-1.704L4.23 8.77c.24-.24.581-.353.917-.303.515.077.877.528 1.073 1.01a2.5 2.5 0 1 0 3.259-3.259c-.482-.196-.933-.558-1.01-1.073-.05-.336.062-.676.303-.917l1.525-1.525A2.402 2.402 0 0 1 12 1.998c.617 0 1.234.236 1.704.706l1.568 1.568c.23.23.556.338.877.29.493-.074.84-.504 1.02-.968a2.5 2.5 0 1 1 3.237 3.237c-.464.18-.894.527-.967 1.02Z',
    ),
  ];

  static final List<Path> download = [
    parseSvgPath('M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'),
    parseSvgPolyline('7 10 12 15 17 10'),
    _line(12, 15, 12, 3),
  ];

  static final List<Path> share = [
    _circle(18, 5, 3),
    _circle(6, 12, 3),
    _circle(18, 19, 3),
    _line(8.59, 13.51, 15.42, 17.49),
    _line(15.41, 6.51, 8.59, 10.49),
  ];

  static final List<Path> calendar = [
    _rect(3, 4, 18, 18, 2),
    _line(16, 2, 16, 6),
    _line(8, 2, 8, 6),
    _line(3, 10, 21, 10),
  ];

  static final List<Path> trendingUp = [
    parseSvgPolyline('23 6 13.5 15.5 8.5 10.5 1 18'),
    parseSvgPolyline('17 6 23 6 23 12'),
  ];

  static final List<Path> brain = [
    parseSvgPath(
      'M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24 2.5 2.5 0 0 1 1.98-3A2.5 2.5 0 0 1 9.5 2Z',
    ),
    parseSvgPath(
      'M14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24 2.5 2.5 0 0 0-1.98-3A2.5 2.5 0 0 0 14.5 2Z',
    ),
  ];
}
