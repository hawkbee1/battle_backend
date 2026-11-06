import 'package:battle_backend/battle_backend.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';
import 'package:test/test.dart';

import '../helpers/backend.dart';

void main() {
  late Backend b;
  late String chief;
  late String other;

  setUp(() async {
    b = Backend();
    await b.wars.create(caller: 'admin', warId: 'w-1');
    chief = (await b.wars.join(caller: 'p-1', warId: 'w-1')).id;
    other = (await b.wars.join(caller: 'p-2', warId: 'w-1')).id;
    await b.raise(chief, 30000);
  });

  Future<GuildRow?> ask(
    GuildAction action, {
    String caller = 'p-1',
    String? section,
    String guildId = 'g-1',
    String? about,
  }) => b.guilds.request(
    caller: caller,
    action: action,
    sectionId: section ?? chief,
    guildId: guildId,
    other: about,
  );

  group('SOC-46 to SOC-50 guild requests between battles', () {
    test(
      'a section creates a guild; another applies and is accepted',
      () async {
        final created = (await ask(GuildAction.create))!;
        expect(created.roles, {chief: 'chief'});
        expect((await b.section(chief)).guildId, 'g-1');

        await ask(GuildAction.apply, caller: 'p-2', section: other);
        expect((await b.section(other)).guildId, 'g-1');
        final accepted = (await ask(GuildAction.accept, about: other))!;
        expect(accepted.roles, {chief: 'chief', other: 'member'});

        final handed = (await ask(GuildAction.handOver, about: other))!;
        expect(handed.roles, {chief: 'member', other: 'chief'});
      },
    );

    test(
      'a refused trainee and a member who leaves are out of the guild',
      () async {
        await ask(GuildAction.create);
        await ask(GuildAction.apply, caller: 'p-2', section: other);
        await ask(GuildAction.refuse, about: other);
        expect((await b.section(other)).guildId, isNull);

        await ask(GuildAction.apply, caller: 'p-2', section: other);
        await ask(GuildAction.accept, about: other);
        await ask(GuildAction.leave, caller: 'p-2', section: other);
        expect((await b.section(other)).guildId, isNull);
      },
    );

    test('decision 215 the chief opts in and out; disbanding frees every '
        'section', () async {
      await ask(GuildAction.create);
      expect((await ask(GuildAction.optIn))!.optedIn, isTrue);
      expect((await ask(GuildAction.optOut))!.optedIn, isFalse);
      await ask(GuildAction.apply, caller: 'p-2', section: other);

      expect(await ask(GuildAction.disband), isNull);
      expect(await b.rows.get(AppwriteIds.guildsTableId, 'g-1'), isNull);
      expect((await b.section(chief)).guildId, isNull);
      expect((await b.section(other)).guildId, isNull);
    });

    test('refuses what the rules refuse', () async {
      expect(
        () => ask(GuildAction.create, caller: 'p-2', section: other),
        refusedWith('level_too_low'),
      );
      await ask(GuildAction.create);
      expect(() => ask(GuildAction.leave), refusedWith('chief_cannot_leave'));
      expect(() => ask(GuildAction.create), refusedWith('guild_exists'));
      expect(
        () => ask(GuildAction.apply, guildId: 'g-9'),
        refusedWith('unknown_guild'),
      );
      expect(() => ask(GuildAction.accept), refusedWith('no_section_named'));
      expect(
        () => ask(GuildAction.apply, section: other),
        refusedWith('not_your_section'),
      );
      expect(
        () => ask(GuildAction.apply, section: 's-9'),
        refusedWith('unknown_section'),
      );
    });

    test('waits for the end of a battle', () async {
      await b.wars.plan(
        caller: 'admin',
        warId: 'w-1',
        battleId: 'b-1',
        mapId: 'valley',
        seed: 1,
      );
      await b.wars.start(caller: 'admin', battleId: 'b-1');

      expect(() => ask(GuildAction.create), refusedWith('battle_running'));
    });
  });
}
