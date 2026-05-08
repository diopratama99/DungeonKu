import 'package:http/http.dart' as http;

/// Wraps an [http.Client] and injects the `ngrok-skip-browser-warning` header
/// on every outbound request.
///
/// Free `*.ngrok-free.dev` tunnels show a one-shot HTML interstitial the first
/// time a new client visits them — that warning page breaks JSON-only API
/// clients (e.g. `supabase_flutter` returns "failed to decode error response"
/// when it tries to parse `<html>...</html>` as JSON). Adding any value to
/// this header tells ngrok to skip the warning for the request.
///
/// Only meant for development. In production, point at a non-ngrok host.
class NgrokSkipClient extends http.BaseClient {
  NgrokSkipClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['ngrok-skip-browser-warning'] = '1';
    // Some ngrok edges also require a non-default User-Agent to bypass the
    // interstitial — set a benign one if the platform default is missing.
    request.headers.putIfAbsent('User-Agent', () => 'DungeonKuApp/0.1');
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
