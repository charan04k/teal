import '../../data/datasources/remote/api_service.dart';
import '../../data/models/tick_model.dart';
import '../../domain/repositories/market_repository.dart';

class MarketRepositoryImpl implements MarketRepository {
  final ApiService _apiService;

  MarketRepositoryImpl(this._apiService);

  @override
  Future<List<TickModel>> getRealtimeCurrent(String symbol) async {
    final data = await _apiService.getRealtimeCurrent(symbol: symbol);
    final ticks = data['data'] as List<dynamic>;
    return ticks.map((e) => TickModel.fromJson(e)).toList();
  }

  @override
  Future<List<TickModel>> getHistoricalData({
    required String symbol,
    required String startDate,
    required String endDate,
  }) async {
    final data = await _apiService.getHistoricalData(
      symbol: symbol,
      startDate: startDate,
      endDate: endDate,
    );
    final ticks = data['data'] as List<dynamic>;
    return ticks.map((e) => TickModel.fromJson(e)).toList();
  }
}