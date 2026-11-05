import 'package:battle_backend/battle_backend.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' as models;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTables extends Mock implements TablesDB;

class _MockUsers extends Mock implements Users;

class _MockUser extends Mock implements models.User;

models.Row _row(String id, Map<String, Object?> data) => models.Row(
  $id: id,
  $sequence: '1',
  $tableId: 'wars',
  $databaseId: 'hawkbee',
  $createdAt: '',
  $updatedAt: '',
  $permissions: const [],
  data: data,
);

void main() {
  group(AppwriteRows, () {
    late _MockTables tables;
    late AppwriteRows rows;

    setUp(() {
      tables = _MockTables();
      rows = AppwriteRows(tables);
    });

    test('gets a row, or null when there is none', () async {
      when(
        () => tables.getRow(databaseId: 'hawkbee', tableId: 'wars', rowId: 'w'),
      ).thenAnswer((_) async => _row('w', const {'over': false}));
      when(
        () => tables.getRow(databaseId: 'hawkbee', tableId: 'wars', rowId: 'x'),
      ).thenThrow(AppwriteException('not found', 404));
      when(
        () => tables.getRow(databaseId: 'hawkbee', tableId: 'wars', rowId: 'y'),
      ).thenThrow(AppwriteException('down', 503));

      expect(await rows.get('wars', 'w'), {'over': false});
      expect(await rows.get('wars', 'x'), isNull);
      expect(() => rows.get('wars', 'y'), throwsA(isA<AppwriteException>()));
    });

    test('writes and deletes rows; a missing row is deleted already', () async {
      when(
        () => tables.upsertRow(
          databaseId: 'hawkbee',
          tableId: 'wars',
          rowId: 'w',
          data: const {'over': true},
        ),
      ).thenAnswer((_) async => _row('w', const {}));
      when(
        () => tables.deleteRow(
          databaseId: 'hawkbee',
          tableId: 'wars',
          rowId: 'w',
        ),
      ).thenAnswer((_) async => {});
      when(
        () => tables.deleteRow(
          databaseId: 'hawkbee',
          tableId: 'wars',
          rowId: 'x',
        ),
      ).thenThrow(AppwriteException('not found', 404));
      when(
        () => tables.deleteRow(
          databaseId: 'hawkbee',
          tableId: 'wars',
          rowId: 'y',
        ),
      ).thenThrow(AppwriteException('down', 503));

      await rows.put('wars', 'w', const {'over': true});
      await rows.delete('wars', 'w');
      await rows.delete('wars', 'x');
      expect(() => rows.delete('wars', 'y'), throwsA(isA<AppwriteException>()));
      verify(
        () => tables.upsertRow(
          databaseId: 'hawkbee',
          tableId: 'wars',
          rowId: 'w',
          data: const {'over': true},
        ),
      ).called(1);
    });

    test('finds rows page by page', () async {
      when(
        () => tables.listRows(
          databaseId: 'hawkbee',
          tableId: 'sections',
          queries: any(named: 'queries'),
        ),
      ).thenAnswer((invocation) async {
        final queries = invocation.namedArguments[#queries] as List<String>;
        final second = queries.any((query) => query.contains('cursorAfter'));
        return models.RowList(
          total: 101,
          rows: second
              ? [_row('s-100', const {})]
              : [for (var i = 0; i < 100; i++) _row('s-$i', const {})],
        );
      });

      final found = await rows.find('sections', const {'war_id': 'w-1'});

      expect(found, hasLength(101));
      expect(found.last.id, 's-100');
      final pages = verify(
        () => tables.listRows(
          databaseId: 'hawkbee',
          tableId: 'sections',
          queries: captureAny(named: 'queries'),
        ),
      ).captured.cast<List<String>>();
      expect(pages.first, [
        Query.equal('war_id', 'w-1'),
        Query.limit(AppwriteRows.pageSize),
      ]);
      expect(pages.last.last, Query.cursorAfter('s-99'));
    });
  });

  group(AppwriteAdmins, () {
    test('decision 161 an admin has the label admin', () async {
      final users = _MockUsers();
      final admin = _MockUser();
      final player = _MockUser();
      when(() => admin.labels).thenReturn(['admin']);
      when(() => player.labels).thenReturn(['beta']);
      when(() => users.get(userId: 'a')).thenAnswer((_) async => admin);
      when(() => users.get(userId: 'p')).thenAnswer((_) async => player);

      expect(await AppwriteAdmins(users).isAdmin('a'), isTrue);
      expect(await AppwriteAdmins(users).isAdmin('p'), isFalse);
    });
  });

  group(Refused, () {
    test('a refusal of the rules core is its name in snake case', () {
      final refused = Refused.rule(_Reason.alreadyInWar);

      expect(refused.code, 'already_in_war');
      expect(refused.status, 409);
      expect(refused.toString(), 'refused: already_in_war');
      expect(Refused.unknown('war').status, 404);
      expect(Refused.notAdmin.status, 403);
    });

    test('rows in memory are found by their columns', () async {
      final rows = MemoryRows();
      await rows.put('t', 'a', const {'k': 1});
      await rows.put('t', 'b', const {'k': 2});

      expect((await rows.find('t', const {'k': 2})).single.id, 'b');
      expect(await rows.find('u', const {}), isEmpty);
    });
  });
}

enum _Reason { alreadyInWar }
