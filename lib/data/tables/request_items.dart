import 'package:drift/drift.dart';

class RequestItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get brand => text()();
  TextColumn get model => text().nullable()();
  TextColumn get type => text().nullable()();
  TextColumn get category => text()();
  TextColumn get ratingOrSize => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get quantity => integer()();
  TextColumn get unit => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get remarks => text().nullable()();
  TextColumn get photoPath => text().nullable()(); // Add this line
}
