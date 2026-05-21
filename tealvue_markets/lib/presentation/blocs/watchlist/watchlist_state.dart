import 'package:equatable/equatable.dart';
import '../../../data/models/symbol_model.dart';
import '../../../data/models/tick_model.dart';

abstract class WatchlistState extends Equatable {
  @override
  List<Object?> get props => [];
}

class WatchlistInitial extends WatchlistState {}
class WatchlistLoading extends WatchlistState {}

class WatchlistLoaded extends WatchlistState {
  final List<SymbolModel> symbols;
  final Map<String, TickModel> ticks;
  final bool isConnected;

  WatchlistLoaded({
    required this.symbols,
    required this.ticks,
    this.isConnected = false,
  });

  WatchlistLoaded copyWith({
    List<SymbolModel>? symbols,
    Map<String, TickModel>? ticks,
    bool? isConnected,
  }) {
    return WatchlistLoaded(
      symbols: symbols ?? this.symbols,
      ticks: ticks ?? this.ticks,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  List<Object?> get props => [symbols, ticks, isConnected];
}

class WatchlistError extends WatchlistState {
  final String message;
  WatchlistError(this.message);
  @override
  List<Object?> get props => [message];
}