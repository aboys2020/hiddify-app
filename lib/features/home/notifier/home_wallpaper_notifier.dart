import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/home/model/home_wallpaper.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// The page never shows more than a wallpaper this wide, on the widest window there is.
const _maxDecodedWidth = 2560;

/// Anything above this is not a wallpaper, and decoding it to throw it away is a waste.
const _maxSourceBytes = 32 * 1024 * 1024;

const _wallpaperDir = 'wallpapers';

/// What the home page should put behind itself, from the saved preference.
final homeWallpaperProvider = Provider<HomeWallpaperSpec>((ref) {
  final path = ref.watch(Preferences.homeWallpaperPath);
  if (path.isEmpty) return const HomeWallpaperSpec.builtin();

  final file = File(path);
  // The user can move or delete the file they picked; the map is always there.
  if (!file.existsSync()) return const HomeWallpaperSpec.builtin();

  return HomeWallpaperSpec(
    // A 30 MP photo decodes to well over a hundred megabytes if it goes into the image
    // cache whole. Width alone is enough: the page is landscape, and cover crops anyway.
    image: ResizeImage(FileImage(file), width: _maxDecodedWidth),
    opacity: ref.watch(Preferences.homeWallpaperOpacity).clamp(.05, 1.0).toDouble(),
    isCustom: true,
  );
});

/// Picking, replacing and clearing the picture. The file is copied into the app's own
/// directory, so it survives the original being moved, and is re-encoded through the
/// codec first: whatever the picked file claims to be, what lands on disk is a PNG of
/// an image this app has already decoded.
class HomeWallpaperController with InfraLogger {
  HomeWallpaperController(this._ref);

  final Ref _ref;

  Future<HomeWallpaperPickResult> pick() async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
        withData: false,
      );
    } catch (e, st) {
      loggy.warning('wallpaper picker failed', e, st);
      return HomeWallpaperPickResult.unreadable;
    }

    final files = picked?.files ?? const <PlatformFile>[];
    final source = files.isEmpty ? null : files.first.path;
    if (source == null) return HomeWallpaperPickResult.cancelled;

    try {
      final file = File(source);
      if (!file.existsSync()) return HomeWallpaperPickResult.unreadable;
      if (await file.length() > _maxSourceBytes) return HomeWallpaperPickResult.tooLarge;

      final normalised = await _normalise(await file.readAsBytes());
      if (normalised == null) return HomeWallpaperPickResult.unreadable;

      final target = await _newTargetFile();
      await target.writeAsBytes(normalised, flush: true);

      final previous = _ref.read(Preferences.homeWallpaperPath);
      await _ref.read(Preferences.homeWallpaperPath.notifier).update(target.path);
      await _deleteFile(previous);
      return HomeWallpaperPickResult.picked;
    } catch (e, st) {
      loggy.warning('could not set the home wallpaper', e, st);
      return HomeWallpaperPickResult.unreadable;
    }
  }

  Future<void> clear() async {
    final current = _ref.read(Preferences.homeWallpaperPath);
    await _ref.read(Preferences.homeWallpaperPath.notifier).update('');
    await _deleteFile(current);
  }

  /// Decodes the bytes once at the size the page can use, and writes them back out as PNG.
  /// Returns null when the file is not an image this platform can decode.
  Future<Uint8List?> _normalise(Uint8List raw) async {
    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(raw, targetWidth: _maxDecodedWidth);
    } on Exception {
      return null;
    }
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<File> _newTargetFile() async {
    final dirs = await _ref.read(appDirectoriesProvider.future);
    final dir = Directory(p.join(dirs.baseDir.path, _wallpaperDir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    // A fresh name each time: the image cache keys on the path, so overwriting one file
    // would keep showing the picture it decoded the first time.
    return File(p.join(dir.path, 'wallpaper-${DateTime.now().millisecondsSinceEpoch}.png'));
  }

  Future<void> _deleteFile(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      // Leaving a stale file behind is harmless; the preference no longer points at it.
      loggy.debug('could not delete the old wallpaper [$path]: $e');
    }
  }
}

enum HomeWallpaperPickResult { picked, cancelled, tooLarge, unreadable }

final homeWallpaperControllerProvider = Provider((ref) => HomeWallpaperController(ref));
