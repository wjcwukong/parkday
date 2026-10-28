# Parkday

A recreation of the Parkday theme-park demo by Brandon DeRosier ([@algebrandon](https://x.com/algebrandon)).
The header stars Lumi, a little 3D lantern spirit rendered live with [Flutter Scene](https://fscene.dev) on Flutter GPU.

## What's in it

- **Lumi** is built from primitives with a custom glass material (`assets/materials/lumi_glass.fmat`).
  It blinks, follows your finger with its eyes and changes expression.
  - Notifications slide in, and Lumi gulps them down and tells you what they said.
  - Pet Lumi slowly and it blushes, gets sleepy and falls asleep. Tap to wake it.
  - Shake it too fast and it gets dizzy. Tap it for a bounce.
  - Scroll the feed and Lumi rides the scrollbar.
- **Home feed**: search, tonight's fireworks, a nearby reward (send Lumi to fetch the key), weather
  (rain brings an umbrella, snow brings a snowman), a photo booth, games, the park map, wait times and dining.
- **Wardrobe**: swap friends (Lumi, Juju, Mochi, Nova), hats, colors and glow.
- **Fireworks over the lagoon**: a 60 second 3D show with a scrubbable timeline and camera chapters.
- **Lumi's room**: an orbitable floating island room. Tap a hat to wear it, or tap the cushion for a nap.
- **Park map**: a 3D island with live waits. Lumi hops over to the ride with the shortest wait.
- **Games**: Star Catch (45 seconds of falling stars) and Sky Lift (float as high as you can, up to the moon).

## Running

Needs Flutter 3.47 or newer (Flutter GPU).

```sh
flutter pub get

# Web (WebGL2 backend, no flags needed)
flutter run -d chrome

# iOS / Android / macOS (Impeller with Flutter GPU)
flutter run --enable-flutter-gpu
```

For a native release build, pass `--enable-flutter-gpu` too, or set `FLTEnableFlutterGPU` in
`Info.plist` / `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml`.

## Layout

- `lib/scene/` holds the 3D rig for Lumi and friends, plus the screen-to-world mapping.
- `lib/lumi/lumi_brain.dart` holds Lumi's behaviour: petting, sleep, notifications, riding and speech.
- `lib/home/` holds the home page, feed cards and wardrobe.
- `lib/screens/` holds the fireworks show, room, park map and games.
