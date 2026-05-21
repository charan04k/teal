import '../../data/models/portfolio_model.dart';

abstract class PortfolioRepository {
  List<PortfolioModel> getPortfolio();
  Future<void> addHolding(PortfolioModel holding);
  Future<void> removeHolding(String symbol);
  Future<void> updateHolding(PortfolioModel holding);
}