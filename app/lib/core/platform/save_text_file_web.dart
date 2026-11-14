import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves [text] as [fileName] through the browser's download.
Future<bool> saveTextFile(
  String fileName,
  String text, {
  String mimeType = 'text/plain',
}) async {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
