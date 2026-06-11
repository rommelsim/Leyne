// NEA / data.gov.sg weather API client.
//
// Mirrors the structure of lta_service.dart:
//   • No API key required — data.gov.sg is free and open.
//   • Per-request 15 s timeout matching the LTA client.
//   • Raises [NeaException] on HTTP / parse failures so callers can
//     distinguish network errors from parse errors without catching Exception.
//
// Endpoints:
//   2-hour forecast:  GET /v1/environment/2-hour-weather-forecast
//   Air temperature:  GET /v1/environment/air-temperature
//   24-hour forecast: GET /v1/environment/24-hour-weather-forecast

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'nea_models.dart';

class NeaException implements Exception {
  NeaException.badResponse(this.statusCode)
      : message = 'NEA returned HTTP $statusCode',
        decodingDetail = null;
  NeaException.decoding(this.decodingDetail)
      : message = 'Couldn\'t read NEA data ($decodingDetail)',
        statusCode = null;

  final String message;
  final int? statusCode;
  final String? decodingDetail;

  @override
  String toString() => message;
}

class NeaService {
  NeaService({http.Client? client}) : _client = client ?? http.Client();

  static final NeaService shared = NeaService();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  static final _baseUri = Uri.https('api.data.gov.sg', '/v1/environment');

  // ─── Public API ───────────────────────────────────────────────────────────

  Future<NeaTwoHourResponse> twoHourForecast() async {
    final json = await _get(_baseUri.resolve('2-hour-weather-forecast'));
    return NeaTwoHourResponse.fromJson(json);
  }

  Future<NeaAirTemperatureResponse> airTemperature() async {
    final json = await _get(_baseUri.resolve('air-temperature'));
    return NeaAirTemperatureResponse.fromJson(json);
  }

  Future<Nea24hResponse> twentyFourHourForecast() async {
    final json = await _get(_baseUri.resolve('24-hour-weather-forecast'));
    return Nea24hResponse.fromJson(json);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final resp = await _client
        .get(uri, headers: {'accept': 'application/json'}).timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw NeaException.badResponse(resp.statusCode);
    }
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw NeaException.decoding(e.toString());
    }
  }
}
