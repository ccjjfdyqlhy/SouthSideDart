import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/backend_client.dart';
import '../theme/app_theme.dart';

enum _LoginTab { qr, phone, email, cookie }

/// 登录引导页:二维码 / 手机验证码 / 邮箱 / COOKIE 四种方式(对齐 Qt 版)。
class LoginPage extends StatefulWidget {
  final BackendClient client;
  final VoidCallback onLoginSuccess;

  /// 跳过登录(匿名使用)。
  final VoidCallback onSkip;

  const LoginPage({
    super.key,
    required this.client,
    required this.onLoginSuccess,
    required this.onSkip,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _LoginTab _tab = _LoginTab.qr;

  // 二维码
  String _qrKey = '';
  String _qrBase64 = '';
  String _qrStatus = '正在生成二维码…';
  Timer? _qrTimer;

  // 手机
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _sending = false;
  int _countdown = 0;
  Timer? _countdownTimer;

  // 邮箱
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _emailPwdCtrl = TextEditingController();

  // 注册(手机)
  final TextEditingController _regNicknameCtrl = TextEditingController();
  final TextEditingController _regPasswordCtrl = TextEditingController();

  // COOKIE
  final TextEditingController _cookieCtrl = TextEditingController();

  bool _busy = false;
  bool _registerMode = false;

  @override
  void initState() {
    super.initState();
    _createQr();
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _countdownTimer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _emailPwdCtrl.dispose();
    _regNicknameCtrl.dispose();
    _regPasswordCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _createQr() async {
    _qrTimer?.cancel();
    setState(() {
      _qrKey = '';
      _qrBase64 = '';
      _qrStatus = '正在生成二维码…';
    });
    try {
      final r = await widget.client.call('login_qr_create');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;
      setState(() {
        _qrKey = (data['key'] ?? '').toString();
        _qrBase64 = (data['qr_base64'] ?? '').toString();
        _qrStatus = '使用网易云音乐 App 扫码登录';
      });
      _startQrPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _qrStatus = '生成二维码失败:$e');
    }
  }

  void _startQrPolling() {
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkQr());
  }

  Future<void> _checkQr() async {
    if (_qrKey.isEmpty || !widget.client.isConnected) return;
    try {
      final r = await widget.client.call('login_qr_check', {'key': _qrKey});
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final code = (data['code'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      switch (code) {
        case 803:
          _qrTimer?.cancel();
          setState(() => _qrStatus = '登录成功');
          widget.onLoginSuccess();
        case 800:
          setState(() => _qrStatus = '二维码已过期,正在重新生成…');
          _createQr();
        case 801:
          setState(() => _qrStatus = '等待扫码…');
        case 802:
          setState(() => _qrStatus = '已扫码,请在手机上确认');
        case 8821:
          _qrTimer?.cancel();
          setState(() => _qrStatus = '登录异常,请稍后重试');
        default:
          break;
      }
    } catch (_) {
      // 网络波动,下一轮重试。
    }
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showError('请输入手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      final r =
          await widget.client.call('login_cellphone_send', {'phone': phone});
      final ok = ((r['result'] as Map<String, dynamic>?) ?? {})['ok'] == true;
      if (!mounted) return;
      setState(() {
        _sending = false;
        _countdown = ok ? 60 : 0;
      });
      if (ok) {
        _startCountdown();
        _showError('验证码已发送');
      } else {
        _showError('验证码发送失败');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showError('发送失败:$e');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _phoneLogin() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _showError('请输入手机号和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.call('login_cellphone_verify', {
        'phone': phone,
        'code': code,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('登录失败:$e');
    }
  }

  Future<void> _cookieLogin() async {
    final cookie = _cookieCtrl.text.trim();
    if (cookie.isEmpty) {
      _showError('请输入 COOKIE');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.call('login_cookie', {'cookie': cookie});
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('登录失败:$e');
    }
  }

  /// 邮箱密码登录(pyncm login.loginViaEmail)。
  Future<void> _emailLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _emailPwdCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('请输入邮箱和密码');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.call('login_email', {
        'email': email,
        'password': password,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('登录失败:$e');
    }
  }

  /// 手机号注册(pyncm login.setRegisterAccountViaCellphone)。
  Future<void> _registerAccount() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final nickname = _regNicknameCtrl.text.trim();
    final password = _regPasswordCtrl.text;
    if (phone.isEmpty || code.isEmpty || nickname.isEmpty || password.isEmpty) {
      _showError('请填写手机号、验证码、昵称和密码');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.call('register_cellphone', {
        'phone': phone,
        'code': code,
        'nickname': nickname,
        'password': password,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('注册成功,已自动登录');
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('注册失败:$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2D7FF9), Color(0xFF5E5CE6)],
                      ),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '登录网易云音乐',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TabChip(
                    label: '二维码',
                    selected: _tab == _LoginTab.qr,
                    onTap: () => setState(() => _tab = _LoginTab.qr),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: '手机',
                    selected: _tab == _LoginTab.phone,
                    onTap: () => setState(() => _tab = _LoginTab.phone),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: '邮箱',
                    selected: _tab == _LoginTab.email,
                    onTap: () => setState(() => _tab = _LoginTab.email),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: 'COOKIE',
                    selected: _tab == _LoginTab.cookie,
                    onTap: () => setState(() => _tab = _LoginTab.cookie),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTabBody(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onSkip,
                child: Text(
                  '暂不登录,匿名使用',
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tab) {
      case _LoginTab.qr:
        return _buildQrTab();
      case _LoginTab.phone:
        return _buildPhoneTab();
      case _LoginTab.email:
        return _buildEmailTab();
      case _LoginTab.cookie:
        return _buildCookieTab();
    }
  }

  Widget _buildQrTab() {
    final colors = context.colors;
    if (_qrBase64.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Text(
            _qrStatus,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.memory(
            base64Decode(_qrBase64),
            width: 200,
            height: 200,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _qrStatus,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _createQr,
          child: const Text('刷新二维码'),
        ),
      ],
    );
  }

  Widget _buildPhoneTab() {
    final colors = context.colors;
    return Column(
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: _inputDecoration('手机号'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: _inputDecoration('验证码'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _sending || _countdown > 0 ? null : _sendCode,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: Text(
                _countdown > 0 ? '重新发送($_countdown)' : '发送验证码',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _phoneLogin,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_busy ? '登录中…' : '登录'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _registerMode = !_registerMode),
          child: Text(
            _registerMode ? '← 返回登录' : '没有账号?注册新账号',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
        if (_registerMode) ...[
          const SizedBox(height: 8),
          _buildRegisterSection(),
        ],
      ],
    );
  }

  Widget _buildCookieTab() {
    final colors = context.colors;
    return Column(
      children: [
        TextField(
          controller: _cookieCtrl,
          maxLines: 5,
          style: TextStyle(fontSize: 13, color: colors.textPrimary),
          decoration: _inputDecoration('粘贴 COOKIE(需包含 MUSIC_U)'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _cookieLogin,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_busy ? '登录中…' : '登录'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailTab() {
    final colors = context.colors;
    return Column(
      children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: _inputDecoration('网易云邮箱'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailPwdCtrl,
          obscureText: true,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: _inputDecoration('密码'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _emailLogin,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_busy ? '登录中…' : '登录'),
          ),
        ),
      ],
    );
  }

  /// 手机号注册入口(可切换 登录/注册)。
  Widget _buildRegisterSection() {
    final colors = context.colors;
    return Column(
      children: [
        TextField(
          controller: _regNicknameCtrl,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: _inputDecoration('昵称'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _regPasswordCtrl,
          obscureText: true,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: _inputDecoration('设置密码'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _registerAccount,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_busy ? '注册中…' : '注册并登录'),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    final colors = context.colors;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
      isDense: true,
      filled: true,
      fillColor: colors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
