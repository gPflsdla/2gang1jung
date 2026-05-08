// ========================================================================
// 배리어프리 보행자 네비게이션 — API 서비스
// ========================================================================
// route_api.dart — 백엔드 경로 탐색 API 통신 담당
// ========================================================================

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/route_response.dart';

/// ── API 통신 서비스 ──
///
/// 백엔드 Django 서버와의 HTTP 통신을 담당한다.
/// 싱글턴 패턴은 사용하지 않고, 테스트 용이성을 위해
/// baseUrl 과 http.Client 를 외부에서 주입할 수 있도록 설계했다.
class RouteApiService {
  /// 백엔드 서버 기본 주소
  /// ★ 실제 배포 시 이 값을 환경 변수나 설정 파일에서 읽도록 변경
  final String baseUrl;

  /// HTTP 클라이언트 (테스트 시 Mock 주입 가능)
  final http.Client _client;

  /// 요청 타임아웃 (초)
  static const int _timeoutSeconds = 15;

  RouteApiService({
    this.baseUrl = 'http://localhost:8000/api/v1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  // ═══════════════════════════════════════════════
  // 경로 탐색 API 호출
  // ═══════════════════════════════════════════════

  /// 출발지/도착지 좌표로 배리어프리 최단 경로를 요청한다.
  ///
  /// [start] 출발지 좌표 (LatLng)
  /// [end]   도착지 좌표 (LatLng)
  ///
  /// 반환: [RouteResponse] — 성공 시 경로 GeoJSON + 총 거리 포함
  ///
  /// ★ POST /api/v1/route/ 엔드포인트를 호출한다.
  Future<RouteResponse> fetchRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    final url = Uri.parse('$baseUrl/route/');

    // ── 요청 바디 구성 ──
    final body = jsonEncode({
      'start_lat': start.latitude,
      'start_lng': start.longitude,
      'end_lat': end.latitude,
      'end_lng': end.longitude,
    });

    try {
      // ── POST 요청 전송 ──
      final response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(Duration(seconds: _timeoutSeconds));

      // ── 응답 파싱 ──
      final jsonData = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return RouteResponse.fromJson(jsonData);
      }

      // 4xx / 5xx 에러 처리
      return RouteResponse(
        success: false,
        error: jsonData['error'] as String? ??
            '서버 오류가 발생했습니다. (${response.statusCode})',
      );
    } on SocketException {
      return const RouteResponse(
        success: false,
        error: '서버에 연결할 수 없습니다.\n네트워크 연결을 확인하세요.',
      );
    } on http.ClientException catch (e) {
      return RouteResponse(
        success: false,
        error: '네트워크 오류: ${e.message}',
      );
    } on FormatException {
      return const RouteResponse(
        success: false,
        error: '서버 응답을 파싱할 수 없습니다.',
      );
    } catch (e) {
      return RouteResponse(
        success: false,
        error: '알 수 없는 오류: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════
  // 헬스체크
  // ═══════════════════════════════════════════════

  /// 백엔드 서버 상태를 확인한다.
  Future<bool> healthCheck() async {
    try {
      final url = Uri.parse('$baseUrl/health/');
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 리소스 해제
  void dispose() {
    _client.close();
  }
}
