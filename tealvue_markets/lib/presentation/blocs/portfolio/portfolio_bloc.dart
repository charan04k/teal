import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/datasources/remote/api_service.dart';
import '../../../data/datasources/remote/socket_service.dart';
import '../../../data/models/portfolio_model.dart';
import '../../../data/models/tick_model.dart';
import '../../../domain/repositories/portfolio_repository.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  final PortfolioRepository _repository;
  final ApiService _apiService;
  final SocketService _socketService;

  List<PortfolioModel> _holdings = [];
  StreamSubscription<Map<String, dynamic>>? _tickSub;

  PortfolioBloc({
    required PortfolioRepository repository,
    required ApiService apiService,
    required SocketService socketService,
  })  : _repository = repository,
        _apiService = apiService,
        _socketService = socketService,
        super(PortfolioInitial()) {
    on<LoadPortfolio>(_onLoad);
    on<AddHolding>(_onAdd);
    on<RemoveHolding>(_onRemove);
    on<UpdatePortfolioPrices>(_onUpdatePrices);
  }

  // ── Load ────────────────────────────────────────────────────────

  void _onLoad(LoadPortfolio event, Emitter<PortfolioState> emit) {
    _holdings = _repository.getPortfolio();
    // Seed currentPrice = avgBuyPrice so the very first emit has
    // totalCurrent = totalInvested and totalPnl = 0 (not -100%).
    // Socket/REST will overwrite this with real market prices shortly.
    for (var h in _holdings) {
      if (h.currentPrice == 0) h.currentPrice = h.avgBuyPrice;
    }
    emit(PortfolioLoaded(List.from(_holdings)));
    _setupSocket();
    _fetchRestPrices();
  }

  // ── Socket setup ────────────────────────────────────────────────
  // Portfolio subscribes to its own symbols on the shared broadcast socket.
  // This is independent of the watchlist — portfolio stocks get live tick
  // updates even when they are NOT on the watchlist.

  void _setupSocket() {
    _tickSub?.cancel();
    _tickSub = _socketService.tickStream.listen((data) {
      final tick = TickModel.fromJson(data);
      if (_holdings.any((h) => h.symbol == tick.symbol)) {
        add(UpdatePortfolioPrices(tick));
      }
    });
    _subscribeCurrentHoldings();
  }

  void _subscribeCurrentHoldings() {
    final symbols = _holdings.map((h) => h.symbol).toList();
    if (symbols.isNotEmpty) {
      _socketService.subscribe(symbols);
    }
  }

  // ── REST price seed ─────────────────────────────────────────────
  // On cold start the socket may not have sent ticks yet.
  // Fetch one tick per holding from REST to populate current prices
  // immediately so the dashboard doesn't show dashes on first load.

  Future<void> _fetchRestPrices() async {
    for (final holding in List<PortfolioModel>.from(_holdings)) {
      try {
        final data = await _apiService.getRealtimeCurrent(
          symbol: holding.symbol,
          limit: 1,
        );
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          add(UpdatePortfolioPrices(TickModel.fromJson(ticks.last)));
        }
      } catch (_) {}
    }
  }

  // ── Add ─────────────────────────────────────────────────────────

  Future<void> _onAdd(AddHolding event, Emitter<PortfolioState> emit) async {
    await _repository.addHolding(event.holding);
    _holdings = _repository.getPortfolio();
    // Seed currentPrice = avgBuyPrice for the new holding immediately
    for (var h in _holdings) {
      if (h.symbol == event.holding.symbol && h.currentPrice == 0) {
        h.currentPrice = event.holding.avgBuyPrice;
      }
    }
    emit(PortfolioLoaded(List.from(_holdings)));
    // Subscribe the new symbol to the socket immediately
    _socketService.subscribe([event.holding.symbol]);
    // Also seed price from REST right away
    try {
      final data = await _apiService.getRealtimeCurrent(
        symbol: event.holding.symbol,
        limit: 1,
      );
      final ticks = data['data'] as List;
      if (ticks.isNotEmpty) {
        add(UpdatePortfolioPrices(TickModel.fromJson(ticks.last)));
      }
    } catch (_) {}
  }

  // ── Remove ──────────────────────────────────────────────────────

  Future<void> _onRemove(
      RemoveHolding event, Emitter<PortfolioState> emit) async {
    await _repository.removeHolding(event.symbol);
    _holdings.removeWhere((h) => h.symbol == event.symbol);
    // Only unsubscribe if symbol is not in any remaining holding
    if (!_holdings.any((h) => h.symbol == event.symbol)) {
      _socketService.unsubscribe([event.symbol]);
    }
    emit(PortfolioLoaded(List.from(_holdings)));
  }

  // ── Price update (from socket or REST) ──────────────────────────

  void _onUpdatePrices(
      UpdatePortfolioPrices event, Emitter<PortfolioState> emit) {
    bool updated = false;
    for (var holding in _holdings) {
      if (holding.symbol == event.tick.symbol) {
        holding.currentPrice = event.tick.ltp;
        updated = true;
      }
    }
    if (updated) {
      emit(PortfolioLoaded(List.from(_holdings)));
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────

  @override
  Future<void> close() {
    _tickSub?.cancel();
    return super.close();
  }
}