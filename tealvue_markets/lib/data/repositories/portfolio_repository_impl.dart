import '../../data/datasources/local/hive_service.dart';
import '../../data/models/portfolio_model.dart';
import '../../domain/repositories/portfolio_repository.dart';

class PortfolioRepositoryImpl implements PortfolioRepository {
  final HiveService _hiveService;

  PortfolioRepositoryImpl(this._hiveService);

  @override
  List<PortfolioModel> getPortfolio() {
    return _hiveService.getPortfolio()
        .map((e) => PortfolioModel.fromMap(e))
        .toList();
  }

  @override
  Future<void> addHolding(PortfolioModel holding) async {
    await _hiveService.saveHolding(holding.toMap());
  }

  @override
  Future<void> removeHolding(String symbol) async {
    await _hiveService.removeHolding(symbol);
  }

  @override
  Future<void> updateHolding(PortfolioModel holding) async {
    await _hiveService.saveHolding(holding.toMap());
  }
}