import 'package:hawkbee_schema/hawkbee_schema.dart';

/// One row: its ID and its data.
typedef Row = ({String id, RowData data});

/// The tables of the Hawkbee database (a port, stack decision 7): the
/// functions read and write their rows through it.
abstract interface class Rows {
  /// The row [id] of [table]; null when there is none.
  Future<RowData?> get(String table, String id);

  /// Writes the row [id] of [table]: creates it, or replaces its data.
  Future<void> put(String table, String id, RowData data);

  /// The rows of [table] whose columns hold the values of [equal].
  Future<List<Row>> find(String table, Map<String, Object> equal);

  /// Deletes the row [id] of [table], if there is one.
  Future<void> delete(String table, String id);
}

/// {@template memory_rows}
/// Tables in memory, for tests and tools.
/// {@endtemplate}
final class MemoryRows implements Rows {
  /// {@macro memory_rows}
  new();

  final _tables = <String, Map<String, RowData>>{};

  @override
  Future<RowData?> get(String table, String id) async => _tables[table]?[id];

  @override
  Future<void> put(String table, String id, RowData data) async =>
      (_tables[table] ??= {})[id] = Map.unmodifiable(data);

  @override
  Future<void> delete(String table, String id) async =>
      _tables[table]?.remove(id);

  @override
  Future<List<Row>> find(String table, Map<String, Object> equal) async => [
    for (final MapEntry(key: id, value: data)
        in (_tables[table] ?? const {}).entries)
      if (equal.entries.every((column) => data[column.key] == column.value))
        (id: id, data: data),
  ];
}
