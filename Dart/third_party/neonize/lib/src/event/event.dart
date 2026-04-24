import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart' as pb;
import 'package:neonize/src/event/type.dart';
import 'package:neonize/src/logging.dart';


typedef EventHandler<T extends pb.GeneratedMessage> =
    void Function(T message);
typedef QREvent = void Function(String qrData);
typedef Emit = void Function(int key, Pointer<UnsignedChar> data, int size);

class Event {
  Map<int, EventHandler<pb.GeneratedMessage>> callback = {};
  QREvent qrEvent = (String qrData) {};
  void on<T extends pb.GeneratedMessage>(EventHandler<T> callbackFunction) {
    log.fine('Registering callback for ${T.toString()}');
    final typeId = typeToIntMap[T];
    if (typeId != null) {
      callback[typeId] = (pb.GeneratedMessage message) {
        callbackFunction(message as T);
      };
    } else {
      throw Exception('Unknown event type: ${T.toString()}');
    }
  }


  void onRawQr(Pointer<Char> uuid, Pointer<Char> qrDataPointer) {
    String qrData = qrDataPointer.cast<Utf8>().toDartString();
    qrEvent(qrData);
  }

  void qr(QREvent callbackFunction) {
    qrEvent = (String qrData) {
      callbackFunction(qrData);
    };
  }

  Uint8List getSubscriber() {
    return Uint8List.fromList(
      callback.keys.map((key) => key.toUnsigned(8)).toList(),
    );
  }

  void rawEmit(
    Pointer<Char> uuid,
    Pointer<UnsignedChar> dataPointer,
    int size,
    int code,
  ) {
    if (size < 0) return;
    // Copia inmediata: con NativeCallable.listener el callback es asíncrono
    // y el buffer C podría liberarse antes de que corra el isolate.
    final data = Uint8List.fromList(
      dataPointer.cast<Uint8>().asTypedList(size),
    );
    emit(code, data);
  }

  void onLogginStatus(Pointer<Char> uuid, Pointer<Char> data) {
    final status = data.cast<Utf8>().toDartString();
    stdout.writeln(status);
    if (status.toLowerCase().contains('timeout')) {
      stderr.writeln('');
      stderr.writeln(
        'Neonize: el intento de login caduco (no se completo el QR a tiempo o fallo la conexion).',
      );
      stderr.writeln(
        '  Cierra otros dart.exe, borra la carpeta data/ del proyecto, revisa red/VPN y reintenta.',
      );
      stderr.writeln(
        '  Para mas detalle en Dart: NEONIZE_LOG_LEVEL=DEBUG (y revisa tambien la salida nativa).',
      );
    }
  }

  void blockingFunctionCallback(Pointer<Char> uuid, bool data) {
    // completerEvent.future;
  }
  void emit(int key, Uint8List data) {
    log.info("Emitting event with key: $key, data size: ${data.length}");

    // print("data: $data");
    pb.GeneratedMessage message;

    final builder = intToTypeMap[key];
    if (builder != null) {
      message = builder(data);
      log.info("Message created: $message");
    } else {
      throw Exception('Unsupported proto type key: $key');
    }
    callback[key]?.call(message);
  }
}
