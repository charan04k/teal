import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/datasources/local/hive_service.dart';
import '../../../data/datasources/remote/api_service.dart';
import '../../../data/datasources/remote/socket_service.dart';
import '../../../data/models/symbol_model.dart';
import '../../../data/models/tick_model.dart';
import '../../../domain/repositories/symbol_repository.dart';
import 'watchlist_event.dart';
import 'watchlist_state.dart';

class WatchlistBloc extends Bloc<WatchlistEvent, WatchlistState> {
  final SymbolRepository _symbolRepository;
  final SocketService _socketService;
  final HiveService _hiveService;
  final ApiService _apiService;

  final Map<String, TickModel> _ticks = {};
  final Set<int> _seenSequences = {};
  List<SymbolModel> _watchlistSymbols = [];

  // Stream subscriptions — stored so they can be cancelled in close().
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  StreamSubscription<void>? _connectedSub;
  StreamSubscription<void>? _disconnectedSub;

  WatchlistBloc({
    required SymbolRepository symbolRepository,
    required SocketService socketService,
    required HiveService hiveService,
    required ApiService apiService,
  })  : _symbolRepository = symbolRepository,
        _socketService = socketService,
        _hiveService = hiveService,
        _apiService = apiService,
        super(WatchlistInitial()) {
    on<LoadWatchlist>(_onLoadWatchlist);
    on<AddToWatchlist>(_onAddToWatchlist);
    on<RemoveFromWatchlist>(_onRemoveFromWatchlist);
    on<TickReceived>(_onTickReceived);
    on<ConnectSocket>(_onConnectSocket);
    on<SocketConnected>(_onSocketConnected);
    on<SocketDisconnected>(_onSocketDisconnected);
  }

  Future<void> _onLoadWatchlist(
      LoadWatchlist event,
      Emitter<WatchlistState> emit,
      ) async {
    emit(WatchlistLoading());
    try {
      final savedSymbols = _hiveService.getWatchlist();
      final allSymbols = await _symbolRepository.getSymbols();
      _watchlistSymbols = allSymbols
          .where((s) => savedSymbols.contains(s.symbol))
          .toList();

      emit(WatchlistLoaded(
        symbols: _watchlistSymbols,
        ticks: Map.from(_ticks),
      ));

      _loadRestPrices();
      _setupSocket();
    } catch (e) {
      emit(WatchlistError(e.toString()));
    }
  }

  Future<void> _loadRestPrices() async {
    for (final symbol in _watchlistSymbols) {
      try {
        final data = await _apiService.getRealtimeCurrent(
          symbol: symbol.symbol,
          limit: 1,
        );
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(ticks.last);
          _ticks[symbol.symbol] = tick;
          add(TickReceived(tick));
        }
      } catch (_) {}
    }
  }

  void _setupSocket() {
    // Cancel any existing subscriptions before creating new ones.
    _tickSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();

    // Subscribe to the broadcast streams.  Because they are broadcast,
    // ChartScreen can also listen simultaneously without evicting us.
    _tickSub = _socketService.tickStream.listen((data) {
      final tick = TickModel.fromJson(data);
      if (_seenSequences.add(tick.sequenceNo)) {
        add(TickReceived(tick));
      }
    });

    _connectedSub = _socketService.connectedStream.listen((_) {
      add(SocketConnected());
    });

    _disconnectedSub = _socketService.disconnectedStream.listen((_) {
      add(SocketDisconnected());
    });

    _socketService.connect();
  }

  void _onConnectSocket(
      ConnectSocket event,
      Emitter<WatchlistState> emit,
      ) {
    _setupSocket();
  }

  void _onSocketConnected(
      SocketConnected event,
      Emitter<WatchlistState> emit,
      ) {
    final symbols = _watchlistSymbols.map((s) => s.symbol).toList();
    if (symbols.isNotEmpty) {
      _socketService.subscribe(symbols);
    }
    if (state is WatchlistLoaded) {
      emit((state as WatchlistLoaded).copyWith(isConnected: true));
    }
  }

  void _onSocketDisconnected(
      SocketDisconnected event,
      Emitter<WatchlistState> emit,
      ) {
    if (state is WatchlistLoaded) {
      emit((state as WatchlistLoaded).copyWith(isConnected: false));
    }
  }

  Future<void> _onAddToWatchlist(
      AddToWatchlist event,
      Emitter<WatchlistState> emit,
      ) async {
    await _hiveService.addToWatchlist(event.symbol);
    final allSymbols = await _symbolRepository.getSymbols();
    _watchlistSymbols = allSymbols
        .where((s) => _hiveService.getWatchlist().contains(s.symbol))
        .toList();
    _socketService.subscribe([event.symbol]);

    try {
      final data = await _apiService.getRealtimeCurrent(
        symbol: event.symbol,
        limit: 1,
      );
      final ticks = data['data'] as List;
      if (ticks.isNotEmpty) {
        final tick = TickModel.fromJson(ticks.last);
        _ticks[event.symbol] = tick;
      }
    } catch (_) {}

    emit(WatchlistLoaded(
      symbols: _watchlistSymbols,
      ticks: Map.from(_ticks),
      isConnected: _socketService.isConnected,
    ));
  }

  Future<void> _onRemoveFromWatchlist(
      RemoveFromWatchlist event,
      Emitter<WatchlistState> emit,
      ) async {
    await _hiveService.removeFromWatchlist(event.symbol);
    _watchlistSymbols.removeWhere((s) => s.symbol == event.symbol);
    _ticks.remove(event.symbol);
    _socketService.unsubscribe([event.symbol]);
    emit(WatchlistLoaded(
      symbols: _watchlistSymbols,
      ticks: Map.from(_ticks),
      isConnected: _socketService.isConnected,
    ));
  }

  void _onTickReceived(
      TickReceived event,
      Emitter<WatchlistState> emit,
      ) {
    _ticks[event.tick.symbol] = event.tick;
    if (state is WatchlistLoaded) {
      emit((state as WatchlistLoaded).copyWith(
        ticks: Map.from(_ticks),
      ));
    }
  }

  @override
  Future<void> close() {
    _tickSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();
    _socketService.disconnect();
    return super.close();
  }
}