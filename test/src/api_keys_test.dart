import 'dart:math';

import 'package:battle_backend/battle_backend.dart';
import 'package:test/test.dart';

import '../helpers/backend.dart';

void main() {
  group('AI-04 decisions 158 161 API keys', () {
    late ApiKeys keys;

    setUp(
      () => keys = ApiKeys(
        rows: MemoryRows(),
        admins: FakeAdmins(),
        random: Random(1),
      ),
    );

    test('a key is shown once and signs in as its account', () async {
      final key = await keys.create(caller: 'p-1');

      expect(key, startsWith('btk_'));
      expect(await keys.accountOf(key), 'p-1');
      expect(await keys.accountOf('btk_not-a-key'), isNull);
      expect(await keys.accountOf('nothing'), isNull);
    });

    test('keys are drawn with a secure random by default', () async {
      final secure = ApiKeys(rows: MemoryRows(), admins: FakeAdmins());

      expect(
        await secure.create(caller: 'p-1'),
        isNot(await secure.create(caller: 'p-1')),
      );
    });

    test('a new key replaces the previous one', () async {
      final first = await keys.create(caller: 'p-1');
      final second = await keys.create(caller: 'p-1');

      expect(await keys.accountOf(first), isNull);
      expect(await keys.accountOf(second), 'p-1');
    });

    test('a revoked key is refused at once', () async {
      final key = await keys.create(caller: 'p-1');

      await keys.revoke(caller: 'p-1', accountId: 'p-1');

      expect(await keys.accountOf(key), isNull);
    });

    test('an admin revokes any key; another player none', () async {
      final key = await keys.create(caller: 'p-1');

      expect(
        () => keys.revoke(caller: 'p-2', accountId: 'p-1'),
        refusedWith('not_admin'),
      );
      expect(
        () => keys.revoke(caller: 'admin', accountId: 'p-9'),
        refusedWith('unknown_key'),
      );
      await keys.revoke(caller: 'admin', accountId: 'p-1');
      expect(await keys.accountOf(key), isNull);
    });
  });
}
