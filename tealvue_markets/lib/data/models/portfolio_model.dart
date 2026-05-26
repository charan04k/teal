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

  /// Creates a new instance with updated fields.
  /// Used by PortfolioBloc so Equatable detects state change on every tick.
  /// Used by PortfolioBloc so Equatable detects state change on every tick.
  PortfolioModel copyWith({
    double? currentPrice,
    double? quantity,
    double? avgBuyPrice,
    String? symbol,
    String? name,
  }) {
    return PortfolioModel(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      avgBuyPrice: avgBuyPrice ?? this.avgBuyPrice,
      currentPrice: currentPrice ?? this.currentPrice,
    );
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