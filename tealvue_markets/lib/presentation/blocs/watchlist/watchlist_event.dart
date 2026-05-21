import 'package:equatable/equatable.dart';
import '../../../data/models/tick_model.dart';

abstract class WatchlistEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadWatchlist extends WatchlistEvent {}

class AddToWatchlist extends WatchlistEvent {
  final String symbol;
  final String name;
  AddToWatchlist(this.symbol, this.name);
  @override
  List<Object?> get props => [symbol];
}

class RemoveFromWatchlist extends WatchlistEvent {
  final String symbol;
  RemoveFromWatchlist(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class TickReceived extends WatchlistEvent {
  final TickModel tick;
  TickReceived(this.tick);
  @override
  List<Object?> get props => [tick.symbol, tick.sequenceNo];
}

class ConnectSocket extends WatchlistEvent {}
class DisconnectSocket extends WatchlistEvent {}
class SocketConnected extends WatchlistEvent {}
class SocketDisconnected extends WatchlistEvent {}