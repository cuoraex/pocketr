import 'dart:math' as math;

double evaluateExcelFormula(
  String formula,
  double Function(int columnIndex, int rowIndex) resolveCell,
) => _ExcelFormulaParser(formula, resolveCell).evaluate();

class _ExcelFormulaParser {
  _ExcelFormulaParser(this.formula, this.resolveCell) {
    _tokenize();
  }

  final String formula;
  final double Function(int columnIndex, int rowIndex) resolveCell;
  final List<String> _tokens = [];
  var _position = 0;

  void _tokenize() {
    var offset = formula.startsWith('=') ? 1 : 0;
    while (offset < formula.length) {
      final remaining = formula.substring(offset);
      final whitespace = RegExp(r'^\s+').firstMatch(remaining);
      if (whitespace != null) {
        offset += whitespace.end;
        if (offset >= formula.length) break;
      }
      final token = RegExp(
        r'^(?:\$?[A-Za-z]{1,3}\$?\d+|\d+(?:\.\d*)?|\.\d+|[()+\-*/^%])',
      ).firstMatch(formula.substring(offset));
      if (token == null) {
        throw FormatException(
          'Rumus "$formula" tidak didukung. Gunakan angka, referensi sel, dan operasi +, -, *, /, ^, atau %.',
        );
      }
      _tokens.add(token.group(0)!);
      offset += token.end;
    }
    if (_tokens.isEmpty) {
      throw const FormatException('Rumus Excel kosong.');
    }
  }

  double evaluate() {
    final result = _sum();
    if (_position != _tokens.length) {
      throw FormatException('Rumus Excel "$formula" tidak valid.');
    }
    if (!result.isFinite) {
      throw FormatException('Hasil rumus Excel "$formula" tidak valid.');
    }
    return result;
  }

  double _sum() {
    var value = _product();
    while (_match('+') || _match('-')) {
      final operator = _previous;
      final right = _product();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  double _product() {
    var value = _unary();
    while (_match('*') || _match('/')) {
      final operator = _previous;
      final right = _unary();
      if (operator == '/' && right == 0) {
        throw const FormatException('Rumus Excel membagi dengan nol.');
      }
      value = operator == '*' ? value * right : value / right;
    }
    return value;
  }

  double _unary() {
    if (_match('+')) return _unary();
    if (_match('-')) return -_unary();
    return _power();
  }

  double _power() {
    final value = _percentage();
    if (_match('^')) {
      return math.pow(value, _unary()).toDouble();
    }
    return value;
  }

  double _percentage() {
    var value = _primary();
    while (_match('%')) {
      value /= 100;
    }
    return value;
  }

  double _primary() {
    if (_match('(')) {
      final value = _sum();
      if (!_match(')')) {
        throw FormatException('Kurung rumus Excel "$formula" tidak berpasangan.');
      }
      return value;
    }
    if (_position >= _tokens.length) {
      throw FormatException('Rumus Excel "$formula" tidak lengkap.');
    }
    final token = _tokens[_position++];
    final reference = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$')
        .firstMatch(token);
    if (reference != null) {
      var columnIndex = 0;
      for (final code in reference[1]!.toUpperCase().codeUnits) {
        columnIndex = columnIndex * 26 + code - 64;
      }
      final rowIndex = int.parse(reference[2]!) - 1;
      if (rowIndex < 0) {
        throw FormatException('Referensi sel "$token" tidak valid.');
      }
      return resolveCell(columnIndex - 1, rowIndex);
    }
    final number = double.tryParse(token);
    if (number == null) {
      throw FormatException('Nilai "$token" pada rumus tidak valid.');
    }
    return number;
  }

  bool _match(String token) {
    if (_position >= _tokens.length || _tokens[_position] != token) {
      return false;
    }
    _position++;
    return true;
  }

  String get _previous => _tokens[_position - 1];
}
