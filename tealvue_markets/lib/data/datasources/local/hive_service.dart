import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

class HiveService {
  late Box _portfolioBox;
  late Box _watchlistBox;

  Future<void> init() async {
    _portfolioBox = await Hive.openBox(AppConstants.portfolioBox);
    _watchlistBox = await Hive.openBox(AppConstants.watchlistBox);
  }

  // Watchlist
  List<String> getWatchlist() {
    return _watchlistBox.values.cast<String>().toList();
  }

  Future<void> addToWatchlist(String symbol) async {
    await _watchlistBox.put(symbol, symbol);
  }

  Future<void> removeFromWatchlist(String symbol) async {
    await _watchlistBox.delete(symbol);
  }

  bool isInWatchlist(String symbol) {
    return _watchlistBox.containsKey(symbol);
  }

  // Portfolio
  List<Map<String, dynamic>> getPortfolio() {
    return _portfolioBox.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> saveHolding(Map<String, dynamic> holding) async {
    await _portfolioBox.put(holding['symbol'], holding);
  }

  Future<void> removeHolding(String symbol) async {
    await _portfolioBox.delete(symbol);
  }

  Map<String, dynamic>? getHolding(String symbol) {
    final data = _portfolioBox.get(symbol);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }
}