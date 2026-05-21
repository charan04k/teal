import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../constants/app_constants.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/remote/socket_service.dart';
import '../../data/datasources/local/hive_service.dart';
import '../../data/repositories/symbol_repository_impl.dart';
import '../../data/repositories/market_repository_impl.dart';
import '../../data/repositories/portfolio_repository_impl.dart';
import '../../domain/repositories/symbol_repository.dart';
import '../../domain/repositories/market_repository.dart';
import '../../domain/repositories/portfolio_repository.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {

  sl.registerLazySingleton<Dio>(() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    if (!kIsWeb && dio.httpClientAdapter is IOHttpClientAdapter) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    return dio;
  });

  // Services
  sl.registerLazySingleton<ApiService>(() => ApiService(sl()));
  sl.registerLazySingleton<SocketService>(() => SocketService());
  sl.registerLazySingleton<HiveService>(() => HiveService());

  // Init Hive
  await sl<HiveService>().init();

  // Repositories
  sl.registerLazySingleton<SymbolRepository>(
        () => SymbolRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<MarketRepository>(
        () => MarketRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<PortfolioRepository>(
        () => PortfolioRepositoryImpl(sl()),
  );
}