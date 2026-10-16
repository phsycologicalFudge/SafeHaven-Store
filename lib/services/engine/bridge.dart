import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safehaven/services/store_service/store_config.dart';
import 'package:safehaven/services/store_service/store_exceptions.dart';

typedef _InitNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _InitFn = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CallNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CallFn = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeFn = void Function(Pointer<Utf8>);

class _Native {
  _Native._(DynamicLibrary lib)
      : _init = lib.lookupFunction<_InitNative, _InitFn>('sh_init'),
        _call = lib.lookupFunction<_CallNative, _CallFn>('sh_call'),
        _free = lib.lookupFunction<_FreeNative, _FreeFn>('sh_free');

  static _Native? _opened;

  static _Native get instance => _opened ??= _Native._(
        DynamicLibrary.open('libsafehaven_engine.so'),
      );

  final _InitFn _init;
  final _CallFn _call;
  final _FreeFn _free;

  void init(String baseUrl, String dataDir) {
    final base = baseUrl.toNativeUtf8();
    final dir = dataDir.toNativeUtf8();
    try {
      if (_init(base, dir) != 0) {
        throw const StoreApiException('engine_init_failed');
      }
    } finally {
      malloc.free(base);
      malloc.free(dir);
    }
  }

  String call(String method, String args) {
    final m = method.toNativeUtf8();
    final a = args.toNativeUtf8();
    try {
      final result = _call(m, a);
      try {
        return result.toDartString();
      } finally {
        _free(result);
      }
    } finally {
      malloc.free(m);
      malloc.free(a);
    }
  }
}

dynamic _invoke(String method, String args) {
  final envelope =
      jsonDecode(_Native.instance.call(method, args)) as Map<String, dynamic>;
  final error = envelope['err'];
  if (error != null) throw StoreApiException(error.toString());
  return envelope['ok'];
}

(T?, String?) _run<T>(String method, String args, T Function(dynamic) decode) {
  try {
    return (decode(_invoke(method, args)), null);
  } on StoreApiException catch (e) {
    return (null, e.message);
  } catch (e) {
    return (null, e.toString());
  }
}

dynamic asIs(dynamic value) => value;

List<dynamic> asList(dynamic value) => value as List<dynamic>;

Map<String, dynamic> asMap(dynamic value) => value as Map<String, dynamic>;

class EngineBridge {
  EngineBridge._();

  static final EngineBridge instance = EngineBridge._();

  Future<void>? _ready;
  bool _initialised = false;

  Future<void> ensureReady() {
    return _ready ??= _initialise().catchError((Object e) {
      _ready = null;
      throw e;
    });
  }

  Future<void> _initialise() async {
    final dir = await getApplicationSupportDirectory();
    _Native.instance.init(storeDefaultBaseUrl, dir.path);
    _initialised = true;
  }

  Future<T> call<T>(
    String method, {
    Map<String, Object?> args = const {},
    required T Function(dynamic) decode,
  }) async {
    await ensureReady();
    final payload = jsonEncode(args);
    final (value, error) = await Isolate.run<(T?, String?)>(
      () => _run<T>(method, payload, decode),
    );
    if (error != null) throw StoreApiException(error);
    return value as T;
  }

  dynamic callSync(String method, [Map<String, Object?> args = const {}]) {
    if (!_initialised) throw const StoreApiException('engine_not_initialised');
    return _invoke(method, jsonEncode(args));
  }
}
