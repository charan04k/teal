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
import '../../domain/repositories/symbol_repository.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_event.dart';
import '../blocs/portfolio/portfolio_state.dart';
import '../blocs/watchlist/watchlist_bloc.dart';
import '../blocs/watchlist/watchlist_state.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  // One ValueNotifier per holding — direct live updates, no BLoC in hot path
  final Map<String, ValueNotifier<PortfolioModel?>> _holdingNotifiers = {};

  // Summary notifier — total portfolio value, P&L, returns
  final ValueNotifier<_PortfolioSummary> _summaryNotifier =
  ValueNotifier(_PortfolioSummary.zero());

  late SocketService _socketService;
  late ApiService _apiService;
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  Timer? _simTimer;
  bool _realTickReceived = false;
  final _simRng = math.Random();
  int _simSeq = 3000000;

  List<PortfolioModel> _holdings = [];

  @override
  void initState() {
    super.initState();
    _socketService = sl<SocketService>();
    _apiService = sl<ApiService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<PortfolioBloc>().state;
      if (state is PortfolioLoaded && state.holdings.isNotEmpty && _holdings.isEmpty) {
        _initLiveUpdates(state.holdings);
      }
    });
  }

  void _initLiveUpdates(List<PortfolioModel> holdings) {
    _holdings = List.from(holdings);
    // Seed notifiers with current holding data
    for (final h in _holdings) {
      _notifierFor(h.symbol).value = h;
    }
    _updateSummary();
    _loadRestPrices();
  }

  Future<void> _loadRestPrices() async {
    for (final holding in List<PortfolioModel>.from(_holdings)) {
      try {
        final data = await _apiService.getRealtimeCurrent(
          symbol: holding.symbol,
          limit: 1,
        );
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(ticks.last);
          if (tick.ltp > 0) _applyTick(holding.symbol, tick.ltp);
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
      if (_holdingNotifiers.containsKey(tick.symbol) && tick.ltp > 0) {
        _applyTick(tick.symbol, tick.ltp);
        _realTickReceived = true;
      }
    });
  }

  void _applyTick(String symbol, double newLtp) {
    final notifier = _holdingNotifiers[symbol];
    if (notifier == null) return;
    final prev = notifier.value;
    if (prev == null) return;
    notifier.value = prev.copyWith(currentPrice: newLtp);
    // Update _holdings list too so simulation uses latest price
    _holdings = _holdings.map((h) =>
    h.symbol == symbol ? h.copyWith(currentPrice: newLtp) : h).toList();
    _updateSummary();
  }

  void _updateSummary() {
    double totalInvested = 0;
    double totalCurrent = 0;
    for (final h in _holdings) {
      totalInvested += h.investedValue;
      totalCurrent += h.currentValue;
    }
    _summaryNotifier.value = _PortfolioSummary(
      totalInvested: totalInvested,
      totalCurrent: totalCurrent,
    );
  }

  void _startSimulation() {
    _simTimer?.cancel();
    if (_holdings.isEmpty) return;
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      for (final holding in List<PortfolioModel>.from(_holdings)) {
        final notifier = _holdingNotifiers[holding.symbol];
        if (notifier == null || notifier.value == null) continue;
        final prev = notifier.value!;
        final pct = (0.0005 + _simRng.nextDouble() * 0.0015) *
            (_simRng.nextBool() ? 1 : -1);
        final newLtp =
        (prev.currentPrice * (1 + pct))
            .clamp(prev.currentPrice * 0.97, prev.currentPrice * 1.03);
        _applyTick(holding.symbol, newLtp);
      }
    });
  }

  void _stopLive() {
    _tickSub?.cancel();
    _simTimer?.cancel();
    _simTimer = null;
  }

  ValueNotifier<PortfolioModel?> _notifierFor(String symbol) =>
      _holdingNotifiers.putIfAbsent(symbol, () => ValueNotifier(null));

  @override
  void dispose() {
    _stopLive();
    for (final n in _holdingNotifiers.values) n.dispose();
    _summaryNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<PortfolioBloc, PortfolioState>(
        // Only rebuild list structure when holdings added/removed
        buildWhen: (prev, curr) {
          if (curr is PortfolioLoading) return true;
          if (prev is PortfolioLoaded && curr is PortfolioLoaded) {
            final prevIds = prev.holdings.map((h) => h.symbol).toSet();
            final currIds = curr.holdings.map((h) => h.symbol).toSet();
            return prevIds != currIds;
          }
          return true;
        },
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
            // Remove notifiers for deleted holdings
            final currentSymbols = state.holdings.map((h) => h.symbol).toSet();
            _holdingNotifiers.keys
                .where((k) => !currentSymbols.contains(k))
                .toList()
                .forEach((k) {
              _holdingNotifiers.remove(k)?.dispose();
            });
            _initLiveUpdates(state.holdings);
          }
        },
        builder: (context, state) {
          if (state is PortfolioLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PortfolioLoaded) {
            if (state.holdings.isEmpty) return _buildEmpty();
            return _buildPortfolio(context, state.holdings);
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildPortfolio(BuildContext context, List<PortfolioModel> holdings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Holdings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${holdings.length} stocks',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        ...holdings.map((h) => _buildHoldingCard(context, h)).toList(),
        const SizedBox(height: 80),
      ],
    );
  }

  // ── Summary card — live via _summaryNotifier ───────────────────
  Widget _buildSummaryCard() {
    return ValueListenableBuilder<_PortfolioSummary>(
      valueListenable: _summaryNotifier,
      builder: (context, summary, _) {
        final isPnlPositive = summary.totalPnl >= 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total Portfolio Value',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                '₹${summary.totalCurrent.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryItem(
                        'Invested',
                        '₹${summary.totalInvested.toStringAsFixed(0)}',
                        Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.3)),
                    Expanded(
                      child: _summaryItem(
                        'P&L',
                        '${isPnlPositive ? '+' : ''}₹${summary.totalPnl.toStringAsFixed(0)}',
                        isPnlPositive
                            ? Icons.trending_up
                            : Icons.trending_down,
                        color: isPnlPositive
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.3)),
                    Expanded(
                      child: _summaryItem(
                        'Returns',
                        '${isPnlPositive ? '+' : ''}${summary.totalPnlPercent.toStringAsFixed(2)}%',
                        Icons.percent,
                        color: isPnlPositive
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
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

  Widget _summaryItem(String label, String value, IconData icon,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.white70, size: 18),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ── Holding card — live via per-symbol ValueNotifier ──────────
  Widget _buildHoldingCard(BuildContext context, PortfolioModel holding) {
    return Dismissible(
      key: ValueKey('holding_${holding.symbol}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove Holding'),
            content: Text('Remove ${holding.symbol} from portfolio?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove',
                      style: TextStyle(color: AppColors.loss))),
            ],
          ),
        );
      },
      onDismissed: (_) {
        context.read<PortfolioBloc>().add(RemoveHolding(holding.symbol));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: AppColors.lossLight,
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: AppColors.loss),
      ),
      child: ValueListenableBuilder<PortfolioModel?>(
        valueListenable: _notifierFor(holding.symbol),
        builder: (context, live, _) {
          final h = live ?? holding;
          final isPnlPositive = h.isProfit;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: Text(h.symbol.substring(0, 1),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.symbol,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(
                              '${h.quantity.toStringAsFixed(0)} shares @ ₹${h.avgBuyPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    // Live price + return %
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${h.currentPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPnlPositive
                                ? AppColors.gainLight
                                : AppColors.lossLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${isPnlPositive ? '+' : ''}${h.unrealisedPnlPercent.toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: isPnlPositive
                                    ? AppColors.gain
                                    : AppColors.loss,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Invested / Current / P&L row
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('Invested',
                          '₹${h.investedValue.toStringAsFixed(0)}'),
                      _stat('Current',
                          '₹${h.currentValue.toStringAsFixed(0)}'),
                      _stat(
                        'P&L',
                        '${isPnlPositive ? '+' : ''}₹${h.unrealisedPnl.toStringAsFixed(0)}',
                        color: isPnlPositive ? AppColors.gain : AppColors.loss,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline_rounded,
              size: 64, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text('No holdings yet',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          SizedBox(height: 8),
          Text('Tap + to add your first holding',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Portfolio summary data class ──────────────────────────────────
class _PortfolioSummary {
  final double totalInvested;
  final double totalCurrent;

  _PortfolioSummary({required this.totalInvested, required this.totalCurrent});

  factory _PortfolioSummary.zero() =>
      _PortfolioSummary(totalInvested: 0, totalCurrent: 0);

  double get totalPnl => totalCurrent - totalInvested;
  double get totalPnlPercent =>
      totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0;
}

// ── Add Holding Sheet ─────────────────────────────────────────────
class AddHoldingSheet extends StatefulWidget {
  const AddHoldingSheet({super.key});

  @override
  State<AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<AddHoldingSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();

  List<SymbolModel> _allSymbols = [];
  SymbolModel? _selectedSymbol;
  bool _isLoadingSymbols = true;
  bool _isFetchingPrice = false;
  double? _marketLtp;
  String _query = '';
  final TextEditingController _priceController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _priceSub;

  @override
  void initState() {
    super.initState();
    _loadSymbols();
    _qtyController.addListener(() => setState(() {}));
    _priceController.addListener(_onPriceChanged);
  }

  Future<void> _loadSymbols() async {
    try {
      final symbols = await sl<SymbolRepository>().getSymbols();
      if (mounted) setState(() { _allSymbols = symbols; _isLoadingSymbols = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingSymbols = false);
    }
  }

  // If WatchlistBloc already has a live tick for this symbol, use it directly
  double? _tickFromWatchlist(String symbol) {
    try {
      final bloc = context.read<WatchlistBloc>();
      final state = bloc.state;
      if (state is WatchlistLoaded) {
        final tick = state.ticks[symbol];
        if (tick != null && tick.ltp > 0) return tick.ltp;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _selectSymbol(SymbolModel symbol) async {
    _priceSub?.cancel();

    // Seed price immediately — field is NEVER blank, spinner is NEVER shown
    // Priority: watchlist live price > deterministic hash seed
    final seedPrice = _tickFromWatchlist(symbol.symbol) ??
        (500.0 + (symbol.symbol.codeUnits.fold(0, (a, b) => a + b) % 3000));

    setState(() {
      _selectedSymbol = symbol;
      _isFetchingPrice = false; // No spinner — show field immediately
      _marketLtp = seedPrice;
      _qtyController.clear();
    });
    // Set text without triggering the listener loop
    _priceController.removeListener(_onPriceChanged);
    _priceController.text = seedPrice.toStringAsFixed(2);
    _priceController.addListener(_onPriceChanged);

    // Silently fetch real price in background — update field if better value found
    _fetchRealPrice(symbol);
  }

  void _onPriceChanged() {
    final val = double.tryParse(_priceController.text.trim());
    if (val != _marketLtp) setState(() => _marketLtp = val);
  }

  Future<void> _fetchRealPrice(SymbolModel symbol) async {
    final apiService = sl<ApiService>();
    double? ltp;

    try {
      final data = await apiService.getRealtimeCurrent(symbol: symbol.symbol, limit: 5000);
      final ticks = data['data'] as List;
      if (ticks.isNotEmpty) {
        final tick = TickModel.fromJson(Map<String, dynamic>.from(ticks.last));
        if (tick.ltp > 0) ltp = tick.ltp;
      }
    } catch (_) {}

    if (ltp == null) {
      try {
        final now = DateTime.now();
        final data = await apiService.getHistoricalData(
          symbol: symbol.symbol,
          startDate: now.subtract(const Duration(days: 7)).toIso8601String().substring(0, 10),
          endDate: now.toIso8601String().substring(0, 10),
          limit: 5000,
        );
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(Map<String, dynamic>.from(ticks.last));
          if (tick.ltp > 0) ltp = tick.ltp;
        }
      } catch (_) {}
    }

    if (ltp == null) {
      try {
        final now = DateTime.now();
        final data = await apiService.getHistoricalData(
          symbol: symbol.symbol,
          startDate: now.subtract(const Duration(days: 90)).toIso8601String().substring(0, 10),
          endDate: now.toIso8601String().substring(0, 10),
          limit: 5000,
        );
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(Map<String, dynamic>.from(ticks.last));
          if (tick.ltp > 0) ltp = tick.ltp;
        }
      } catch (_) {}
    }

    // Only update if we got a real price AND it's different from current
    if (ltp != null && mounted && ltp != _marketLtp &&
        _selectedSymbol?.symbol == symbol.symbol) {
      setState(() => _marketLtp = ltp);
      _priceController.removeListener(_onPriceChanged);
      _priceController.text = ltp!.toStringAsFixed(2);
      _priceController.addListener(_onPriceChanged);
    }
  }

  double get _qty => double.tryParse(_qtyController.text.trim()) ?? 0;
  double get _totalInvestment => _qty > 0 && _marketLtp != null ? _qty * _marketLtp! : 0;

  void _submit() {
    if (_selectedSymbol == null) return;

    if (_qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }

    if (_marketLtp == null || _marketLtp! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Market price not available yet, please wait'),
        ),
      );
      return;
    }

    final portfolioBloc = context.read<PortfolioBloc>();

    final currentState = portfolioBloc.state;

    PortfolioModel newHolding = PortfolioModel(
      symbol: _selectedSymbol!.symbol,
      name: _selectedSymbol!.name,
      quantity: _qty,
      avgBuyPrice: _marketLtp!,
    );

    if (currentState is PortfolioLoaded) {
      try {
        final existing = currentState.holdings.firstWhere(
              (h) => h.symbol == _selectedSymbol!.symbol,
        );
        final totalQty = existing.quantity + _qty;
        final totalInvestment =
            (existing.quantity * existing.avgBuyPrice) +
                (_qty * _marketLtp!);

        final avgPrice = totalInvestment / totalQty;

        newHolding = existing.copyWith(
          quantity: totalQty,
          avgBuyPrice: avgPrice,
        );

        portfolioBloc.add(RemoveHolding(existing.symbol));
      } catch (_) {
      }
    }

    portfolioBloc.add(AddHolding(newHolding));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _allSymbols
        : _allSymbols.where((s) =>
    s.symbol.contains(_query.toUpperCase()) ||
        s.name.toUpperCase().contains(_query.toUpperCase())).toList();

    final showList = _selectedSymbol == null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add Holding', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),

          if (showList) ...[
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search stock e.g. RELIANCE',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingSymbols)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (filtered.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No stocks found')))
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.38),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text(s.symbol.substring(0, 1),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                      ),
                      title: Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                      onTap: () => _selectSymbol(s),
                    );
                  },
                ),
              ),
          ],

          if (!showList) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(_selectedSymbol!.symbol.substring(0, 1),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_selectedSymbol!.symbol, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(_selectedSymbol!.name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  GestureDetector(
                    onTap: () => setState(() { _selectedSymbol = null; _searchController.clear(); _qtyController.clear(); _priceController.clear(); _marketLtp = null; _query = ''; }),
                    child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Avg Buy Price (₹)',
                hintText: 'Enter price',
                prefixIcon: Icon(Icons.currency_rupee, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter Quantity',
                prefixIcon: Icon(Icons.numbers),
                labelText: 'Quantity',
              ),
            ),
            const SizedBox(height: 12),
            if (_qty > 0 && _marketLtp != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.gainLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gain.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Investment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(
                      '₹${_totalInvestment.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.gain),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_qty <= 0 || _marketLtp == null) ? null : _submit,
                child: const Text('Add to Portfolio',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _priceSub?.cancel();
    _searchController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}