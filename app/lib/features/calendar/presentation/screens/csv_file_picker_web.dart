import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get canUploadCsv => true;

/// Opens the browser's file picker (restricted to .csv) and returns the file
/// contents as text, or null if the user cancels / the read fails.
Future<String?> pickCsvFileContent() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv';

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final result = reader.result;
      final text = (result != null && result.isA<JSString>())
          ? (result as JSString).toDart
          : null;
      if (!completer.isCompleted) completer.complete(text);
    }.toJS;
    reader.onerror = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;
    reader.readAsText(files.item(0)!);
  }.toJS;

  input.click();
  return completer.future;
}
