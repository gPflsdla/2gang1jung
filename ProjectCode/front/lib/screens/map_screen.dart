import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../api/route_api.dart';
import '../models/route_response.dart';

enum RouteMode { wheelchair, normal }

enum MapPickTarget { start, end }

class CampusPoi {
  final String id;
  final String name;
  final List<String> alias;
  final LatLng point;
  final String type;
  final double radiusMeters;

  const CampusPoi({
    required this.id,
    required this.name,
    required this.alias,
    required this.point,
    required this.type,
    required this.radiusMeters,
  });

  factory CampusPoi.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num).toDouble();
    final lng = (json['lng'] as num).toDouble();

    return CampusPoi(
      id: json['id'] as String,
      name: json['name'] as String,
      alias: (json['alias'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      // lat은 위도(latitude), lng는 경도(longitude)입니다.
      point: LatLng(lat, lng),
      type: json['type'] as String? ?? 'place',
      radiusMeters: (json['radius_m'] as num?)?.toDouble() ?? 30.0,
    );
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return name.toLowerCase().contains(normalized) ||
        alias.any((item) => item.toLowerCase().contains(normalized));
  }
}

class FavoritePlace {
  final String id;
  final String name;
  final LatLng point;
  final String type;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.point,
    required this.type,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final RouteApiService _apiService = RouteApiService(
    baseUrl: 'http://10.0.2.2:8000/api/v1',
  );

  static const LatLng _campusSouthWest = LatLng(33.4465, 126.5485);
  static const LatLng _campusNorthEast = LatLng(33.4655, 126.5735);
  static final LatLngBounds _campusBounds = LatLngBounds(
    _campusSouthWest,
    _campusNorthEast,
  );
  static const LatLng _initialCenter = LatLng(33.4559, 126.5618);
  static const double _initialZoom = 17.0;

  List<CampusPoi> _campusPois = [];
  final List<FavoritePlace> _favorites = [];

  LatLng? _currentLocation;
  LatLng? _startPoint;
  LatLng? _endPoint;
  String? _startLabel;
  String? _endLabel;
  RouteResponse? _routeData;
  List<LatLng> _routeCoords = [];

  LatLng? _pendingPoint;
  String? _pendingLabel;
  CampusPoi? _pendingPoi;

  RouteMode _routeMode = RouteMode.wheelchair;
  MapPickTarget _mapPickTarget = MapPickTarget.end;
  bool _isStartPointFromGps = false;
  bool _isLoading = false;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMapData();
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _initializeMapData() async {
    await _loadCampusPois();
    await _setCurrentLocationAsStart();
  }

  Future<void> _loadCampusPois() async {
    try {
      final jsonText = await rootBundle.loadString('assets/data/jnu_pois.json');
      final rawItems = jsonDecode(jsonText) as List<dynamic>;
      final pois = rawItems
          .map((item) => CampusPoi.fromJson(item as Map<String, dynamic>))
          .where(_isValidPoi)
          .toList();

      if (!mounted) return;
      setState(() => _campusPois = pois);
    } catch (error) {
      debugPrint('POI 로드 실패: $error');
      if (mounted) setState(() => _campusPois = []);
    }
  }

  bool _isValidPoi(CampusPoi poi) {
    final lat = poi.point.latitude;
    final lng = poi.point.longitude;
    final hasValidLatLng =
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

    if (!hasValidLatLng) {
      debugPrint(
        'POI 좌표 오류: ${poi.id} ${poi.name} lat=$lat lng=$lng '
        '(lat은 위도, lng는 경도)',
      );
      return false;
    }

    if (poi.radiusMeters <= 0) {
      debugPrint(
        'POI radius_m 경고: ${poi.id} ${poi.name} '
        'radius_m=${poi.radiusMeters}',
      );
    }

    if (!_isWithinCampusBounds(poi.point)) {
      debugPrint(
        'POI bounds 경고: ${poi.id} ${poi.name} '
        'lat=$lat lng=$lng 제주대학교 아라캠퍼스 bounds 밖',
      );
    }

    return true;
  }

  Future<void> _setCurrentLocationAsStart() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('위치 서비스를 사용할 수 없습니다.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showSnackBar('현재 위치 권한이 거부되었습니다.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('현재 위치 권한이 영구적으로 거부되었습니다.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(position.latitude, position.longitude);

      if (!_isWithinCampusBounds(point)) {
        setState(() => _currentLocation = null);
        _showSnackBar('현재 위치가 제주대학교 아라캠퍼스 밖입니다.');
        return;
      }

      if (!mounted) return;
      setState(() => _currentLocation = point);
      _setStartPoint(
        point,
        label: '현재 위치',
        fromGps: true,
        showMessage: false,
      );
      _mapController.move(point, _initialZoom);
      _showSnackBar('현재 위치가 출발지로 설정되었습니다.');
      _startLocationStream();
    } catch (_) {
      _showSnackBar('현재 위치를 가져올 수 없습니다.');
    }
  }

  void _startLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        final point = LatLng(position.latitude, position.longitude);
        if (!mounted) return;
        setState(() {
          _currentLocation = _isWithinCampusBounds(point) ? point : null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _currentLocation = null);
      },
    );
  }

  void _moveToCurrentLocation() {
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      _showSnackBar('현재 위치를 확인할 수 없습니다.');
      return;
    }

    _mapController.move(currentLocation, _initialZoom);
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    if (!_isWithinCampusBounds(point)) {
      _showSnackBar('제주대학교 아라캠퍼스 안에서만 선택할 수 있습니다.');
      return;
    }

    final poi = _nearestPoiForPoint(point);
    setState(() {
      _pendingPoint = point;
      _pendingPoi = poi;
      _pendingLabel = poi?.name ?? '지도 선택 위치';
    });
  }

  bool _isWithinCampusBounds(LatLng point) {
    return point.latitude >= _campusSouthWest.latitude &&
        point.latitude <= _campusNorthEast.latitude &&
        point.longitude >= _campusSouthWest.longitude &&
        point.longitude <= _campusNorthEast.longitude;
  }

  bool _isSamePoint(LatLng? a, LatLng b) {
    const epsilon = 0.000001;
    return a != null &&
        (a.latitude - b.latitude).abs() < epsilon &&
        (a.longitude - b.longitude).abs() < epsilon;
  }

  CampusPoi? _nearestPoiForPoint(LatLng point) {
    const distance = Distance();
    CampusPoi? nearest;
    double nearestMeters = double.infinity;

    for (final poi in _campusPois) {
      final meters = distance.as(LengthUnit.Meter, point, poi.point);
      if (meters <= poi.radiusMeters && meters < nearestMeters) {
        nearest = poi;
        nearestMeters = meters;
      }
    }

    return nearest;
  }

  void _setStartPoint(
    LatLng point, {
    required String label,
    required bool fromGps,
    bool showMessage = true,
  }) {
    setState(() {
      _startPoint = point;
      _startLabel = label;
      _endPoint = null;
      _endLabel = null;
      _routeData = null;
      _routeCoords = [];
      _pendingPoint = null;
      _pendingLabel = null;
      _pendingPoi = null;
      _isStartPointFromGps = fromGps;
      _mapPickTarget = MapPickTarget.end;
    });

    if (showMessage) {
      _showSnackBar('출발지가 설정되었습니다. 도착지를 선택하세요.');
    }
  }

  void _setEndPoint(
    LatLng point, {
    required String label,
    bool showMessage = true,
  }) {
    setState(() {
      _endPoint = point;
      _endLabel = label;
      _routeData = null;
      _routeCoords = [];
      _pendingPoint = null;
      _pendingLabel = null;
      _pendingPoi = null;
      _mapPickTarget = MapPickTarget.end;
    });

    if (showMessage) {
      _showSnackBar('도착지가 설정되었습니다. 경로 검색을 누르세요.');
    }
  }

  void _selectRouteMode(RouteMode mode) {
    setState(() {
      _routeMode = mode;
      _routeData = null;
      _routeCoords = [];
    });
  }

  void _activateMapPickTarget(MapPickTarget target) {
    setState(() => _mapPickTarget = target);
    _showSnackBar(
      target == MapPickTarget.start
          ? '지도에서 출발지를 길게 눌러 선택하세요.'
          : '지도에서 도착지를 길게 눌러 선택하세요.',
    );
  }

  Future<void> _openPoiSearch({required bool forStart}) async {
    final selected = await showModalBottomSheet<CampusPoi>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PoiSearchSheet(
        title: forStart ? '출발지 검색' : '도착지 검색',
        pois: _campusPois,
      ),
    );

    if (selected == null) return;
    if (forStart) {
      _setStartPoint(selected.point, label: selected.name, fromGps: false);
    } else {
      _setEndPoint(selected.point, label: selected.name);
    }
    _mapController.move(selected.point, _initialZoom);
  }

  Future<void> _fetchRoute() async {
    if (_startPoint == null || _endPoint == null) {
      _showSnackBar('출발지와 도착지를 모두 설정해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _routeData = null;
      _routeCoords = [];
    });

    RouteResponse response;
    try {
      // 백엔드가 mode를 지원하면 route_mode 값을 body에 포함하면 됨.
      response = await _apiService.fetchRoute(
        start: _startPoint!,
        end: _endPoint!,
      );
    } catch (_) {
      response = const RouteResponse(
        success: false,
        error: '경로 요청 중 오류가 발생했습니다.',
      );
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _routeData = response;
      if (response.success && response.routeGeoJson != null) {
        _routeCoords = response.routeGeoJson!.coordinates;
      }
    });

    if (response.success && _routeCoords.isNotEmpty) {
      _fitBoundsToRoute();
      _showSnackBar('경로를 찾았습니다! (${response.totalDistanceDisplay})');
    } else {
      _showSnackBar(response.error ?? '경로를 찾을 수 없습니다.');
    }
  }

  void _fitBoundsToRoute() {
    final points = [
      ..._routeCoords,
      if (_startPoint != null) _startPoint!,
      if (_endPoint != null) _endPoint!,
    ];
    if (points.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(64, 180, 64, 180),
        ),
      );
    });
  }

  void _clearRoute() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _startLabel = null;
      _endLabel = null;
      _routeData = null;
      _routeCoords = [];
      _pendingPoint = null;
      _pendingLabel = null;
      _pendingPoi = null;
      _isStartPointFromGps = false;
      _mapPickTarget = MapPickTarget.end;
      _isLoading = false;
    });
  }

  FavoritePlace? _favoriteForPending() {
    final point = _pendingPoint;
    if (point == null) return null;

    if (_pendingPoi != null) {
      return _favorites
          .where((favorite) => favorite.id == _pendingPoi!.id)
          .firstOrNull;
    }

    const epsilon = 0.000001;
    return _favorites.where((favorite) {
      return (favorite.point.latitude - point.latitude).abs() < epsilon &&
          (favorite.point.longitude - point.longitude).abs() < epsilon;
    }).firstOrNull;
  }

  Future<void> _togglePendingFavorite() async {
    final point = _pendingPoint;
    final label = _pendingLabel;
    if (point == null || label == null) return;

    final existing = _favoriteForPending();
    if (existing != null) {
      setState(() {
        _favorites.removeWhere((favorite) => favorite.id == existing.id);
      });
      return;
    }

    String favoriteName;
    if (_pendingPoi != null) {
      favoriteName = _pendingPoi!.name;
    } else {
      final customName = await _showFavoriteNameDialog(
        initialName: '사용자 지정 위치',
      );
      if (customName == null) return;
      favoriteName = customName.trim().isEmpty ? '사용자 지정 위치' : customName.trim();
    }

    setState(() {
      _favorites.add(
        FavoritePlace(
          id: _pendingPoi?.id ??
              'favorite_${DateTime.now().millisecondsSinceEpoch}',
          name: favoriteName,
          point: point,
          type: _pendingPoi?.type ?? 'custom',
        ),
      );
    });
  }

  Future<String?> _showFavoriteNameDialog({required String initialName}) async {
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('즐겨찾기 이름 설정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '이름',
              hintText: '사용자 지정 위치',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _openFavoriteActions(FavoritePlace favorite) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    favorite.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(favorite.type),
                ),
                ListTile(
                  leading: const Icon(Icons.trip_origin),
                  title: const Text('출발지로 설정'),
                  onTap: () => Navigator.of(context).pop('start'),
                ),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('도착지로 설정'),
                  onTap: () => Navigator.of(context).pop('end'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('이름 수정'),
                  onTap: () => Navigator.of(context).pop('rename'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('즐겨찾기 삭제'),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == 'start') {
      _setStartPoint(favorite.point, label: favorite.name, fromGps: false);
      _mapController.move(favorite.point, _initialZoom);
    } else if (action == 'end') {
      _setEndPoint(favorite.point, label: favorite.name);
      _mapController.move(favorite.point, _initialZoom);
    } else if (action == 'rename') {
      final newName = await _showFavoriteNameDialog(
        initialName: favorite.name,
      );
      if (newName == null) return;
      final trimmedName = newName.trim().isEmpty ? '사용자 지정 위치' : newName.trim();
      setState(() {
        final index = _favorites.indexWhere((item) => item.id == favorite.id);
        if (index == -1) return;
        _favorites[index] = FavoritePlace(
          id: favorite.id,
          name: trimmedName,
          point: favorite.point,
          type: favorite.type,
        );
        if (_isSamePoint(_startPoint, favorite.point) &&
            _startLabel == favorite.name) {
          _startLabel = trimmedName;
        }
        if (_isSamePoint(_endPoint, favorite.point) &&
            _endLabel == favorite.name) {
          _endLabel = trimmedName;
        }
      });
    } else if (action == 'delete') {
      setState(() {
        _favorites.removeWhere((item) => item.id == favorite.id);
      });
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 86),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final topMaxHeight = constraints.maxHeight * 0.48;
          final bottomMaxHeight = constraints.maxHeight * 0.28;

          return Stack(
            children: [
              _buildMap(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: topMaxHeight),
                      child: _buildTopPanel(),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 184),
                    child: _buildCurrentLocationButton(),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: bottomMaxHeight),
                    child: _buildBottomPanel(),
                  ),
                ),
              ),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          );
        },
      ),
      floatingActionButton: (_startPoint != null || _endPoint != null)
          ? FloatingActionButton.small(
              onPressed: _clearRoute,
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
              tooltip: '초기화',
              child: const Icon(Icons.clear),
            )
          : null,
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: _initialZoom,
        minZoom: 5,
        maxZoom: 22,
        cameraConstraint: CameraConstraint.contain(bounds: _campusBounds),
        onLongPress: _onMapLongPress,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.barrierfree.navigation',
          maxZoom: 22,
        ),
        if (_routeCoords.isNotEmpty) _buildRoutePolylineLayer(),
        if (_routeData != null && _routeData!.success)
          _buildElevatorMarkersLayer(),
        _buildCurrentLocationLayer(),
        _buildEndpointMarkersLayer(),
      ],
    );
  }

  Widget _buildCurrentLocationButton() {
    return Material(
      color: Colors.white,
      elevation: 6,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: '현재 위치로 이동',
        icon: const Icon(Icons.my_location),
        color: const Color(0xFF1976D2),
        onPressed: _moveToCurrentLocation,
      ),
    );
  }

  Widget _buildTopPanel() {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLocationField(
                label: '출발지',
                value: _startLabel ?? '출발지를 선택하세요',
                icon: _isStartPointFromGps
                    ? Icons.my_location
                    : Icons.trip_origin,
                color: const Color(0xFF2E7D32),
                selected: _mapPickTarget == MapPickTarget.start,
                onFieldTap: () => _activateMapPickTarget(MapPickTarget.start),
                onSearchTap: () => _openPoiSearch(forStart: true),
              ),
              const SizedBox(height: 8),
              _buildLocationField(
                label: '도착지',
                value: _endLabel ?? '도착지를 선택하세요',
                icon: Icons.location_on,
                color: const Color(0xFFC62828),
                selected: _mapPickTarget == MapPickTarget.end,
                onFieldTap: () => _activateMapPickTarget(MapPickTarget.end),
                onSearchTap: () => _openPoiSearch(forStart: false),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      label: '휠체어 모드',
                      icon: Icons.accessible_forward,
                      mode: RouteMode.wheelchair,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModeButton(
                      label: '일반 모드',
                      icon: Icons.directions_walk,
                      mode: RouteMode.normal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _fetchRoute,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.route),
                  label: Text(_isLoading ? '경로 검색 중' : '경로 검색'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationField({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onFieldTap,
    required VoidCallback onSearchTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.08) : Colors.white,
        border: Border.all(
          color: selected ? color : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onFieldTap,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(10),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '$label 검색',
            icon: const Icon(Icons.search),
            color: selected ? color : Colors.grey[700],
            onPressed: onSearchTap,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required RouteMode mode,
  }) {
    final selected = _routeMode == mode;
    final Color accent = mode == RouteMode.wheelchair
        ? const Color(0xFF4B83C4)
        : const Color(0xFF4C9A6A);
    final Color background = mode == RouteMode.wheelchair
        ? const Color(0xFFEAF3FF)
        : const Color(0xFFEAF7EF);

    return InkWell(
      onTap: () => _selectRouteMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? background : Colors.grey.shade50,
          border: Border.all(
            color: selected ? accent : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? accent : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF263238) : Colors.grey[800],
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: _pendingPoint != null
              ? _buildSelectionCard()
              : _routeData != null && _routeData!.success
                  ? _buildRouteSummary()
                  : _buildFavoritesPanel(),
        ),
      ),
    );
  }

  Widget _buildSelectionCard() {
    final point = _pendingPoint!;
    final label = _pendingLabel ?? '지도 선택 위치';
    final favorite = _favoriteForPending();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.place, color: Color(0xFF455A64)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: favorite == null ? '즐겨찾기 추가' : '즐겨찾기 제거',
              icon: Icon(
                favorite == null ? Icons.star_border : Icons.star,
                color: const Color(0xFFFFA000),
              ),
              onPressed: _togglePendingFavorite,
            ),
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _pendingPoint = null;
                  _pendingLabel = null;
                  _pendingPoi = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.trip_origin),
                label: const Text('출발지로 설정'),
                onPressed: () => _setStartPoint(
                  point,
                  label: label,
                  fromGps: false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.location_on),
                label: const Text('도착지로 설정'),
                onPressed: () => _setEndPoint(point, label: label),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFavoritesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.star, size: 18, color: Color(0xFFFFA000)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '즐겨찾는 장소',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _mapPickTarget == MapPickTarget.start ? '출발지 선택 중' : '도착지 선택 중',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_favorites.isEmpty)
          Text(
            '선택 카드의 별표를 눌러 장소를 추가하세요.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _favorites.map((favorite) {
              return ActionChip(
                avatar: const Icon(Icons.star, size: 16),
                label: Text(favorite.name, overflow: TextOverflow.ellipsis),
                onPressed: () => _openFavoriteActions(favorite),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildRouteSummary() {
    final data = _routeData!;
    final elevatorCount = data.pathNodes.where((node) => node.isElevator).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.route, color: Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data.totalDistanceDisplay,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text('${data.nodeCount}개 구간'),
          ],
        ),
        if (elevatorCount > 0) ...[
          const SizedBox(height: 8),
          Text('엘리베이터 $elevatorCount곳 경유'),
        ],
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.22),
          child: const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePolylineLayer() {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: _routeCoords,
          strokeWidth: 10,
          color: const Color(0xFF1565C0).withValues(alpha: 0.35),
        ),
        Polyline(
          points: _routeCoords,
          strokeWidth: 6,
          color: const Color(0xFF1976D2),
        ),
      ],
    );
  }

  Widget _buildElevatorMarkersLayer() {
    final elevatorNodes = _routeData!.pathNodes
        .where((node) => node.isElevator)
        .toList();

    return MarkerLayer(
      markers: elevatorNodes.map((node) {
        return Marker(
          point: node.toLatLng(),
          width: 40,
          height: 40,
          child: Tooltip(
            message: '엘리베이터: ${node.name}',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.indigo,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.elevator, color: Colors.white, size: 20),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCurrentLocationLayer() {
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      return const SizedBox.shrink();
    }

    return MarkerLayer(
      markers: [
        Marker(
          point: currentLocation,
          width: 30,
          height: 30,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndpointMarkersLayer() {
    return MarkerLayer(
      markers: [
        if (_startPoint != null)
          Marker(
            point: _startPoint!,
            width: 76,
            height: 58,
            alignment: Alignment.topCenter,
            child: _buildMarkerIcon(
              icon: _isStartPointFromGps ? Icons.my_location : Icons.trip_origin,
              color: const Color(0xFF2E7D32),
              label: _isStartPointFromGps ? '현재 위치' : '출발',
            ),
          ),
        if (_endPoint != null)
          Marker(
            point: _endPoint!,
            width: 64,
            height: 58,
            alignment: Alignment.topCenter,
            child: _buildMarkerIcon(
              icon: Icons.location_on,
              color: const Color(0xFFC62828),
              label: '도착',
            ),
          ),
      ],
    );
  }

  Widget _buildMarkerIcon({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(icon, color: color, size: 30),
      ],
    );
  }
}

class _PoiSearchSheet extends StatefulWidget {
  final String title;
  final List<CampusPoi> pois;

  const _PoiSearchSheet({
    required this.title,
    required this.pois,
  });

  @override
  State<_PoiSearchSheet> createState() => _PoiSearchSheetState();
}

class _PoiSearchSheetState extends State<_PoiSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.pois.where((poi) => poi.matches(_query)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '장소명 또는 별칭 검색',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final poi = filtered[index];
                    return ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(poi.name),
                      subtitle: poi.alias.isEmpty
                          ? null
                          : Text(poi.alias.join(', ')),
                      onTap: () => Navigator.of(context).pop(poi),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
