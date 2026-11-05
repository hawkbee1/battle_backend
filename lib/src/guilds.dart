import 'package:battle_backend/src/refused.dart';
import 'package:battle_backend/src/rows.dart';
import 'package:battle_backend/src/wars.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';

/// A guild request (SOC-46 to SOC-50).
enum GuildAction {
  /// A section creates a guild and becomes its chief.
  create,

  /// A section applies to a guild as a trainee.
  apply,

  /// The chief accepts a trainee as a member.
  accept,

  /// The chief refuses a trainee.
  refuse,

  /// A member or a trainee leaves.
  leave,

  /// The chief hands the role to a member.
  handOver,

  /// The chief disbands the guild.
  disband,

  /// The chief puts the guild on the newcomer list.
  optIn,

  /// The chief takes it off.
  optOut,
}

/// {@template guilds}
/// Guild requests between battles (stack decision 8): during a battle the
/// host handles them. A player acts for their own section,
/// with the rules core's guild rules (SOC-46 to SOC-50, decisions 213 to
/// 215, 221); between battles a section may apply to any guild of its war.
/// {@endtemplate}
final class Guilds {
  /// {@macro guilds}
  new({required this.rows, required this.wars})
    : _rules = GuildRules(wars.data.units.progression),
      _levels = SectionLevel(wars.data.units.progression);

  /// The tables.
  final Rows rows;

  /// The wars, whose battles the requests wait for.
  final Wars wars;

  final GuildRules _rules;
  final SectionLevel _levels;

  /// The player [caller] makes the request [action] for their section
  /// [sectionId] on the guild [guildId]; [other] is the trainee or the
  /// member it is about, for [GuildAction.accept], [GuildAction.refuse]
  /// and [GuildAction.handOver]. Gives the guild after it, or null once
  /// disbanded.
  Future<GuildRow?> request({
    required String caller,
    required GuildAction action,
    required String sectionId,
    required String guildId,
    String? other,
  }) async {
    final section = SectionRow.fromData(
      sectionId,
      await rows.get(AppwriteIds.sectionsTableId, sectionId) ??
          (throw Refused.unknown('section')),
    );
    if (section.accountId != caller) {
      throw const Refused('not_your_section', status: 403);
    }
    if ((await wars.war(section.warId)).current != null) {
      throw const Refused('battle_running');
    }
    final stored = await rows.get(AppwriteIds.guildsTableId, guildId);
    if (action == GuildAction.create) {
      if (stored != null) throw const Refused('guild_exists');
    } else if (stored == null) {
      throw Refused.unknown('guild');
    }
    final guild = stored == null
        ? null
        : guildOf(GuildRow.fromData(guildId, stored));
    String about() => other ?? (throw const Refused('no_section_named'));
    final inGuild = section.guildId != null;
    final change = switch (action) {
      GuildAction.create => _rules.create(
        guildId: guildId,
        sectionId: sectionId,
        inGuild: inGuild,
        commanderLevel: _levels.levelFor(section.kept.xp),
      ),
      GuildAction.apply => _rules.apply(
        guild!,
        sectionId: sectionId,
        inGuild: inGuild,
        sameTeam: true,
      ),
      GuildAction.accept => _rules.accept(
        guild!,
        by: sectionId,
        trainee: about(),
      ),
      GuildAction.refuse => _rules.refuse(
        guild!,
        by: sectionId,
        trainee: about(),
      ),
      GuildAction.leave => _rules.leave(guild!, sectionId: sectionId),
      GuildAction.handOver => _rules.handOver(
        guild!,
        by: sectionId,
        to: about(),
      ),
      GuildAction.disband => _rules.disband(guild!, by: sectionId),
      GuildAction.optIn => _rules.optIn(guild!, by: sectionId, optedIn: true),
      GuildAction.optOut => _rules.optIn(guild!, by: sectionId, optedIn: false),
    };
    final after = switch (change) {
      GuildChanged(:final guild) => guild,
      GuildRefused(:final reason) => throw Refused.rule(reason),
    };
    final before = guild?.roles.keys.toSet() ?? const <String>{};
    final now = after?.roles.keys.toSet() ?? const <String>{};
    for (final id in {...before, ...now}) {
      if (before.contains(id) == now.contains(id)) continue;
      final member = SectionRow.fromData(
        id,
        (await rows.get(AppwriteIds.sectionsTableId, id))!,
      );
      await rows.put(
        AppwriteIds.sectionsTableId,
        id,
        member
            .copyWith(guildId: () => now.contains(id) ? guildId : null)
            .toData(),
      );
    }
    if (after == null) {
      await rows.delete(AppwriteIds.guildsTableId, guildId);
      return null;
    }
    final row = GuildRow(
      id: guildId,
      warId: section.warId,
      roles: {
        for (final MapEntry(key: id, value: role) in after.roles.entries)
          id: role.name,
      },
      xp: after.xp,
      optedIn: after.optedIn,
    );
    await rows.put(AppwriteIds.guildsTableId, guildId, row.toData());
    return row;
  }
}
