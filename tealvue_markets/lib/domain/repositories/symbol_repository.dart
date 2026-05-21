// symbol_repository.dart
import '../../data/models/symbol_model.dart';

abstract class SymbolRepository {
  Future<List<SymbolModel>> getSymbols();
}