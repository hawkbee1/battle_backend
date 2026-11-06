import 'package:battle_backend/src/rows.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';

/// {@template appwrite_rows}
/// The tables of the Hawkbee database in Appwrite (Adapter, stack decision
/// 7), through the TablesDB service of a server client.
/// {@endtemplate}
final class AppwriteRows implements Rows {
  /// {@macro appwrite_rows}
  const new(this.tables);

  /// The TablesDB service.
  final TablesDB tables;

  /// The rows a page holds at most.
  static const pageSize = 100;

  @override
  Future<RowData?> get(String table, String id) async {
    try {
      final row = await tables.getRow(
        databaseId: AppwriteIds.databaseId,
        tableId: table,
        rowId: id,
      );
      return row.data;
    } on AppwriteException catch (error) {
      if (error.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> put(String table, String id, RowData data) => tables.upsertRow(
    databaseId: AppwriteIds.databaseId,
    tableId: table,
    rowId: id,
    data: data,
  );

  @override
  Future<void> delete(String table, String id) async {
    try {
      await tables.deleteRow(
        databaseId: AppwriteIds.databaseId,
        tableId: table,
        rowId: id,
      );
    } on AppwriteException catch (error) {
      if (error.code != 404) rethrow;
    }
  }

  @override
  Future<List<Row>> find(String table, Map<String, Object> equal) async {
    final found = <Row>[];
    String? after;
    while (true) {
      final page = await tables.listRows(
        databaseId: AppwriteIds.databaseId,
        tableId: table,
        queries: [
          for (final MapEntry(:key, :value) in equal.entries)
            Query.equal(key, value),
          Query.limit(pageSize),
          if (after != null) Query.cursorAfter(after),
        ],
      );
      found.addAll([
        for (final row in page.rows) (id: row.$id, data: row.data),
      ]);
      if (page.rows.length < pageSize) return found;
      after = page.rows.last.$id;
    }
  }
}

/// {@template admins}
/// Who is an admin (stack decision 6): an account with the Appwrite label
/// `admin`, checked on the server.
/// {@endtemplate}
abstract interface class Admins {
  /// Whether [accountId] is an admin.
  Future<bool> isAdmin(String accountId);
}

/// {@template appwrite_admins}
/// [Admins] from the labels of Appwrite Auth's users (Adapter).
/// {@endtemplate}
final class AppwriteAdmins implements Admins {
  /// {@macro appwrite_admins}
  const new(this.users);

  /// The Users service of a server client.
  final Users users;

  @override
  Future<bool> isAdmin(String accountId) async =>
      (await users.get(userId: accountId)).labels
          .contains(AppwriteIds.adminLabel);
}
