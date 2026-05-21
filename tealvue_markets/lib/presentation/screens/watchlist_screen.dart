import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: BlocBuilder<WatchlistBloc, WatchlistState>(
              builder: (context, state) {
                if (state is WatchlistLoading) return _buildShimmer();
                if (state is WatchlistError) return _buildError(state.message);
                if (state is WatchlistLoaded) {
                  if (state.symbols.isEmpty) return _buildEmpty();
                  return _buildList(state.symbols, state.ticks);
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

  Widget _buildList(List<SymbolModel> symbols, Map<String, TickModel> ticks) {
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
        final tick = ticks[symbol.symbol];
        return _buildSymbolTile(context, symbol, tick);
      },
    );
  }

  Widget _buildSymbolTile(
      BuildContext context, SymbolModel symbol, TickModel? tick) {
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
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove',
                    style: TextStyle(color: AppColors.loss)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        context.read<WatchlistBloc>().add(RemoveFromWatchlist(symbol.symbol));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.lossLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: AppColors.loss),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChartScreen(symbol: symbol)),
        ),
        child: _FlashingTile(
          key: ValueKey('tile_${symbol.symbol}'),
          symbol: symbol,
          tick: tick,
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
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text('Your watchlist is empty',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          SizedBox(height: 8),
          Text('Tap + to add stocks',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text('Connection failed',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () =>
                context.read<WatchlistBloc>().add(LoadWatchlist()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Retry',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// ── Flashing Tile ─────────────────────────────────────────────────
class _FlashingTile extends StatefulWidget {
  final SymbolModel symbol;
  final TickModel? tick;
  const _FlashingTile({super.key, required this.symbol, required this.tick});

  @override
  State<_FlashingTile> createState() => _FlashingTileState();
}

class _FlashingTileState extends State<_FlashingTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _colorAnimation =
        ColorTween(begin: Colors.transparent, end: Colors.transparent)
            .animate(_controller);
  }

  @override
  void didUpdateWidget(_FlashingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLtp = widget.tick?.ltp;
    final oldLtp = oldWidget.tick?.ltp;
    if (newLtp != null && oldLtp != null && newLtp != oldLtp) {
      final flashColor =
      newLtp > oldLtp ? AppColors.gainLight : AppColors.lossLight;
      _colorAnimation = ColorTween(begin: flashColor, end: Colors.transparent)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tick = widget.tick;
    final isPositive = tick?.isPositive ?? true;
    final ltp = tick?.ltp ?? 0;
    final change = tick?.change ?? 0;
    final changePercent = tick?.changePercent ?? 0;

    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _controller.isAnimating
              ? _colorAnimation.value
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(widget.symbol.symbol.substring(0, 1),
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
                  Text(widget.symbol.symbol,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(widget.symbol.name,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ltp > 0 ? '₹${ltp.toStringAsFixed(2)}' : '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (tick != null)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? AppColors.gainLight
                          : AppColors.lossLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                      style: TextStyle(
                          color: isPositive ? AppColors.gain : AppColors.loss,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Symbol Sheet (public for main_screen) ─────────────────────
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
      setState(() {
        _allSymbols = symbols;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _allSymbols
        : _allSymbols
        .where((s) =>
    s.symbol.contains(_query) ||
        s.name.toUpperCase().contains(_query))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add to Watchlist',
                  style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
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
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No symbols found')))
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final symbol = filtered[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Text(symbol.symbol.substring(0, 1),
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700))),
                    ),
                    title: Text(symbol.symbol,
                        style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(symbol.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary),
                    onTap: () {
                      context.read<WatchlistBloc>().add(
                          AddToWatchlist(symbol.symbol, symbol.name));
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