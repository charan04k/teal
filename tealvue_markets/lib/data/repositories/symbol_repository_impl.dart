import '../../data/datasources/remote/api_service.dart';
import '../../data/models/symbol_model.dart';
import '../../domain/repositories/symbol_repository.dart';

class SymbolRepositoryImpl implements SymbolRepository {
  final ApiService _apiService;

  SymbolRepositoryImpl(this._apiService);

  @override
  Future<List<SymbolModel>> getSymbols() async {
    final data = await _apiService.getSymbols();
    return data.map((e) => SymbolModel.fromJson(e)).toList();
  }
}