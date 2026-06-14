// Plugin-free CSV file picker. On web it uses the browser's native file input;
// other platforms fall back to the stub (paste only). Conditional export keeps
// the app compiling everywhere without a native file-picker plugin.
export 'csv_file_picker_stub.dart'
    if (dart.library.js_interop) 'csv_file_picker_web.dart';
