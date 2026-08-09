import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/developer_profile_service.dart';
import '../services/theme/theme_manager.dart';
import 'animated_tap.dart';
import 'avatar_crop_screen.dart';
import 'settings_picker_dialog.dart';
import 'package:safehaven/translations/app_localizations.dart';

class ProfileEditDialog extends StatefulWidget {
  const ProfileEditDialog({
    super.key,
    required this.currentName,
    required this.fallbackName,
  });

  final String? currentName;
  final String fallbackName;

  static Future<void> show({
    required BuildContext context,
    required String? currentName,
    required String fallbackName,
  }) {
    return SettingsPickerDialog.show<void>(
      context: context,
      title: AppLocalizations.of(context)!.devEditProfile,
      children: [
        ProfileEditDialog(currentName: currentName, fallbackName: fallbackName),
      ],
    );
  }

  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late final TextEditingController _controller;
  final ImagePicker _picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(imageBytes: bytes),
        fullscreenDialog: true,
      ),
    );

    if (cropped == null || !mounted) return;
    await DeveloperProfileService.instance.setAvatarBytes(cropped);
    if (mounted) setState(() {});
  }

  Future<void> _removeAvatar() async {
    await DeveloperProfileService.instance.clearAvatar();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await DeveloperProfileService.instance.setDisplayName(_controller.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final avatarFile = DeveloperProfileService.instance.avatarFile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedTap(
            borderRadius: 40,
            onTap: _pickAvatar,
            child: Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.iconBackground,
                border: Border.all(color: colors.border),
                image: avatarFile != null
                    ? DecorationImage(image: FileImage(avatarFile), fit: BoxFit.cover)
                    : null,
              ),
              child: avatarFile == null
                  ? Icon(Icons.add_a_photo_rounded, color: colors.textMuted, size: 22)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          if (avatarFile != null)
            AnimatedTap(
              borderRadius: 8,
              onTap: _removeAvatar,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: Text(
                  AppLocalizations.of(context)!.devRemovePhoto,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            maxLength: 30,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              hintText: widget.fallbackName,
              hintStyle: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w700),
              filled: true,
              fillColor: colors.iconBackground,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context)!.commonCancel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(AppLocalizations.of(context)!.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}