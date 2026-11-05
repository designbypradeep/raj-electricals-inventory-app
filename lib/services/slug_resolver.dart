import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SlugResolver {
  static const String _kPrefSlugKey = 'shop_business_slug';
  final AppLinks _appLinks = AppLinks();

  /// Resolve the initial slug from Deep Link or Storage
  Future<String?> resolveInitialSlug() async {
    // 1. Check Deep Link (Priority)
    try {
      final Uri? uri = await _appLinks.getInitialLink();
      if (uri != null) {
        final slug = _parseSlugFromUri(uri);
        if (slug != null && slug.isNotEmpty) {
          await saveSlug(slug);
          return slug;
        }
      }
    } catch (e) {
      debugPrint('Error checking initial link: $e');
    }

    // 2. Check Storage (Fallback)
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPrefSlugKey);
  }

  /// Listen for deep links while app is running
  Stream<String> get slugStream {
    return _appLinks.uriLinkStream
        .map((uri) {
          final slug = _parseSlugFromUri(uri);
          if (slug != null && slug.isNotEmpty) {
            saveSlug(slug); // Auto-save on incoming link
            return slug;
          }
          return '';
        })
        .where((slug) => slug.isNotEmpty);
  }

  /// Parse slug from URI: https://inventoza.com/s/{slug}, myshop://store/{slug}, etc.
  String? _parseSlugFromUri(Uri uri) {
    final segments = uri.pathSegments;

    // 1. Inventoza SvelteKit Path: /s/{slug} (e.g. https://inventoza.com/s/raj-electricals)
    if (segments.length >= 2 && segments[0] == 's') {
      return segments[1];
    }
    // 2. Legacy / Store Path: /store/{slug}
    if (segments.length >= 2 && segments[0] == 'store') {
      return segments[1];
    }
    // 3. Custom Scheme Host: myshop://store/slug or inventoza://s/slug
    if ((uri.host == 'store' || uri.host == 's') && segments.isNotEmpty) {
      return segments[0];
    }
    // 4. Query Parameter fallbacks: ?id=slug or ?shop=slug or ?slug=slug
    if (uri.queryParameters.containsKey('id')) {
      return uri.queryParameters['id'];
    }
    if (uri.queryParameters.containsKey('shop')) {
      return uri.queryParameters['shop'];
    }
    if (uri.queryParameters.containsKey('slug')) {
      return uri.queryParameters['slug'];
    }
    return null;
  }

  /// Persist slug to storage
  Future<void> saveSlug(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefSlugKey, slug);
  }

  /// Clear saved slug (Logout/Change Shop)
  Future<void> clearSlug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefSlugKey);
  }
}
