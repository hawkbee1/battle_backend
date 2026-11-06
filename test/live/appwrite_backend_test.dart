@Tags(['appwrite', 'skip_very_good_optimization'])
library;

import 'dart:io';

import 'package:battle_backend/battle_backend.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';
import 'package:test/test.dart';

import '../helpers/backend.dart';

/// The lifecycle of a war on the local Appwrite, in the tables of
/// `backend/appwrite.config.json` (stack decision 8): pushed first with
/// `melos run backend:deploy` or `appwrite push tables`.
void main() {
  final environment = Platform.environment;
  final client = Client()
      .setEndpoint(
        environment['APPWRITE_ENDPOINT'] ?? 'http://appwrite-traefik/v1',
      )
      .setProject(environment['APPWRITE_PROJECT_ID'] ?? 'hawkbee')
      .setKey(environment['APPWRITE_API_KEY'] ?? '');
  final rows = AppwriteRows(TablesDB(client));
  // The rows stay in the tables: each run takes IDs of its own.
  final run = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final wars = Wars(rows: rows, admins: FakeAdmins(), data: planData());

  test('SOC-16 SOC-17 UNIT-30 a war created, a battle set up, ended and '
      'carried over to the next', () async {
    final warId = 'w$run';
    await wars.create(caller: 'admin', warId: warId);
    final section = await wars.join(caller: 'p$run', warId: warId);
    for (final battle in ['b1$run', 'b2$run']) {
      await wars.plan(
        caller: 'admin',
        warId: warId,
        battleId: battle,
        mapId: 'valley',
        seed: 1,
      );
    }
    final running = await wars.start(caller: 'admin', battleId: 'b1$run');
    await rows.put(
      AppwriteIds.battlesTableId,
      running.id,
      BattleRow(
        id: running.id,
        warId: warId,
        mapId: running.mapId,
        seed: running.seed,
        status: BattleStatus.ended,
        teams: running.teams,
        winner: 'team-1',
        result: BattleResult(
          winner: 'team-1',
          sections: {section.id: const KeptSection(money: 777, xp: 12)},
        ),
      ).toData(),
    );

    expect(await wars.end(running.id), isTrue);

    final war = await wars.war(warId);
    expect(war.current, isNull);
    expect(war.planned, ['b2$run']);
    final kept = SectionRow.fromData(
      section.id,
      (await rows.get(AppwriteIds.sectionsTableId, section.id))!,
    ).kept;
    expect(kept.money, 777);
    expect(
      (await wars.start(caller: 'admin', battleId: 'b2$run')).status,
      BattleStatus.running,
    );
  });

  test('AI-04 decision 161 a revoked key is refused at once', () async {
    final keys = ApiKeys(rows: rows, admins: FakeAdmins());
    final key = await keys.create(caller: 'k$run');
    expect(await keys.accountOf(key), 'k$run');

    await keys.revoke(caller: 'k$run', accountId: 'k$run');

    expect(await keys.accountOf(key), isNull);
  });
}
