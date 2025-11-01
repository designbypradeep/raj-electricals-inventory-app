// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProductsTable extends Products
    with drift.TableInfo<$ProductsTable, Product> {
  @override
  final drift.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const drift.VerificationMeta _idMeta = const drift.VerificationMeta(
    'id',
  );
  @override
  late final drift.GeneratedColumn<int> id = drift.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const drift.VerificationMeta _nameMeta = const drift.VerificationMeta(
    'name',
  );
  @override
  late final drift.GeneratedColumn<String> name = drift.GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _brandMeta = const drift.VerificationMeta(
    'brand',
  );
  @override
  late final drift.GeneratedColumn<String> brand =
      drift.GeneratedColumn<String>(
        'brand',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _modelMeta = const drift.VerificationMeta(
    'model',
  );
  @override
  late final drift.GeneratedColumn<String> model =
      drift.GeneratedColumn<String>(
        'model',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _sizeOrTypeMeta =
      const drift.VerificationMeta('sizeOrType');
  @override
  late final drift.GeneratedColumn<String> sizeOrType =
      drift.GeneratedColumn<String>(
        'size_or_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _categoryMeta =
      const drift.VerificationMeta('category');
  @override
  late final drift.GeneratedColumn<String> category =
      drift.GeneratedColumn<String>(
        'category',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _quantityMeta =
      const drift.VerificationMeta('quantity');
  @override
  late final drift.GeneratedColumn<int> quantity = drift.GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _priceMeta = const drift.VerificationMeta(
    'price',
  );
  @override
  late final drift.GeneratedColumn<int> price = drift.GeneratedColumn<int>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _imagePathsMeta =
      const drift.VerificationMeta('imagePaths');
  @override
  late final drift.GeneratedColumn<String> imagePaths =
      drift.GeneratedColumn<String>(
        'image_paths',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _isDeletedMeta =
      const drift.VerificationMeta('isDeleted');
  @override
  late final drift.GeneratedColumn<bool> isDeleted =
      drift.GeneratedColumn<bool>(
        'is_deleted',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_deleted" IN (0, 1))',
        ),
        defaultValue: const drift.Constant(false),
      );
  @override
  List<drift.GeneratedColumn> get $columns => [
    id,
    name,
    brand,
    model,
    sizeOrType,
    category,
    quantity,
    price,
    imagePaths,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  drift.VerificationContext validateIntegrity(
    drift.Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = drift.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    } else if (isInserting) {
      context.missing(_brandMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('size_or_type')) {
      context.handle(
        _sizeOrTypeMeta,
        sizeOrType.isAcceptableOrUnknown(
          data['size_or_type']!,
          _sizeOrTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sizeOrTypeMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('image_paths')) {
      context.handle(
        _imagePathsMeta,
        imagePaths.isAcceptableOrUnknown(data['image_paths']!, _imagePathsMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<drift.GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      sizeOrType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}size_or_type'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price'],
      )!,
      imagePaths: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_paths'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends drift.DataClass implements drift.Insertable<Product> {
  final int id;
  final String name;
  final String brand;
  final String? model;
  final String sizeOrType;
  final String category;
  final int quantity;
  final int price;
  final String? imagePaths;
  final bool isDeleted;
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    this.model,
    required this.sizeOrType,
    required this.category,
    required this.quantity,
    required this.price,
    this.imagePaths,
    required this.isDeleted,
  });
  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    map['id'] = drift.Variable<int>(id);
    map['name'] = drift.Variable<String>(name);
    map['brand'] = drift.Variable<String>(brand);
    if (!nullToAbsent || model != null) {
      map['model'] = drift.Variable<String>(model);
    }
    map['size_or_type'] = drift.Variable<String>(sizeOrType);
    map['category'] = drift.Variable<String>(category);
    map['quantity'] = drift.Variable<int>(quantity);
    map['price'] = drift.Variable<int>(price);
    if (!nullToAbsent || imagePaths != null) {
      map['image_paths'] = drift.Variable<String>(imagePaths);
    }
    map['is_deleted'] = drift.Variable<bool>(isDeleted);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: drift.Value(id),
      name: drift.Value(name),
      brand: drift.Value(brand),
      model: model == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(model),
      sizeOrType: drift.Value(sizeOrType),
      category: drift.Value(category),
      quantity: drift.Value(quantity),
      price: drift.Value(price),
      imagePaths: imagePaths == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(imagePaths),
      isDeleted: drift.Value(isDeleted),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String>(json['brand']),
      model: serializer.fromJson<String?>(json['model']),
      sizeOrType: serializer.fromJson<String>(json['sizeOrType']),
      category: serializer.fromJson<String>(json['category']),
      quantity: serializer.fromJson<int>(json['quantity']),
      price: serializer.fromJson<int>(json['price']),
      imagePaths: serializer.fromJson<String?>(json['imagePaths']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String>(brand),
      'model': serializer.toJson<String?>(model),
      'sizeOrType': serializer.toJson<String>(sizeOrType),
      'category': serializer.toJson<String>(category),
      'quantity': serializer.toJson<int>(quantity),
      'price': serializer.toJson<int>(price),
      'imagePaths': serializer.toJson<String?>(imagePaths),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Product copyWith({
    int? id,
    String? name,
    String? brand,
    drift.Value<String?> model = const drift.Value.absent(),
    String? sizeOrType,
    String? category,
    int? quantity,
    int? price,
    drift.Value<String?> imagePaths = const drift.Value.absent(),
    bool? isDeleted,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    model: model.present ? model.value : this.model,
    sizeOrType: sizeOrType ?? this.sizeOrType,
    category: category ?? this.category,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    imagePaths: imagePaths.present ? imagePaths.value : this.imagePaths,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      sizeOrType: data.sizeOrType.present
          ? data.sizeOrType.value
          : this.sizeOrType,
      category: data.category.present ? data.category.value : this.category,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      price: data.price.present ? data.price.value : this.price,
      imagePaths: data.imagePaths.present
          ? data.imagePaths.value
          : this.imagePaths,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('sizeOrType: $sizeOrType, ')
          ..write('category: $category, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('imagePaths: $imagePaths, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    brand,
    model,
    sizeOrType,
    category,
    quantity,
    price,
    imagePaths,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.sizeOrType == this.sizeOrType &&
          other.category == this.category &&
          other.quantity == this.quantity &&
          other.price == this.price &&
          other.imagePaths == this.imagePaths &&
          other.isDeleted == this.isDeleted);
}

class ProductsCompanion extends drift.UpdateCompanion<Product> {
  final drift.Value<int> id;
  final drift.Value<String> name;
  final drift.Value<String> brand;
  final drift.Value<String?> model;
  final drift.Value<String> sizeOrType;
  final drift.Value<String> category;
  final drift.Value<int> quantity;
  final drift.Value<int> price;
  final drift.Value<String?> imagePaths;
  final drift.Value<bool> isDeleted;
  const ProductsCompanion({
    this.id = const drift.Value.absent(),
    this.name = const drift.Value.absent(),
    this.brand = const drift.Value.absent(),
    this.model = const drift.Value.absent(),
    this.sizeOrType = const drift.Value.absent(),
    this.category = const drift.Value.absent(),
    this.quantity = const drift.Value.absent(),
    this.price = const drift.Value.absent(),
    this.imagePaths = const drift.Value.absent(),
    this.isDeleted = const drift.Value.absent(),
  });
  ProductsCompanion.insert({
    this.id = const drift.Value.absent(),
    required String name,
    required String brand,
    this.model = const drift.Value.absent(),
    required String sizeOrType,
    required String category,
    required int quantity,
    required int price,
    this.imagePaths = const drift.Value.absent(),
    this.isDeleted = const drift.Value.absent(),
  }) : name = drift.Value(name),
       brand = drift.Value(brand),
       sizeOrType = drift.Value(sizeOrType),
       category = drift.Value(category),
       quantity = drift.Value(quantity),
       price = drift.Value(price);
  static drift.Insertable<Product> custom({
    drift.Expression<int>? id,
    drift.Expression<String>? name,
    drift.Expression<String>? brand,
    drift.Expression<String>? model,
    drift.Expression<String>? sizeOrType,
    drift.Expression<String>? category,
    drift.Expression<int>? quantity,
    drift.Expression<int>? price,
    drift.Expression<String>? imagePaths,
    drift.Expression<bool>? isDeleted,
  }) {
    return drift.RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (sizeOrType != null) 'size_or_type': sizeOrType,
      if (category != null) 'category': category,
      if (quantity != null) 'quantity': quantity,
      if (price != null) 'price': price,
      if (imagePaths != null) 'image_paths': imagePaths,
      if (isDeleted != null) 'is_deleted': isDeleted,
    });
  }

  ProductsCompanion copyWith({
    drift.Value<int>? id,
    drift.Value<String>? name,
    drift.Value<String>? brand,
    drift.Value<String?>? model,
    drift.Value<String>? sizeOrType,
    drift.Value<String>? category,
    drift.Value<int>? quantity,
    drift.Value<int>? price,
    drift.Value<String?>? imagePaths,
    drift.Value<bool>? isDeleted,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      sizeOrType: sizeOrType ?? this.sizeOrType,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      imagePaths: imagePaths ?? this.imagePaths,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    if (id.present) {
      map['id'] = drift.Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = drift.Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = drift.Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = drift.Variable<String>(model.value);
    }
    if (sizeOrType.present) {
      map['size_or_type'] = drift.Variable<String>(sizeOrType.value);
    }
    if (category.present) {
      map['category'] = drift.Variable<String>(category.value);
    }
    if (quantity.present) {
      map['quantity'] = drift.Variable<int>(quantity.value);
    }
    if (price.present) {
      map['price'] = drift.Variable<int>(price.value);
    }
    if (imagePaths.present) {
      map['image_paths'] = drift.Variable<String>(imagePaths.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = drift.Variable<bool>(isDeleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('sizeOrType: $sizeOrType, ')
          ..write('category: $category, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('imagePaths: $imagePaths, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }
}

class $PurchasesTable extends Purchases
    with drift.TableInfo<$PurchasesTable, Purchase> {
  @override
  final drift.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchasesTable(this.attachedDatabase, [this._alias]);
  static const drift.VerificationMeta _idMeta = const drift.VerificationMeta(
    'id',
  );
  @override
  late final drift.GeneratedColumn<int> id = drift.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const drift.VerificationMeta _productIdMeta =
      const drift.VerificationMeta('productId');
  @override
  late final drift.GeneratedColumn<int> productId = drift.GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE',
  );
  static const drift.VerificationMeta _quantityMeta =
      const drift.VerificationMeta('quantity');
  @override
  late final drift.GeneratedColumn<int> quantity = drift.GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _unitPriceMeta =
      const drift.VerificationMeta('unitPrice');
  @override
  late final drift.GeneratedColumn<int> unitPrice = drift.GeneratedColumn<int>(
    'unit_price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _unitTypeMeta =
      const drift.VerificationMeta('unitType');
  @override
  late final drift.GeneratedColumn<String> unitType =
      drift.GeneratedColumn<String>(
        'unit_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _qtyPerUnitMeta =
      const drift.VerificationMeta('qtyPerUnit');
  @override
  late final drift.GeneratedColumn<int> qtyPerUnit = drift.GeneratedColumn<int>(
    'qty_per_unit',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const drift.VerificationMeta _sellerNameMeta =
      const drift.VerificationMeta('sellerName');
  @override
  late final drift.GeneratedColumn<String> sellerName =
      drift.GeneratedColumn<String>(
        'seller_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _purchaseDateMeta =
      const drift.VerificationMeta('purchaseDate');
  @override
  late final drift.GeneratedColumn<DateTime> purchaseDate =
      drift.GeneratedColumn<DateTime>(
        'purchase_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _conditionMeta =
      const drift.VerificationMeta('condition');
  @override
  late final drift.GeneratedColumn<String> condition =
      drift.GeneratedColumn<String>(
        'condition',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const drift.Constant('New'),
      );
  static const drift.VerificationMeta _warrantyMonthsMeta =
      const drift.VerificationMeta('warrantyMonths');
  @override
  late final drift.GeneratedColumn<int> warrantyMonths =
      drift.GeneratedColumn<int>(
        'warranty_months',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _productImagePathMeta =
      const drift.VerificationMeta('productImagePath');
  @override
  late final drift.GeneratedColumn<String> productImagePath =
      drift.GeneratedColumn<String>(
        'product_image_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _billReferencePathMeta =
      const drift.VerificationMeta('billReferencePath');
  @override
  late final drift.GeneratedColumn<String> billReferencePath =
      drift.GeneratedColumn<String>(
        'bill_reference_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<drift.GeneratedColumn> get $columns => [
    id,
    productId,
    quantity,
    unitPrice,
    unitType,
    qtyPerUnit,
    sellerName,
    purchaseDate,
    condition,
    warrantyMonths,
    productImagePath,
    billReferencePath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchases';
  @override
  drift.VerificationContext validateIntegrity(
    drift.Insertable<Purchase> instance, {
    bool isInserting = false,
  }) {
    final context = drift.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price')) {
      context.handle(
        _unitPriceMeta,
        unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta),
      );
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('unit_type')) {
      context.handle(
        _unitTypeMeta,
        unitType.isAcceptableOrUnknown(data['unit_type']!, _unitTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_unitTypeMeta);
    }
    if (data.containsKey('qty_per_unit')) {
      context.handle(
        _qtyPerUnitMeta,
        qtyPerUnit.isAcceptableOrUnknown(
          data['qty_per_unit']!,
          _qtyPerUnitMeta,
        ),
      );
    }
    if (data.containsKey('seller_name')) {
      context.handle(
        _sellerNameMeta,
        sellerName.isAcceptableOrUnknown(data['seller_name']!, _sellerNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sellerNameMeta);
    }
    if (data.containsKey('purchase_date')) {
      context.handle(
        _purchaseDateMeta,
        purchaseDate.isAcceptableOrUnknown(
          data['purchase_date']!,
          _purchaseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_purchaseDateMeta);
    }
    if (data.containsKey('condition')) {
      context.handle(
        _conditionMeta,
        condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta),
      );
    }
    if (data.containsKey('warranty_months')) {
      context.handle(
        _warrantyMonthsMeta,
        warrantyMonths.isAcceptableOrUnknown(
          data['warranty_months']!,
          _warrantyMonthsMeta,
        ),
      );
    }
    if (data.containsKey('product_image_path')) {
      context.handle(
        _productImagePathMeta,
        productImagePath.isAcceptableOrUnknown(
          data['product_image_path']!,
          _productImagePathMeta,
        ),
      );
    }
    if (data.containsKey('bill_reference_path')) {
      context.handle(
        _billReferencePathMeta,
        billReferencePath.isAcceptableOrUnknown(
          data['bill_reference_path']!,
          _billReferencePathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<drift.GeneratedColumn> get $primaryKey => {id};
  @override
  Purchase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Purchase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      unitPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price'],
      )!,
      unitType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_type'],
      )!,
      qtyPerUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty_per_unit'],
      ),
      sellerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}seller_name'],
      )!,
      purchaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purchase_date'],
      )!,
      condition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}condition'],
      )!,
      warrantyMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}warranty_months'],
      ),
      productImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_image_path'],
      ),
      billReferencePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bill_reference_path'],
      ),
    );
  }

  @override
  $PurchasesTable createAlias(String alias) {
    return $PurchasesTable(attachedDatabase, alias);
  }
}

class Purchase extends drift.DataClass implements drift.Insertable<Purchase> {
  final int id;
  final int productId;
  final int quantity;
  final int unitPrice;
  final String unitType;
  final int? qtyPerUnit;
  final String sellerName;
  final DateTime purchaseDate;
  final String condition;
  final int? warrantyMonths;
  final String? productImagePath;
  final String? billReferencePath;
  const Purchase({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.unitType,
    this.qtyPerUnit,
    required this.sellerName,
    required this.purchaseDate,
    required this.condition,
    this.warrantyMonths,
    this.productImagePath,
    this.billReferencePath,
  });
  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    map['id'] = drift.Variable<int>(id);
    map['product_id'] = drift.Variable<int>(productId);
    map['quantity'] = drift.Variable<int>(quantity);
    map['unit_price'] = drift.Variable<int>(unitPrice);
    map['unit_type'] = drift.Variable<String>(unitType);
    if (!nullToAbsent || qtyPerUnit != null) {
      map['qty_per_unit'] = drift.Variable<int>(qtyPerUnit);
    }
    map['seller_name'] = drift.Variable<String>(sellerName);
    map['purchase_date'] = drift.Variable<DateTime>(purchaseDate);
    map['condition'] = drift.Variable<String>(condition);
    if (!nullToAbsent || warrantyMonths != null) {
      map['warranty_months'] = drift.Variable<int>(warrantyMonths);
    }
    if (!nullToAbsent || productImagePath != null) {
      map['product_image_path'] = drift.Variable<String>(productImagePath);
    }
    if (!nullToAbsent || billReferencePath != null) {
      map['bill_reference_path'] = drift.Variable<String>(billReferencePath);
    }
    return map;
  }

  PurchasesCompanion toCompanion(bool nullToAbsent) {
    return PurchasesCompanion(
      id: drift.Value(id),
      productId: drift.Value(productId),
      quantity: drift.Value(quantity),
      unitPrice: drift.Value(unitPrice),
      unitType: drift.Value(unitType),
      qtyPerUnit: qtyPerUnit == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(qtyPerUnit),
      sellerName: drift.Value(sellerName),
      purchaseDate: drift.Value(purchaseDate),
      condition: drift.Value(condition),
      warrantyMonths: warrantyMonths == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(warrantyMonths),
      productImagePath: productImagePath == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(productImagePath),
      billReferencePath: billReferencePath == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(billReferencePath),
    );
  }

  factory Purchase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return Purchase(
      id: serializer.fromJson<int>(json['id']),
      productId: serializer.fromJson<int>(json['productId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPrice: serializer.fromJson<int>(json['unitPrice']),
      unitType: serializer.fromJson<String>(json['unitType']),
      qtyPerUnit: serializer.fromJson<int?>(json['qtyPerUnit']),
      sellerName: serializer.fromJson<String>(json['sellerName']),
      purchaseDate: serializer.fromJson<DateTime>(json['purchaseDate']),
      condition: serializer.fromJson<String>(json['condition']),
      warrantyMonths: serializer.fromJson<int?>(json['warrantyMonths']),
      productImagePath: serializer.fromJson<String?>(json['productImagePath']),
      billReferencePath: serializer.fromJson<String?>(
        json['billReferencePath'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'productId': serializer.toJson<int>(productId),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'unitType': serializer.toJson<String>(unitType),
      'qtyPerUnit': serializer.toJson<int?>(qtyPerUnit),
      'sellerName': serializer.toJson<String>(sellerName),
      'purchaseDate': serializer.toJson<DateTime>(purchaseDate),
      'condition': serializer.toJson<String>(condition),
      'warrantyMonths': serializer.toJson<int?>(warrantyMonths),
      'productImagePath': serializer.toJson<String?>(productImagePath),
      'billReferencePath': serializer.toJson<String?>(billReferencePath),
    };
  }

  Purchase copyWith({
    int? id,
    int? productId,
    int? quantity,
    int? unitPrice,
    String? unitType,
    drift.Value<int?> qtyPerUnit = const drift.Value.absent(),
    String? sellerName,
    DateTime? purchaseDate,
    String? condition,
    drift.Value<int?> warrantyMonths = const drift.Value.absent(),
    drift.Value<String?> productImagePath = const drift.Value.absent(),
    drift.Value<String?> billReferencePath = const drift.Value.absent(),
  }) => Purchase(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    unitType: unitType ?? this.unitType,
    qtyPerUnit: qtyPerUnit.present ? qtyPerUnit.value : this.qtyPerUnit,
    sellerName: sellerName ?? this.sellerName,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    condition: condition ?? this.condition,
    warrantyMonths: warrantyMonths.present
        ? warrantyMonths.value
        : this.warrantyMonths,
    productImagePath: productImagePath.present
        ? productImagePath.value
        : this.productImagePath,
    billReferencePath: billReferencePath.present
        ? billReferencePath.value
        : this.billReferencePath,
  );
  Purchase copyWithCompanion(PurchasesCompanion data) {
    return Purchase(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      unitType: data.unitType.present ? data.unitType.value : this.unitType,
      qtyPerUnit: data.qtyPerUnit.present
          ? data.qtyPerUnit.value
          : this.qtyPerUnit,
      sellerName: data.sellerName.present
          ? data.sellerName.value
          : this.sellerName,
      purchaseDate: data.purchaseDate.present
          ? data.purchaseDate.value
          : this.purchaseDate,
      condition: data.condition.present ? data.condition.value : this.condition,
      warrantyMonths: data.warrantyMonths.present
          ? data.warrantyMonths.value
          : this.warrantyMonths,
      productImagePath: data.productImagePath.present
          ? data.productImagePath.value
          : this.productImagePath,
      billReferencePath: data.billReferencePath.present
          ? data.billReferencePath.value
          : this.billReferencePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Purchase(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('unitType: $unitType, ')
          ..write('qtyPerUnit: $qtyPerUnit, ')
          ..write('sellerName: $sellerName, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('condition: $condition, ')
          ..write('warrantyMonths: $warrantyMonths, ')
          ..write('productImagePath: $productImagePath, ')
          ..write('billReferencePath: $billReferencePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    quantity,
    unitPrice,
    unitType,
    qtyPerUnit,
    sellerName,
    purchaseDate,
    condition,
    warrantyMonths,
    productImagePath,
    billReferencePath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Purchase &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.unitType == this.unitType &&
          other.qtyPerUnit == this.qtyPerUnit &&
          other.sellerName == this.sellerName &&
          other.purchaseDate == this.purchaseDate &&
          other.condition == this.condition &&
          other.warrantyMonths == this.warrantyMonths &&
          other.productImagePath == this.productImagePath &&
          other.billReferencePath == this.billReferencePath);
}

class PurchasesCompanion extends drift.UpdateCompanion<Purchase> {
  final drift.Value<int> id;
  final drift.Value<int> productId;
  final drift.Value<int> quantity;
  final drift.Value<int> unitPrice;
  final drift.Value<String> unitType;
  final drift.Value<int?> qtyPerUnit;
  final drift.Value<String> sellerName;
  final drift.Value<DateTime> purchaseDate;
  final drift.Value<String> condition;
  final drift.Value<int?> warrantyMonths;
  final drift.Value<String?> productImagePath;
  final drift.Value<String?> billReferencePath;
  const PurchasesCompanion({
    this.id = const drift.Value.absent(),
    this.productId = const drift.Value.absent(),
    this.quantity = const drift.Value.absent(),
    this.unitPrice = const drift.Value.absent(),
    this.unitType = const drift.Value.absent(),
    this.qtyPerUnit = const drift.Value.absent(),
    this.sellerName = const drift.Value.absent(),
    this.purchaseDate = const drift.Value.absent(),
    this.condition = const drift.Value.absent(),
    this.warrantyMonths = const drift.Value.absent(),
    this.productImagePath = const drift.Value.absent(),
    this.billReferencePath = const drift.Value.absent(),
  });
  PurchasesCompanion.insert({
    this.id = const drift.Value.absent(),
    required int productId,
    required int quantity,
    required int unitPrice,
    required String unitType,
    this.qtyPerUnit = const drift.Value.absent(),
    required String sellerName,
    required DateTime purchaseDate,
    this.condition = const drift.Value.absent(),
    this.warrantyMonths = const drift.Value.absent(),
    this.productImagePath = const drift.Value.absent(),
    this.billReferencePath = const drift.Value.absent(),
  }) : productId = drift.Value(productId),
       quantity = drift.Value(quantity),
       unitPrice = drift.Value(unitPrice),
       unitType = drift.Value(unitType),
       sellerName = drift.Value(sellerName),
       purchaseDate = drift.Value(purchaseDate);
  static drift.Insertable<Purchase> custom({
    drift.Expression<int>? id,
    drift.Expression<int>? productId,
    drift.Expression<int>? quantity,
    drift.Expression<int>? unitPrice,
    drift.Expression<String>? unitType,
    drift.Expression<int>? qtyPerUnit,
    drift.Expression<String>? sellerName,
    drift.Expression<DateTime>? purchaseDate,
    drift.Expression<String>? condition,
    drift.Expression<int>? warrantyMonths,
    drift.Expression<String>? productImagePath,
    drift.Expression<String>? billReferencePath,
  }) {
    return drift.RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (unitType != null) 'unit_type': unitType,
      if (qtyPerUnit != null) 'qty_per_unit': qtyPerUnit,
      if (sellerName != null) 'seller_name': sellerName,
      if (purchaseDate != null) 'purchase_date': purchaseDate,
      if (condition != null) 'condition': condition,
      if (warrantyMonths != null) 'warranty_months': warrantyMonths,
      if (productImagePath != null) 'product_image_path': productImagePath,
      if (billReferencePath != null) 'bill_reference_path': billReferencePath,
    });
  }

  PurchasesCompanion copyWith({
    drift.Value<int>? id,
    drift.Value<int>? productId,
    drift.Value<int>? quantity,
    drift.Value<int>? unitPrice,
    drift.Value<String>? unitType,
    drift.Value<int?>? qtyPerUnit,
    drift.Value<String>? sellerName,
    drift.Value<DateTime>? purchaseDate,
    drift.Value<String>? condition,
    drift.Value<int?>? warrantyMonths,
    drift.Value<String?>? productImagePath,
    drift.Value<String?>? billReferencePath,
  }) {
    return PurchasesCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      unitType: unitType ?? this.unitType,
      qtyPerUnit: qtyPerUnit ?? this.qtyPerUnit,
      sellerName: sellerName ?? this.sellerName,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      condition: condition ?? this.condition,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      productImagePath: productImagePath ?? this.productImagePath,
      billReferencePath: billReferencePath ?? this.billReferencePath,
    );
  }

  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    if (id.present) {
      map['id'] = drift.Variable<int>(id.value);
    }
    if (productId.present) {
      map['product_id'] = drift.Variable<int>(productId.value);
    }
    if (quantity.present) {
      map['quantity'] = drift.Variable<int>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = drift.Variable<int>(unitPrice.value);
    }
    if (unitType.present) {
      map['unit_type'] = drift.Variable<String>(unitType.value);
    }
    if (qtyPerUnit.present) {
      map['qty_per_unit'] = drift.Variable<int>(qtyPerUnit.value);
    }
    if (sellerName.present) {
      map['seller_name'] = drift.Variable<String>(sellerName.value);
    }
    if (purchaseDate.present) {
      map['purchase_date'] = drift.Variable<DateTime>(purchaseDate.value);
    }
    if (condition.present) {
      map['condition'] = drift.Variable<String>(condition.value);
    }
    if (warrantyMonths.present) {
      map['warranty_months'] = drift.Variable<int>(warrantyMonths.value);
    }
    if (productImagePath.present) {
      map['product_image_path'] = drift.Variable<String>(
        productImagePath.value,
      );
    }
    if (billReferencePath.present) {
      map['bill_reference_path'] = drift.Variable<String>(
        billReferencePath.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchasesCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('unitType: $unitType, ')
          ..write('qtyPerUnit: $qtyPerUnit, ')
          ..write('sellerName: $sellerName, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('condition: $condition, ')
          ..write('warrantyMonths: $warrantyMonths, ')
          ..write('productImagePath: $productImagePath, ')
          ..write('billReferencePath: $billReferencePath')
          ..write(')'))
        .toString();
  }
}

class $RequestItemsTable extends RequestItems
    with drift.TableInfo<$RequestItemsTable, RequestItem> {
  @override
  final drift.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RequestItemsTable(this.attachedDatabase, [this._alias]);
  static const drift.VerificationMeta _idMeta = const drift.VerificationMeta(
    'id',
  );
  @override
  late final drift.GeneratedColumn<int> id = drift.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const drift.VerificationMeta _brandMeta = const drift.VerificationMeta(
    'brand',
  );
  @override
  late final drift.GeneratedColumn<String> brand =
      drift.GeneratedColumn<String>(
        'brand',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _modelMeta = const drift.VerificationMeta(
    'model',
  );
  @override
  late final drift.GeneratedColumn<String> model =
      drift.GeneratedColumn<String>(
        'model',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _typeMeta = const drift.VerificationMeta(
    'type',
  );
  @override
  late final drift.GeneratedColumn<String> type = drift.GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const drift.VerificationMeta _categoryMeta =
      const drift.VerificationMeta('category');
  @override
  late final drift.GeneratedColumn<String> category =
      drift.GeneratedColumn<String>(
        'category',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const drift.VerificationMeta _ratingOrSizeMeta =
      const drift.VerificationMeta('ratingOrSize');
  @override
  late final drift.GeneratedColumn<String> ratingOrSize =
      drift.GeneratedColumn<String>(
        'rating_or_size',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _descriptionMeta =
      const drift.VerificationMeta('description');
  @override
  late final drift.GeneratedColumn<String> description =
      drift.GeneratedColumn<String>(
        'description',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _quantityMeta =
      const drift.VerificationMeta('quantity');
  @override
  late final drift.GeneratedColumn<int> quantity = drift.GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _unitMeta = const drift.VerificationMeta(
    'unit',
  );
  @override
  late final drift.GeneratedColumn<String> unit = drift.GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const drift.VerificationMeta _statusMeta =
      const drift.VerificationMeta('status');
  @override
  late final drift.GeneratedColumn<String> status =
      drift.GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const drift.Constant('pending'),
      );
  static const drift.VerificationMeta _remarksMeta =
      const drift.VerificationMeta('remarks');
  @override
  late final drift.GeneratedColumn<String> remarks =
      drift.GeneratedColumn<String>(
        'remarks',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const drift.VerificationMeta _photoPathMeta =
      const drift.VerificationMeta('photoPath');
  @override
  late final drift.GeneratedColumn<String> photoPath =
      drift.GeneratedColumn<String>(
        'photo_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<drift.GeneratedColumn> get $columns => [
    id,
    brand,
    model,
    type,
    category,
    ratingOrSize,
    description,
    quantity,
    unit,
    status,
    remarks,
    photoPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'request_items';
  @override
  drift.VerificationContext validateIntegrity(
    drift.Insertable<RequestItem> instance, {
    bool isInserting = false,
  }) {
    final context = drift.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    } else if (isInserting) {
      context.missing(_brandMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('rating_or_size')) {
      context.handle(
        _ratingOrSizeMeta,
        ratingOrSize.isAcceptableOrUnknown(
          data['rating_or_size']!,
          _ratingOrSizeMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('remarks')) {
      context.handle(
        _remarksMeta,
        remarks.isAcceptableOrUnknown(data['remarks']!, _remarksMeta),
      );
    }
    if (data.containsKey('photo_path')) {
      context.handle(
        _photoPathMeta,
        photoPath.isAcceptableOrUnknown(data['photo_path']!, _photoPathMeta),
      );
    }
    return context;
  }

  @override
  Set<drift.GeneratedColumn> get $primaryKey => {id};
  @override
  RequestItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RequestItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      ratingOrSize: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating_or_size'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      remarks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remarks'],
      ),
      photoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_path'],
      ),
    );
  }

  @override
  $RequestItemsTable createAlias(String alias) {
    return $RequestItemsTable(attachedDatabase, alias);
  }
}

class RequestItem extends drift.DataClass
    implements drift.Insertable<RequestItem> {
  final int id;
  final String brand;
  final String? model;
  final String? type;
  final String category;
  final String? ratingOrSize;
  final String? description;
  final int quantity;
  final String unit;
  final String status;
  final String? remarks;
  final String? photoPath;
  const RequestItem({
    required this.id,
    required this.brand,
    this.model,
    this.type,
    required this.category,
    this.ratingOrSize,
    this.description,
    required this.quantity,
    required this.unit,
    required this.status,
    this.remarks,
    this.photoPath,
  });
  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    map['id'] = drift.Variable<int>(id);
    map['brand'] = drift.Variable<String>(brand);
    if (!nullToAbsent || model != null) {
      map['model'] = drift.Variable<String>(model);
    }
    if (!nullToAbsent || type != null) {
      map['type'] = drift.Variable<String>(type);
    }
    map['category'] = drift.Variable<String>(category);
    if (!nullToAbsent || ratingOrSize != null) {
      map['rating_or_size'] = drift.Variable<String>(ratingOrSize);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = drift.Variable<String>(description);
    }
    map['quantity'] = drift.Variable<int>(quantity);
    map['unit'] = drift.Variable<String>(unit);
    map['status'] = drift.Variable<String>(status);
    if (!nullToAbsent || remarks != null) {
      map['remarks'] = drift.Variable<String>(remarks);
    }
    if (!nullToAbsent || photoPath != null) {
      map['photo_path'] = drift.Variable<String>(photoPath);
    }
    return map;
  }

  RequestItemsCompanion toCompanion(bool nullToAbsent) {
    return RequestItemsCompanion(
      id: drift.Value(id),
      brand: drift.Value(brand),
      model: model == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(model),
      type: type == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(type),
      category: drift.Value(category),
      ratingOrSize: ratingOrSize == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(ratingOrSize),
      description: description == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(description),
      quantity: drift.Value(quantity),
      unit: drift.Value(unit),
      status: drift.Value(status),
      remarks: remarks == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(remarks),
      photoPath: photoPath == null && nullToAbsent
          ? const drift.Value.absent()
          : drift.Value(photoPath),
    );
  }

  factory RequestItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return RequestItem(
      id: serializer.fromJson<int>(json['id']),
      brand: serializer.fromJson<String>(json['brand']),
      model: serializer.fromJson<String?>(json['model']),
      type: serializer.fromJson<String?>(json['type']),
      category: serializer.fromJson<String>(json['category']),
      ratingOrSize: serializer.fromJson<String?>(json['ratingOrSize']),
      description: serializer.fromJson<String?>(json['description']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unit: serializer.fromJson<String>(json['unit']),
      status: serializer.fromJson<String>(json['status']),
      remarks: serializer.fromJson<String?>(json['remarks']),
      photoPath: serializer.fromJson<String?>(json['photoPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= drift.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'brand': serializer.toJson<String>(brand),
      'model': serializer.toJson<String?>(model),
      'type': serializer.toJson<String?>(type),
      'category': serializer.toJson<String>(category),
      'ratingOrSize': serializer.toJson<String?>(ratingOrSize),
      'description': serializer.toJson<String?>(description),
      'quantity': serializer.toJson<int>(quantity),
      'unit': serializer.toJson<String>(unit),
      'status': serializer.toJson<String>(status),
      'remarks': serializer.toJson<String?>(remarks),
      'photoPath': serializer.toJson<String?>(photoPath),
    };
  }

  RequestItem copyWith({
    int? id,
    String? brand,
    drift.Value<String?> model = const drift.Value.absent(),
    drift.Value<String?> type = const drift.Value.absent(),
    String? category,
    drift.Value<String?> ratingOrSize = const drift.Value.absent(),
    drift.Value<String?> description = const drift.Value.absent(),
    int? quantity,
    String? unit,
    String? status,
    drift.Value<String?> remarks = const drift.Value.absent(),
    drift.Value<String?> photoPath = const drift.Value.absent(),
  }) => RequestItem(
    id: id ?? this.id,
    brand: brand ?? this.brand,
    model: model.present ? model.value : this.model,
    type: type.present ? type.value : this.type,
    category: category ?? this.category,
    ratingOrSize: ratingOrSize.present ? ratingOrSize.value : this.ratingOrSize,
    description: description.present ? description.value : this.description,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    status: status ?? this.status,
    remarks: remarks.present ? remarks.value : this.remarks,
    photoPath: photoPath.present ? photoPath.value : this.photoPath,
  );
  RequestItem copyWithCompanion(RequestItemsCompanion data) {
    return RequestItem(
      id: data.id.present ? data.id.value : this.id,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      type: data.type.present ? data.type.value : this.type,
      category: data.category.present ? data.category.value : this.category,
      ratingOrSize: data.ratingOrSize.present
          ? data.ratingOrSize.value
          : this.ratingOrSize,
      description: data.description.present
          ? data.description.value
          : this.description,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      status: data.status.present ? data.status.value : this.status,
      remarks: data.remarks.present ? data.remarks.value : this.remarks,
      photoPath: data.photoPath.present ? data.photoPath.value : this.photoPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RequestItem(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('type: $type, ')
          ..write('category: $category, ')
          ..write('ratingOrSize: $ratingOrSize, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('status: $status, ')
          ..write('remarks: $remarks, ')
          ..write('photoPath: $photoPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    brand,
    model,
    type,
    category,
    ratingOrSize,
    description,
    quantity,
    unit,
    status,
    remarks,
    photoPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestItem &&
          other.id == this.id &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.type == this.type &&
          other.category == this.category &&
          other.ratingOrSize == this.ratingOrSize &&
          other.description == this.description &&
          other.quantity == this.quantity &&
          other.unit == this.unit &&
          other.status == this.status &&
          other.remarks == this.remarks &&
          other.photoPath == this.photoPath);
}

class RequestItemsCompanion extends drift.UpdateCompanion<RequestItem> {
  final drift.Value<int> id;
  final drift.Value<String> brand;
  final drift.Value<String?> model;
  final drift.Value<String?> type;
  final drift.Value<String> category;
  final drift.Value<String?> ratingOrSize;
  final drift.Value<String?> description;
  final drift.Value<int> quantity;
  final drift.Value<String> unit;
  final drift.Value<String> status;
  final drift.Value<String?> remarks;
  final drift.Value<String?> photoPath;
  const RequestItemsCompanion({
    this.id = const drift.Value.absent(),
    this.brand = const drift.Value.absent(),
    this.model = const drift.Value.absent(),
    this.type = const drift.Value.absent(),
    this.category = const drift.Value.absent(),
    this.ratingOrSize = const drift.Value.absent(),
    this.description = const drift.Value.absent(),
    this.quantity = const drift.Value.absent(),
    this.unit = const drift.Value.absent(),
    this.status = const drift.Value.absent(),
    this.remarks = const drift.Value.absent(),
    this.photoPath = const drift.Value.absent(),
  });
  RequestItemsCompanion.insert({
    this.id = const drift.Value.absent(),
    required String brand,
    this.model = const drift.Value.absent(),
    this.type = const drift.Value.absent(),
    required String category,
    this.ratingOrSize = const drift.Value.absent(),
    this.description = const drift.Value.absent(),
    required int quantity,
    required String unit,
    this.status = const drift.Value.absent(),
    this.remarks = const drift.Value.absent(),
    this.photoPath = const drift.Value.absent(),
  }) : brand = drift.Value(brand),
       category = drift.Value(category),
       quantity = drift.Value(quantity),
       unit = drift.Value(unit);
  static drift.Insertable<RequestItem> custom({
    drift.Expression<int>? id,
    drift.Expression<String>? brand,
    drift.Expression<String>? model,
    drift.Expression<String>? type,
    drift.Expression<String>? category,
    drift.Expression<String>? ratingOrSize,
    drift.Expression<String>? description,
    drift.Expression<int>? quantity,
    drift.Expression<String>? unit,
    drift.Expression<String>? status,
    drift.Expression<String>? remarks,
    drift.Expression<String>? photoPath,
  }) {
    return drift.RawValuesInsertable({
      if (id != null) 'id': id,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (type != null) 'type': type,
      if (category != null) 'category': category,
      if (ratingOrSize != null) 'rating_or_size': ratingOrSize,
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (status != null) 'status': status,
      if (remarks != null) 'remarks': remarks,
      if (photoPath != null) 'photo_path': photoPath,
    });
  }

  RequestItemsCompanion copyWith({
    drift.Value<int>? id,
    drift.Value<String>? brand,
    drift.Value<String?>? model,
    drift.Value<String?>? type,
    drift.Value<String>? category,
    drift.Value<String?>? ratingOrSize,
    drift.Value<String?>? description,
    drift.Value<int>? quantity,
    drift.Value<String>? unit,
    drift.Value<String>? status,
    drift.Value<String?>? remarks,
    drift.Value<String?>? photoPath,
  }) {
    return RequestItemsCompanion(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      type: type ?? this.type,
      category: category ?? this.category,
      ratingOrSize: ratingOrSize ?? this.ratingOrSize,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  @override
  Map<String, drift.Expression> toColumns(bool nullToAbsent) {
    final map = <String, drift.Expression>{};
    if (id.present) {
      map['id'] = drift.Variable<int>(id.value);
    }
    if (brand.present) {
      map['brand'] = drift.Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = drift.Variable<String>(model.value);
    }
    if (type.present) {
      map['type'] = drift.Variable<String>(type.value);
    }
    if (category.present) {
      map['category'] = drift.Variable<String>(category.value);
    }
    if (ratingOrSize.present) {
      map['rating_or_size'] = drift.Variable<String>(ratingOrSize.value);
    }
    if (description.present) {
      map['description'] = drift.Variable<String>(description.value);
    }
    if (quantity.present) {
      map['quantity'] = drift.Variable<int>(quantity.value);
    }
    if (unit.present) {
      map['unit'] = drift.Variable<String>(unit.value);
    }
    if (status.present) {
      map['status'] = drift.Variable<String>(status.value);
    }
    if (remarks.present) {
      map['remarks'] = drift.Variable<String>(remarks.value);
    }
    if (photoPath.present) {
      map['photo_path'] = drift.Variable<String>(photoPath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RequestItemsCompanion(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('type: $type, ')
          ..write('category: $category, ')
          ..write('ratingOrSize: $ratingOrSize, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('status: $status, ')
          ..write('remarks: $remarks, ')
          ..write('photoPath: $photoPath')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends drift.GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $PurchasesTable purchases = $PurchasesTable(this);
  late final $RequestItemsTable requestItems = $RequestItemsTable(this);
  @override
  Iterable<drift.TableInfo<drift.Table, Object?>> get allTables =>
      allSchemaEntities.whereType<drift.TableInfo<drift.Table, Object?>>();
  @override
  List<drift.DatabaseSchemaEntity> get allSchemaEntities => [
    products,
    purchases,
    requestItems,
  ];
}

typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      drift.Value<int> id,
      required String name,
      required String brand,
      drift.Value<String?> model,
      required String sizeOrType,
      required String category,
      required int quantity,
      required int price,
      drift.Value<String?> imagePaths,
      drift.Value<bool> isDeleted,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      drift.Value<int> id,
      drift.Value<String> name,
      drift.Value<String> brand,
      drift.Value<String?> model,
      drift.Value<String> sizeOrType,
      drift.Value<String> category,
      drift.Value<int> quantity,
      drift.Value<int> price,
      drift.Value<String?> imagePaths,
      drift.Value<bool> isDeleted,
    });

class $$ProductsTableFilterComposer
    extends drift.Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get sizeOrType => $composableBuilder(
    column: $table.sizeOrType,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get imagePaths => $composableBuilder(
    column: $table.imagePaths,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => drift.ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends drift.Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get sizeOrType => $composableBuilder(
    column: $table.sizeOrType,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get imagePaths => $composableBuilder(
    column: $table.imagePaths,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => drift.ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends drift.Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  drift.GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  drift.GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  drift.GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  drift.GeneratedColumn<String> get sizeOrType => $composableBuilder(
    column: $table.sizeOrType,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  drift.GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  drift.GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  drift.GeneratedColumn<String> get imagePaths => $composableBuilder(
    column: $table.imagePaths,
    builder: (column) => column,
  );

  drift.GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);
}

class $$ProductsTableTableManager
    extends
        drift.RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (
            Product,
            drift.BaseReferences<_$AppDatabase, $ProductsTable, Product>,
          ),
          Product,
          drift.PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        drift.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                drift.Value<String> name = const drift.Value.absent(),
                drift.Value<String> brand = const drift.Value.absent(),
                drift.Value<String?> model = const drift.Value.absent(),
                drift.Value<String> sizeOrType = const drift.Value.absent(),
                drift.Value<String> category = const drift.Value.absent(),
                drift.Value<int> quantity = const drift.Value.absent(),
                drift.Value<int> price = const drift.Value.absent(),
                drift.Value<String?> imagePaths = const drift.Value.absent(),
                drift.Value<bool> isDeleted = const drift.Value.absent(),
              }) => ProductsCompanion(
                id: id,
                name: name,
                brand: brand,
                model: model,
                sizeOrType: sizeOrType,
                category: category,
                quantity: quantity,
                price: price,
                imagePaths: imagePaths,
                isDeleted: isDeleted,
              ),
          createCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                required String name,
                required String brand,
                drift.Value<String?> model = const drift.Value.absent(),
                required String sizeOrType,
                required String category,
                required int quantity,
                required int price,
                drift.Value<String?> imagePaths = const drift.Value.absent(),
                drift.Value<bool> isDeleted = const drift.Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                name: name,
                brand: brand,
                model: model,
                sizeOrType: sizeOrType,
                category: category,
                quantity: quantity,
                price: price,
                imagePaths: imagePaths,
                isDeleted: isDeleted,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), drift.BaseReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    drift.ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, drift.BaseReferences<_$AppDatabase, $ProductsTable, Product>),
      Product,
      drift.PrefetchHooks Function()
    >;
typedef $$PurchasesTableCreateCompanionBuilder =
    PurchasesCompanion Function({
      drift.Value<int> id,
      required int productId,
      required int quantity,
      required int unitPrice,
      required String unitType,
      drift.Value<int?> qtyPerUnit,
      required String sellerName,
      required DateTime purchaseDate,
      drift.Value<String> condition,
      drift.Value<int?> warrantyMonths,
      drift.Value<String?> productImagePath,
      drift.Value<String?> billReferencePath,
    });
typedef $$PurchasesTableUpdateCompanionBuilder =
    PurchasesCompanion Function({
      drift.Value<int> id,
      drift.Value<int> productId,
      drift.Value<int> quantity,
      drift.Value<int> unitPrice,
      drift.Value<String> unitType,
      drift.Value<int?> qtyPerUnit,
      drift.Value<String> sellerName,
      drift.Value<DateTime> purchaseDate,
      drift.Value<String> condition,
      drift.Value<int?> warrantyMonths,
      drift.Value<String?> productImagePath,
      drift.Value<String?> billReferencePath,
    });

class $$PurchasesTableFilterComposer
    extends drift.Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get unitType => $composableBuilder(
    column: $table.unitType,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get qtyPerUnit => $composableBuilder(
    column: $table.qtyPerUnit,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get sellerName => $composableBuilder(
    column: $table.sellerName,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get warrantyMonths => $composableBuilder(
    column: $table.warrantyMonths,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get productImagePath => $composableBuilder(
    column: $table.productImagePath,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get billReferencePath => $composableBuilder(
    column: $table.billReferencePath,
    builder: (column) => drift.ColumnFilters(column),
  );
}

class $$PurchasesTableOrderingComposer
    extends drift.Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get unitType => $composableBuilder(
    column: $table.unitType,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get qtyPerUnit => $composableBuilder(
    column: $table.qtyPerUnit,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get sellerName => $composableBuilder(
    column: $table.sellerName,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get warrantyMonths => $composableBuilder(
    column: $table.warrantyMonths,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get productImagePath => $composableBuilder(
    column: $table.productImagePath,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get billReferencePath => $composableBuilder(
    column: $table.billReferencePath,
    builder: (column) => drift.ColumnOrderings(column),
  );
}

class $$PurchasesTableAnnotationComposer
    extends drift.Composer<_$AppDatabase, $PurchasesTable> {
  $$PurchasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  drift.GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  drift.GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  drift.GeneratedColumn<int> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  drift.GeneratedColumn<String> get unitType =>
      $composableBuilder(column: $table.unitType, builder: (column) => column);

  drift.GeneratedColumn<int> get qtyPerUnit => $composableBuilder(
    column: $table.qtyPerUnit,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get sellerName => $composableBuilder(
    column: $table.sellerName,
    builder: (column) => column,
  );

  drift.GeneratedColumn<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  drift.GeneratedColumn<int> get warrantyMonths => $composableBuilder(
    column: $table.warrantyMonths,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get productImagePath => $composableBuilder(
    column: $table.productImagePath,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get billReferencePath => $composableBuilder(
    column: $table.billReferencePath,
    builder: (column) => column,
  );
}

class $$PurchasesTableTableManager
    extends
        drift.RootTableManager<
          _$AppDatabase,
          $PurchasesTable,
          Purchase,
          $$PurchasesTableFilterComposer,
          $$PurchasesTableOrderingComposer,
          $$PurchasesTableAnnotationComposer,
          $$PurchasesTableCreateCompanionBuilder,
          $$PurchasesTableUpdateCompanionBuilder,
          (
            Purchase,
            drift.BaseReferences<_$AppDatabase, $PurchasesTable, Purchase>,
          ),
          Purchase,
          drift.PrefetchHooks Function()
        > {
  $$PurchasesTableTableManager(_$AppDatabase db, $PurchasesTable table)
    : super(
        drift.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                drift.Value<int> productId = const drift.Value.absent(),
                drift.Value<int> quantity = const drift.Value.absent(),
                drift.Value<int> unitPrice = const drift.Value.absent(),
                drift.Value<String> unitType = const drift.Value.absent(),
                drift.Value<int?> qtyPerUnit = const drift.Value.absent(),
                drift.Value<String> sellerName = const drift.Value.absent(),
                drift.Value<DateTime> purchaseDate = const drift.Value.absent(),
                drift.Value<String> condition = const drift.Value.absent(),
                drift.Value<int?> warrantyMonths = const drift.Value.absent(),
                drift.Value<String?> productImagePath =
                    const drift.Value.absent(),
                drift.Value<String?> billReferencePath =
                    const drift.Value.absent(),
              }) => PurchasesCompanion(
                id: id,
                productId: productId,
                quantity: quantity,
                unitPrice: unitPrice,
                unitType: unitType,
                qtyPerUnit: qtyPerUnit,
                sellerName: sellerName,
                purchaseDate: purchaseDate,
                condition: condition,
                warrantyMonths: warrantyMonths,
                productImagePath: productImagePath,
                billReferencePath: billReferencePath,
              ),
          createCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                required int productId,
                required int quantity,
                required int unitPrice,
                required String unitType,
                drift.Value<int?> qtyPerUnit = const drift.Value.absent(),
                required String sellerName,
                required DateTime purchaseDate,
                drift.Value<String> condition = const drift.Value.absent(),
                drift.Value<int?> warrantyMonths = const drift.Value.absent(),
                drift.Value<String?> productImagePath =
                    const drift.Value.absent(),
                drift.Value<String?> billReferencePath =
                    const drift.Value.absent(),
              }) => PurchasesCompanion.insert(
                id: id,
                productId: productId,
                quantity: quantity,
                unitPrice: unitPrice,
                unitType: unitType,
                qtyPerUnit: qtyPerUnit,
                sellerName: sellerName,
                purchaseDate: purchaseDate,
                condition: condition,
                warrantyMonths: warrantyMonths,
                productImagePath: productImagePath,
                billReferencePath: billReferencePath,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), drift.BaseReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PurchasesTableProcessedTableManager =
    drift.ProcessedTableManager<
      _$AppDatabase,
      $PurchasesTable,
      Purchase,
      $$PurchasesTableFilterComposer,
      $$PurchasesTableOrderingComposer,
      $$PurchasesTableAnnotationComposer,
      $$PurchasesTableCreateCompanionBuilder,
      $$PurchasesTableUpdateCompanionBuilder,
      (
        Purchase,
        drift.BaseReferences<_$AppDatabase, $PurchasesTable, Purchase>,
      ),
      Purchase,
      drift.PrefetchHooks Function()
    >;
typedef $$RequestItemsTableCreateCompanionBuilder =
    RequestItemsCompanion Function({
      drift.Value<int> id,
      required String brand,
      drift.Value<String?> model,
      drift.Value<String?> type,
      required String category,
      drift.Value<String?> ratingOrSize,
      drift.Value<String?> description,
      required int quantity,
      required String unit,
      drift.Value<String> status,
      drift.Value<String?> remarks,
      drift.Value<String?> photoPath,
    });
typedef $$RequestItemsTableUpdateCompanionBuilder =
    RequestItemsCompanion Function({
      drift.Value<int> id,
      drift.Value<String> brand,
      drift.Value<String?> model,
      drift.Value<String?> type,
      drift.Value<String> category,
      drift.Value<String?> ratingOrSize,
      drift.Value<String?> description,
      drift.Value<int> quantity,
      drift.Value<String> unit,
      drift.Value<String> status,
      drift.Value<String?> remarks,
      drift.Value<String?> photoPath,
    });

class $$RequestItemsTableFilterComposer
    extends drift.Composer<_$AppDatabase, $RequestItemsTable> {
  $$RequestItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get ratingOrSize => $composableBuilder(
    column: $table.ratingOrSize,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => drift.ColumnFilters(column),
  );

  drift.ColumnFilters<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => drift.ColumnFilters(column),
  );
}

class $$RequestItemsTableOrderingComposer
    extends drift.Composer<_$AppDatabase, $RequestItemsTable> {
  $$RequestItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get ratingOrSize => $composableBuilder(
    column: $table.ratingOrSize,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => drift.ColumnOrderings(column),
  );

  drift.ColumnOrderings<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => drift.ColumnOrderings(column),
  );
}

class $$RequestItemsTableAnnotationComposer
    extends drift.Composer<_$AppDatabase, $RequestItemsTable> {
  $$RequestItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  drift.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  drift.GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  drift.GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  drift.GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  drift.GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  drift.GeneratedColumn<String> get ratingOrSize => $composableBuilder(
    column: $table.ratingOrSize,
    builder: (column) => column,
  );

  drift.GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  drift.GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  drift.GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  drift.GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  drift.GeneratedColumn<String> get remarks =>
      $composableBuilder(column: $table.remarks, builder: (column) => column);

  drift.GeneratedColumn<String> get photoPath =>
      $composableBuilder(column: $table.photoPath, builder: (column) => column);
}

class $$RequestItemsTableTableManager
    extends
        drift.RootTableManager<
          _$AppDatabase,
          $RequestItemsTable,
          RequestItem,
          $$RequestItemsTableFilterComposer,
          $$RequestItemsTableOrderingComposer,
          $$RequestItemsTableAnnotationComposer,
          $$RequestItemsTableCreateCompanionBuilder,
          $$RequestItemsTableUpdateCompanionBuilder,
          (
            RequestItem,
            drift.BaseReferences<
              _$AppDatabase,
              $RequestItemsTable,
              RequestItem
            >,
          ),
          RequestItem,
          drift.PrefetchHooks Function()
        > {
  $$RequestItemsTableTableManager(_$AppDatabase db, $RequestItemsTable table)
    : super(
        drift.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RequestItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RequestItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RequestItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                drift.Value<String> brand = const drift.Value.absent(),
                drift.Value<String?> model = const drift.Value.absent(),
                drift.Value<String?> type = const drift.Value.absent(),
                drift.Value<String> category = const drift.Value.absent(),
                drift.Value<String?> ratingOrSize = const drift.Value.absent(),
                drift.Value<String?> description = const drift.Value.absent(),
                drift.Value<int> quantity = const drift.Value.absent(),
                drift.Value<String> unit = const drift.Value.absent(),
                drift.Value<String> status = const drift.Value.absent(),
                drift.Value<String?> remarks = const drift.Value.absent(),
                drift.Value<String?> photoPath = const drift.Value.absent(),
              }) => RequestItemsCompanion(
                id: id,
                brand: brand,
                model: model,
                type: type,
                category: category,
                ratingOrSize: ratingOrSize,
                description: description,
                quantity: quantity,
                unit: unit,
                status: status,
                remarks: remarks,
                photoPath: photoPath,
              ),
          createCompanionCallback:
              ({
                drift.Value<int> id = const drift.Value.absent(),
                required String brand,
                drift.Value<String?> model = const drift.Value.absent(),
                drift.Value<String?> type = const drift.Value.absent(),
                required String category,
                drift.Value<String?> ratingOrSize = const drift.Value.absent(),
                drift.Value<String?> description = const drift.Value.absent(),
                required int quantity,
                required String unit,
                drift.Value<String> status = const drift.Value.absent(),
                drift.Value<String?> remarks = const drift.Value.absent(),
                drift.Value<String?> photoPath = const drift.Value.absent(),
              }) => RequestItemsCompanion.insert(
                id: id,
                brand: brand,
                model: model,
                type: type,
                category: category,
                ratingOrSize: ratingOrSize,
                description: description,
                quantity: quantity,
                unit: unit,
                status: status,
                remarks: remarks,
                photoPath: photoPath,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), drift.BaseReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RequestItemsTableProcessedTableManager =
    drift.ProcessedTableManager<
      _$AppDatabase,
      $RequestItemsTable,
      RequestItem,
      $$RequestItemsTableFilterComposer,
      $$RequestItemsTableOrderingComposer,
      $$RequestItemsTableAnnotationComposer,
      $$RequestItemsTableCreateCompanionBuilder,
      $$RequestItemsTableUpdateCompanionBuilder,
      (
        RequestItem,
        drift.BaseReferences<_$AppDatabase, $RequestItemsTable, RequestItem>,
      ),
      RequestItem,
      drift.PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db, _db.purchases);
  $$RequestItemsTableTableManager get requestItems =>
      $$RequestItemsTableTableManager(_db, _db.requestItems);
}
