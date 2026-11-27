import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:worship_chat/colors.dart';
import 'package:worship_chat/common/utils/location_service.dart';
import 'package:worship_chat/common/utils/map_style_config.dart';

enum LocationShareType { current, live }

class LocationResult {
  final LocationShareType type;
  final double latitude;
  final double longitude;
  final Duration? duration;
  final double? accuracy;
  final double? heading;
  final double? speed;
  final String? placeName;
  final String? address;

  LocationResult({
    required this.type,
    required this.latitude,
    required this.longitude,
    this.duration,
    this.accuracy,
    this.heading,
    this.speed,
    this.placeName,
    this.address,
  });
}

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key});

  static Future<LocationResult?> show(BuildContext context) {
    return showModalBottomSheet<LocationResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: false,
      builder: (context) => const LocationPickerSheet(),
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Position? _gpsPosition;
  LatLng? _selectedPoint;
  bool _isUsingCustomPin = false;
  bool _isDraggingMap = false;
  bool _isMapReady = false;

  bool _isLoading = true;
  bool _isRefreshingGps = false;
  LocationReadiness _readiness = LocationReadiness.ready;
  String? _errorMessage;

  String? _resolvedPlaceName;
  String? _resolvedAddress;
  bool _isReverseGeocoding = false;

  List<PlaceSearchResult> _searchResults = const [];
  bool _isSearching = false;
  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  CancelToken? _searchCancel;
  CancelToken? _reverseCancel;

  Duration _selectedLiveDuration = const Duration(hours: 1);
  bool _showDurationSelector = false;
  AppMapStyle _mapStyle = MapStyleRegistry.styleNotifier.value;

  AnimationController? _cameraAnimController;

  @override
  void initState() {
    super.initState();
    _initStylesAndLocation();
  }

  Future<void> _initStylesAndLocation() async {
    unawaited(
      MapStyleRegistry.loadSavedStyle().then((saved) {
        if (mounted && saved != _mapStyle) {
          setState(() => _mapStyle = saved);
        }
      }),
    );
    await _fetchPosition();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCancel?.cancel();
    _reverseCancel?.cancel();
    _cameraAnimController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchPosition() async {
    setState(() {
      if (_gpsPosition == null) {
        _isLoading = true;
      } else {
        _isRefreshingGps = true;
      }
      _errorMessage = null;
    });

    try {
      // Seed quickly from last known GPS so the map renders right away.
      final fast = await LocationService.instance.getFastInitialPosition();
      if (mounted && fast != null && _selectedPoint == null) {
        final fastLatLng = LatLng(fast.latitude, fast.longitude);
        setState(() {
          _gpsPosition = fast;
          _selectedPoint = fastLatLng;
          _isLoading = false;
        });
        _scheduleReverseGeocode(fastLatLng);
      }

      final readiness = await LocationService.instance.checkLocationReadiness();
      if (!mounted) return;
      _readiness = readiness;

      if (readiness != LocationReadiness.ready) {
        setState(() {
          _isLoading = false;
          _isRefreshingGps = false;
          _errorMessage = switch (readiness) {
            LocationReadiness.serviceDisabled =>
              'GPS is turned off on your device. Turn on Location services to pinpoint your spot.',
            LocationReadiness.permissionDenied =>
              'Location permission was denied. Allow access so we can share your location.',
            LocationReadiness.permissionDeniedForever =>
              'Location permission is permanently denied. Enable it in App Settings.',
            LocationReadiness.ready => null,
          };
        });
        return;
      }

      final pos = await LocationService.instance.getCurrentLocation();
      if (!mounted) return;

      if (pos != null) {
        final gpsLatLng = LatLng(pos.latitude, pos.longitude);
        final shouldSnapToGps = !_isUsingCustomPin;
        setState(() {
          _gpsPosition = pos;
          if (shouldSnapToGps || _selectedPoint == null) {
            _selectedPoint = gpsLatLng;
          }
          _isLoading = false;
          _isRefreshingGps = false;
        });
        if (shouldSnapToGps) {
          _animateCamera(gpsLatLng, 16.5);
          _scheduleReverseGeocode(gpsLatLng);
        }
      } else {
        setState(() {
          _isLoading = false;
          _isRefreshingGps = false;
          if (_selectedPoint == null) {
            _errorMessage = 'Could not acquire a GPS signal. Try again outdoors.';
          }
        });
      }
    } catch (e) {
      log('Error in LocationPickerSheet: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshingGps = false;
          if (_selectedPoint == null) {
            _errorMessage = 'Could not get location: $e';
          }
        });
      }
    }
  }

  void _animateCamera(LatLng dest, double destZoom) {
    if (!_isMapReady) return;
    _cameraAnimController?.stop();
    _cameraAnimController?.dispose();
    _cameraAnimController = null;

    final camera = _mapController.camera;
    final latTween = Tween<double>(begin: camera.center.latitude, end: dest.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _cameraAnimController = ctrl;
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);

    ctrl.addListener(() {
      if (!mounted || !_isMapReady) return;
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (identical(_cameraAnimController, ctrl)) {
          _cameraAnimController = null;
        }
        ctrl.dispose();
      }
    });
    ctrl.forward();
  }

  void _scheduleReverseGeocode(LatLng point) {
    _reverseDebounce?.cancel();
    _reverseCancel?.cancel();
    if (mounted) {
      setState(() => _isReverseGeocoding = true);
    }

    _reverseDebounce = Timer(const Duration(milliseconds: 420), () async {
      final token = CancelToken();
      _reverseCancel = token;
      try {
        final result = await LocationService.instance.reverseGeocode(
          point.latitude,
          point.longitude,
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        setState(() {
          _resolvedPlaceName = result?.placeName;
          _resolvedAddress = result?.address;
          _isReverseGeocoding = false;
        });
      } catch (_) {
        if (mounted && !token.isCancelled) {
          setState(() => _isReverseGeocoding = false);
        }
      }
    });
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchCancel?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final token = CancelToken();
      _searchCancel = token;
      try {
        final bias = _selectedPoint ??
            (_gpsPosition != null
                ? LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude)
                : null);
        final items = await LocationService.instance.searchPlaces(
          query,
          biasLat: bias?.latitude,
          biasLng: bias?.longitude,
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        setState(() {
          _searchResults = items;
          _isSearching = false;
        });
      } catch (_) {
        if (mounted && !token.isCancelled) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  void _selectSearchResult(PlaceSearchResult item) {
    HapticFeedback.selectionClick();
    _searchFocusNode.unfocus();
    final target = item.latLng;
    setState(() {
      _searchResults = const [];
      _searchController.clear();
      _selectedPoint = target;
      _isUsingCustomPin = true;
      _errorMessage = null;
      _isLoading = false;
      _resolvedPlaceName = item.name;
      _resolvedAddress = item.subtitle.isNotEmpty
          ? '${item.name}, ${item.subtitle}'
          : item.name;
    });
    _animateCamera(target, 16.5);
  }

  void _recenterToMyGps() {
    HapticFeedback.selectionClick();
    if (_gpsPosition == null) {
      _fetchPosition();
      return;
    }
    final gpsLatLng = LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude);
    setState(() {
      _isUsingCustomPin = false;
      _selectedPoint = gpsLatLng;
    });
    _animateCamera(gpsLatLng, 16.8);
    _scheduleReverseGeocode(gpsLatLng);
  }

  void _cycleMapStyle() {
    HapticFeedback.selectionClick();
    const styles = [
      AppMapStyle.street,
      AppMapStyle.dark,
      AppMapStyle.hybrid,
      AppMapStyle.terrain,
    ];
    final nextIdx = (styles.indexOf(_mapStyle) + 1) % styles.length;
    final nextStyle = styles[nextIdx];
    setState(() => _mapStyle = nextStyle);
    MapStyleRegistry.saveStyle(nextStyle);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetMaxHeight = media.size.height * 0.88;
    final activePoint = _selectedPoint ??
        (_gpsPosition != null
            ? LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude)
            : null);

    return Container(
      constraints: BoxConstraints(maxHeight: sheetMaxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF151622),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF4FC3F7),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Share Location',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isRefreshingGps)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4FC3F7),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: greyColor),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                  ),
                ],
              ),
            ),

            // Search bar (always accessible so user can search or paste coordinates even without GPS)
            if (!_isLoading || activePoint != null || _errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: _buildSearchField(),
              ),

            if (_isLoading && activePoint == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 42),
                child: Column(
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFF1A73E8),
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Acquiring GPS location...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else if (_errorMessage != null && activePoint == null)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151622),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: _buildSearchResultsList(),
                        ),
                      _buildErrorState(),
                    ],
                  ),
                ),
              )
            else if (activePoint != null) ...[
              // Interactive Map Frame + Search Overlay
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInteractiveMapBox(activePoint),
                      const SizedBox(height: 10),
                      _buildSelectedPlaceSummary(activePoint),
                      const SizedBox(height: 12),

                      // Option 1: Send Current / Selected Pin Location
                      _buildSendStaticButton(activePoint),

                      // Option 2: Share Live Location (only when device GPS is available)
                      if (_gpsPosition != null) ...[
                        const SizedBox(height: 10),
                        _buildLiveSharingSection(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              color: Colors.orangeAccent,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_readiness == LocationReadiness.serviceDisabled ||
                  _readiness == LocationReadiness.permissionDeniedForever)
                OutlinedButton.icon(
                  onPressed: () {
                    if (_readiness == LocationReadiness.serviceDisabled) {
                      LocationService.instance.openLocationSettings();
                    } else {
                      LocationService.instance.openAppSettings();
                    }
                  },
                  icon: const Icon(Icons.settings_rounded, size: 17),
                  label: Text(
                    _readiness == LocationReadiness.serviceDisabled
                        ? 'Location Settings'
                        : 'App Settings',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4FC3F7),
                    side: const BorderSide(color: Color(0xFF4FC3F7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _fetchPosition,
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: Colors.white),
                label: const Text(
                  'Retry GPS',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF202233),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: Colors.white60, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: 'Search places, temples, addresses...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4FC3F7),
                ),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchResults = const []);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMapBox(LatLng activePoint) {
    final spec = MapStyleRegistry.specFor(_mapStyle);
    final gpsLatLng = _gpsPosition != null
        ? LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude)
        : null;
    final accuracyMeters =
        (_gpsPosition?.accuracy ?? 20.0).clamp(6.0, 200.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 270,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(color: spec.canvasBackgroundColor),
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: activePoint,
                initialZoom: 16.4,
                minZoom: 3.0,
                maxZoom: 20.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  if (mounted) {
                    setState(() => _isMapReady = true);
                  }
                },
                onMapEvent: (event) {
                  if (event is MapEventMoveStart &&
                      event.source != MapEventSource.mapController) {
                    if (!_isDraggingMap) {
                      setState(() => _isDraggingMap = true);
                    }
                  } else if (event is MapEventMove &&
                      event.source != MapEventSource.mapController) {
                    _selectedPoint = event.camera.center;
                    if (!_isUsingCustomPin) {
                      _isUsingCustomPin = true;
                    }
                  } else if (event is MapEventMoveEnd &&
                      event.source != MapEventSource.mapController) {
                    final target = event.camera.center;
                    setState(() {
                      _isDraggingMap = false;
                      _isUsingCustomPin = true;
                      _selectedPoint = target;
                    });
                    _scheduleReverseGeocode(target);
                  }
                },
              ),
              children: [
                ...WorshipMapTiles.buildTileLayers(
                  context,
                  _mapStyle,
                  keepBuffer: 2,
                  panBuffer: 1,
                ),
                if (gpsLatLng != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: gpsLatLng,
                        radius: accuracyMeters,
                        useRadiusInMeter: true,
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.16),
                        borderColor:
                            const Color(0xFF1A73E8).withValues(alpha: 0.45),
                        borderStrokeWidth: 1.4,
                      ),
                    ],
                  ),
                if (gpsLatLng != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: gpsLatLng,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1A73E8),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1A73E8)
                                    .withValues(alpha: 0.45),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                Scalebar(
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.only(left: 10, bottom: 10),
                  textStyle: TextStyle(
                    color: spec.isDarkCanvas ? Colors.white70 : Colors.black87,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  lineColor: spec.isDarkCanvas ? Colors.white70 : Colors.black87,
                ),
              ],
            ),

            // Animated center teardrop pin (lifts cleanly while panning)
            IgnorePointer(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 140),
                offset: _isDraggingMap ? const Offset(0, -0.22) : Offset.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isUsingCustomPin
                            ? const Color(0xFFEA4335)
                            : const Color(0xFF1A73E8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Container(
                      width: _isDraggingMap ? 8 : 5,
                      height: 3,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top drag hint pill
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF151622).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _isUsingCustomPin ? 'Custom Pin' : 'Drag map to move pin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Map layer & My GPS controls
            Positioned(
              right: 10,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniMapAction(
                    icon: spec.icon,
                    color: Colors.white,
                    tooltip: 'Switch style (${spec.title})',
                    onTap: _cycleMapStyle,
                  ),
                  const SizedBox(height: 8),
                  _miniMapAction(
                    icon: Icons.my_location_rounded,
                    color: _isUsingCustomPin
                        ? Colors.white
                        : const Color(0xFF4FC3F7),
                    tooltip: 'Center on GPS',
                    onTap: _recenterToMyGps,
                  ),
                ],
              ),
            ),

            // Place search suggestions dropdown overlay
            if (_searchResults.isNotEmpty)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF151622).withValues(alpha: 0.96),
                  child: _buildSearchResultsList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    return Material(
      type: MaterialType.transparency,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        itemBuilder: (_, idx) {
          final item = _searchResults[idx];
          return ListTile(
            dense: true,
            leading: const Icon(
              Icons.place_rounded,
              color: Color(0xFF4FC3F7),
              size: 20,
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: item.subtitle.isNotEmpty
                ? Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                    ),
                  )
                : null,
            onTap: () => _selectSearchResult(item),
          );
        },
      ),
    );
  }

  Widget _miniMapAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF151622).withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, color: color, size: 19),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPlaceSummary(LatLng activePoint) {
    final coordLine =
        '${activePoint.latitude.toStringAsFixed(5)}, ${activePoint.longitude.toStringAsFixed(5)}';
    final title = _resolvedPlaceName?.isNotEmpty == true
        ? _resolvedPlaceName!
        : (_isUsingCustomPin ? 'Selected Pin' : 'Your Current Location');
    final subtitle = _isReverseGeocoding
        ? 'Looking up street address...'
        : (_resolvedAddress?.isNotEmpty == true ? _resolvedAddress! : coordLine);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            _isUsingCustomPin
                ? Icons.location_on_rounded
                : Icons.my_location_rounded,
            color: _isUsingCustomPin
                ? const Color(0xFFEA4335)
                : const Color(0xFF4FC3F7),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (_isUsingCustomPin && _gpsPosition != null)
            TextButton(
              onPressed: _recenterToMyGps,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4FC3F7),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Use GPS', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildSendStaticButton(LatLng activePoint) {
    final subtitle = _isUsingCustomPin
        ? (_resolvedPlaceName ?? 'Custom map pin')
        : (_gpsPosition != null
            ? 'Accurate to ${_gpsPosition!.accuracy.round()} meters'
            : 'Fast static GPS snapshot');

    return Material(
      color: const Color(0xFF1A73E8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.mediumImpact();
          Navigator.pop(
            context,
            LocationResult(
              type: LocationShareType.current,
              latitude: activePoint.latitude,
              longitude: activePoint.longitude,
              accuracy: _isUsingCustomPin ? null : _gpsPosition?.accuracy,
              placeName: _resolvedPlaceName,
              address: _resolvedAddress,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isUsingCustomPin
                          ? 'Send Selected Location'
                          : 'Send Your Current Location',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white70, size: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveSharingSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _showDurationSelector = !_showDurationSelector);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: Color(0xFF00E676),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Live Location',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Streams real-time GPS movement & speed',
                          style: TextStyle(color: Colors.white60, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showDurationSelector
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white60,
                  ),
                ],
              ),
            ),
          ),
          if (_showDurationSelector)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildDurationChip(const Duration(minutes: 15), '15 mins'),
                      const SizedBox(width: 8),
                      _buildDurationChip(const Duration(hours: 1), '1 hour'),
                      const SizedBox(width: 8),
                      _buildDurationChip(const Duration(hours: 8), '8 hours'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Start Live Sharing',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B074),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(
                          context,
                          LocationResult(
                            type: LocationShareType.live,
                            latitude: _gpsPosition!.latitude,
                            longitude: _gpsPosition!.longitude,
                            duration: _selectedLiveDuration,
                            accuracy: _gpsPosition!.accuracy,
                            heading: _gpsPosition!.heading,
                            speed: _gpsPosition!.speed,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDurationChip(Duration duration, String label) {
    final isSelected = _selectedLiveDuration == duration;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedLiveDuration = duration);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00B074)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
