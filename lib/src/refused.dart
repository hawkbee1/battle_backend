/// {@template refused}
/// A request the rules or the caller's rights refuse: its [code], and the
/// HTTP [status] a function answers it with.
/// {@endtemplate}
final class Refused implements Exception {
  /// {@macro refused}
  const new(this.code, {this.status = 409});

  /// A refusal of [what], which does not exist.
  factory unknown(String what) => Refused('unknown_$what', status: 404);

  /// A refusal of the rules core, as a code: `alreadyInWar` gives
  /// `already_in_war`.
  factory rule(Enum reason) => Refused(
    reason.name.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match[0]!.toLowerCase()}',
    ),
  );

  /// The caller is not an admin.
  static const notAdmin = Refused('not_admin', status: 403);

  /// Why, as a code.
  final String code;

  /// The HTTP status.
  final int status;

  @override
  String toString() => 'refused: $code';
}
