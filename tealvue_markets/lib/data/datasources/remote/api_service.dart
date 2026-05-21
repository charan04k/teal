import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  Future<List<dynamic>> getSymbols() async {
    final response = await _dio.get('/symbols');
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getRealtimeCurrent({
    required String symbol,
    int limit = 5000,
    int offset = 0,
  }) async {
    final response = await _dio.post('/realtime-current', data: {
      'symbol': symbol,
      'limit': limit,
      'offset': offset,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getHistoricalData({
    required String symbol,
    required String startDate,
    required String endDate,
    int limit = 5000,
    int offset = 0,
  }) async {
    final response = await _dio.post('/historical', data: {
      'symbol': symbol,
      'start_date': startDate,
      'end_date': endDate,
      'limit': limit,
      'offset': offset,
    });
    return response.data as Map<String, dynamic>;
  }
}