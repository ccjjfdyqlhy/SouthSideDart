import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 连接到 Python 内核(``standalone.py``)的 TCP JSON-RPC 客户端。
///
/// 协议与 ``src/backend/standalone.py`` 一致:换行分隔的
/// ``{"id":..,"method":..,"params":{..}}`` 请求,响应为
/// ``{"id":..,"result":..}`` 或 ``{"id":..,"error":..}``。
class BackendClient {
  static const defaultHost = '127.0.0.1';
  static const defaultPort = 15490;

  Socket? _socket;
  final StringBuffer _buffer = StringBuffer();
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;
  bool _connected = false;

  /// 后端主动推送(当前协议未使用,保留扩展位)。
  void Function(Map<String, dynamic> message)? onEvent;

  bool get isConnected => _connected;

  /// 尝试连接内核,超时或失败返回 false。
  Future<bool> connect({String host = defaultHost, int port = defaultPort}) async {
    if (_connected) return true;
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
      _socket = socket;
      _connected = true;
      socket.listen(_onData, onError: (Object _) => _onClosed(), onDone: _onClosed);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  void disconnect() {
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
    if (_socket == null || !_connected) {
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
    _socket!.write('$request\n');
    try {
      final response = await completer.future
          .timeout(const Duration(seconds: 10));
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

  void _onData(Uint8List data) {
    _buffer.write(utf8.decode(data, allowMalformed: true));
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
