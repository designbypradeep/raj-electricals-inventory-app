import 'package:drift/drift.dart';
// 👈 required

class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId => integer().customConstraint(
    'NOT NULL REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE',
  )();

  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  TextColumn get unitType => text()();
  IntColumn get qtyPerUnit => integer().nullable()();
  TextColumn get sellerName => text()();
  DateTimeColumn get purchaseDate => dateTime()();
  TextColumn get condition => text().withDefault(const Constant('New'))();
  IntColumn get warrantyMonths => integer().nullable()();
  TextColumn get productImagePath => text().nullable()();
  TextColumn get billReferencePath => text().nullable()();
}
