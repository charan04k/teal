import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/remote/socket_service.dart';
import '../../data/models/symbol_model.dart';
import '../../data/models/tick_model.dart';
import 'dart:math' as math;

// ─── Chart Screen ────────────────────────────────────────────────
class ChartScreen extends StatefulWidget {
  final SymbolModel symbol;
  const ChartScreen({super.key, required this.symbol});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  // ValueNotifiers allow targeted widget rebuilds:
  // - _spotsNotifier  → only the LineChart widget re-renders per tick
  // - _latestTickNotifier → only the StatsBar / AppBar price re-renders per tick
  // setState() is now reserved for infrequent structural changes
  // (loading state, live↔historical toggle, range selection).
  final ValueNotifier<List<FlSpot>> _spotsNotifier = ValueNotifier([]);
  final ValueNotifier<TickModel?> _latestTickNotifier = ValueNotifier(null);

  final List<TickModel> _rawTicks = [];
  final Set<int> _seenSequences = {};
  bool _isLoading = true;
  bool _isHistorical = false;
  String _statusMessage = 'Loading...';
  int _tickCount = 0;

  // Convenience getters so the rest of the code stays readable
  List<FlSpot> get _spots => _spotsNotifier.value;
  TickModel? get _latestTick => _latestTickNotifier.value;

  // Selected quick-range label (null = custom calendar)
  String? _selectedRange; // '1D', '1W', '1M'

  final TransformationController _transformationController =
  TransformationController();

  StreamSubscription<Map<String, dynamic>>? _tickSub;

  late SocketService _socketService;
  late ApiService _apiService;

  // Live line simulation timer
  Timer? _simTimer;
  final _simRng = math.Random();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _socketService = sl<SocketService>();
    _apiService = sl<ApiService>();
    _loadData();
  }

  // ── Live mode ─────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    _stopSimulation();
    _tickSub?.cancel();
    _spotsNotifier.value = [];
    _rawTicks.clear();
    _seenSequences.clear();
    _tickCount = 0;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching data...';
      _isHistorical = false;
      _selectedRange = null;
    });

    try {
      final realtimeData = await _apiService.getRealtimeCurrent(
        symbol: widget.symbol.symbol,
        limit: 5000,
      );

      final realtimeTicks = (realtimeData['data'] as List)
          .map((e) => TickModel.fromJson(e))
          .toList();

      if (realtimeTicks.isNotEmpty) {
        final newSpots = <FlSpot>[];
        for (var t in realtimeTicks) {
          if (_seenSequences.add(t.sequenceNo)) {
            newSpots.add(FlSpot(_tickCount.toDouble(), t.ltp));
            _rawTicks.add(t);
            _tickCount++;
          }
        }
        _spotsNotifier.value = newSpots;
        _latestTickNotifier.value = realtimeTicks.last;
        setState(() {
          _isLoading = false;
          _statusMessage = 'Live · $_tickCount ticks';
        });
        _connectSocket();
        return;
      }

      // Realtime returned nothing — stay in Live mode, connect socket + simulation
      setState(() {
        _isLoading = false;
        _statusMessage = 'Waiting for live data...';
      });
      _connectSocket();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading data';
        _isLoading = false;
      });
    }
  }

  // ── Socket & simulation ───────────────────────────────────────

  void _connectSocket() {
    _tickSub?.cancel();
    _stopSimulation();
    _tickSub = _socketService.tickStream.listen((data) {
      if (!mounted) return;
      final tick = TickModel.fromJson(data);
      if (tick.symbol == widget.symbol.symbol &&
          _seenSequences.add(tick.sequenceNo)) {
        // Hot path: update notifiers directly — no setState, no full rebuild.
        // Only the ValueListenableBuilder wrapping LineChart re-renders.
        final updated = List<FlSpot>.from(_spotsNotifier.value)
          ..add(FlSpot(_spotsNotifier.value.length.toDouble(), tick.ltp));
        _spotsNotifier.value = updated;
        _latestTickNotifier.value = tick;
        _rawTicks.add(tick);
        _tickCount++;
      }
    });
    _socketService.subscribe([widget.symbol.symbol]);

    // Start simulation if no real ticks arrive within 3 s
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _isHistorical) return;
      _startSimulation();
    });
  }

  void _startSimulation() {
    _stopSimulation();
    // Seed a price if none exists yet (API returned nothing)
    if (_latestTickNotifier.value == null) {
      final hash = widget.symbol.symbol.codeUnits.fold(0, (a, b) => a + b);
      final seed = 500.0 + (hash % 3000);
      _latestTickNotifier.value = TickModel(
        symbol: widget.symbol.symbol, ltp: seed, open: seed,
        high: seed, low: seed, prevClose: seed, atp: seed,
        ttq: 0, turnover: 0, timestamp: '', sequenceNo: 0,
      );
      final spot = FlSpot(0, seed);
      _spotsNotifier.value = [spot];
      _tickCount = 1;
    }
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final currentSpots = _spotsNotifier.value;
      final base = currentSpots.isNotEmpty
          ? currentSpots.last.y
          : _latestTickNotifier.value!.ltp;
      final pct = (0.0005 + _simRng.nextDouble() * 0.0015) *
          (_simRng.nextBool() ? 1 : -1);
      final newPrice = (base * (1 + pct)).clamp(base * 0.97, base * 1.03);
      // No setState — notifiers trigger only their respective widgets
      final updated = List<FlSpot>.from(currentSpots)
        ..add(FlSpot(currentSpots.length.toDouble(), newPrice));
      _spotsNotifier.value = updated;

      // Also update _latestTickNotifier so AppBar price + stats bar re-render
      final prev = _latestTickNotifier.value!;
      _latestTickNotifier.value = TickModel(
        symbol: prev.symbol,
        ltp: newPrice,
        open: prev.open,
        high: newPrice > prev.high ? newPrice : prev.high,
        low: newPrice < prev.low ? newPrice : prev.low,
        prevClose: prev.prevClose,
        atp: prev.atp,
        ttq: prev.ttq,
        turnover: prev.turnover,
        timestamp: prev.timestamp,
        sequenceNo: prev.sequenceNo + 1,
      );
      _tickCount++;
    });
  }

  void _stopSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
  }

  // ── Historical mode ───────────────────────────────────────────

  void _loadQuickRange(String label, int days) {
    _stopSimulation();
    _tickSub?.cancel();
    setState(() => _selectedRange = label);
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    _loadHistoricalRange(DateTimeRange(start: start, end: end));
  }

  Future<void> _loadHistoricalRange(DateTimeRange range) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isHistorical = true;
      _statusMessage = 'Loading historical...';
    });

    try {
      final start = range.start.toIso8601String().substring(0, 10);
      final end = range.end.toIso8601String().substring(0, 10);

      final data = await _apiService.getHistoricalData(
        symbol: widget.symbol.symbol,
        startDate: start,
        endDate: end,
        limit: 5000,
      );

      final ticks = (data['data'] as List)
          .map((e) => TickModel.fromJson(e))
          .toList();

      _rawTicks.clear();
      _seenSequences.clear();
      _tickCount = 0;
      final newSpots = <FlSpot>[];
      for (var i = 0; i < ticks.length; i++) {
        newSpots.add(FlSpot(i.toDouble(), ticks[i].ltp));
        _rawTicks.add(ticks[i]);
        _tickCount++;
      }
      _spotsNotifier.value = newSpots;
      if (ticks.isNotEmpty) _latestTickNotifier.value = ticks.last;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Historical · $_tickCount ticks';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error loading data';
      });
    }
  }

  Future<void> _openCalendarPicker() async {
    _stopSimulation();
    _tickSub?.cancel();
    final range = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DateRangeSheet(
        firstDate: DateTime(2024, 1, 1),
        lastDate: DateTime.now(),
        initialRange: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        ),
      ),
    );
    if (range != null) {
      setState(() => _selectedRange = null);
      _loadHistoricalRange(range);
    }
  }

  // ── Zoom reset ────────────────────────────────────────────────

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tickSub?.cancel();
    _stopSimulation();
    // Do NOT unsubscribe here — WatchlistBloc owns the server subscription
    // for watchlist symbols. Unsubscribing here would stop ticks from
    // arriving in the watchlist after returning from ChartScreen.
    _transformationController.dispose();
    _spotsNotifier.dispose();
    _latestTickNotifier.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: isLandscape ? null : _buildAppBar(),
      body: isLandscape ? _buildFullscreenChart() : _buildPortraitLayout(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.symbol.symbol,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.symbol.exchange,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.symbol.name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                // Wrap only the live-updating price+change in ValueListenableBuilder
                ValueListenableBuilder<TickModel?>(
                  valueListenable: _latestTickNotifier,
                  builder: (context, tick, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tick != null ? '₹${tick.ltp.toStringAsFixed(2)}' : '—',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (tick != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tick.isPositive
                                  ? AppColors.gainLight
                                  : AppColors.lossLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${tick.isPositive ? '+' : ''}${tick.change.toStringAsFixed(2)} (${tick.changePercent.toStringAsFixed(2)}%)',
                              style: TextStyle(
                                color: tick.isPositive
                                    ? AppColors.gain
                                    : AppColors.loss,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildTabBar(),
        // Historical sub-controls: quick buttons + calendar
        if (_isHistorical) _buildHistoricalControls(),
        Expanded(child: _buildChartArea()),
        if (!_isLoading) _buildStatsBar(),
      ],
    );
  }

  Widget _buildFullscreenChart() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
          child: _buildChartArea(),
        ),
        Positioned(
          top: 8,
          left: 16,
          child: SafeArea(
            child: ValueListenableBuilder<TickModel?>(
              valueListenable: _latestTickNotifier,
              builder: (context, tick, _) {
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(widget.symbol.symbol,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    if (tick != null)
                      Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tick.isPositive
                              ? AppColors.gainLight
                              : AppColors.lossLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '₹${tick.ltp.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: tick.isPositive
                                ? AppColors.gain
                                : AppColors.loss,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─── Tab bar ──────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _tabButton('Live', !_isHistorical, _loadData),
          const SizedBox(width: 8),
          _tabButton('Historical', _isHistorical, () {
            if (!_isHistorical) {
              _stopSimulation();
              _tickSub?.cancel();
              setState(() {
                _isHistorical = true;
                _selectedRange = '1D';
              });
              _loadQuickRange('1D', 1);
            }
          }),
          const Spacer(),
          // Live indicator (only in live mode)
          if (!_isHistorical)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _isLoading
                          ? Colors.orange
                          : _spotsNotifier.value.isNotEmpty
                          ? AppColors.gain
                          : AppColors.loss,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isLoading
                        ? 'Loading...'
                        : _spotsNotifier.value.isNotEmpty
                        ? '$_tickCount ticks'
                        : 'No data',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Historical controls: 1D / 1W / 1M + calendar ────────────

  Widget _buildHistoricalControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _rangeChip('1D', () => _loadQuickRange('1D', 1)),
          const SizedBox(width: 8),
          _rangeChip('1W', () => _loadQuickRange('1W', 7)),
          const SizedBox(width: 8),
          _rangeChip('1M', () => _loadQuickRange('1M', 30)),
          const Spacer(),
          // Calendar icon button
          GestureDetector(
            onTap: _openCalendarPicker,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _selectedRange == null
                    ? AppColors.primary
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selectedRange == null
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: _selectedRange == null
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(String label, VoidCallback onTap) {
    final isActive = _selectedRange == label;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ─── Chart area ───────────────────────────────────────────────

  Widget _buildChartArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading chart data...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // ValueListenableBuilder ensures only this subtree re-renders per tick.
    // The AppBar, TabBar, and StatsBar are outside this builder and stay still.
    return ValueListenableBuilder<List<FlSpot>>(
      valueListenable: _spotsNotifier,
      builder: (context, spots, _) {
        if (spots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.show_chart, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(_statusMessage,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Retry', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 5.0,
              child: _buildLineChart(spots),
            ),
            if (!_isHistorical)
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.gain,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('LIVE',
                        style: TextStyle(
                            fontSize: 9,
                            color: AppColors.gain,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLineChart(List<FlSpot> spots) {
    final prices = spots.map((s) => s.y).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range == 0 ? 10.0 : range * 0.1;

    final bool isPositive;
    if (_isHistorical && spots.length >= 2) {
      isPositive = spots.last.y >= spots.first.y;
    } else {
      isPositive = _latestTickNotifier.value?.isPositive ?? true;
    }
    final lineColor = isPositive ? AppColors.gain : AppColors.loss;
    final fillColor = isPositive ? AppColors.gainLight : AppColors.lossLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: LineChart(
        LineChartData(
          minY: minY - padding,
          maxY: maxY + padding,
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range == 0 ? 10 : range / 4,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.border,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 72,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '₹${value.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
            bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.from(spots),
              isCurved: true,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: fillColor.withValues(alpha: 0.25),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: AppColors.textPrimary,
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                '₹${s.y.toStringAsFixed(2)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ))
                  .toList(),
            ),
          ),
        ),
        duration: Duration.zero,
      ),
    );
  }

  Widget _buildStatsBar() {
    return ValueListenableBuilder<TickModel?>(
      valueListenable: _latestTickNotifier,
      builder: (context, tick, _) {
        if (tick == null) return const SizedBox();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
            color: AppColors.surface,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Open', tick.open),
              _statItem('High', tick.high),
              _statItem('Low', tick.low),
              _statItem('VWAP', tick.atp),
              _statItem('Prev', tick.prevClose),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String label, double value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          '₹${value.toStringAsFixed(1)}',
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

// ─── Custom Date Range Picker Sheet ──────────────────────────────

class _DateRangeSheet extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;

  const _DateRangeSheet({
    required this.firstDate,
    required this.lastDate,
    this.initialRange,
  });

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _month;

  static const List<String> _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];
  static const List<String> _shortMonths = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
    _month = DateTime(
      widget.initialRange?.start.year ?? widget.lastDate.year,
      widget.initialRange?.start.month ?? widget.lastDate.month,
    );
  }

  bool _isEnabled(DateTime d) {
    final day = _stripTime(d);
    return !day.isBefore(_stripTime(widget.firstDate)) &&
        !day.isAfter(_stripTime(widget.lastDate));
  }

  bool _isStart(DateTime d) =>
      _start != null && _stripTime(d) == _stripTime(_start!);
  bool _isEnd(DateTime d) =>
      _end != null && _stripTime(d) == _stripTime(_end!);

  bool _inRange(DateTime d) {
    if (_start == null || _end == null) return false;
    final day = _stripTime(d);
    return day.isAfter(_stripTime(_start!)) && day.isBefore(_stripTime(_end!));
  }

  DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  void _onTap(DateTime d) {
    if (!_isEnabled(d)) return;
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = d;
        _end = null;
      } else {
        if (d.isBefore(_start!)) {
          _end = _start;
          _start = d;
        } else {
          _end = d;
        }
      }
    });
  }

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';

  void _prevMonth() {
    final prev = DateTime(_month.year, _month.month - 1);
    if (!prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month))) {
      setState(() => _month = prev);
    }
  }

  void _nextMonth() {
    final next = DateTime(_month.year, _month.month + 1);
    if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) {
      setState(() => _month = next);
    }
  }

  bool get _canPrev {
    final prev = DateTime(_month.year, _month.month - 1);
    return !prev.isBefore(
        DateTime(widget.firstDate.year, widget.firstDate.month));
  }

  bool get _canNext {
    final next = DateTime(_month.year, _month.month + 1);
    return !next
        .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
  }

  bool get _canApply => _start != null && _end != null;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                _sheetIconBtn(Icons.close_rounded,
                    onTap: () => Navigator.pop(context)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Date Range',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
                GestureDetector(
                  onTap: _canApply
                      ? () => Navigator.pop(
                      context, DateTimeRange(start: _start!, end: _end!))
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: _canApply ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _canApply ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Selected range pill
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _rangeLabel(_fmt(_start),
                    active: _start != null && _end == null),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      height: 1.5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 14, color: AppColors.primary),
                  ]),
                ),
                _rangeLabel(_fmt(_end),
                    active: _start != null && _end == null),
              ],
            ),
          ),

          // Month navigator
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                _sheetIconBtn(Icons.chevron_left_rounded,
                    onTap: _canPrev ? _prevMonth : null,
                    enabled: _canPrev),
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
                _sheetIconBtn(Icons.chevron_right_rounded,
                    onTap: _canNext ? _nextMonth : null,
                    enabled: _canNext),
              ],
            ),
          ),

          // Day-of-week headers
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                  .map((h) => Expanded(
                child: Center(
                  child: Text(h,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                ),
              ))
                  .toList(),
            ),
          ),

          // Calendar grid
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          //   child: _buildGrid(daysInMonth, firstWeekday),
          // ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildGrid(int daysInMonth, int firstWeekday) {
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      final enabled = _isEnabled(date);
      final start = _isStart(date);
      final end = _isEnd(date);
      final mid = _inRange(date);
      final singleDay = start && _end != null && _isEnd(date);

      cells.add(_DayCell(
        day: d,
        enabled: enabled,
        isStart: start,
        isEnd: end,
        isMid: mid,
        isSingleDay: singleDay,
        onTap: () => _onTap(date),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.05,
      children: cells,
    );
  }

  Widget _rangeLabel(String text, {required bool active}) {
    return Column(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 2,
          width: active ? 36 : 0,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _sheetIconBtn(IconData icon,
      {VoidCallback? onTap, bool enabled = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            size: 20,
            color: enabled ? AppColors.textPrimary : AppColors.textMuted),
      ),
    );
  }
}

// ─── Individual day cell ──────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int day;
  final bool enabled;
  final bool isStart;
  final bool isEnd;
  final bool isMid;
  final bool isSingleDay;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.enabled,
    required this.isStart,
    required this.isEnd,
    required this.isMid,
    required this.isSingleDay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!isSingleDay && (isStart || isEnd || isMid))
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: isStart
                          ? Colors.transparent
                          : AppColors.primaryLight,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color:
                      isEnd ? Colors.transparent : AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),
          if (isMid && !isStart && !isEnd)
            Positioned.fill(
              child: Container(color: AppColors.primaryLight),
            ),
          if (isStart || isEnd)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight:
              (isStart || isEnd) ? FontWeight.w700 : FontWeight.w400,
              color: isStart || isEnd
                  ? Colors.white
                  : enabled
                  ? AppColors.textPrimary
                  : AppColors.textMuted.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}