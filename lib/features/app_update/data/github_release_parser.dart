import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';

abstract class GithubReleaseParser {
  /// A release's tag: v5.4.0, optionally with a pre-release (v5.4.0-beta.1, v5.4.0.dev) or a build
  /// number (v5.4.0+540). Tags that are no version, like the rolling "draft" release, do not match.
  static final _tag = RegExp(r'^v?(\d+\.\d+\.\d+)(?:[-.]([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$');

  /// The release, or null when its tag names no version or it is a draft.
  static RemoteVersionEntity? parse(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final fullTag = (json['tag_name'] as String? ?? '').trim();
    final match = _tag.firstMatch(fullTag);
    if (match == null) return null;
    final suffix = match.group(2) ?? '';
    final flavor = suffix == Environment.dev.name ? Environment.dev : Environment.prod;
    final assets = [
      for (final asset in json['assets'] as List? ?? const [])
        if (asset case {'name': final String name, 'browser_download_url': final String url})
          // An asset is downloaded and then run, so only files GitHub itself serves are kept:
          // a tampered API response cannot point the updater at some other host, or at http.
          if (_isTrustedAssetUrl(url))
            ReleaseAsset(
              name: name,
              url: url,
              size: (asset['size'] as num?)?.toInt() ?? 0,
              digest: asset['digest'] as String?,
            ),
    ];
    return RemoteVersionEntity(
      version: match.group(1)!,
      buildNumber: match.group(3) ?? '',
      releaseTag: fullTag,
      // GitHub's flag is set on every release the workflow uploads, stable or not: the tag says
      // which a release is
      preRelease: suffix.isNotEmpty,
      url: json['html_url'] as String,
      publishedAt: DateTime.parse(json['published_at'] as String),
      flavor: flavor,
      assets: assets,
    );
  }

  /// Hosts a release asset legitimately comes from: the release page, the API, and the two
  /// hosts GitHub redirects downloads to.
  static const _trustedAssetHosts = {
    'github.com',
    'api.github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  static bool _isTrustedAssetUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty && _trustedAssetHosts.contains(uri.host);
  }
}
