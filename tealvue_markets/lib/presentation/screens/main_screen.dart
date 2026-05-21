import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/injection_container.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/local/hive_service.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/remote/socket_service.dart';
import '../../domain/repositories/portfolio_repository.dart';
import '../../domain/repositories/symbol_repository.dart';
import '../blocs/watchlist/watchlist_bloc.dart';
import '../blocs/watchlist/watchlist_event.dart';
import '../blocs/watchlist/watchlist_state.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_event.dart';
import '../blocs/portfolio/portfolio_state.dart';
import 'watchlist_screen.dart';
import 'portfolio_screen.dart';
import 'dashboard_screen.dart';
import 'about_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    WatchlistScreen(),
    PortfolioScreen(),
    DashboardScreen(),
    AboutScreen()
  ];

  final List<String> _titles = [
    'Watchlist',
    'Portfolio',
    'Dashboard',
    'About',
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(
      icon: Icons.bookmark_border_rounded,
      activeIcon: Icons.bookmark_rounded,
      label: 'Watchlist',
    ),
    _NavItem(
      icon: Icons.pie_chart_outline_rounded,
      activeIcon: Icons.pie_chart_rounded,
      label: 'Portfolio',
    ),
    _NavItem(
      icon: Icons.grid_view_rounded,
      activeIcon: Icons.grid_view_rounded,
      label: 'Dashboard',
    ),
    _NavItem(
      icon: Icons.info_outline_rounded,
      activeIcon: Icons.info_rounded,
      label: 'About',
    ),
  ];

  late WatchlistBloc _watchlistBloc;
  late PortfolioBloc _portfolioBloc;

  @override
  void initState() {
    super.initState();
    _watchlistBloc = WatchlistBloc(
      symbolRepository: sl<SymbolRepository>(),
      socketService: sl<SocketService>(),
      hiveService: sl<HiveService>(),
      apiService: sl<ApiService>(),
    )..add(LoadWatchlist());

    _portfolioBloc = PortfolioBloc(
      repository: sl<PortfolioRepository>(),
      apiService: sl<ApiService>(),
      socketService: sl<SocketService>(),
    )..add(LoadPortfolio());
  }

  @override
  void dispose() {
    _watchlistBloc.close();
    _portfolioBloc.close();
    super.dispose();
  }

  void _showAddSymbolSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BlocProvider.value(
        value: _watchlistBloc,
        child: const AddSymbolSheet(),
      ),
    );
  }

  void _showAddHoldingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BlocProvider.value(
        value: _portfolioBloc,
        child: const AddHoldingSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _watchlistBloc),
        BlocProvider.value(value: _portfolioBloc),
      ],
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: _buildHeader(context),
            ),
            body: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            // Single FAB controlled by current tab
            floatingActionButton: _currentIndex == 0
                ? FloatingActionButton(
              heroTag: 'main_fab',
              onPressed: () => _showAddSymbolSheet(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
                : _currentIndex == 1
                ? FloatingActionButton(
              heroTag: 'main_fab',
              onPressed: () => _showAddHoldingSheet(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
                : null,
            bottomNavigationBar: _buildBottomNav(),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Crest',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _titles[_currentIndex],
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              BlocBuilder<WatchlistBloc, WatchlistState>(
                builder: (context, state) {
                  final isConnected =
                      state is WatchlistLoaded && state.isConnected;
                  final hasData =
                      state is WatchlistLoaded && state.ticks.isNotEmpty;
                  final showGreen = isConnected || hasData;
                  final badgeLabel = isConnected ? 'Live' : 'NSE';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: showGreen
                          ? AppColors.gainLight
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: showGreen
                            ? AppColors.gain
                            : AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: showGreen
                                ? AppColors.gain
                                : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: showGreen
                                ? AppColors.gain
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_navItems.length, (index) {
              final item = _navItems[index];
              final isActive = _currentIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isActive ? 24 : 0,
                        height: isActive ? 3 : 0,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Icon(
                        isActive ? item.activeIcon : item.icon,
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        size: isActive ? 24 : 20,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}