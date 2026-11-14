/// Not wired outside the browser: returns false so the caller can copy the
/// text to the clipboard instead.
Future<bool> saveTextFile(
  String fileName,
  String text, {
  String mimeType = 'text/plain',
}) async => false;
