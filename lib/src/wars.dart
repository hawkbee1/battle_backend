import 'dart:convert';

import 'package:battle_backend/src/appwrite_rows.dart';
import 'package:battle_backend/src/refused.dart';
import 'package:battle_backend/src/rows.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:crypto/crypto.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';

/// The ID of the section of [accountId] in [warId]: the same each time,
/// and short enough for a row ID.
String sectionIdOf(String warId, String accountId) =>
    's${sha256.convert(utf8.encode(jsonEncode([warId, accountId])))}'.substring(
      0,
      32,
    );

/// {@template wars}
/// Wars and their battles (SOC-16 to SOC-20, SOC-30; stack decision 8),
/// on the tables of the Hawkbee database:
/// - an admin creates a war, plans its battles in order and starts the
///   next one: its teams are formed from the war's sections, balanced by
///   power with each guild kept together (SOC-20, decision 103);
/// - a player joins a war: a new section with the war's starting money and
///   its commander; during a battle it joins the weakest team (SOC-02,
///   SOC-30);
/// - when the host has ended a battle with its result, the sections keep
///   what they had at its end (UNIT-30), the guilds earn what their
///   sections earned (SOC-47), and the war goes on, or ends when nothing
///   else is planned (SOC-17).
/// {@endtemplate}
final class Wars {
  /// {@macro wars}
  new({required this.rows, required this.admins, required this.data})
    : _teams = TeamRules(battle: data.battle, medals: data.medals),
      _guilds = GuildRules(data.units.progression);

  /// The tables.
  final Rows rows;

  /// Who is an admin.
  final Admins admins;

  /// The plan's data.
  final GameData data;

  final TeamRules _teams;
  final GuildRules _guilds;

  Future<void> _admin(String caller) async {
    if (!await admins.isAdmin(caller)) throw Refused.notAdmin;
  }

  /// The war [warId].
  Future<WarRow> war(String warId) async => WarRow.fromData(
    warId,
    await rows.get(AppwriteIds.warsTableId, warId) ??
        (throw Refused.unknown('war')),
  );

  /// The battle [battleId].
  Future<BattleRow> battle(String battleId) async => BattleRow.fromData(
    battleId,
    await rows.get(AppwriteIds.battlesTableId, battleId) ??
        (throw Refused.unknown('battle')),
  );

  Future<List<SectionRow>> _sections(String warId) async => [
    for (final row in await rows.find(AppwriteIds.sectionsTableId, {
      'war_id': warId,
    }))
      SectionRow.fromData(row.id, row.data),
  ];

  Future<void> _putWar(War war) => rows.put(
    AppwriteIds.warsTableId,
    war.id,
    WarRow(
      id: war.id,
      minStartingMoney: war.minStartingMoney,
      planned: war.planned,
      current: war.current,
      sections: war.sections,
      over: war.over,
    ).toData(),
  );

  static War _rules(WarRow row) => War(
    id: row.id,
    minStartingMoney: row.minStartingMoney,
    planned: row.planned,
    current: row.current,
    sections: row.sections,
    over: row.over,
  );

  static War _changed(WarChange change) => switch (change) {
    WarChanged(:final war) => war,
    WarRefused(:final reason) => throw Refused.rule(reason),
  };

  double _power(SectionRow section) => _teams.sectionPower(
    sectionXp: section.kept.xp,
    units: [
      for (final unit in section.kept.units)
        UnitXp(earned: unit.xpEarned, unspent: unit.xpUnspent),
    ],
  );

  /// [caller], an admin, creates the war [warId], whose sections start
  /// with [minStartingMoney] w€, the plan's floor by default (SOC-10).
  Future<WarRow> create({
    required String caller,
    required String warId,
    int? minStartingMoney,
  }) async {
    await _admin(caller);
    if (await rows.get(AppwriteIds.warsTableId, warId) != null) {
      throw const Refused('war_exists');
    }
    final war = War(
      id: warId,
      minStartingMoney: minStartingMoney ?? data.economy.minStartingMoney,
    );
    await _putWar(war);
    return await this.war(warId);
  }

  /// [caller], a player, joins the war [warId] with a new section: the
  /// war's starting money and a commander (SOC-15, SOC-30). During a
  /// battle, the section joins its weakest team, a tie drawn with a random
  /// of the battle's seed (SOC-02, decision 211).
  Future<SectionRow> join({
    required String caller,
    required String warId,
  }) async {
    final row = await war(warId);
    final sectionId = sectionIdOf(warId, caller);
    final joined = _changed(
      _rules(row).join(playerId: caller, sectionId: sectionId),
    );
    final section = SectionRow(
      id: sectionId,
      warId: warId,
      accountId: caller,
      kept: KeptSection(
        money: row.minStartingMoney,
        xp: 0,
        units: [KeptUnit(id: '$sectionId-commander', type: 'commander')],
      ),
    );
    await rows.put(AppwriteIds.sectionsTableId, sectionId, section.toData());
    await _putWar(joined);
    if (row.current case final current?) {
      final running = await battle(current);
      final powers = {
        for (final MapEntry(key: team, value: ids) in running.teams.entries)
          team: [
            for (final other in await _sections(warId))
              if (ids.contains(other.id)) _power(other),
          ].fold<double>(0, (sum, power) => sum + power),
      };
      final team = _teams.newcomerTeam(
        powers,
        XorshiftRandom(
          running.seed + running.teams.values.expand((t) => t).length,
        ),
      );
      await rows.put(
        AppwriteIds.battlesTableId,
        current,
        running
            .copyWith(
              teams: {
                ...running.teams,
                team: [...running.teams[team]!, sectionId],
              },
            )
            .toData(),
      );
    }
    return section;
  }

  /// [caller], an admin, plans the battle [battleId] of the war [warId] on
  /// [mapId], with the random of [seed], after the others (SOC-16).
  Future<BattleRow> plan({
    required String caller,
    required String warId,
    required String battleId,
    required String mapId,
    required int seed,
  }) async {
    await _admin(caller);
    if (await rows.get(AppwriteIds.battlesTableId, battleId) != null) {
      throw const Refused('battle_exists');
    }
    final planned = _changed(_rules(await war(warId)).plan(battleId));
    final battle = BattleRow(
      id: battleId,
      warId: warId,
      mapId: mapId,
      seed: seed,
    );
    await rows.put(AppwriteIds.battlesTableId, battleId, battle.toData());
    await _putWar(planned);
    return battle;
  }

  /// [caller], an admin, starts the battle [battleId], the next planned of
  /// its war: its teams are the war's sections balanced by power, each
  /// guild together (SOC-20, decision 103). The host then runs it.
  Future<BattleRow> start({
    required String caller,
    required String battleId,
  }) async {
    await _admin(caller);
    final planned = await battle(battleId);
    final row = await war(planned.warId);
    if (row.planned.firstOrNull != battleId) {
      throw const Refused('not_next');
    }
    final started = _changed(_rules(row).startBattle());
    final teams = _teams.formTeams([
      for (final section in await _sections(row.id))
        TeamSection(
          sectionId: section.id,
          power: _power(section),
          guildId: section.guildId,
        ),
    ]);
    final running = planned.copyWith(
      status: BattleStatus.running,
      teams: {
        for (final (index, team) in teams.indexed) 'team-${index + 1}': team,
      },
    );
    await rows.put(AppwriteIds.battlesTableId, battleId, running.toData());
    await _putWar(started);
    return running;
  }

  /// Carries over the battle [battleId], which its host ended with its
  /// result: each section keeps what it had at its end (UNIT-30), each
  /// guild earns what its sections earned in it (SOC-47), and the war goes
  /// on to its next battle, or ends (SOC-17). A battle already carried
  /// over, or not ended, changes nothing: the answer is false.
  Future<bool> end(String battleId) async {
    final ended = await battle(battleId);
    final result = ended.result;
    if (ended.status != BattleStatus.ended || result == null) return false;
    final sections = await _sections(ended.warId);
    final earned = <String, double>{};
    for (final section in sections) {
      final kept = result.sections[section.id];
      if (kept == null) continue;
      await rows.put(
        AppwriteIds.sectionsTableId,
        section.id,
        section.copyWith(kept: kept).toData(),
      );
      if (section.guildId case final guild?) {
        earned[guild] = (earned[guild] ?? 0) + (result.earned[section.id] ?? 0);
      }
    }
    for (final MapEntry(key: guildId, value: xp) in earned.entries) {
      final row = GuildRow.fromData(
        guildId,
        (await rows.get(AppwriteIds.guildsTableId, guildId))!,
      );
      final guild = _guilds.earned(guildOf(row), xp);
      await rows.put(
        AppwriteIds.guildsTableId,
        guildId,
        GuildRow(
          id: guildId,
          warId: row.warId,
          roles: row.roles,
          xp: guild.xp,
          optedIn: row.optedIn,
        ).toData(),
      );
    }
    await _putWar(_changed(_rules(await war(ended.warId)).endBattle()));
    await rows.put(
      AppwriteIds.battlesTableId,
      battleId,
      ended.copyWith(status: BattleStatus.closed).toData(),
    );
    return true;
  }
}

/// The rules core's guild of [row].
Guild guildOf(GuildRow row) => Guild(
  id: row.id,
  roles: {
    for (final MapEntry(key: section, value: role) in row.roles.entries)
      section: GuildRole.values.byName(role),
  },
  xp: row.xp,
  optedIn: row.optedIn,
);
