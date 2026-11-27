import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Maps–inspired basemap modes backed by free open-source tile servers.
enum AppMapStyle {
  street,
  dark,
  satellite,
  hybrid,
  terrain,
}

class MapStyleSpec {
  final AppMapStyle style;
  final String title;
  final String subtitle;
  final IconData icon;
  final String urlTemplate;
  final String? labelOverlayTemplate;
  final List<String> subdomains;
  final int maxNativeZoom;
  final bool isDarkCanvas;
  final Color canvasBackgroundColor;
  final Color previewPrimaryColor;
  final Color previewSecondaryColor;
  final Color previewAccentColor;

  const MapStyleSpec({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.urlTemplate,
    this.labelOverlayTemplate,
    this.subdomains = const ['a', 'b', 'c', 'd'],
    this.maxNativeZoom = 19,
    required this.isDarkCanvas,
    required this.canvasBackgroundColor,
    required this.previewPrimaryColor,
    required this.previewSecondaryColor,
    required this.previewAccentColor,
  });
}

class MapStyleRegistry {
  MapStyleRegistry._();

  static const String _prefKey = 'preferred_map_style_v1';
  static final ValueNotifier<AppMapStyle> styleNotifier =
      ValueNotifier<AppMapStyle>(AppMapStyle.street);

  static const Map<AppMapStyle, MapStyleSpec> specs = {
    AppMapStyle.street: MapStyleSpec(
      style: AppMapStyle.street,
      title: 'Default',
      subtitle: 'Crisp Street Map',
      icon: Icons.map_rounded,
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      maxNativeZoom: 19,
      isDarkCanvas: false,
      canvasBackgroundColor: Color(0xFFEDEFF2),
      previewPrimaryColor: Color(0xFFF3EFE6),
      previewSecondaryColor: Color(0xFFAAD3DF),
      previewAccentColor: Color(0xFF1A73E8),
    ),
    AppMapStyle.dark: MapStyleSpec(
      style: AppMapStyle.dark,
      title: 'Night',
      subtitle: 'Dark Vector Look',
      icon: Icons.dark_mode_rounded,
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      maxNativeZoom: 19,
      isDarkCanvas: true,
      canvasBackgroundColor: Color(0xFF141821),
      previewPrimaryColor: Color(0xFF181D27),
      previewSecondaryColor: Color(0xFF2B3445),
      previewAccentColor: Color(0xFF00E5FF),
    ),
    AppMapStyle.satellite: MapStyleSpec(
      style: AppMapStyle.satellite,
      title: 'Satellite',
      subtitle: 'Aerial Imagery',
      icon: Icons.satellite_alt_rounded,
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      subdomains: [],
      maxNativeZoom: 18,
      isDarkCanvas: true,
      canvasBackgroundColor: Color(0xFF0F1614),
      previewPrimaryColor: Color(0xFF1B3529),
      previewSecondaryColor: Color(0xFF315946),
      previewAccentColor: Color(0xFF26A69A),
    ),
    AppMapStyle.hybrid: MapStyleSpec(
      style: AppMapStyle.hybrid,
      title: 'Hybrid',
      subtitle: 'Imagery + Roads',
      icon: Icons.layers_rounded,
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      labelOverlayTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}{r}.png',
      subdomains: [],
      maxNativeZoom: 18,
      isDarkCanvas: true,
      canvasBackgroundColor: Color(0xFF0F1614),
      previewPrimaryColor: Color(0xFF1E3228),
      previewSecondaryColor: Color(0xFFFFD54F),
      previewAccentColor: Color(0xFF00E676),
    ),
    AppMapStyle.terrain: MapStyleSpec(
      style: AppMapStyle.terrain,
      title: 'Terrain',
      subtitle: 'Contours & Relief',
      icon: Icons.terrain_rounded,
      urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      maxNativeZoom: 17,
      isDarkCanvas: false,
      canvasBackgroundColor: Color(0xFFE7ECE4),
      previewPrimaryColor: Color(0xFFDDE7D3),
      previewSecondaryColor: Color(0xFFC3AF8D),
      previewAccentColor: Color(0xFF43A047),
    ),
  };

  static MapStyleSpec specFor(AppMapStyle style) =>
      specs[style] ?? specs[AppMapStyle.street]!;

  static Future<AppMapStyle> loadSavedStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        final match = AppMapStyle.values.where((v) => v.name == saved);
        if (match.isNotEmpty) {
          styleNotifier.value = match.first;
          return match.first;
        }
      }
    } catch (_) {}
    return styleNotifier.value;
  }

  static Future<void> saveStyle(AppMapStyle style) async {
    styleNotifier.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, style.name);
    } catch (_) {}
  }
}

/// Shared cached tile provider so map panning/zooming is fast and resilient.
class WorshipMapTiles {
  WorshipMapTiles._();

  static const String userAgentPackage = 'com.shadow.worshipchat';
  static NetworkTileProvider? _sharedTileProvider;

  static TileProvider get tileProvider {
    return _sharedTileProvider ??= NetworkTileProvider(
      silenceExceptions: true,
      headers: {
        'User-Agent': 'WorshipChat/1.0 ($userAgentPackage)',
      },
      cachingProvider: _createSafeCachingProvider(),
    );
  }

  static MapCachingProvider _createSafeCachingProvider() {
    try {
      final provider = BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: 150 * 1024 * 1024,
        overrideFreshAge: const Duration(days: 14),
      );
      if (provider.isSupported) {
        return provider;
      }
    } catch (_) {}
    return const DisabledMapCachingProvider();
  }

  /// Builds the primary raster [TileLayer] and, for Hybrid mode, the floating
  /// road/city label overlay [TileLayer].
  static List<Widget> buildTileLayers(
    BuildContext context,
    AppMapStyle style, {
    int keepBuffer = 3,
    int panBuffer = 1,
  }) {
    final spec = MapStyleRegistry.specFor(style);
    final bool isHighDpi = RetinaMode.isHighDensity(context);

    final baseLayer = TileLayer(
      key: ValueKey('base_${style.name}'),
      urlTemplate: spec.urlTemplate,
      subdomains: spec.subdomains,
      userAgentPackageName: userAgentPackage,
      maxNativeZoom: spec.maxNativeZoom,
      maxZoom: 20.0,
      keepBuffer: keepBuffer,
      panBuffer: panBuffer,
      retinaMode: spec.urlTemplate.contains('{r}') ? isHighDpi : false,
      tileProvider: tileProvider,
      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 180),
      ),
    );

    if (spec.labelOverlayTemplate == null) {
      return [baseLayer];
    }

    final labelOverlay = TileLayer(
      key: ValueKey('labels_${style.name}'),
      urlTemplate: spec.labelOverlayTemplate,
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: userAgentPackage,
      maxNativeZoom: 19,
      maxZoom: 20.0,
      keepBuffer: keepBuffer,
      panBuffer: panBuffer,
      retinaMode: isHighDpi,
      tileProvider: tileProvider,
      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 180),
      ),
    );

    return [baseLayer, labelOverlay];
  }
}
