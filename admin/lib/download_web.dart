import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void saveDocument(Uint8List bytes, String contentType, String kind) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: contentType),
  );
  final url = web.URL.createObjectURL(blob);
  final extension = contentType == 'application/pdf'
      ? 'pdf'
      : contentType == 'image/png'
      ? 'png'
      : 'jpg';
  (web.HTMLAnchorElement()
        ..href = url
        ..download = '$kind.$extension')
      .click();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
