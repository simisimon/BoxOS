// Non-web fallback: file upload isn't wired outside the browser, so callers
// should rely on pasting instead.
bool get canUploadCsv => false;

Future<String?> pickCsvFileContent() async => null;
