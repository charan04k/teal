import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/remote/socket_service.dart';
import '../../data/models/symbol_model.dart';
import '../../data/models/tick_model.dart';
import '../../domain/repositories/symbol_repository.dart';
import '../blocs/watchlist/watchlist_bloc.dart';
import '../blocs/watchlist/watchlist_event.dart';
import '../blocs/watchlist/watchlist_state.dart';
import 'chart_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, ValueNotifier<TickModel?>> _tickNotifiers = {};

  late SocketService _socketService;
  late ApiService _apiService;
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  Timer? _simTimer;
  final _simRng = math.Random();
  int _simSeq = 2000000;
  List<SymbolModel> _symbols = [];
  bool _liveStarted = false;

  @override
  void initState() {
    super.initState();
    _socketService = sl<SocketService>();
    _apiService = sl<ApiService>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs every time this widget gets new dependencies — including first build.
    // Safe to read context here.
    if (!_liveStarted) {
      final state = context.read<WatchlistBloc>().state;
      if (state is WatchlistLoaded && state.symbols.isNotEmpty) {
        _liveStarted = true;
        _startLive(state.symbols, state.ticks);
      }
    }
  }

  void _startLive(List<SymbolModel> symbols, Map<String, TickModel> existingTicks) {
    _stopLive();
    _symbols = List.from(symbols);

    // Create notifiers
    for (final s in symbols) {
      _tickNotifiers.putIfAbsent(s.symbol, () => ValueNotifier(null));
    }

    // Seed immediately from existing bloc ticks
    existingTicks.forEach((symbol, tick) {
      if (tick.ltp > 0 && _tickNotifiers.containsKey(symbol)) {
        _tickNotifiers[symbol]!.value = tick;
      }
    });

    // Start socket listener
    _tickSub = _socketService.tickStream.listen((data) {
      if (!mounted) return;
      final tick = TickModel.fromJson(data);
      final notifier = _tickNotifiers[tick.symbol];
      if (notifier == null || tick.ltp <= 0) return;
      notifier.value = tick;
    });

    // Fetch REST prices for each symbol
    _fetchPrices();
  }

  Future<void> _fetchPrices() async {
    for (final symbol in List<SymbolModel>.from(_symbols)) {
      if (!mounted) return;
      try {
        final data = await _apiService.getRealtimeCurrent(
            symbol: symbol.symbol, limit: 5000);
        final ticks = data['data'] as List;
        if (ticks.isNotEmpty) {
          final tick = TickModel.fromJson(ticks.last);
          if (tick.ltp > 0) _tickNotifiers[symbol.symbol]?.value = tick;
        }
      } catch (_) {}
    }

    // After REST, start simulation for any notifiers still null
    if (!mounted) return;
    _startSimulation();
  }

  void _startSimulation() {
    _simTimer?.cancel();
    // For symbols with no price yet, give them a seed price
    for (final s in _symbols) {
      final notifier = _tickNotifiers[s.symbol];
      if (notifier != null && notifier.value == null) {
        // Use symbol hash as seed so same symbol always starts at same price
        final hash = s.symbol.codeUnits.fold(0, (a, b) => a + b);
        final seed = 500.0 + (hash % 3000);
        notifier.value = TickModel(
          symbol: s.symbol, ltp: seed, open: seed,
          high: seed, low: seed, prevClose: seed,
          atp: seed, ttq: 0, turnover: 0,
          timestamp: '', sequenceNo: _simSeq++,
        );
      }
    }

    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      for (final symbol in _symbols) {
        final notifier = _tickNotifiers[symbol.symbol];
        if (notifier == null) continue;
        final prev = notifier.value;
        if (prev == null) continue;
        final pct = (0.0005 + _simRng.nextDouble() * 0.0015) *
            (_simRng.nextBool() ? 1 : -1);
        final newLtp = (prev.ltp * (1 + pct))
            .clamp(prev.ltp * 0.97, prev.ltp * 1.03);
        notifier.value = TickModel(
          symbol: prev.symbol, ltp: newLtp,
          open: prev.open,
          high: newLtp > prev.high ? newLtp : prev.high,
          low: newLtp < prev.low ? newLtp : prev.low,
          prevClose: prev.prevClose, atp: prev.atp,
          ttq: prev.ttq, turnover: prev.turnover,
          timestamp: prev.timestamp, sequenceNo: _simSeq++,
        );
      }
    });
  }

  void _stopLive() {
    _tickSub?.cancel();
    _simTimer?.cancel();
    _simTimer = null;
  }

  ValueNotifier<TickModel?> _notifierFor(String symbol) =>
      _tickNotifiers.putIfAbsent(symbol, () => ValueNotifier(null));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: BlocConsumer<WatchlistBloc, WatchlistState>(
              buildWhen: (prev, curr) {
                if (curr is WatchlistLoading || curr is WatchlistError) return true;
                if (prev is WatchlistLoaded && curr is WatchlistLoaded) {
                  final prevIds = prev.symbols.map((s) => s.symbol).toSet();
                  final currIds = curr.symbols.map((s) => s.symbol).toSet();
                  return prevIds != currIds;
                }
                return true;
              },
              listenWhen: (prev, curr) {
                if (curr is WatchlistLoaded && !_liveStarted) return true;
                if (curr is WatchlistLoaded && prev is WatchlistLoaded) {
                  final prevIds = prev.symbols.map((s) => s.symbol).toSet();
                  final currIds = curr.symbols.map((s) => s.symbol).toSet();
                  return prevIds != currIds;
                }
                return false;
              },
              listener: (context, state) {
                if (state is WatchlistLoaded) {
                  _liveStarted = true;
                  _startLive(state.symbols, state.ticks);
                }
              },
              builder: (context, state) {
                if (state is WatchlistLoading) return _buildShimmer();
                if (state is WatchlistError) return _buildError(state.message);
                if (state is WatchlistLoaded) {
                  if (state.symbols.isEmpty) return _buildEmpty();
                  return _buildList(state.symbols);
                }
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.toUpperCase()),
        decoration: const InputDecoration(
          hintText: 'Search watchlist...',
          prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _buildList(List<SymbolModel> symbols) {
    final filtered = symbols
        .where((s) =>
    s.symbol.contains(_searchQuery) ||
        s.name.toUpperCase().contains(_searchQuery))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final symbol = filtered[index];
        return _buildSymbolTile(context, symbol, _notifierFor(symbol.symbol));
      },
    );
  }

  Widget _buildSymbolTile(BuildContext context, SymbolModel symbol,
      ValueNotifier<TickModel?> tickNotifier) {
    return Dismissible(
      key: ValueKey(symbol.symbol),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove Stock'),
            content: Text('Remove ${symbol.symbol} from watchlist?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove', style: TextStyle(color: AppColors.loss))),
            ],
          ),
        );
      },
      onDismissed: (_) => context.read<WatchlistBloc>().add(RemoveFromWatchlist(symbol.symbol)),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.lossLight, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: AppColors.loss),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChartScreen(symbol: symbol))),
        child: _WatchlistTile(
          key: ValueKey('tile_${symbol.symbol}'),
          symbol: symbol,
          tickNotifier: tickNotifier,
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey[200]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 72,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bookmark_border, size: 64, color: AppColors.textMuted),
        SizedBox(height: 16),
        Text('Your watchlist is empty',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        SizedBox(height: 8),
        Text('Tap + to add stocks', style: TextStyle(color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 16),
        const Text('Connection failed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => context.read<WatchlistBloc>().add(LoadWatchlist()),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Retry', style: TextStyle(color: Colors.white)),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _stopLive();
    _searchController.dispose();
    for (final n in _tickNotifiers.values) n.dispose();
    super.dispose();
  }
}

// ── Tile ──────────────────────────────────────────────────────────
class _WatchlistTile extends StatelessWidget {
  final SymbolModel symbol;
  final ValueNotifier<TickModel?> tickNotifier;
  const _WatchlistTile({super.key, required this.symbol, required this.tickNotifier});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(symbol.symbol.substring(0, 1),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(symbol.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(symbol.name,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          ValueListenableBuilder<TickModel?>(
            valueListenable: tickNotifier,
            builder: (context, tick, _) {
              final ltp = tick?.ltp ?? 0;
              final isPositive = tick?.isPositive ?? true;
              final change = tick?.change ?? 0;
              final changePercent = tick?.changePercent ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(ltp > 0 ? '₹${ltp.toStringAsFixed(2)}' : '—',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (tick != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPositive ? AppColors.gainLight : AppColors.lossLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                        style: TextStyle(
                            color: isPositive ? AppColors.gain : AppColors.loss,
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Add Symbol Sheet ──────────────────────────────────────────────
class AddSymbolSheet extends StatefulWidget {
  const AddSymbolSheet({super.key});
  @override
  State<AddSymbolSheet> createState() => _AddSymbolSheetState();
}

class _AddSymbolSheetState extends State<AddSymbolSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  List<SymbolModel> _allSymbols = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  Future<void> _loadSymbols() async {
    try {
      final symbols = await sl<SymbolRepository>().getSymbols();
      if (mounted) setState(() { _allSymbols = symbols; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _allSymbols
        : _allSymbols.where((s) =>
    s.symbol.contains(_query) ||
        s.name.toUpperCase().contains(_query)).toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add to Watchlist',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.toUpperCase()),
            decoration: const InputDecoration(
              hintText: 'Search symbol e.g. RELIANCE',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No symbols found')))
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final symbol = filtered[index];
                  return ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(symbol.symbol.substring(0, 1),
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                    ),
                    title: Text(symbol.symbol, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(symbol.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                    onTap: () {
                      context.read<WatchlistBloc>().add(AddToWatchlist(symbol.symbol, symbol.name));
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}