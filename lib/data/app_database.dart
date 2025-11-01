import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' as drift;
import 'tables/products.dart';
import 'tables/purchases.dart';
import 'tables/request_items.dart';

// add this at the top

part 'app_database.g.dart'; // Will be generated

@DriftDatabase(tables: [Products, Purchases, RequestItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from == 1) {
        await migrator.addColumn(products, products.imagePaths);
      }
    },
  );

  Future<List<RequestItem>> getAllRequestItems() {
    return select(requestItems).get();
  }

  Future<int> insertRequestItem(RequestItemsCompanion item) {
    return into(requestItems).insert(item);
  }

  Future<bool> updateRequestItem(RequestItem item) {
    return update(requestItems).replace(item);
  }

  Future<int> deleteRequestItem(int id) {
    return (delete(requestItems)..where((tbl) => tbl.id.equals(id))).go();
  }

  // CRUD: Get all products
  Future<List<Product>> getAllProducts() {
    return (select(
      products,
    )..where((tbl) => tbl.isDeleted.equals(false))).get();
  }

  // CRUD: Add new product
  Future<int> insertProduct(ProductsCompanion product) =>
      into(products).insert(product);

  // CRUD: Update existing product
  Future<bool> updateProduct(Product product) =>
      update(products).replace(product);

  // Custom: Update product by ID (used in dialog editing)
  Future<int> updateProductById(
    int id,
    String newName,
    int newQty,
    int newPrice,
  ) {
    return (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        name: drift.Value(newName),
        quantity: drift.Value(newQty),
        price: drift.Value(newPrice),
      ),
    );
  }

  Future<void> softDeleteProduct(int productId) async {
    await (update(products)..where((t) => t.id.equals(productId))).write(
      const ProductsCompanion(isDeleted: drift.Value(true)),
    );
  }

  // CRUD: Delete product
  // Delete a purchase by ID
  Future<int> deletePurchaseById(int id) {
    return (delete(purchases)..where((tbl) => tbl.id.equals(id))).go();
  }

  // Add this new method
  Future<int> restoreProductById(int id) =>
      (update(products)..where((t) => t.id.equals(id))).write(
        const ProductsCompanion(isDeleted: drift.Value(false)),
      );

  // CRUD: Get all purchases
  Future<List<Purchase>> getAllPurchases() => select(purchases).get();

  Future<int> insertPurchase(PurchasesCompanion purchase) async {
    // Insert purchase first
    final purchaseId = await into(purchases).insert(purchase);

    // Find the product and update quantity
    final product =
        await (select(products)
              ..where((tbl) => tbl.id.equals(purchase.productId.value)))
            .getSingleOrNull();

    if (product != null) {
      final updatedQty = product.quantity + purchase.quantity.value;
      await (update(products)..where((t) => t.id.equals(product.id))).write(
        ProductsCompanion(quantity: drift.Value(updatedQty)),
      );
    }

    return purchaseId;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = Directory.current; // Windows-safe
    final file = File(p.join(dbFolder.path, 'raj_inventory.sqlite'));

    return NativeDatabase(
      file,
      logStatements: false,
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON;'); // ✅ No await here
      },
    );
  });
}
