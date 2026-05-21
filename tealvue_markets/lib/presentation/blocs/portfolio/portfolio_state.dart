import 'package:equatable/equatable.dart';
import '../../../data/models/portfolio_model.dart';

abstract class PortfolioState extends Equatable {
  @override
  List<Object?> get props => [];
}

class PortfolioInitial extends PortfolioState {}
class PortfolioLoading extends PortfolioState {}

class PortfolioLoaded extends PortfolioState {
  final List<PortfolioModel> holdings;

  PortfolioLoaded(this.holdings);

  double get totalInvested =>
      holdings.fold(0.0, (sum, h) => sum + h.investedValue);

  // Use investedValue as fallback when currentPrice has not yet arrived
  // from socket/REST. This prevents totalCurrent from being 0 and
  // causing the -100% P&L bug on first load.
  double get totalCurrent => holdings.fold(0.0, (sum, h) {
    final value = h.currentPrice > 0 ? h.currentValue : h.investedValue;
    return sum + value;
  });

  double get totalPnl => totalCurrent - totalInvested;
  double get totalPnlPercent =>
      totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0;

  @override
  List<Object?> get props => [holdings];
}

class PortfolioError extends PortfolioState {
  final String message;
  PortfolioError(this.message);
  @override
  List<Object?> get props => [message];
}