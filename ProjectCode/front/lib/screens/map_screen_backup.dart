// ========================================================================
// 배리어프리 보행자 네비게이션 — 메인 지도 화면
// ========================================================================
// map_screen.dart — 전체 화면 지도 + 마커 + 경로 폴리라인 + 정보 패널
//
// ★ 사용자 흐름:
//   1) 지도 롱프레스 → 출발지 마커 설정 (초록색)
//   2) 다시 롱프레스 → 도착지 마커 설정 (빨간색)
//   3) 자동으로 API 호출 → 경로 수신 → 폴리라인 렌더링
//   4) 하단 패널에 총 거리 + 경유 엘리베이터 정보 표시
// ========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/route_api.dart';
import '../models/route_response.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // ── 지도 컨트롤러 ──
  final MapController _mapController = MapController();

  // ── API 서비스 ──
  // ★ baseUrl 은 실제 서버 주소로 변경하세요.
  //   Android 에뮬레이터: http://10.0.2.2:8000/api/v1
  //   iOS 시뮬레이터:     http://localhost:8000/api/v1
  //   실제 디바이스:      http://<서버IP>:8000/api/v1
  final RouteApiService _apiService = RouteApiService(
    baseUrl: 'http://10.0.2.2:8000/api/v1',
  );

  // ── 상태 변수 ──
  LatLng? _startPoint;       // 출발지 좌표
  LatLng? _endPoint;         // 도착지 좌표
  RouteResponse? _routeData; // API 응답 결과
  List<LatLng> _routeCoords = [];  // 폴리라인 좌표 목록
  bool _isLoading = false;   // 로딩 상태
  String? _errorMessage;     // 에러 메시지

  // ── 초기 지도 설정 (서울시청 근처) ──
  static const LatLng _initialCenter = LatLng(37.5665, 126.9780);
  static const double _initialZoom = 17.0;

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  // 핵심 로직: 마커 설정 & 경로 요청
  // ═══════════════════════════════════════════════

  /// 지도 롱프레스 핸들러
  ///
  /// ★ 첫 번째 롱프레스 → 출발지 설정
  ///   두 번째 롱프레스 → 도착지 설정 + API 호출
  ///   세 번째 롱프레스 → 초기화 후 새 출발지 설정
  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    setState(() {
      if (_startPoint == null) {
        // ── 1) 출발지 설정 ──
        _startPoint = point;
        _endPoint = null;
        _routeData = null;
        _routeCoords = [];
        _errorMessage = null;

        _showSnackBar(
          '출발지가 설정되었습니다. 도착지를 롱프레스하세요.',
          icon: Icons.trip_origin,
          color: const Color(0xFF2E7D32),
        );
      } else if (_endPoint == null) {
        // ── 2) 도착지 설정 → API 호출 ──
        _endPoint = point;
        _fetchRoute();
      } else {
        // ── 3) 초기화 후 새 출발지 ──
        _startPoint = point;
        _endPoint = null;
        _routeData = null;
        _routeCoords = [];
        _errorMessage = null;

        _showSnackBar(
          '경로가 초기화되었습니다. 새 출발지가 설정되었습니다.',
          icon: Icons.refresh,
          color: Colors.blueGrey,
        );
      }
    });
  }

  /// 백엔드 API 로 경로 탐색 요청
  Future<void> _fetchRoute() async {
    if (_startPoint == null || _endPoint == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _routeData = null;
      _routeCoords = [];
    });

    // ── API 호출 ──
    final response = await _apiService.fetchRoute(
      start: _startPoint!,
      end: _endPoint!,
    );

    setState(() {
      _isLoading = false;
      _routeData = response;

      if (response.success && response.routeGeoJson != null) {
        // ★ GeoJSON LineString 좌표를 폴리라인용 LatLng 리스트로 변환
        _routeCoords = response.routeGeoJson!.coordinates;

        // 경로가 지도에 잘 보이도록 bounds 조정
        if (_routeCoords.isNotEmpty) {
          _fitBoundsToRoute();
        }

        _showSnackBar(
          '경로를 찾았습니다! (${response.totalDistanceDisplay})',
          icon: Icons.check_circle,
          color: const Color(0xFF2E7D32),
        );
      } else {
        _errorMessage = response.error ?? '경로를 찾을 수 없습니다.';
        _showSnackBar(
          _errorMessage!,
          icon: Icons.error_outline,
          color: Colors.red,
        );
      }
    });
  }

  /// 경로 전체가 보이도록 지도 뷰 조정
  void _fitBoundsToRoute() {
    if (_routeCoords.isEmpty) return;

    // 모든 좌표 + 출발/도착 마커를 포함하는 bounds 계산
    final allPoints = [
      ..._routeCoords,
      if (_startPoint != null) _startPoint!,
      if (_endPoint != null) _endPoint!,
    ];

    final bounds = LatLngBounds.fromPoints(allPoints);

    // 약간의 딜레이 후 애니메이션 이동
    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    });
  }

  /// 전체 초기화
  void _clearAll() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _routeData = null;
      _routeCoords = [];
      _errorMessage = null;
      _isLoading = false;
    });
  }

  /// 스낵바 표시 유틸리티
  void _showSnackBar(String message, {IconData? icon, Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color ?? Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 위젯 빌드
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── 전체 화면 지도 ──
          _buildMap(),

          // ── 상단 안내 배너 ──
          _buildTopBanner(),

          // ── 로딩 인디케이터 ──
          if (_isLoading) _buildLoadingOverlay(),

          // ── 하단 경로 정보 패널 ──
          if (_routeData != null && _routeData!.success)
            _buildRouteInfoPanel(),

          // ── 하단 에러 패널 ──
          if (_errorMessage != null && !_isLoading)
            _buildErrorPanel(),
        ],
      ),

      // ── FAB: 초기화 버튼 ──
      floatingActionButton: (_startPoint != null)
          ? FloatingActionButton(
              onPressed: _clearAll,
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
              tooltip: '경로 초기화',
              child: const Icon(Icons.clear),
            )
          : null,
    );
  }

  // ── 지도 위젯 ──
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: _initialZoom,
        minZoom: 5,
        maxZoom: 22,
        // ★ 롱프레스로 마커 설정
        onLongPress: _onMapLongPress,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        // ── 배경 타일 레이어 (OpenStreetMap) ──
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.barrierfree.navigation',
          maxZoom: 22,
        ),

        // ── 경로 폴리라인 레이어 ──
        if (_routeCoords.isNotEmpty) _buildRoutePolylineLayer(),

        // ── 경유 엘리베이터 마커 레이어 ──
        if (_routeData != null && _routeData!.success)
          _buildElevatorMarkersLayer(),

        // ── 출발/도착 마커 레이어 ──
        _buildEndpointMarkersLayer(),
      ],
    );
  }

  /// 경로 폴리라인 레이어
  ///
  /// ★ 두꺼운 선 + 반투명 테두리로 가시성 확보
  Widget _buildRoutePolylineLayer() {
    return PolylineLayer(
      polylines: [
        // ── 외곽선 (테두리 효과) ──
        Polyline(
          points: _routeCoords,
          strokeWidth: 10.0,
          color: const Color(0xFF1565C0).withValues(alpha: 0.4),
        ),
        // ── 메인 경로선 ──
        Polyline(
          points: _routeCoords,
          strokeWidth: 6.0,
          color: const Color(0xFF1976D2),
        ),
      ],
    );
  }

  /// 경유 엘리베이터 마커 레이어
  Widget _buildElevatorMarkersLayer() {
    final elevatorNodes = _routeData!.pathNodes
        .where((node) => node.isElevator)
        .toList();

    if (elevatorNodes.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: elevatorNodes.map((node) {
        return Marker(
          point: node.toLatLng(),
          width: 40,
          height: 40,
          child: Tooltip(
            message: '엘리베이터: ${node.name}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.indigo,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.elevator,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 출발지/도착지 마커 레이어
  Widget _buildEndpointMarkersLayer() {
    final markers = <Marker>[];

    // ── 출발지 마커 (초록) ──
    if (_startPoint != null) {
      markers.add(
        Marker(
          point: _startPoint!,
          width: 50,
          height: 50,
          alignment: Alignment.topCenter,
          child: _buildMarkerIcon(
            icon: Icons.trip_origin,
            color: const Color(0xFF2E7D32),
            label: '출발',
          ),
        ),
      );
    }

    // ── 도착지 마커 (빨강) ──
    if (_endPoint != null) {
      markers.add(
        Marker(
          point: _endPoint!,
          width: 50,
          height: 50,
          alignment: Alignment.topCenter,
          child: _buildMarkerIcon(
            icon: Icons.location_on,
            color: const Color(0xFFC62828),
            label: '도착',
          ),
        ),
      );
    }

    return MarkerLayer(markers: markers);
  }

  /// 마커 아이콘 위젯
  Widget _buildMarkerIcon({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 레이블 ──
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        // ── 아이콘 ──
        Icon(icon, color: color, size: 30),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  // UI 오버레이 위젯
  // ═══════════════════════════════════════════════

  /// 상단 안내 배너
  Widget _buildTopBanner() {
    String message;
    IconData icon;
    Color bgColor;

    if (_startPoint == null) {
      message = '지도를 길게 눌러 출발지를 설정하세요';
      icon = Icons.touch_app;
      bgColor = const Color(0xFF37474F);
    } else if (_endPoint == null) {
      message = '도착지를 길게 눌러 설정하세요';
      icon = Icons.flag;
      bgColor = const Color(0xFF2E7D32);
    } else if (_isLoading) {
      message = '배리어프리 경로를 탐색 중입니다...';
      icon = Icons.explore;
      bgColor = const Color(0xFF1565C0);
    } else if (_routeData != null && _routeData!.success) {
      message = '경로 안내 준비 완료 (${_routeData!.totalDistanceDisplay})';
      icon = Icons.check_circle;
      bgColor = const Color(0xFF2E7D32);
    } else {
      message = '경로를 초기화하려면 다시 길게 누르세요';
      icon = Icons.info_outline;
      bgColor = Colors.blueGrey;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 로딩 오버레이
  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: Card(
            elevation: 8,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    '배리어프리 경로 탐색 중...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '장애물을 회피하는 최적 경로를 계산하고 있습니다',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 하단 경로 정보 패널
  Widget _buildRouteInfoPanel() {
    final data = _routeData!;
    final elevatorNodes =
        data.pathNodes.where((n) => n.isElevator).toList();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 거리 + 노드 수 헤더 ──
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.accessible_forward,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '배리어프리 경로',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            data.totalDistanceDisplay,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 경유 노드 수
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${data.nodeCount}개 구간',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 경유 엘리베이터 정보 ──
              if (elevatorNodes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.elevator,
                          color: Colors.indigo, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '엘리베이터 ${elevatorNodes.length}곳 경유',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
                // 엘리베이터 목록
                ...elevatorNodes.map(
                  (node) => Padding(
                    padding: const EdgeInsets.fromLTRB(48, 4, 20, 0),
                    child: Text(
                      '• ${node.name.isNotEmpty ? node.name : "엘리베이터"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ],

              // ── 안내 문구 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '계단·급경사를 회피하는 최단 거리 경로입니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 에러 패널
  Widget _buildErrorPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '경로를 찾을 수 없습니다',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _errorMessage ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: Colors.red,
                onPressed: _fetchRoute,
                tooltip: '다시 시도',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
