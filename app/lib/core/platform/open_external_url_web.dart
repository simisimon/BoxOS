import 'package:web/web.dart' as web;

/// Navigates the current tab to [url].
Future<bool> openExternalUrl(String url) async {
  web.window.location.href = url;
  return true;
}
