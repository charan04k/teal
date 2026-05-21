import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/portfolio_model.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_state.dart';
import '../blocs/watchlist/watchlist_bloc.dart';
import '../blocs/watchlist/watchlist_state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPortfolioSummary(),
          const SizedBox(height: 20),
          _buildHoldingsBreakdown(),
          const SizedBox(height: 20),
          _buildMarketTable(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Total summary card ─────────────────────────────────────────

  Widget _buildPortfolioSummary() {
    return BlocBuilder<PortfolioBloc, PortfolioState>(
      builder: (context, state) {
        if (state is! PortfolioLoaded) return const SizedBox();
        final isPnlPositive = state.totalPnl >= 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Summary',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    'Invested',
                    '₹${state.totalInvested.toStringAsFixed(0)}',
                    Icons.account_balance_wallet_outlined,
                    AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    'Current',
                    state.totalCurrent > 0
                        ? '₹${state.totalCurrent.toStringAsFixed(0)}'
                        : '₹${state.totalInvested.toStringAsFixed(0)}',
                    Icons.trending_up,
                    AppColors.gain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPnlPositive
                    ? AppColors.gainLight
                    : AppColors.lossLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isPnlPositive ? AppColors.gain : AppColors.loss,
                    width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total P&L',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    '${isPnlPositive ? '+' : ''}₹${state.totalPnl.toStringAsFixed(2)} (${state.totalPnlPercent.toStringAsFixed(2)}%)',
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

  // ── Per-stock holdings breakdown ───────────────────────────────

  Widget _buildHoldingsBreakdown() {
    return BlocBuilder<PortfolioBloc, PortfolioState>(
      builder: (context, state) {
        if (state is! PortfolioLoaded) return const SizedBox();
        if (state.holdings.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Holdings Breakdown',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text('${state.holdings.length} stocks',
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
                  ...state.holdings.map(
                        (h) => _holdingRow(h),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
          Expanded(
            flex: 3,
            child: Text('Stock',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    fontSize: 11)),
          ),
          Expanded(
            flex: 2,
            child: Text('Invested',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    fontSize: 11)),
          ),
          Expanded(
            flex: 2,
            child: Text('Current',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    fontSize: 11)),
          ),
          Expanded(
            flex: 2,
            child: Text('P&L',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _holdingRow(PortfolioModel h) {
    final hasPrice = h.currentPrice > 0;
    final isProfit = h.isProfit;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // Stock name + qty
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.symbol,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${h.quantity.toStringAsFixed(0)} × ₹${h.avgBuyPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          // Invested
          Expanded(
            flex: 2,
            child: Text(
              '₹${h.investedValue.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          // Current value — show invested as fallback until live price arrives
          Expanded(
            flex: 2,
            child: Text(
              '₹${(hasPrice ? h.currentValue : h.investedValue).toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: hasPrice
                      ? AppColors.textPrimary
                      : AppColors.textMuted),
            ),
          ),
          // Unrealised P&L — show 0.00 as fallback until live price arrives
          Expanded(
            flex: 2,
            child: hasPrice
                ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isProfit ? '+' : ''}₹${h.unrealisedPnl.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isProfit
                          ? AppColors.gain
                          : AppColors.loss),
                ),
                Text(
                  '${isProfit ? '+' : ''}${h.unrealisedPnlPercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontSize: 10,
                      color: isProfit
                          ? AppColors.gain
                          : AppColors.loss),
                ),
              ],
            )
                : const Text('Awaiting price...',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ── Market overview (LTP / VWAP / Chg%) ───────────────────────

  Widget _buildMarketTable(BuildContext context) {
    return BlocBuilder<WatchlistBloc, WatchlistState>(
      builder: (context, state) {
        if (state is! WatchlistLoaded) return const SizedBox();
        if (state.symbols.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Market Overview',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
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
                  ...state.symbols.map((symbol) {
                    final tick = state.ticks[symbol.symbol];
                    return _tableRow(
                      symbol.symbol,
                      tick?.ltp ?? 0,
                      tick?.atp ?? 0,
                      tick?.changePercent ?? 0,
                      tick?.isPositive ?? true,
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
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
          Expanded(
              flex: 2,
              child: Text('Stock',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              child: Text('LTP',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              child: Text('VWAP',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
          Expanded(
              child: Text('Chg%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 12))),
        ],
      ),
    );
  }

  Widget _tableRow(String symbol, double ltp, double vwap,
      double changePercent, bool isPositive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(symbol,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(
                  ltp > 0 ? '₹${ltp.toStringAsFixed(1)}' : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text(
                  vwap > 0 ? '₹${vwap.toStringAsFixed(1)}' : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary))),
          Expanded(
            child: Text(
              ltp > 0
                  ? '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%'
                  : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isPositive ? AppColors.gain : AppColors.loss,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
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
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}