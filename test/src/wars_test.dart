import 'package:battle_backend/battle_backend.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';
import 'package:test/test.dart';

import '../helpers/backend.dart';

void main() {
  late Backend b;

  setUp(() => b = Backend());

  Future<String> join(String account) async =>
      (await b.wars.join(caller: account, warId: 'w-1')).id;

  group('SOC-16 an admin', () {
    test("creates a war, whose sections start with the plan's floor", () async {
      final war = await b.wars.create(caller: 'admin', warId: 'w-1');

      expect(war.minStartingMoney, 500);
      expect(war.planned, isEmpty);
      expect(
        () => b.wars.create(caller: 'admin', warId: 'w-1'),
        refusedWith('war_exists'),
      );
      expect(
        () => b.wars.create(caller: 'p-1', warId: 'w-2'),
        refusedWith('not_admin'),
      );
      expect(
        (await b.wars.create(
          caller: 'admin',
          warId: 'w-3',
          minStartingMoney: 900,
        )).minStartingMoney,
        900,
      );
    });

    test('COMBAT-02 UNIT-44 plans a testing battle with its own settings, '
        'and the others with none', () async {
      await b.wars.create(caller: 'admin', warId: 'w-1');
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 3,
        settings: {
          'ap': {'recovery_delay_s': 1},
          'test_units': true,
        },
      );
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-2',
        mapId: 'valley',
        seed: 4,
      );

      expect((await b.wars.battle('b-1')).settings, {
        'ap': {'recovery_delay_s': 1},
        'test_units': true,
      });
      expect((await b.wars.battle('b-2')).settings, isEmpty);
    });

    test('refuses settings the plan would refuse (decision 238)', () async {
      await b.wars.create(caller: 'admin', warId: 'w-1');

      for (final settings in <Map<String, Object?>>[
        {
          'ap': {'recovery_delay_s': 0},
        },
        {'recovery_delay_s': 1},
        {'test_units': 'yes'},
      ]) {
        expect(
          () => b.wars.plan(
            caller: 'admin',
            warId: 'w-1',
            battleId: 'b-1',
            mapId: 'valley',
            seed: 3,
            settings: settings,
          ),
          throwsA(
            isA<Refused>()
                .having((r) => r.code, 'code', 'bad_settings')
                .having((r) => r.status, 'status', 400),
          ),
        );
      }
      expect(await b.rows.get(AppwriteIds.battlesTableId, 'b-1'), isNull);
    });

    test('plans battles in order and starts the next one', () async {
      await b.wars.create(caller: 'admin', warId: 'w-1');
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 3,
      );
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-2',
        mapId: 'valley',
        seed: 4,
      );

      expect((await b.wars.war('w-1')).planned, ['b-1', 'b-2']);
      expect((await b.wars.battle('b-1')).status, BattleStatus.planned);
      expect(
        () => b.wars.plan(
          caller: 'admin',
          warId: 'w-1',
          battleId: 'b-1',
          mapId: 'valley',
          seed: 3,
        ),
        refusedWith('battle_exists'),
      );
      expect(
        () => b.wars.start(caller: 'admin', battleId: 'b-2'),
        refusedWith('not_next'),
      );
      expect(
        () => b.wars.start(caller: 'p-1', battleId: 'b-1'),
        refusedWith('not_admin'),
      );
      expect(
        () => b.wars.plan(
          caller: 'p-1',
          warId: 'w-1',
          battleId: 'b-3',
          mapId: 'valley',
          seed: 3,
        ),
        refusedWith('not_admin'),
      );

      final running = await b.wars.start(caller: 'admin', battleId: 'b-1');
      expect(running.status, BattleStatus.running);
      expect((await b.wars.war('w-1')).current, 'b-1');
      expect(() => b.wars.battle('b-9'), refusedWith('unknown_battle'));
    });

    test('SOC-20 decision 103 the teams of a battle are balanced by power, '
        'each guild together', () async {
      await b.wars.create(caller: 'admin', warId: 'w-1');
      final strong = await join('p-1');
      final weak = await join('p-2');
      final weaker = await join('p-3');
      await b.raise(strong, 1000);
      await b.raise(weak, 400);
      await b.raise(weaker, 300);
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 3,
      );

      final running = await b.wars.start(caller: 'admin', battleId: 'b-1');

      expect(running.teams['team-1'], [strong]);
      expect(running.teams['team-2'], unorderedEquals([weak, weaker]));
    });
  });

  group('SOC-15 SOC-30 a player joins a war', () {
    setUp(() => b.wars.create(caller: 'admin', warId: 'w-1'));

    test(
      "with a section of the war's starting money and a commander",
      () async {
        final section = await b.wars.join(caller: 'p-1', warId: 'w-1');

        expect(section.id, sectionIdOf('w-1', 'p-1'));
        expect(section.id, hasLength(32));
        expect(section.kept.money, 500);
        expect(section.kept.units.single.type, 'commander');
        expect((await b.wars.war('w-1')).sections, {'p-1': section.id});
        expect(await b.section(section.id), isA<SectionRow>());
        expect(
          () => b.wars.join(caller: 'p-1', warId: 'w-1'),
          refusedWith('already_in_war'),
        );
        expect(
          () => b.wars.join(caller: 'p-1', warId: 'w-9'),
          refusedWith('unknown_war'),
        );
      },
    );

    test('SOC-02 during a battle, into its weakest team', () async {
      final first = await join('p-1');
      await b.raise(first, 100);
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 3,
      );
      await b.wars.start(caller: 'admin', battleId: 'b-1');

      final late = await join('p-2');

      expect((await b.wars.battle('b-1')).teams, {
        'team-1': [first],
        'team-2': [late],
      });
    });

    test('SOC-02 newcomers with no XP spread over the teams', () async {
      final first = await join('p-1');
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 3,
      );
      await b.wars.start(caller: 'admin', battleId: 'b-1');

      final late = [for (var i = 2; i <= 5; i++) await join('p-$i')];

      final teams = (await b.wars.battle('b-1')).teams;
      expect(teams['team-1']!.length, inInclusiveRange(2, 3));
      expect(teams['team-2']!.length, inInclusiveRange(2, 3));
      expect([...teams['team-1']!, ...teams['team-2']!], hasLength(5));
      expect(late, everyElement(isNotEmpty));
    });
  });

  group('UNIT-30 SOC-17 the end of a battle', () {
    late String red;
    late String blue;

    setUp(() async {
      await b.wars.create(caller: 'admin', warId: 'w-1');
      red = await join('p-1');
      blue = await join('p-2');
      await b.raise(red, 30000);
      await b.guilds.request(
        caller: 'p-1',
        action: GuildAction.create,
        sectionId: red,
        guildId: 'g-1',
      );
      for (final battle in ['b-1', 'b-2']) {
        await b.wars.plan(
          caller: 'admin',
          warId: 'w-1',
          battleId: battle,
          mapId: 'valley',
          seed: 3,
        );
      }
      await b.wars.start(caller: 'admin', battleId: 'b-1');
    });

    Future<void> endWith(String battleId, BattleResult result) async {
      final running = await b.wars.battle(battleId);
      await b.rows.put(
        AppwriteIds.battlesTableId,
        battleId,
        BattleRow(
          id: battleId,
          warId: 'w-1',
          mapId: running.mapId,
          seed: running.seed,
          status: BattleStatus.ended,
          teams: running.teams,
          winner: result.winner,
          result: result,
        ).toData(),
      );
    }

    const kept = KeptSection(
      money: 1200,
      xp: 31000,
      units: [KeptUnit(id: 'u-1', type: 'soldier', xpEarned: 80)],
    );

    test('carries each section over, gives its guild what it earned, and '
        'goes on to the next battle', () async {
      expect(await b.wars.end('b-1'), isFalse);
      await endWith(
        'b-1',
        BattleResult(
          winner: 'team-1',
          sections: {red: kept},
          earned: {red: 80, blue: 5},
        ),
      );

      expect(await b.wars.end('b-1'), isTrue);

      expect((await b.section(red)).kept.toJson(), kept.toJson());
      expect((await b.section(blue)).kept.money, 500);
      final guild = GuildRow.fromData(
        'g-1',
        (await b.rows.get(AppwriteIds.guildsTableId, 'g-1'))!,
      );
      expect(guild.xp, 80);
      final war = await b.wars.war('w-1');
      expect(war.current, isNull);
      expect(war.planned, ['b-2']);
      expect(war.over, isFalse);
      expect((await b.wars.battle('b-1')).status, BattleStatus.closed);
      expect(await b.wars.end('b-1'), isFalse);
    });

    test('ends the war when nothing else is planned', () async {
      await endWith('b-1', const BattleResult(winner: 'team-2', sections: {}));
      await b.wars.end('b-1');
      await b.wars.start(caller: 'admin', battleId: 'b-2');
      await endWith('b-2', const BattleResult(winner: 'team-2', sections: {}));

      await b.wars.end('b-2');

      expect((await b.wars.war('w-1')).over, isTrue);
      expect(
        () => b.wars.join(caller: 'p-3', warId: 'w-1'),
        refusedWith('war_over'),
      );
    });
  });
}
