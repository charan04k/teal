class PortfolioModel {
  final String symbol;
  final String name;
  final double quantity;
  final double avgBuyPrice;
  double currentPrice;

  PortfolioModel({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.avgBuyPrice,
    this.currentPrice = 0,
  });

  double get investedValue => quantity * avgBuyPrice;
  double get currentValue => quantity * currentPrice;
  double get unrealisedPnl => currentValue - investedValue;
  double get unrealisedPnlPercent =>
      investedValue > 0 ? (unrealisedPnl / investedValue) * 100 : 0;
  bool get isProfit => unrealisedPnl >= 0;

  Map<String, dynamic> toMap() {
    return {
      'symbol': symbol,
      'name': name,
      'quantity': quantity,
      'avgBuyPrice': avgBuyPrice,
    };
  }

  factory PortfolioModel.fromMap(Map<String, dynamic> map) {
    return PortfolioModel(
      symbol: map['symbol'] ?? '',
      name: map['name'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      avgBuyPrice: (map['avgBuyPrice'] ?? 0).toDouble(),
    );
  }
}