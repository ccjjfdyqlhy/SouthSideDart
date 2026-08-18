import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 与 Python 内核(``standalone.py``)通信的 JSON-RPC 客户端。
///
/// 支持两种传输:
/// - ``connectTcp``:连接 ``127.0.0.1:15490`` 的 TCP RPC 服务(手动启动内核);
/// - ``connectProcess``:由前端启动内核子进程,经 stdin/stdout 直连(更紧密,
///   生命周期随前端,无需手动启动、无端口依赖)。
///
/// 协议与 ``src/backend/standalone.py`` 一致:换行分隔的
/// ``{"id":..,"method":..,"params":{..}}`` 请求,响应为
/// ``{"id":..,"result":..}`` 或 ``{"id":..,"error":..}``;事件推送为
/// ``{"event":"..","data":{..}}``。
class BackendClient {
  static const defaultHost = '127.0.0.1';
  static const defaultPort = 15490;

  Socket? _socket;
  Process? _process;
  bool _processMode = false;
  final StringBuffer _buffer = StringBuffer();
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;
  bool _connected = false;

  /// 内核主动推送的事件(当前协议未用,保留扩展位)。
  void Function(Map<String, dynamic> message)? onEvent;

  /// 内核启动日志行(子进程 stderr,用于启动进度显示)。
  void Function(String line)? onStartupLog;

  bool get isConnected => _connected;
  bool get isProcessMode => _processMode;

  /// 连接手动启动的内核 TCP RPC 服务。
  Future<bool> connectTcp({String host = defaultHost, int port = defaultPort}) async {
    if (_connected) return true;
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
      _socket = socket;
      _processMode = false;
      _connected = true;
      socket.listen(_onSocketData,
          onError: (Object _) => _onClosed(), onDone: _onClosed);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// 由前端启动内核子进程,经 stdin/stdout 直连。
  Future<bool> connectProcess({
    required List<String> command,
    String? workingDirectory,
  }) async {
    if (_connected) return true;
    try {
      final process = await Process.start(
        command.first,
        command.sublist(1),
        workingDirectory: workingDirectory,
      );
      _process = process;
      _processMode = true;
      _connected = true;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleLine, onError: (Object _) => _onClosed(), onDone: _onClosed);
      // stderr 转发为启动日志(同时防缓冲阻塞)。
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => onStartupLog?.call(line),
            onError: (Object _) {},
          );
      process.exitCode.then((int _) => _onClosed());
      return true;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    // 进程模式:先优雅 shutdown,再回收。
    if (_processMode && _process != null) {
      try {
        _process!.stdin.writeln(jsonEncode({'id': 0, 'method': 'shutdown'}));
        _process!.stdin.flush();
      } catch (_) {}
      _process!.kill();
      _process = null;
    }
    _processMode = false;
    _connected = false;
    _socket?.destroy();
    _socket = null;
    final err = StateError('backend disconnected');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(err);
    }
    _pending.clear();
    _buffer.clear();
  }

  /// 发起一次 RPC 调用,返回完整响应消息。
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (!_connected) {
      throw StateError('backend not connected');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final request = jsonEncode({
      'id': id,
      'method': method,
      'params': params ?? {},
    });
    _write('$request\n');
    try {
      final response = await completer.future
          .timeout(const Duration(seconds: 12));
      if (response.containsKey('error')) {
        throw BackendError(
          (response['error'] as Map<String, dynamic>)['message'] as String? ??
              'backend error',
        );
      }
      return response;
    } finally {
      _pending.remove(id);
    }
  }

  void _write(String text) {
    if (_processMode) {
      _process?.stdin.write(text);
      _process?.stdin.flush();
    } else {
      _socket?.write(text);
    }
  }

  void _onSocketData(Uint8List data) {
    _buffer.write(utf8.decode(data, allowMalformed: true));
    _flushLines();
  }

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = message['id'];
    if (id is int) {
      final completer = _pending[id];
      if (completer != null) completer.complete(message);
      return;
    }
    onEvent?.call(message);
  }

  void _flushLines() {
    final text = _buffer.toString();
    var start = 0;
    while (true) {
      final end = text.indexOf('\n', start);
      if (end < 0) break;
      _handleLine(text.substring(start, end));
      start = end + 1;
    }
    _buffer.clear();
    if (start < text.length) _buffer.write(text.substring(start));
  }

  void _onClosed() {
    if (!_connected) return;
    disconnect();
  }
}

/// 后端返回 error 时抛出的异常。
class BackendError implements Exception {
  final String message;

  BackendError(this.message);

  @override
  String toString() => 'BackendError: $message';
}
