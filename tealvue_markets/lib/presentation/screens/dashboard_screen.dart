import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/remote/socket_service.dart';
import '../../data/models/portfolio_model.dart';
import '../../data/models/symbol_model.dart';
import '../../data/models/tick_model.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_state.dart';
import '../blocs/watchlist/watchlist_bloc.dart';
import '../blocs/watchlist/watchlist_state.dart';
import 'chart_screen.dart';

// ── Live data holders ─────────────────────────────────────────────

class _HoldingLive {
  final double currentPrice;
  _HoldingLive(this.currentPrice);
}

class _TickLive {
  final double ltp;
  final double vwap;
  final double changePercent;
  final bool isPositive;
  _TickLive({required this.ltp, required this.vwap,
    required this.changePercent, required this.isPositive});
}

class _Summary {
  final double invested;
  final double current;
  _Summary({required this.invested, required this.current});
  double get pnl => current - invested;
  double get pnlPercent => invested > 0 ? (pnl / invested) * 100 : 0;
  static _Summary zero() => _Summary(invested: 0, current: 0);
}

// ── Dashboard Screen ──────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Portfolio live notifiers
  final Map<String, ValueNotifier<_HoldingLive?>> _holdingNotifiers = {};
  final ValueNotifier<_Summary> _summaryNotifier =
  ValueNotifier(_Summary.zero());

  // Watchlist / market overview live notifiers
  final Map<String, ValueNotifier<_TickLive?>> _tickNotifiers = {};

  // Sim + socket
  late SocketService _socketService;
  late ApiService _apiService;
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  Timer? _simTimer;
  bool _realTickReceived = false;
  final _simRng = math.Random();
  int _simSeq = 4000000;

  List<PortfolioModel> _holdings = [];
  List<String> _watchlistSymbols = [];

  @override
  void initState() {
    super.initState();
    _socketService = sl<SocketService>();
    _apiService = sl<ApiService>();
  }

  // ── Initialise live updates for all symbols ───────────────────

  void _initLive(List<PortfolioModel> holdings, List<String> watchlist) {
    _holdings = List.from(holdings);
    _watchlistSymbols = List.from(watchlist);

    // Seed holding notifiers with avgBuyPrice until REST loads
    for (final h in _holdings) {
      _holdingNotifiers
          .putIfAbsent(h.symbol, () => ValueNotifier(null))
          .value = _HoldingLive(h.currentPrice > 0 ? h.currentPrice : h.avgBuyPrice);
    }
    _updateSummary();
    _loadRestPrices();
  }

  Future<void> _loadRestPrices() async {
    // All unique symbols across holdings + watchlist
    final symbols = {
      ..._holdings.map((h) => h.symbol),
      ..._watchlistSymbols,
    };
    for (final symbol in symbols) {
      try {
        final data = await _apiService.getRealtimeCurrent(
            symbol: symbol, limit: 1);
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(ticks.last);
          if (tick.ltp > 0) _applyTick(symbol, tick);
        }
      } catch (_) {}
    }
    _startSocketListener();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _realTickReceived) return;
      _startSimulation();
    });
  }

  void _startSocketListener() {
    _tickSub?.cancel();
    _tickSub = _socketService.tickStream.listen((data) {
      if (!mounted) return;
      final tick = TickModel.fromJson(data);
      _applyTick(tick.symbol, tick);
      _realTickReceived = true;
    });
  }

  void _applyTick(String symbol, TickModel tick) {
    if (tick.ltp <= 0) return;

    // Update holding notifier if this is a portfolio symbol
    final holdingNotifier = _holdingNotifiers[symbol];
    if (holdingNotifier != null) {
      holdingNotifier.value = _HoldingLive(tick.ltp);
      // Update _holdings for summary recalc
      _holdings = _holdings.map((h) =>
      h.symbol == symbol ? h.copyWith(currentPrice: tick.ltp) : h).toList();
      _updateSummary();
    }

    // Update market tick notifier if this is a watchlist symbol
    if (_watchlistSymbols.contains(symbol)) {
      _tickNotifiers
          .putIfAbsent(symbol, () => ValueNotifier(null))
          .value = _TickLive(
        ltp: tick.ltp,
        vwap: tick.atp,
        changePercent: tick.changePercent,
        isPositive: tick.isPositive,
      );
    }
  }

  void _updateSummary() {
    double invested = 0, current = 0;
    for (final h in _holdings) {
      invested += h.investedValue;
      current += h.currentValue;
    }
    _summaryNotifier.value = _Summary(invested: invested, current: current);
  }

  void _startSimulation() {
    _simTimer?.cancel();
    final allSymbols = {
      ..._holdings.map((h) => h.symbol),
      ..._watchlistSymbols,
    };
    if (allSymbols.isEmpty) return;

    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      for (final symbol in allSymbols) {
        // Get current ltp from whichever notifier has data
        double? baseLtp;
        final hn = _holdingNotifiers[symbol];
        if (hn?.value != null) baseLtp = hn!.value!.currentPrice;
        final tn = _tickNotifiers[symbol];
        if (baseLtp == null && tn?.value != null) baseLtp = tn!.value!.ltp;
        if (baseLtp == null || baseLtp <= 0) continue;

        final pct = (0.0005 + _simRng.nextDouble() * 0.0015) *
            (_simRng.nextBool() ? 1 : -1);
        final newLtp = (baseLtp * (1 + pct))
            .clamp(baseLtp * 0.97, baseLtp * 1.03);

        // Build a synthetic TickModel
        final prevHolding = _holdings.firstWhere(
                (h) => h.symbol == symbol,
            orElse: () => PortfolioModel(
                symbol: symbol, name: symbol,
                quantity: 0, avgBuyPrice: baseLtp!));
        final prevTick = _tickNotifiers[symbol]?.value;
        final synth = TickModel(
          symbol: symbol,
          ltp: newLtp,
          open: prevTick?.ltp ?? newLtp,
          high: newLtp,
          low: newLtp,
          prevClose: prevHolding.avgBuyPrice > 0
              ? prevHolding.avgBuyPrice
              : baseLtp,
          atp: prevTick?.vwap ?? newLtp,
          ttq: 0,
          turnover: 0,
          timestamp: '',
          sequenceNo: _simSeq++,
        );
        _applyTick(symbol, synth);
      }
    });
  }

  void _stopLive() {
    _tickSub?.cancel();
    _simTimer?.cancel();
    _simTimer = null;
  }

  @override
  void dispose() {
    _stopLive();
    for (final n in _holdingNotifiers.values) n.dispose();
    for (final n in _tickNotifiers.values) n.dispose();
    _summaryNotifier.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Dashboard')),
      body: MultiBlocListener(
        listeners: [
          // Portfolio symbols changed → reinit live
          BlocListener<PortfolioBloc, PortfolioState>(
            listenWhen: (prev, curr) {
              if (curr is! PortfolioLoaded) return false;
              if (prev is! PortfolioLoaded) return true;
              final prevIds = prev.holdings.map((h) => h.symbol).toSet();
              final currIds = curr.holdings.map((h) => h.symbol).toSet();
              return prevIds != currIds;
            },
            listener: (context, state) {
              if (state is PortfolioLoaded) {
                _stopLive();
                _realTickReceived = false;
                final wState = context.read<WatchlistBloc>().state;
                final watchlist = wState is WatchlistLoaded
                    ? wState.symbols.map((s) => s.symbol).toList()
                    : <String>[];
                _initLive(state.holdings, watchlist);
              }
            },
          ),
          // Watchlist symbols changed → reinit live
          BlocListener<WatchlistBloc, WatchlistState>(
            listenWhen: (prev, curr) {
              if (curr is! WatchlistLoaded) return false;
              if (prev is! WatchlistLoaded) return true;
              final prevIds = prev.symbols.map((s) => s.symbol).toSet();
              final currIds = curr.symbols.map((s) => s.symbol).toSet();
              return prevIds != currIds;
            },
            listener: (context, state) {
              if (state is WatchlistLoaded) {
                _stopLive();
                _realTickReceived = false;
                final pState = context.read<PortfolioBloc>().state;
                final holdings = pState is PortfolioLoaded
                    ? pState.holdings
                    : <PortfolioModel>[];
                _initLive(holdings,
                    state.symbols.map((s) => s.symbol).toList());
              }
            },
          ),
        ],
        child: BlocBuilder<PortfolioBloc, PortfolioState>(
          // Only rebuild when holdings list structure changes
          buildWhen: (prev, curr) {
            if (curr is! PortfolioLoaded) return true;
            if (prev is! PortfolioLoaded) return true;
            final prevIds = prev.holdings.map((h) => h.symbol).toSet();
            final currIds = curr.holdings.map((h) => h.symbol).toSet();
            return prevIds != currIds;
          },
          builder: (context, pState) {
            return BlocBuilder<WatchlistBloc, WatchlistState>(
              buildWhen: (prev, curr) {
                if (curr is! WatchlistLoaded) return true;
                if (prev is! WatchlistLoaded) return true;
                final prevIds = prev.symbols.map((s) => s.symbol).toSet();
                final currIds = curr.symbols.map((s) => s.symbol).toSet();
                return prevIds != currIds;
              },
              builder: (context, wState) {
                // First load — kick off live updates
                if (pState is PortfolioLoaded && wState is WatchlistLoaded) {
                  final pIds = pState.holdings.map((h) => h.symbol).toSet();
                  final wIds = wState.symbols.map((s) => s.symbol).toSet();
                  final allIds = {...pIds, ...wIds};
                  final notifierIds = {
                    ..._holdingNotifiers.keys,
                    ..._tickNotifiers.keys
                  };
                  if (allIds.isNotEmpty && notifierIds.isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _initLive(pState.holdings,
                            wState.symbols.map((s) => s.symbol).toList());
                      }
                    });
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummary(pState),
                    const SizedBox(height: 20),
                    _buildHoldingsBreakdown(pState),
                    const SizedBox(height: 20),
                    _buildMarketTable(wState),
                    const SizedBox(height: 80),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Summary ───────────────────────────────────────────────────

  Widget _buildSummary(PortfolioState pState) {
    if (pState is! PortfolioLoaded) return const SizedBox();
    return ValueListenableBuilder<_Summary>(
      valueListenable: _summaryNotifier,
      builder: (context, summary, _) {
        final isPnlPositive = summary.pnl >= 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statCard('Invested',
                      '₹${summary.invested.toStringAsFixed(0)}',
                      Icons.account_balance_wallet_outlined, AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard('Current',
                      '₹${summary.current.toStringAsFixed(0)}',
                      Icons.trending_up, AppColors.gain),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPnlPositive ? AppColors.gainLight : AppColors.lossLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isPnlPositive ? AppColors.gain : AppColors.loss),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total P&L',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    '${isPnlPositive ? '+' : ''}₹${summary.pnl.toStringAsFixed(2)} (${summary.pnlPercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: isPnlPositive ? AppColors.gain : AppColors.loss,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Holdings breakdown ────────────────────────────────────────

  Widget _buildHoldingsBreakdown(PortfolioState pState) {
    if (pState is! PortfolioLoaded || pState.holdings.isEmpty) {
      return const SizedBox();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Holdings Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${pState.holdings.length} stocks',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _holdingHeader(),
              ...pState.holdings.map(
                    (h) => GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChartScreen(
                          symbol: SymbolModel(
                            name: h.name, symbol: h.symbol, exchange:"NSE" , type: 'EQUITY', isActive: true,
                          ),
                        )
                      ),
                    );
                  },
                  child: _holdingRow(h),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _holdingHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Stock', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 11))),
          Expanded(flex: 2, child: Text('Invested', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 11))),
          Expanded(flex: 2, child: Text('Current', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 11))),
          Expanded(flex: 2, child: Text('P&L', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _holdingRow(PortfolioModel holding) {
    return ValueListenableBuilder<_HoldingLive?>(
      valueListenable: _holdingNotifiers.putIfAbsent(
          holding.symbol, () => ValueNotifier(null)),
      builder: (context, live, _) {
        final price = live?.currentPrice ??
            (holding.currentPrice > 0 ? holding.currentPrice : holding.avgBuyPrice);
        final currentValue = holding.quantity * price;
        final investedValue = holding.investedValue;
        final pnl = currentValue - investedValue;
        final pnlPct = investedValue > 0 ? (pnl / investedValue) * 100 : 0.0;
        final isProfit = pnl >= 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider))),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(holding.symbol, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('${holding.quantity.toStringAsFixed(0)} × ₹${holding.avgBuyPrice.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('₹${investedValue.toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                flex: 2,
                child: Text('₹${currentValue.toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: isProfit ? AppColors.gain : AppColors.loss),
                    ),
                    Text(
                      '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                      style: TextStyle(fontSize: 10,
                          color: isProfit ? AppColors.gain : AppColors.loss),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Market overview ───────────────────────────────────────────

  Widget _buildMarketTable(WatchlistState wState) {
    if (wState is! WatchlistLoaded || wState.symbols.isEmpty) {
      return const SizedBox();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Market Overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _tableHeader(),
              ...wState.symbols.map((s) => _tableRow(s.symbol)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Stock', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 12))),
          Expanded(child: Text('LTP', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 12))),
          Expanded(child: Text('VWAP', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 12))),
          Expanded(child: Text('Chg%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _tableRow(String symbol) {
    return ValueListenableBuilder<_TickLive?>(
      valueListenable: _tickNotifiers.putIfAbsent(
          symbol, () => ValueNotifier(null)),
      builder: (context, tick, _) {
        final ltp = tick?.ltp ?? 0;
        final vwap = tick?.vwap ?? 0;
        final chg = tick?.changePercent ?? 0;
        final isPos = tick?.isPositive ?? true;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider))),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(
                child: Text(ltp > 0 ? '₹${ltp.toStringAsFixed(1)}' : '—',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: Text(vwap > 0 ? '₹${vwap.toStringAsFixed(1)}' : '—',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: Text(
                  ltp > 0 ? '${isPos ? '+' : ''}${chg.toStringAsFixed(2)}%' : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: isPos ? AppColors.gain : AppColors.loss,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Shared helpers ────────────────────────────────────────────

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}