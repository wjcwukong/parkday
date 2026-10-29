// Renders one screen at phone size and saves a PNG, for checking the 3D
// scenes without a screen-recording permission.
//
//   flutter run -d macos -t tool/shot.dart --dart-define=SHOT=room
//
// SHOT is home, room, map, fireworks, stars or sky; WAIT is the delay in ms before the
// capture. The PNG lands in the app's temp folder (printed as SHOT_SAVED).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:parkday/home/home_page.dart';
import 'package:parkday/lumi/lumi_brain.dart';
import 'package:parkday/screens/fireworks_show.dart';
import 'package:parkday/screens/lumi_room.dart';
import 'package:parkday/screens/park_map.dart';
import 'package:parkday/screens/sky_lift.dart';
import 'package:parkday/screens/star_catch.dart';
import 'package:parkday/theme.dart';

const _shot = String.fromEnvironment('SHOT', defaultValue: 'home');
const _wait = int.fromEnvironment('WAIT', defaultValue: 6000);
const _phone = Size(390, 844);

void main() => runApp(const _ShotApp());

class _ShotApp extends StatefulWidget {
  const _ShotApp();

  @override
  State<_ShotApp> createState() => _ShotAppState();
}

class _ShotAppState extends State<_ShotApp> {
  final boundary = GlobalKey();
  final brain = LumiBrain();

  @override
  void initState() {
    super.initState();
    if (_shot != 'home') brain.init();
    Future.delayed(const Duration(milliseconds: _wait), _capture);
  }

  Future<void> _capture() async {
    final box = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/shot_$_shot.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT_SAVED ${file.path}');
    exit(0);
  }

  Widget _screen() => switch (_shot) {
    'room' => LumiRoom(brain: brain),
    'map' => ParkMapScreen(brain: brain),
    'fireworks' => FireworksShow(brain: brain),
    'stars' => StarCatchGame(brain: brain),
    'sky' => SkyLiftGame(brain: brain, onBest: (_) {}),
    _ => const HomePage(),
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: OverflowBox(
          minWidth: _phone.width,
          maxWidth: _phone.width,
          minHeight: _phone.height,
          maxHeight: _phone.height,
          child: RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQueryData(size: _phone, devicePixelRatio: 2),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Pd.theme(),
                home: _screen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
