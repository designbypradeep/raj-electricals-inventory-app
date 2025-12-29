import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get brand => text()();
  TextColumn get model => text().nullable()();
  TextColumn get sizeOrType => text()();
  TextColumn get category => text()();
  IntColumn get quantity => integer()();
  IntColumn get price => integer()();
  TextColumn get imagePaths =>
      text().nullable()(); // JSON array of image file paths
  TextColumn get itemCode => text().nullable()();
  BoolColumn get isDeleted =>
      boolean().withDefault(const Constant(false))(); // Soft delete support
}
