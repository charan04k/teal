class TickModel {
  final String symbol;
  final double ltp;
  final double open;
  final double high;
  final double low;
  final double prevClose;
  final double atp;
  final int ttq;
  final double turnover;
  final String timestamp;
  final int sequenceNo;

  TickModel({
    required this.symbol,
    required this.ltp,
    required this.open,
    required this.high,
    required this.low,
    required this.prevClose,
    required this.atp,
    required this.ttq,
    required this.turnover,
    required this.timestamp,
    required this.sequenceNo,
  });

  factory TickModel.fromJson(Map<String, dynamic> json) {
    return TickModel(
      symbol: json['SYMBOL']?.toString() ?? '',
      ltp: _toDouble(json['LTP']),
      open: _toDouble(json['OPEN']),
      high: _toDouble(json['HIGH']),
      low: _toDouble(json['LOW']),
      prevClose: _toDouble(json['PREV_CLOSE']),
      atp: _toDouble(json['ATP']),
      ttq: _toInt(json['TTQ']),
      turnover: _toDouble(json['TURNOVER']),
      timestamp: json['TS']?.toString() ?? '',
      sequenceNo: _toInt(json['SEQUENCE_NO']),
    );
  }

  // Safe conversion from any type to double
  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      if (value.isEmpty) return 0.0;
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  // Safe conversion from any type to int
  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      if (value.isEmpty) return 0;
      return int.tryParse(value) ??
          double.tryParse(value)?.toInt() ?? 0;
    }
    return 0;
  }

  double get change => ltp - prevClose;
  double get changePercent =>
      prevClose > 0 ? (change / prevClose) * 100 : 0;
  bool get isPositive => change >= 0;
}