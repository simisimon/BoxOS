import 'package:dio/dio.dart';

String errorMessageFrom(Object error, {required String fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      // FastAPI puts the reason in `detail`; older endpoints used `message`.
      for (final key in const ['message', 'detail']) {
        final message = data[key];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
    }
    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!;
    }
  }

  return fallback;
}
