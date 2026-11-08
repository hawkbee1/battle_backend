import 'package:battle_backend/src/api_keys.dart';
import 'package:battle_backend/src/refused.dart';
import 'package:battle_backend/src/rows.dart';
import 'package:hawkbee_schema/hawkbee_schema.dart';

/// {@template battle_hosts}
/// Where a client finds the host of its battle (M6 Issue 6; stack
/// decisions 1 and 3): the address of the host named in the battle's row,
/// from that host's row in `hosts`.
///
/// Only a player of the battle gets it: an account with a section in one of
/// its teams, signed in to Appwrite (a JWT or a session) or with its API
/// key (AI-04). The `hosts` table grants no client any permission, so this
/// is the only way to it, and `battles` stays as it is.
/// {@endtemplate}
final class BattleHosts {
  /// {@macro battle_hosts}
  new({required this.rows, required this.keys});

  /// The tables.
  final Rows rows;

  /// The API keys, for agents that sign in with one.
  final ApiKeys keys;

  /// The public address of the host that runs [battleId], for [caller], the
  /// signed-in account (empty when none), or the account of [key].
  ///
  /// Throws a [Refused]: `not_signed_in` (401) with neither or with a key
  /// that is not one, `unknown_battle` (404), `not_your_battle` (403) for
  /// an account with no section in it, `not_running` (409) for a battle
  /// planned or over, and `no_host` (503) while no host runs it: the client
  /// asks again later.
  Future<String> addressOf({
    required String battleId,
    required String caller,
    String? key,
  }) async {
    final account = caller.isNotEmpty
        ? caller
        : key == null
        ? null
        : await keys.accountOf(key);
    if (account == null) throw notSignedIn;
    final data =
        await rows.get(AppwriteIds.battlesTableId, battleId) ??
        (throw Refused.unknown('battle'));
    final battle = BattleRow.fromData(battleId, data);
    final mine = await rows.find(AppwriteIds.sectionsTableId, {
      'war_id': battle.warId,
      'account_id': account,
    });
    final seated = {for (final ids in battle.teams.values) ...ids};
    if (!mine.any((section) => seated.contains(section.id))) {
      throw notYourBattle;
    }
    if (battle.status != BattleStatus.running) throw notRunning;
    final hostId = battle.host;
    final host = hostId == null
        ? null
        : await rows.get(AppwriteIds.hostsTableId, hostId);
    if (host == null) throw noHost;
    return HostRow.fromData(host).address;
  }

  /// Neither a signed-in account nor a key of one.
  static const notSignedIn = Refused('not_signed_in', status: 401);

  /// The account has no section in the battle.
  static const notYourBattle = Refused('not_your_battle', status: 403);

  /// The battle is planned or over.
  static const notRunning = Refused('not_running');

  /// No host runs the battle now.
  static const noHost = Refused('no_host', status: 503);
}
