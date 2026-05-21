import 'package:flutter/material.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../core/di/injection_container.dart';
import '../../domain/repositories/symbol_repository.dart';
import '../../data/models/symbol_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/portfolio_model.dart';
import '../../data/models/tick_model.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_event.dart';
import '../blocs/portfolio/portfolio_state.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocBuilder<PortfolioBloc, PortfolioState>(
        builder: (context, state) {
          if (state is PortfolioLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PortfolioLoaded) {
            if (state.holdings.isEmpty) return _buildEmpty();
            return _buildPortfolio(context, state);
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildPortfolio(BuildContext context, PortfolioLoaded state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(state),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Holdings',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${state.holdings.length} stocks',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        ...state.holdings.map((h) => _buildHoldingCard(context, h)).toList(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSummaryCard(PortfolioLoaded state) {
    final isPnlPositive = state.totalPnl >= 0;
    // Use live current value when prices are loaded; fall back to invested value
    // (prices not yet received means totalCurrent == 0).
    final pricesLoaded = state.totalCurrent > 0;
    final displayValue =
    pricesLoaded ? state.totalCurrent : state.totalInvested;
    final displayLabel =
    pricesLoaded ? 'Total Portfolio Value' : 'Total Invested';
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
          Text(displayLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            '₹${displayValue.toStringAsFixed(2)}',
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
                    '₹${state.totalInvested.toStringAsFixed(0)}',
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
                    '${isPnlPositive ? '+' : ''}₹${state.totalPnl.toStringAsFixed(0)}',
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
                    '${isPnlPositive ? '+' : ''}${state.totalPnlPercent.toStringAsFixed(2)}%',
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
              style:
              const TextStyle(color: Colors.white60, fontSize: 11)),
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

  Widget _buildHoldingCard(BuildContext context, PortfolioModel holding) {
    final isPnlPositive = holding.isProfit;
    // hasLivePrice = true once socket/REST delivers a real market price.
    // Initially currentPrice is seeded to avgBuyPrice, so P&L = 0 until live.
    final hasLivePrice = holding.currentPrice > 0;
    final hasPrice = hasLivePrice;

    return Dismissible(
      key: ValueKey('holding_${holding.symbol}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove Holding'),
            content:
            Text('Remove ${holding.symbol} from portfolio?'),
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
      child: Container(
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
                    child: Text(holding.symbol.substring(0, 1),
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
                      Text(holding.symbol,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                          '${holding.quantity.toStringAsFixed(0)} shares @ ₹${holding.avgBuyPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hasPrice
                          ? '₹${holding.currentPrice.toStringAsFixed(2)}'
                          : '₹${holding.avgBuyPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (hasPrice)
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
                          '${isPnlPositive ? '+' : ''}${holding.unrealisedPnlPercent.toStringAsFixed(2)}%',
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Invested',
                      '₹${holding.investedValue.toStringAsFixed(0)}'),
                  _stat('Current',
                      '₹${(hasPrice ? holding.currentValue : holding.investedValue).toStringAsFixed(0)}'),
                  _stat(
                    'P&L',
                    hasPrice
                        ? '${isPnlPositive ? '+' : ''}₹${holding.unrealisedPnl.toStringAsFixed(0)}'
                        : '₹0',
                    color: hasPrice
                        ? (isPnlPositive ? AppColors.gain : AppColors.loss)
                        : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
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

  @override
  void initState() {
    super.initState();
    _loadSymbols();
    _qtyController.addListener(() => setState(() {}));
  }

  Future<void> _loadSymbols() async {
    try {
      final symbols = await sl<SymbolRepository>().getSymbols();
      if (mounted) setState(() { _allSymbols = symbols; _isLoadingSymbols = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingSymbols = false);
    }
  }

  Future<void> _selectSymbol(SymbolModel symbol) async {
    setState(() {
      _selectedSymbol = symbol;
      _isFetchingPrice = true;
      _marketLtp = null;
      _qtyController.clear();
    });
    try {
      final data = await sl<ApiService>().getRealtimeCurrent(symbol: symbol.symbol, limit: 1);
      final ticks = data['data'] as List;
      if (ticks.isNotEmpty && mounted) {
        // API returns UPPERCASE keys (LTP, OPEN, etc.)
        // Always parse through TickModel.fromJson — never access map keys directly
        final tick = TickModel.fromJson(Map<String, dynamic>.from(ticks.last));
        setState(() { _marketLtp = tick.ltp > 0 ? tick.ltp : null; _isFetchingPrice = false; });
      } else {
        if (mounted) setState(() => _isFetchingPrice = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isFetchingPrice = false);
    }
  }

  double get _qty => double.tryParse(_qtyController.text.trim()) ?? 0;
  double get _totalInvestment => _qty > 0 && _marketLtp != null ? _qty * _marketLtp! : 0;

  void _submit() {
    if (_selectedSymbol == null) return;
    if (_qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid quantity')));
      return;
    }
    if (_marketLtp == null || _marketLtp! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Market price not available yet, please wait')));
      return;
    }
    context.read<PortfolioBloc>().add(
      AddHolding(PortfolioModel(
        symbol: _selectedSymbol!.symbol,
        name: _selectedSymbol!.name,
        quantity: _qty,
        avgBuyPrice: _marketLtp!,
      )),
    );
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add Holding', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),

          // ── Phase 1: Stock Search ────────────────────────────────
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

          // ── Phase 2: Quantity + Auto Price ───────────────────────
          if (!showList) ...[
            // Selected stock chip
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
                    onTap: () => setState(() { _selectedSymbol = null; _searchController.clear(); _qtyController.clear(); _marketLtp = null; _query = ''; }),
                    child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Market Price (LTP) — read-only, fetched from API
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Market Price (LTP)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text('Avg Buy Price = LTP at time of adding', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                  _isFetchingPrice
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                    _marketLtp != null ? '₹${_marketLtp!.toStringAsFixed(2)}' : '—',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quantity field
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

            // Total Investment preview (auto-calculated)
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

            // Add button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_isFetchingPrice || _qty <= 0 || _marketLtp == null) ? null : _submit,
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
    _searchController.dispose();
    _qtyController.dispose();
    super.dispose();
  }
}