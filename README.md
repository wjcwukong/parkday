# Parkday

A recreation of the Parkday theme-park demo by Brandon DeRosier ([@algebrandon](https://x.com/algebrandon)).
The header stars Lumi, a little 3D lantern spirit rendered live with [Flutter Scene](https://fscene.dev) on Flutter GPU.

## What's in it

- **Lumi** is built from primitives with a custom glass material (`assets/materials/lumi_glass.fmat`).
  It blinks, follows your finger with its eyes and changes expression.
  - Notifications fly in as cards in the 3D scene (`lib/scene/note_card.dart`). Lumi catches one,
    tips it up to its mouth and swallows it whole, then tells you what it said.
  - Tap the "Parkday" wordmark and the whole page tips back into perspective: the feed cards stand up
    as slabs and Lumi glides over them, lighting each one up. The scene camera swings by the same
    transform as the widgets, so the 3D and the UI stay in register.
  - Pet Lumi slowly and it blushes, gets sleepy and falls asleep. Tap to wake it.
  - Shake it too fast and it gets dizzy. Tap it for a bounce.
  - Scroll the feed and Lumi rides the scrollbar.
- **Home feed**: search, tonight's fireworks, a nearby reward (send Lumi to fetch the key), weather
  (rain brings an umbrella, snow brings a snowman), a photo booth, games, the park map, wait times and dining.
- **Wardrobe**: swap friends (Lumi, Juju, Mochi, Nova), hats, colors and glow. Swaps, tricks and found
  keys fire 3D spark bursts (`lib/scene/fx.dart`) that bloom over the UI.
- **Fireworks over the lagoon**: a 60 second 3D show with a scrubbable timeline and camera chapters.
  Every spark, trail and smoke puff is one mesh moved on the GPU by `assets/materials/sparks.fmat`
  (motion is a function of time, so scrubbing is free). The lagoon mirrors the scene with a planar
  reflector and `lagoon.fmat`, with bloom, purple haze and depth of field on the close shots.
- **Lumi's room**: an orbitable floating island room. Tap a hat to wear it, or tap the cushion for a nap.
- **Park map**: a 3D island with live waits. Each ride's wait tag is the real Flutter widget on a card in
  the scene (Flutter Scene's `WidgetComponent`), so it sits in perspective and hides behind the rides.
  Tap a tag and Lumi hops over.
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

- `lib/scene/` holds the 3D rig for Lumi and friends, the spark effects, note cards, and the
  screen-to-world mapping.
- `lib/lumi/lumi_brain.dart` holds Lumi's behaviour: petting, sleep, notifications, the page fly-over,
  riding and speech.
- `lib/home/` holds the home page, feed cards and wardrobe.
- `lib/screens/` holds the fireworks show, room, park map and games.
