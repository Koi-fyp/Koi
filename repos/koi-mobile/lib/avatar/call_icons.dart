import 'dart:ui';

import '../shell/svg_path.dart';

// Avatar call screen icons: Feather icons (MIT), the same 24x24 stroked
// set as the web chat's send icon (InputBar.tsx 'M22 2L11 13').

// feather "mic"
final List<Path> micIconPaths = [
  parseSvgPath('M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z'),
  parseSvgPath('M19 10v2a7 7 0 0 1-14 0v-2'),
  parseSvgPath('M12 19v4'),
  parseSvgPath('M8 23h8'),
];

// feather "video"
final List<Path> videoIconPaths = [
  parseSvgPath('M23 7l-7 5 7 5V7z'),
  parseSvgPath(
    'M3 5h11a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
  ),
];

// feather "message-square"
final List<Path> chatIconPaths = [
  parseSvgPath('M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'),
];

// feather "phone-off"
final List<Path> endCallIconPaths = [
  parseSvgPath(
    'M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 '
    '12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2 '
    '19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34'
    'a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 '
    '12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91',
  ),
  parseSvgPath('M23 1L1 23'),
];

// feather "x"
final List<Path> closeIconPaths = [
  parseSvgPath('M18 6L6 18'),
  parseSvgPath('M6 6l12 12'),
];
