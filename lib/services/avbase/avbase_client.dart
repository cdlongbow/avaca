import '../http_safety.dart';
import 'avbase_html_parser.dart';
import 'avbase_models.dart';
import 'avbase_transport.dart';

final class AvBaseClient {
  AvBaseClient({
    required AvBaseTransport transport,
    AvBaseHtmlParser? parser,
    Uri? baseUri,
  }) : _transport = transport,
       _parser = parser ?? AvBaseHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://www.avbase.net/') {
    _validateNavigationUri(_baseUri);
  }

  final AvBaseTransport _transport;
  final AvBaseHtmlParser _parser;
  final Uri _baseUri;

  Future<AvBaseWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    final details = _parser.parseWorkPage(source, pageUri: uri);
    if (details.code.isEmpty) {
      throw AvBaseRequestException(
        uri,
        null,
        kind: AvBaseFailureKind.parserInvalid,
      );
    }
    return details;
  }

  Future<AvBaseWorkDetails> fetchWorkDetailsByCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Must not be empty.');
    }
    final searchUri = _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
        'works',
      ],
      queryParameters: {'q': trimmed},
    );
    return _fetchWorkDetailsBySearch(searchUri, trimmed);
  }

  Future<AvBaseWorkDetails> _fetchWorkDetailsBySearch(
    Uri searchUri,
    String code,
  ) async {
    final source = await _transport.get(searchUri);
    final uri = _parser.findWorkUriByCode(
      source,
      pageUri: searchUri,
      code: code,
    );
    if (uri == null) {
      throw AvBaseRequestException(
        searchUri,
        404,
        kind: AvBaseFailureKind.notFound,
      );
    }
    return fetchWorkDetails(uri);
  }

  void close() {
    final transport = _transport;
    if (transport is HttpAvBaseTransport) {
      transport.close();
    }
  }

  void _validateNavigationUri(Uri uri) {
    final expectedPort = _baseUri.hasPort ? _baseUri.port : 443;
    final actualPort = uri.hasPort ? uri.port : 443;
    if (_baseUri.scheme != 'https' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != _baseUri.host.toLowerCase() ||
        actualPort != expectedPort) {
      throw UnsafeHttpUriException(uri);
    }
  }
}
