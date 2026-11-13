import 'package:web/web.dart' as web;

/// Navigates the current tab to [url], or opens it in a new tab.
Future<bool> openExternalUrl(String url, {bool newTab = false}) async {
  if (newTab) {
    web.window.open(url, '_blank', 'noopener');
  } else {
    web.window.location.href = url;
  }
  return true;
}
