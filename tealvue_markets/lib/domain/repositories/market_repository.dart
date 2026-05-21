import '../../data/models/tick_model.dart';

abstract class MarketRepository {
  Future<List<TickModel>> getRealtimeCurrent(String symbol);
  Future<List<TickModel>> getHistoricalData({
    required String symbol,
    required String startDate,
    required String endDate,
  });
}