import 'dart:io';

import 'package:battle_backend/battle_backend.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';
import 'package:test/test.dart';

/// The plan's data, in the hawkbee checkout.
GameData planData() {
  String read(String path) =>
      File('../../apps/battle_team/plan/$path').readAsStringSync();
  return GameData.parse(
    units: read('data/units.yaml'),
    combat: read('data/combat.yaml'),
    terrain: read('data/terrain.yaml'),
    battle: read('data/battle.yaml'),
    economy: read('milestones/economy.yaml'),
    medals: read('data/medals.yaml'),
  );
}

/// The admins are [ids].
final class FakeAdmins implements Admins {
  new([this.ids = const {'admin'}]);

  final Set<String> ids;

  @override
  Future<bool> isAdmin(String accountId) async => ids.contains(accountId);
}

/// Wars on tables in memory.
final class Backend {
  final rows = MemoryRows();
  late final wars = Wars(rows: rows, admins: FakeAdmins(), data: planData());
  late final guilds = Guilds(rows: rows, wars: wars);

  /// The section [sectionId].
  Future<SectionRow> section(String sectionId) async => SectionRow.fromData(
    sectionId,
    (await rows.get(AppwriteIds.sectionsTableId, sectionId))!,
  );

  /// Gives the section [sectionId] [xp] section XP.
  Future<void> raise(String sectionId, double xp) async {
    final row = await section(sectionId);
    await rows.put(
      AppwriteIds.sectionsTableId,
      sectionId,
      row
          .copyWith(
            kept: KeptSection(
              money: row.kept.money,
              xp: xp,
              units: row.kept.units,
            ),
          )
          .toData(),
    );
  }
}

/// A matcher of a call that throws a [Refused] with [code].
Matcher refusedWith(String code) =>
    throwsA(isA<Refused>().having((refused) => refused.code, 'code', code));
