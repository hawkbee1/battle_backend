import 'dart:math';

import 'package:battle_backend/battle_backend.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';
import 'package:test/test.dart';

import '../helpers/backend.dart';

void main() {
  group('M6 Issue 6 the host of a battle', () {
    late MemoryRows rows;
    late ApiKeys keys;
    late BattleHosts hosts;

    Future<void> battle({
      BattleStatus status = BattleStatus.running,
      String? host = 'host-a',
    }) => rows.put(
      AppwriteIds.battlesTableId,
      'b-1',
      BattleRow(
        id: 'b-1',
        warId: 'w-1',
        mapId: 'saint_lo',
        seed: 1,
        status: status,
        teams: const {
          't-1': ['s-1'],
          't-2': ['s-2'],
        },
        host: host,
      ).toData(),
    );

    Future<void> section(String id, String warId, String accountId) => rows.put(
      AppwriteIds.sectionsTableId,
      id,
      SectionRow(
        id: id,
        warId: warId,
        accountId: accountId,
        kept: const KeptSection(money: 0, xp: 0),
      ).toData(),
    );

    setUp(() async {
      rows = MemoryRows();
      keys = ApiKeys(rows: rows, admins: FakeAdmins(), random: Random(1));
      hosts = BattleHosts(rows: rows, keys: keys);
      await battle();
      await section('s-1', 'w-1', 'p-1');
      await section('s-2', 'w-1', 'p-2');
      // In the war, not in the battle.
      await section('s-3', 'w-1', 'p-3');
      // In another war.
      await section('s-4', 'w-2', 'p-4');
      await rows.put(
        AppwriteIds.hostsTableId,
        'host-a',
        HostRow(
          address: 'https://h1.example',
          seenAt: DateTime.utc(2026, 11, 8),
        ).toData(),
      );
    });

    test('a player of the battle gets its host address', () async {
      expect(
        await hosts.addressOf(battleId: 'b-1', caller: 'p-1'),
        'https://h1.example',
      );
      expect(
        await hosts.addressOf(battleId: 'b-1', caller: 'p-2'),
        'https://h1.example',
      );
    });

    test('AI-04 an agent gets it with its API key', () async {
      final key = await keys.create(caller: 'p-2');

      expect(
        await hosts.addressOf(battleId: 'b-1', caller: '', key: key),
        'https://h1.example',
      );
    });

    test('nobody else gets it', () async {
      final other = await keys.create(caller: 'p-4');

      for (final (caller, key, code) in [
        ('', null, 'not_signed_in'),
        ('', 'btk_not-a-key', 'not_signed_in'),
        ('p-3', null, 'not_your_battle'),
        ('p-4', null, 'not_your_battle'),
        ('', other, 'not_your_battle'),
      ]) {
        expect(
          () => hosts.addressOf(battleId: 'b-1', caller: caller, key: key),
          refusedWith(code),
        );
      }
      expect(
        () => hosts.addressOf(battleId: 'b-9', caller: 'p-1'),
        refusedWith('unknown_battle'),
      );
    });

    test('a battle planned or over has no host to reach', () async {
      for (final status in [BattleStatus.planned, BattleStatus.ended]) {
        await battle(status: status);

        expect(
          () => hosts.addressOf(battleId: 'b-1', caller: 'p-1'),
          refusedWith('not_running'),
        );
      }
    });

    test('a battle no host runs now is asked for again later', () async {
      await battle(host: null);

      expect(
        () => hosts.addressOf(battleId: 'b-1', caller: 'p-1'),
        throwsA(
          isA<Refused>()
              .having((refused) => refused.code, 'code', 'no_host')
              .having((refused) => refused.status, 'status', 503),
        ),
      );

      await battle(host: 'host-gone');

      expect(
        () => hosts.addressOf(battleId: 'b-1', caller: 'p-1'),
        refusedWith('no_host'),
      );
    });
  });
}
