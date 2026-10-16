import 'dart:convert';

const marketplaceNames = <String, String>{
  'lazada': 'Lazada',
  'shopee': 'Shopee',
  'tiktok': 'TikTok',
  'tokopedia': 'Tokopedia',
  'lainnya': 'Lainnya',
};

const categoryNames = <String, String>{
  'operasional': 'Operasional',
  'iklan': 'Iklan',
  'gaji': 'Gaji pegawai',
  'thr': 'THR Lebaran',
};

var _lastGeneratedId = 0;

String makeId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  _lastGeneratedId = timestamp > _lastGeneratedId
      ? timestamp
      : _lastGeneratedId + 1;
  return '$_lastGeneratedId';
}

String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

String shiftMonth(String ym, int amount) {
  final parts = ym.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1] + amount);
  return monthKey(date);
}

String formatMoney(num value) {
  final rounded = value.round().abs().toString();
  final grouped = rounded.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
  return '${value < 0 ? '-' : ''}Rp $grouped';
}

String formatNumber(num value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final pieces = fixed.split('.');
  pieces[0] = pieces[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
  return pieces.length == 1 ? pieces[0] : '${pieces[0]},${pieces[1]}';
}

List<List<String>> parseCsvRows(String source) {
  final rows = <List<String>>[];
  final delimiters = <String, int>{',': 0, ';': 0, '\t': 0};
  var headerQuoted = false;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (char == '"') {
      if (headerQuoted &&
          index + 1 < source.length &&
          source[index + 1] == '"') {
        index++;
      } else {
        headerQuoted = !headerQuoted;
      }
    } else if (!headerQuoted && (char == '\n' || char == '\r')) {
      break;
    } else if (!headerQuoted && delimiters.containsKey(char)) {
      delimiters[char] = delimiters[char]! + 1;
    }
  }
  final separator = delimiters.entries
      .reduce((best, entry) => entry.value > best.value ? entry : best)
      .key;
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (char == '"') {
      if (quoted && index + 1 < source.length && source[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && char == separator) {
      row.add(field.toString().trim());
      field.clear();
    } else if (!quoted && (char == '\n' || char == '\r')) {
      if (char == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString().trim());
      field.clear();
      if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
      row = [];
    } else {
      field.write(char);
    }
  }
  if (quoted) throw const FormatException('Tanda kutip CSV tidak berpasangan.');
  row.add(field.toString().trim());
  if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
  return rows;
}

String monthLabel(String ym) {
  const names = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final parts = ym.split('-');
  return '${names[int.parse(parts[1]) - 1]} ${parts[0]}';
}

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

enum MaterialCategory { bahanBaku, ongkosJahit }

class MaterialCost {
  MaterialCost({
    String? id,
    required this.name,
    this.qty = 1,
    this.unit = '',
    this.price = 0,
    this.ref,
    MaterialCategory? category,
  }) : id = id ?? makeId(),
       _category = category ?? MaterialCategory.bahanBaku;

  String id;
  String name;
  double qty;
  String unit;
  double price;
  String? ref;
  MaterialCategory? _category;

  MaterialCategory get category => _category ?? MaterialCategory.bahanBaku;

  set category(MaterialCategory value) => _category = value;

  double get subtotal => qty * price;

  factory MaterialCost.fromJson(Map<String, dynamic> json) => MaterialCost(
    id: json['id']?.toString(),
    name: '${json['name'] ?? ''}',
    qty: _number(json['qty']),
    unit: '${json['unit'] ?? ''}',
    price: _number(json['price']),
    ref: json['ref']?.toString(),
    category: json['category'] == MaterialCategory.ongkosJahit.name
        ? MaterialCategory.ongkosJahit
        : MaterialCategory.bahanBaku,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'qty': qty,
    'unit': unit,
    'price': price,
    'category': category.name,
    if (ref != null) 'ref': ref,
  };
}

class Product {
  Product({
    String? id,
    required this.name,
    List<MaterialCost>? materials,
    List<String>? colors,
    List<String>? sizes,
    List<String>? variants,
    this.img = '',
    this.stock,
  }) : id = id ?? makeId(),
       materials = materials ?? [],
       colors = colors ?? [],
       sizes = sizes ?? [],
       variants = variants ?? [];

  String id;
  String name;
  List<MaterialCost> materials;
  List<String> colors;
  List<String> sizes;
  List<String> variants;
  String img;
  StockData? stock;

  double get hpp => materials
      .fold<double>(0, (total, material) => total + material.subtotal)
      .roundToDouble();

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id']?.toString(),
    name: '${json['name'] ?? ''}',
    materials: (json['materials'] as List? ?? [])
        .whereType<Map>()
        .map((item) => MaterialCost.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    colors: (json['colors'] as List? ?? []).map((value) => '$value').toList(),
    sizes: (json['sizes'] as List? ?? []).map((value) => '$value').toList(),
    variants: (json['variants'] as List? ?? [])
        .map((value) => '$value')
        .toList(),
    img: '${json['img'] ?? ''}',
    stock: json['stock'] is Map
        ? StockData.fromJson(Map<String, dynamic>.from(json['stock'] as Map))
        : null,
  );

  Map<String, dynamic> toJson({bool includeImage = true}) => {
    'id': id,
    'name': name,
    'materials': materials.map((item) => item.toJson()).toList(),
    if (colors.isNotEmpty) 'colors': colors,
    if (sizes.isNotEmpty) 'sizes': sizes,
    if (variants.isNotEmpty) 'variants': variants,
    if (includeImage && img.isNotEmpty) 'img': img,
    if (stock != null) 'stock': stock!.toJson(),
  };
}

class StockEntry {
  StockEntry({
    String? id,
    required this.date,
    required this.qty,
    this.note = '',
    this.color = '',
  }) : id = id ?? makeId();

  String id;
  String date;
  double qty;
  String note;
  String color;

  factory StockEntry.fromJson(Map<String, dynamic> json) => StockEntry(
    id: json['id']?.toString(),
    date: '${json['date'] ?? ''}',
    qty: _number(json['qty']),
    note: '${json['note'] ?? ''}',
    color: '${json['color'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'qty': qty,
    'note': note,
    if (color.isNotEmpty) 'color': color,
  };
}

class StockData {
  StockData({List<StockEntry>? log}) : log = log ?? [];

  List<StockEntry> log;

  factory StockData.fromJson(Map<String, dynamic> json) => StockData(
    log: (json['log'] as List? ?? [])
        .whereType<Map>()
        .map((entry) => StockEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'log': log.map((entry) => entry.toJson()).toList(),
  };
}

class Sale {
  Sale({
    String? id,
    required this.date,
    required this.platform,
    required this.productId,
    required this.productName,
    this.qty = 1,
    this.orderNo = '',
    this.received = 0,
    this.hpp = 0,
    this.color = '',
    this.size = '',
    this.other = '',
  }) : id = id ?? makeId();

  String id;
  String date;
  String platform;
  String productId;
  String productName;
  double qty;
  String orderNo;
  double received;
  double hpp;
  String color;
  String size;
  String other;

  String get variant =>
      [color, size, other].where((part) => part.isNotEmpty).join(' / ');

  factory Sale.fromJson(Map<String, dynamic> json) {
    final variant = '${json['variant'] ?? ''}';
    return Sale(
      id: json['id']?.toString(),
      date: '${json['date'] ?? ''}',
      platform: '${json['platform'] ?? 'shopee'}',
      productId: '${json['productId'] ?? ''}',
      productName: '${json['productName'] ?? ''}',
      qty: _number(json['qty']),
      orderNo: '${json['orderNo'] ?? ''}',
      received: _number(json['received']),
      hpp: _number(json['hpp']),
      color:
          '${json['color'] ?? (variant.contains(' / ') ? variant.split(' / ').first : '')}',
      size: '${json['size'] ?? ''}',
      other: '${json['other'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'platform': platform,
    'productId': productId,
    'productName': productName,
    'qty': qty,
    'orderNo': orderNo,
    'received': received,
    'hpp': hpp,
    'color': color,
    'size': size,
    'other': other,
    'variant': variant,
  };
}

String _normalizeProductName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

Map<String, (String, double, double, double)> aggregateProductSales(
  Iterable<Sale> sales, {
  double Function(Sale sale)? hppForSale,
}) {
  final namesByProductId = <String, Set<String>>{};
  for (final sale in sales) {
    final productId = sale.productId.trim();
    final name = _normalizeProductName(sale.productName);
    if (productId.isNotEmpty && name.isNotEmpty) {
      namesByProductId.putIfAbsent(productId, () => {}).add(name);
    }
  }

  final totals = <String, (String, double, double, double)>{};
  for (final sale in sales) {
    final productId = sale.productId.trim();
    final name = sale.productName.trim();
    final normalized = _normalizeProductName(name);
    final productNames = namesByProductId[productId];
    final key = productId.isEmpty
        ? normalized.isEmpty
              ? 'sale:${sale.id}'
              : 'name:$normalized'
        : productNames != null &&
              productNames.length > 1 &&
              normalized.isNotEmpty
        ? 'id:$productId|name:$normalized'
        : 'id:$productId';
    final current = totals[key] ?? (name, 0, 0, 0);
    totals[key] = (
      current.$1.isEmpty ? name : current.$1,
      current.$2 + sale.qty,
      current.$3 + sale.received,
      current.$4 + sale.qty * (hppForSale?.call(sale) ?? sale.hpp),
    );
  }
  return totals;
}

class Expense {
  Expense({
    String? id,
    required this.month,
    required this.category,
    required this.name,
    this.date = '',
    this.amount = 0,
    this.note = '',
    this.platform = 'shopee',
    this.productId = '',
    this.productName = '',
    this.ppn = false,
  }) : id = id ?? makeId();

  String id;
  String month;
  String category;
  String name;
  String date;
  double amount;
  String note;
  String platform;
  String productId;
  String productName;
  bool ppn;

  factory Expense.fromJson(Map<String, dynamic> json) {
    final month = '${json['month'] ?? ''}';
    final category = '${json['cat'] ?? json['category'] ?? 'operasional'}';
    return Expense(
      id: json['id']?.toString(),
      month: month,
      category: category,
      name: '${json['name'] ?? ''}',
      date:
          '${json['date'] ?? (category == 'thr' && month.length == 7 ? '$month-01' : '')}',
      amount: _number(json['amount']),
      note: '${json['note'] ?? ''}',
      platform: '${json['platform'] ?? 'shopee'}',
      productId: '${json['productId'] ?? ''}',
      productName: '${json['productName'] ?? ''}',
      ppn: json['ppn'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'month': month,
    'cat': category,
    'name': name,
    if (date.isNotEmpty) 'date': date,
    'amount': amount,
    'note': note,
    if (category == 'iklan') ...{
      'platform': platform,
      'productId': productId,
      'productName': productName,
      'ppn': ppn,
    },
  };
}

class Owner {
  Owner({required this.id, required this.name, required this.pct});

  String id;
  String name;
  double pct;

  factory Owner.fromJson(Map<String, dynamic> json) {
    final rawName = '${json['name'] ?? 'Pemilik'}';
    final defaultName = RegExp(
      r'^Owner(?:\s+(\d+))?$',
      caseSensitive: false,
    ).firstMatch(rawName.trim());
    final name = defaultName == null
        ? rawName
        : 'Pemilik${defaultName.group(1) == null ? '' : ' ${defaultName.group(1)}'}';
    return Owner(
      id: '${json['id'] ?? makeId()}',
      name: name,
      pct: _number(json['pct']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pct': pct};
}

class FinanceData {
  FinanceData({
    this.businessName = 'PocketR',
    this.tagline = '',
    this.logo = '',
    this.zakatPct = 2.5,
    this.ppnPct = 11,
    this.targetRevenue = 0,
    this.stockWarningThreshold = 5,
    List<Product>? products,
    List<MaterialCost>? materials,
    List<Sale>? sales,
    List<Expense>? expenses,
    List<Owner>? owners,
    Map<String, bool>? paid,
    Map<String, String>? shopeeProductMappings,
  }) : products = products ?? [],
       materials = materials ?? [],
       sales = sales ?? [],
       expenses = expenses ?? [],
       owners =
           owners ??
           List.generate(
             4,
             (index) => Owner(
               id: 'o${index + 1}',
               name: 'Pemilik ${index + 1}',
               pct: 25,
             ),
           ),
       paid = paid ?? {},
       shopeeProductMappings = shopeeProductMappings ?? {};

  String businessName;
  String tagline;
  String logo;
  double zakatPct;
  double ppnPct;
  double targetRevenue;
  int stockWarningThreshold;
  List<Product> products;
  List<MaterialCost> materials;
  List<Sale> sales;
  List<Expense> expenses;
  List<Owner> owners;
  Map<String, bool> paid;
  Map<String, String> shopeeProductMappings;

  factory FinanceData.fromJson(Map<String, dynamic> json) {
    final settings = Map<String, dynamic>.from(json['settings'] as Map? ?? {});
    final profile = Map<String, dynamic>.from(json['profile'] as Map? ?? {});
    final profileName = '${profile['name'] ?? ''}'.trim();
    final businessName =
        profileName.isEmpty || profileName.toLowerCase() == 'rochinku'
        ? 'PocketR'
        : profileName;
    final ownerJson = settings['owners'] as List?;
    final products = (json['products'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final sales = (json['sales'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Sale.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final productCountsByIdAndName = <String, int>{};
    for (final product in products) {
      final key =
          '${product.id.trim()}\u0000${_normalizeProductName(product.name)}';
      productCountsByIdAndName.update(
        key,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final usedProductIds = <String>{};
    final repairedProducts = <(String, String, String)>[];
    for (final product in products) {
      final originalId = product.id;
      final normalizedId = originalId.trim();
      if (normalizedId.isNotEmpty &&
          normalizedId == originalId &&
          usedProductIds.add(normalizedId)) {
        continue;
      }
      var newId = makeId();
      while (!usedProductIds.add(newId)) {
        newId = makeId();
      }
      repairedProducts.add((
        normalizedId,
        _normalizeProductName(product.name),
        newId,
      ));
      product.id = newId;
    }
    for (final repair in repairedProducts) {
      final key = '${repair.$1}\u0000${repair.$2}';
      if (productCountsByIdAndName[key] != 1) continue;
      for (final sale in sales) {
        if (sale.productId.trim() == repair.$1 &&
            _normalizeProductName(sale.productName) == repair.$2) {
          sale.productId = repair.$3;
        }
      }
    }
    return FinanceData(
      businessName: businessName,
      tagline: '${profile['tagline'] ?? ''}',
      logo: '${profile['logo'] ?? ''}',
      zakatPct: _number(settings['zakatPct'] ?? 2.5),
      ppnPct: _number(settings['ppnPct'] ?? 11),
      targetRevenue: _number(settings['targetRev']),
      stockWarningThreshold: _number(settings['stockWarningThreshold'] ?? 5)
          .round()
          .clamp(0, 999999)
          .toInt(),
      products: products,
      materials: (json['materials'] as List? ?? [])
          .whereType<Map>()
          .map((item) => MaterialCost.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      sales: sales,
      expenses: (json['expenses'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Expense.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      owners: ownerJson
          ?.whereType<Map>()
          .map((item) => Owner.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      paid: Map<String, bool>.from(
        (json['paid'] as Map? ?? {}).map(
          (key, value) => MapEntry('$key', value == true),
        ),
      ),
      shopeeProductMappings: Map<String, String>.from(
        (settings['shopeeProductMappings'] as Map? ?? {}).map(
          (key, value) => MapEntry('$key', '$value'),
        ),
      ),
    );
  }

  factory FinanceData.fromBackup(String source) {
    final decoded = jsonDecode(source);
    final backupData =
        decoded is Map<String, dynamic> &&
            (decoded['format'] == 'pocketr-backup' ||
                decoded['format'] == 'rochinku-backup') &&
            decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : decoded;
    if (backupData is! Map<String, dynamic> ||
        backupData['products'] is! List ||
        backupData['sales'] is! List ||
        backupData['expenses'] is! List) {
      throw const FormatException('Format cadangan PocketR tidak valid.');
    }
    return FinanceData.fromJson(backupData);
  }

  Map<String, dynamic> toJson({bool includeImages = true}) => {
    'linkedMat': true,
    'profile': {
      'name': businessName,
      'tagline': tagline,
      if (includeImages && logo.isNotEmpty) 'logo': logo,
    },
    'products': products
        .map((item) => item.toJson(includeImage: includeImages))
        .toList(),
    'materials': materials.map((item) => item.toJson()).toList(),
    'sales': sales.map((item) => item.toJson()).toList(),
    'expenses': expenses.map((item) => item.toJson()).toList(),
    'paid': paid,
    'settings': {
      'zakatPct': zakatPct,
      'ppnPct': ppnPct,
      'targetRev': targetRevenue,
      'stockWarningThreshold': stockWarningThreshold,
      'owners': owners.map((item) => item.toJson()).toList(),
      'shopeeProductMappings': shopeeProductMappings,
    },
  };

  String toBackup({bool includeImages = true}) =>
      const JsonEncoder.withIndent('  ')
          .convert(toJson(includeImages: includeImages));

  Product? productById(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  MaterialCost effectiveMaterial(MaterialCost material) {
    for (final catalogItem in materials) {
      if (material.ref == catalogItem.id) {
        return MaterialCost(
          id: material.id,
          name: catalogItem.name,
          qty: material.qty,
          unit: catalogItem.unit,
          price: catalogItem.price,
          ref: material.ref,
          category: catalogItem.category,
        );
      }
    }
    return material;
  }

  double productHpp(Product product) => product.materials
      .fold<double>(
        0,
        (sum, material) => sum + effectiveMaterial(material).subtotal,
      )
      .roundToDouble();

  double? stockOf(Product product) {
    if (product.stock == null) return null;
    return stockByColor(product).values
        .fold<double>(0, (sum, value) => sum + value);
  }

  Map<String, double> stockByColor(Product product) {
    final stock = product.stock;
    if (stock == null) return {};
    final overallStart = stock.log.isEmpty
        ? '9999-99-99'
        : stock.log
              .map((entry) => entry.date)
              .reduce(
                (first, next) => first.compareTo(next) < 0 ? first : next,
              );
    final coloredEntries = stock.log
        .where((entry) => entry.color.isNotEmpty)
        .toList();
    final colorTrackingStart = coloredEntries.isEmpty
        ? null
        : coloredEntries
              .map((entry) => entry.date)
              .reduce(
                (first, next) => first.compareTo(next) < 0 ? first : next,
              );
    final colors = <String>{
      ...product.colors,
      ...stock.log.map((entry) => entry.color),
      ...sales
          .where((sale) => sale.productId == product.id)
          .map((sale) => sale.color),
    };
    return {
      for (final color in colors)
        color: _stockBalanceForColor(
          product,
          stock,
          color,
          overallStart,
          colorTrackingStart,
        ),
    };
  }

  double _stockBalanceForColor(
    Product product,
    StockData stock,
    String color,
    String overallStart,
    String? colorTrackingStart,
  ) {
    final entries = stock.log.where((entry) => entry.color == color);
    final added = entries.fold<double>(0, (sum, entry) => sum + entry.qty);
    final start = color.isEmpty
        ? overallStart
        : entries.isEmpty
        ? colorTrackingStart
        : entries
              .map((entry) => entry.date)
              .reduce(
                (first, next) => first.compareTo(next) < 0 ? first : next,
              );
    final sold = sales
        .where(
          (sale) =>
              sale.productId == product.id &&
              sale.date.compareTo(start ?? '9999-99-99') >= 0 &&
              (color.isEmpty
                  ? colorTrackingStart == null ||
                        sale.date.compareTo(colorTrackingStart) < 0 ||
                        sale.color.isEmpty
                  : sale.color == color),
        )
        .fold<double>(0, (sum, sale) => sum + sale.qty);
    return added - sold;
  }

  double expenseTotal(Expense expense) =>
      expense.category == 'iklan' && expense.ppn
      ? (expense.amount * (1 + ppnPct / 100)).roundToDouble()
      : expense.amount;

  MonthSummary summary(String ym) {
    final monthSales = sales.where((sale) => sale.date.startsWith(ym)).toList();
    final monthExpenses = expenses.where((expense) => expense.month == ym);
    final revenue = monthSales.fold<double>(
      0,
      (sum, sale) => sum + sale.received,
    );
    final hpp = monthSales.fold<double>(
      0,
      (sum, sale) => sum + sale.qty * sale.hpp,
    );
    final pcs = monthSales.fold<double>(0, (sum, sale) => sum + sale.qty);
    final orders = monthSales
        .map((sale) => sale.orderNo.isEmpty ? sale.id : sale.orderNo)
        .toSet()
        .length;
    double categoryTotal(String category) => monthExpenses
        .where((expense) => expense.category == category)
        .fold<double>(0, (sum, expense) => sum + expenseTotal(expense));
    final operations = categoryTotal('operasional');
    final ads = monthExpenses
        .where((expense) => expense.category == 'iklan')
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    final tax = monthExpenses
        .where((expense) => expense.category == 'iklan')
        .fold<double>(
          0,
          (sum, expense) => sum + expenseTotal(expense) - expense.amount,
        );
    final salary = categoryTotal('gaji');
    final thr = categoryTotal('thr');
    final preTax = revenue - hpp - operations - ads - salary - thr - tax;
    final zakat = (preTax > 0 ? preTax * zakatPct / 100 : 0).roundToDouble();
    return MonthSummary(
      revenue: revenue,
      hpp: hpp,
      pcs: pcs,
      orders: orders,
      operations: operations,
      ads: ads,
      ppn: tax,
      salary: salary,
      thr: thr,
      preTax: preTax,
      zakat: zakat,
      net: preTax - zakat,
    );
  }
}

class MonthSummary {
  const MonthSummary({
    required this.revenue,
    required this.hpp,
    required this.pcs,
    required this.orders,
    required this.operations,
    required this.ads,
    required this.ppn,
    required this.salary,
    required this.thr,
    required this.preTax,
    required this.zakat,
    required this.net,
  });

  final double revenue;
  final double hpp;
  final double pcs;
  final int orders;
  final double operations;
  final double ads;
  final double ppn;
  final double salary;
  final double thr;
  final double preTax;
  final double zakat;
  final double net;

  double get costs => operations + ads + ppn + salary + thr + zakat;
}
