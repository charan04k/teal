import 'package:equatable/equatable.dart';
import '../../../data/models/portfolio_model.dart';
import '../../../data/models/tick_model.dart';

abstract class PortfolioEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadPortfolio extends PortfolioEvent {}

class AddHolding extends PortfolioEvent {
  final PortfolioModel holding;
  AddHolding(this.holding);
  @override
  List<Object?> get props => [holding.symbol];
}

class RemoveHolding extends PortfolioEvent {
  final String symbol;
  RemoveHolding(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class UpdatePortfolioPrices extends PortfolioEvent {
  final TickModel tick;
  UpdatePortfolioPrices(this.tick);
  @override
  List<Object?> get props => [tick.symbol, tick.sequenceNo];
}