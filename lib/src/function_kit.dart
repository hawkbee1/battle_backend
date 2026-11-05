// The Open Runtimes Dart executor passes [serve] an untyped `context`.
// ignore_for_file: avoid_dynamic_calls
import 'package:battle_backend/src/refused.dart';
import 'package:dart_appwrite/dart_appwrite.dart';

/// A JSON object of an answer.
typedef Json = Map<String, Object?>;

/// The answer of [run] in a function: its value with 200, a [Refused] with
/// its status and code, a body without what it needs with 400.
Future<(int, Json)> answer(Future<Json> Function() run) async {
  try {
    return (200, await run());
  } on Refused catch (refused) {
    return (refused.status, {'error': refused.code});
  }
}

/// The text field [key] of [body].
///
/// Throws a [Refused] with 400 when there is none.
String textOf(Object? body, String key) => switch (_field(body, key)) {
  final String value => value,
  _ => throw Refused('no_$key', status: 400),
};

/// The whole number field [key] of [body], or null when there is none.
int? integerOf(Object? body, String key) => switch (_field(body, key)) {
  final int value => value,
  _ => null,
};

Object? _field(Object? body, String key) =>
    body is Map<String, Object?> ? body[key] : null;

/// The account that executes, from the header Appwrite sets for a signed-in
/// user.
///
/// Throws a [Refused] with 401 for an execution of nobody.
String callerOf(Map<String, Object?> headers) => switch (headers) {
  {'x-appwrite-user-id': final String id} when id.isNotEmpty => id,
  _ => throw const Refused('not_signed_in', status: 401),
};

/// A server client on the project of [environment], an execution's
/// environment, with its API key [key]. Appwrite sets the endpoint and the
/// project of a function's execution; anywhere else, a test, it is the
/// local endpoint and no project.
Client serverClient(Map<String, String> environment, String key) => Client()
    .setEndpoint(
      environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? 'http://localhost/v1',
    )
    .setProject(environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '')
    .setKey(key);

/// {@template execution}
/// What a function is asked: by [caller], with [body], and the server
/// [client] of its project.
/// {@endtemplate}
final class Execution {
  /// {@macro execution}
  const new({required this.caller, required this.body, required this.client});

  /// The signed-in account that executes; empty for an event or a
  /// schedule.
  final String caller;

  /// The JSON body.
  final Object? body;

  /// A server client with the execution's API key.
  final Client client;
}

/// Serves the execution of [context], an Open Runtimes context, on the
/// project of [environment] (Adapter, stack decision 8): [run] answers it,
/// as JSON. Only a signed-in user may execute, unless [anyone] may: an
/// event or a schedule.
Future<dynamic> serve(
  dynamic context,
  Map<String, String> environment,
  Future<Json> Function(Execution execution) run, {
  bool anyone = false,
}) async {
  final request = context.req;
  final headers = Map<String, Object?>.from(request.headers as Map);
  final (status, body) = await answer(
    () => run(
      Execution(
        caller: anyone
            ? headers['x-appwrite-user-id'] as String? ?? ''
            : callerOf(headers),
        body: request.bodyJson,
        client: serverClient(
          environment,
          headers['x-appwrite-key'] as String? ?? '',
        ),
      ),
    ),
  );
  context.log('$status $body');
  return context.res.json(body, status);
}
