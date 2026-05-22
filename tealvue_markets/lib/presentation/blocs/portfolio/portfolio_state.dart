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
  final int version;

  PortfolioLoaded(this.holdings, {this.version = 0});

  double get totalInvested =>
      holdings.fold(0.0, (sum, h) => sum + h.investedValue);

  double get totalCurrent =>
      holdings.fold(0.0, (sum, h) => sum + h.currentValue);

  double get totalPnl => totalCurrent - totalInvested;

  double get totalPnlPercent =>
      totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0;

  @override
  List<Object?> get props => [holdings, version];
}

class PortfolioError extends PortfolioState {
  final String message;
  PortfolioError(this.message);
  @override
  List<Object?> get props => [message];
}