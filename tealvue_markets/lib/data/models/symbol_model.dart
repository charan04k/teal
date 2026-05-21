class SymbolModel {
  final String symbol;
  final String name;
  final String exchange;
  final String type;
  final bool isActive;

  SymbolModel({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.type,
    required this.isActive,
  });

  factory SymbolModel.fromJson(Map<String, dynamic> json) {
    return SymbolModel(
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      exchange: json['exchange'] ?? '',
      type: json['type'] ?? '',
      isActive: json['isActive'] ?? true,
    );
  }
}