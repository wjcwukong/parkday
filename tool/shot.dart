// Renders one screen at phone size and saves a PNG, for checking the 3D
// scenes without a screen-recording permission.
//
//   flutter run -d macos -t tool/shot.dart --dart-define=SHOT=room
//
// SHOT is home, room, map, fireworks, stars or sky; WAIT is the delay in ms
// before the capture. The PNG lands in the app's temp folder (printed as
// SHOT_SAVED). For a sequence, TAP=x,y taps the screen at WAIT and
// FRAMES=ms,ms,... saves a frame that long after the tap, e.g. SHOT=home
// TAP=40,23 for Lumi's hops over the cards. Frames are kept in memory and
// only encoded at the end, so they can come every few frames.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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
const _tap = String.fromEnvironment('TAP');
const _frames = String.fromEnvironment('FRAMES');
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
    Future.delayed(const Duration(milliseconds: _wait), _tap.isEmpty ? _capture : _sequence);
  }

  Future<void> _capture() async {
    await _save('shot_$_shot');
    exit(0);
  }

  Future<void> _sequence() async {
    final box = boundary.currentContext!.findRenderObject()! as RenderBox;
    final xy = _tap.split(',').map(double.parse).toList();
    final at = box.localToGlobal(Offset(xy[0], xy[1]));
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(position: at));
    await Future.delayed(const Duration(milliseconds: 60));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(position: at));
    final start = DateTime.now();
    final frames = _frames.split(',').map(int.parse).toList();
    final images = <ui.Image>[];
    for (var i = 0; i < frames.length; i++) {
      final wait = frames[i] - DateTime.now().difference(start).inMilliseconds;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      images.add(await _grab());
      // ignore: avoid_print
      print('SHOT_AT $i ${DateTime.now().difference(start).inMilliseconds}');
    }
    for (var i = 0; i < images.length; i++) {
      await _save('shot_${_shot}_$i', images[i]);
    }
    exit(0);
  }

  Future<ui.Image> _grab() {
    final box = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return box.toImage(pixelRatio: 2);
  }

  Future<void> _save(String name, [ui.Image? image]) async {
    image ??= await _grab();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT_SAVED ${file.path}');
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
      // Top left, so a TAP near the top lands inside the window.
      child: Align(
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
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
