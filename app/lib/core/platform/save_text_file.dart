// Plugin-free "download this text as a file". On web the browser saves it;
// other platforms fall back to the stub, and callers copy the text instead.
export 'save_text_file_stub.dart'
    if (dart.library.js_interop) 'save_text_file_web.dart';
