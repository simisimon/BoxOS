// Plugin-free "open this link". On web the current tab navigates to the URL
// (used for Stripe onboarding, which sends the owner back to the app); other
// platforms fall back to the stub, and callers copy the link instead.
export 'open_external_url_stub.dart'
    if (dart.library.js_interop) 'open_external_url_web.dart';
