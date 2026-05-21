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
  int _version = 0;

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
    // Seed currentPrice = avgBuyPrice so the very first render shows
    // correct invested value. Socket/REST will overwrite with real prices.
    _holdings = _holdings
        .map((h) => h.currentPrice == 0
        ? h.copyWith(currentPrice: h.avgBuyPrice)
        : h)
        .toList();
    emit(PortfolioLoaded(List.from(_holdings), version: ++_version));
    _setupSocket();
    _fetchRestPrices();
  }

  // ── Socket ──────────────────────────────────────────────────────

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
    _holdings = _holdings
        .map((h) => h.symbol == event.holding.symbol && h.currentPrice == 0
        ? h.copyWith(currentPrice: event.holding.avgBuyPrice)
        : h)
        .toList();
    emit(PortfolioLoaded(List.from(_holdings), version: ++_version));
    _socketService.subscribe([event.holding.symbol]);
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
    if (!_holdings.any((h) => h.symbol == event.symbol)) {
      _socketService.unsubscribe([event.symbol]);
    }
    emit(PortfolioLoaded(List.from(_holdings), version: ++_version));
  }

  // ── Price update (socket or REST) ───────────────────────────────
  //
  // Uses copyWith so each updated holding is a NEW object instance.
  // Combined with the version counter, Equatable always detects the
  // state as changed and BlocBuilder rebuilds on every tick.

  void _onUpdatePrices(
      UpdatePortfolioPrices event, Emitter<PortfolioState> emit) {
    bool updated = false;
    _holdings = _holdings.map((h) {
      if (h.symbol == event.tick.symbol && event.tick.ltp > 0) {
        updated = true;
        return h.copyWith(currentPrice: event.tick.ltp);
      }
      return h;
    }).toList();

    if (updated) {
      emit(PortfolioLoaded(List.from(_holdings), version: ++_version));
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────

  @override
  Future<void> close() {
    _tickSub?.cancel();
    return super.close();
  }
}