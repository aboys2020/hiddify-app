import 'package:flutter/painting.dart';

/// What the home page draws behind the connect button: a picture the user picked, or
/// the built-in world map.
///
/// The map is a hint of a thing — it sits at 9% over the page so the connect button
/// and the profile card stay readable across it. A picture the user chose themselves
/// is there because they want to see it, so it starts much stronger and is drawn in
/// its own colours (the map is flattened to grey, which would ruin a photo).
///
/// Every field is final and equality is by value, so a rebuild repaints the background
/// only when the picture or its strength really changed.
class HomeWallpaperSpec {
  const HomeWallpaperSpec({required this.image, required this.opacity, required this.isCustom});

  /// The bundled world map, drawn as it always was.
  const HomeWallpaperSpec.builtin()
    : image = const AssetImage('assets/images/world_map.png'),
      opacity = .09,
      isCustom = false;

  final ImageProvider image;

  /// Passed to [DecorationImage.opacity]: how much of the page background shows through.
  final double opacity;

  /// True when [image] is the user's own picture rather than the bundled map.
  final bool isCustom;

  @override
  bool operator ==(Object other) =>
      other is HomeWallpaperSpec && other.image == image && other.opacity == opacity && other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(image, opacity, isCustom);
}
