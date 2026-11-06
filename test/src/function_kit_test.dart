import 'package:battle_backend/battle_backend.dart';
import 'package:test/test.dart';

void main() {
  serveTests();
  group('the function kit', () {
    test('answers a value with 200 and a refusal with its status', () async {
      final (status, body) = await answer(() async => {'ok': 1});
      expect(status, 200);
      expect(body, {'ok': 1});
      final (refused, error) = await answer(
        () async => throw Refused.unknown('war'),
      );
      expect(refused, 404);
      expect(error, {'error': 'unknown_war'});
    });

    test('reads the fields of a body', () {
      expect(textOf({'warId': 'w'}, 'warId'), 'w');
      expect(
        () => textOf({'warId': 3}, 'warId'),
        throwsA(
          isA<Refused>()
              .having((r) => r.code, 'code', 'no_warId')
              .having((r) => r.status, 'status', 400),
        ),
      );
      expect(integerOf({'seed': 3}, 'seed'), 3);
      expect(integerOf(null, 'seed'), isNull);
    });

    test('knows the caller from the header of a signed-in user', () {
      expect(callerOf({'x-appwrite-user-id': 'p-1'}), 'p-1');
      for (final headers in [
        <String, Object?>{},
        {'x-appwrite-user-id': ''},
      ]) {
        expect(
          () => callerOf(headers),
          throwsA(isA<Refused>().having((r) => r.status, 'status', 401)),
        );
      }
    });

    test('makes a server client on the project of the execution', () {
      expect(
        serverClient(const {
          'APPWRITE_FUNCTION_API_ENDPOINT': 'http://appwrite.test/v1',
          'APPWRITE_FUNCTION_PROJECT_ID': 'hawkbee',
        }, 'key').endPoint,
        'http://appwrite.test/v1',
      );
      expect(serverClient(const {}, 'key').endPoint, 'http://localhost/v1');
    });
  });
}

class _Request {
  new(this.bodyJson, this.headers);

  final Object? bodyJson;
  final Map<String, String> headers;
}

class _Response {
  int? status;
  Object? body;

  Object json(Object data, int status) {
    this.status = status;
    return body = data;
  }
}

class _Context {
  new(Object? body, Map<String, String> headers)
    : req = _Request(body, headers);

  final _Request req;
  final res = _Response();
  final logs = <String>[];

  void log(String message) => logs.add(message);
}

const _environment = {
  'APPWRITE_FUNCTION_API_ENDPOINT': 'http://appwrite.test/v1',
  'APPWRITE_FUNCTION_PROJECT_ID': 'hawkbee',
};

void serveTests() {
  group(serve, () {
    test('runs the request of a signed-in user', () async {
      final context = _Context(
        {'n': 1},
        {'x-appwrite-user-id': 'p-1', 'x-appwrite-key': 'key'},
      );
      Execution? seen;

      await serve(context, _environment, (execution) async {
        seen = execution;
        return {'done': true};
      });

      expect(seen!.caller, 'p-1');
      expect(seen!.body, {'n': 1});
      expect(seen!.client.endPoint, 'http://appwrite.test/v1');
      expect(context.res.status, 200);
      expect(context.logs.single, '200 {done: true}');
    });

    test('answers 401 to nobody, unless anyone may execute', () async {
      final nobody = _Context(null, {});
      await serve(nobody, _environment, (_) async => {});
      expect(nobody.res.status, 401);

      final event = _Context(null, {});
      await serve(event, _environment, (execution) async {
        expect(execution.caller, isEmpty);
        return {};
      }, anyone: true);
      expect(event.res.status, 200);
    });
  });
}
