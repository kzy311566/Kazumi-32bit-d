import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/storage/danmaku_credential_store.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

/// Lets the user supply their own DanDanPlay open API credentials.
///
/// The upstream project binds these at compile time from private CI secrets.
/// Builds that cannot read those secrets ship without any danmaku source, so
/// this tile is the way to restore it without rebuilding — and it also lets a
/// user swap in their own credentials on an otherwise complete build.
class DanmakuCredentialTile extends StatefulWidget {
  const DanmakuCredentialTile({super.key});

  @override
  State<DanmakuCredentialTile> createState() => _DanmakuCredentialTileState();
}

class _DanmakuCredentialTileState extends State<DanmakuCredentialTile> {
  Future<void> _edit() async {
    final saved = await KazumiDialog.show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (context) => const _DanmakuCredentialDialog(),
    );
    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _clear() async {
    await DanmakuCredentialStore.clear();
    if (mounted) {
      setState(() {});
      KazumiDialog.showToast(context: context, message: '已清除自定义凭证');
    }
  }

  String get _statusLabel {
    if (DandanCredentials.hasUserCredentials) return '自定义';
    if (DandanCredentials.hasBuildTimeCredentials) return '已内置';
    return '未配置';
  }

  String get _statusDescription {
    if (DandanCredentials.isConfigured) {
      return 'AppId ${DandanCredentials.appIdForDisplay}';
    }
    return '未配置时无法加载弹弹play弹幕';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsTile(
          leading: Icons.badge_outlined,
          title: const Text('弹弹play API 凭证'),
          description: Text(_statusDescription),
          value: Text(_statusLabel),
          onPressed: (_) => _edit(),
        ),
        if (DandanCredentials.hasUserCredentials)
          SettingsTile(
            leading: Icons.restart_alt_rounded,
            title: const Text('恢复为内置凭证'),
            description: const Text('清除本机填写的 AppId 与 AppSecret'),
            onPressed: (_) => _clear(),
          ),
      ],
    );
  }
}

class _DanmakuCredentialDialog extends StatefulWidget {
  const _DanmakuCredentialDialog();

  @override
  State<_DanmakuCredentialDialog> createState() =>
      _DanmakuCredentialDialogState();
}

class _DanmakuCredentialDialogState extends State<_DanmakuCredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _appIdController;
  late final TextEditingController _secretController;
  bool _secretObscured = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _appIdController = TextEditingController(
      text: DanmakuCredentialStore.storedAppId,
    );
    _secretController = TextEditingController(
      text: DanmakuCredentialStore.storedSecret,
    );
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  /// The DevCenter shows the pair as one `appId;appSecret` string, so a paste
  /// into a single field is a supported input form. Validation therefore has to
  /// accept the field that the user left empty as long as the other one carries
  /// the combined value; otherwise the helper text below would advertise an
  /// input the form rejects.
  bool get _eitherFieldHoldsCombinedPair =>
      _appIdController.text.contains(';') ||
      _secretController.text.contains(';');

  String? _combinedPairProblem() {
    final combined = _appIdController.text.contains(';')
        ? _appIdController.text
        : _secretController.text;
    final separator = combined.indexOf(';');
    final id = combined.substring(0, separator).trim();
    final secret = combined.substring(separator + 1).trim();
    if (id.isEmpty) return '「;」前面缺少 AppId';
    if (secret.isEmpty) return '「;」后面缺少 AppSecret';
    if (RegExp(r'\s').hasMatch(id)) return 'AppId 不能包含空格';
    if (RegExp(r'\s').hasMatch(secret)) return 'AppSecret 不能包含空格';
    return null;
  }

  String? _validateAppId(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _eitherFieldHoldsCombinedPair ? null : '请填写 AppId';
    }
    final id = text.contains(';') ? text.split(';').first.trim() : text;
    if (id.isEmpty) return '请填写 AppId';
    if (RegExp(r'\s').hasMatch(id)) return 'AppId 不能包含空格';
    return null;
  }

  String? _validateSecret(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _eitherFieldHoldsCombinedPair ? null : '请填写 AppSecret';
    }
    if (text.contains(';')) {
      final secret = text.substring(text.indexOf(';') + 1).trim();
      if (secret.isEmpty) return '请填写 AppSecret';
      if (RegExp(r'\s').hasMatch(secret)) return 'AppSecret 不能包含空格';
      return null;
    }
    if (RegExp(r'\s').hasMatch(text)) return 'AppSecret 不能包含空格';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // A combined paste must still be internally consistent.
    if (_eitherFieldHoldsCombinedPair) {
      final problem = _combinedPairProblem();
      if (problem != null) {
        KazumiDialog.showToast(context: context, message: problem);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await DanmakuCredentialStore.save(
        appId: _appIdController.text.trim(),
        secret: _secretController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      KazumiDialog.showToast(
        context: context,
        message: '凭证已保存，重新加载弹幕即可生效',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        KazumiDialog.showToast(context: context, message: '凭证保存失败，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('弹弹play API 凭证'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '在弹弹play开发者中心创建应用后，将 AppId 与 AppSecret 填到此处。'
                '凭证仅保存在本机；留空则使用安装包内置的凭证。',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _appIdController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'AppId',
                  hintText: '在弹弹play开发者中心创建应用后获得',
                  border: OutlineInputBorder(),
                ),
                validator: _validateAppId,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secretController,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: _secretObscured,
                decoration: InputDecoration(
                  labelText: 'AppSecret',
                  helperText: '可直接粘贴「AppId;AppSecret」整串',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _secretObscured
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _secretObscured = !_secretObscured),
                  ),
                ),
                validator: _validateSecret,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
