import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../state/app_scope.dart';
import '../../../state/auth_state.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/profile-page.tsx`.
///
/// Saves through `PATCH /users/{id}/profile`, a multipart endpoint that takes
/// only the fields that actually changed — the service rejects a request with no
/// changed fields, so a no-op save is a bug rather than a no-op.
///
/// The avatar is picked with `image_picker` and validated here exactly as the web
/// client does (image, under 5MB) because the service enforces the same limits
/// and would otherwise fail on the user with a bare 400.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _maxAvatarBytes = 5 * 1024 * 1024;

  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();

  AppUser? _baseline;
  Uint8List? _avatarBytes;
  String? _avatarPreview;
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _email.dispose();
    _mobile.dispose();
    super.dispose();
  }

  void _hydrate(AppUser user) {
    _baseline = user;
    _name.text = user.userName;
    _bio.text = user.bioData ?? '';
    _email.text = user.email ?? '';
    _mobile.text = user.mobileNumber ?? '';
  }

  void _reset() {
    final user = _baseline;
    if (user != null) _hydrate(user);
    setState(() {
      _avatarBytes = null;
      _avatarPreview = null;
      _editing = false;
    });
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxAvatarBytes) {
        AppToast.error(context, 'Image too large (max 5MB)');
        return;
      }
      setState(() {
        _avatarBytes = bytes;
        _avatarPreview = null;
      });
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open the image picker');
    }
  }

  Future<void> _save() async {
    final user = _baseline;
    if (user == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, 'Full name is required');
      return;
    }
    final fields = <String, String>{
      if (name != user.userName) 'user_name': name,
      if (_bio.text.trim() != (user.bioData ?? '')) 'bio_data': _bio.text.trim(),
      if (_email.text.trim() != (user.email ?? '')) 'email': _email.text.trim(),
      if (_mobile.text.trim() != (user.mobileNumber ?? ''))
        'mobile_number': _mobile.text.trim(),
    };
    if (fields.isEmpty && _avatarBytes == null) {
      AppToast.info(context, 'Nothing to save');
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final services = AppScope.read(context);
    final token = services.auth.token;
    final url = ApiClient.buildUrl(
        ApiConfig.baseFor(ServiceNames.users), '/users/${user.id}/profile');
    try {
      // The profile endpoint reads Form fields, so it has to be multipart — and
      // the file part is optional, since the service only touches `user_dp`
      // when an avatar actually arrives.
      final request = http.MultipartRequest('PATCH', Uri.parse(url))
        ..fields.addAll(fields)
        ..headers['Accept'] = 'application/json';
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final avatar = _avatarBytes;
      if (avatar != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar',
          avatar,
          filename: 'avatar.jpg',
          contentType: http.MediaType('image', 'jpeg'),
        ));
      }
      final streamed = await request.send().timeout(ApiConfig.longTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) {
        throw ApiException(
          extractErrorMessage(response.body),
          statusCode: response.statusCode,
          url: url,
          method: 'PATCH',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        // Push the server's copy into the session so the shell, drawer and this
        // screen all show the new name without a re-login.
        await services.auth.updateUser(AppUser.fromJson(decoded));
      }
      if (!mounted) return;
      setState(() {
        _avatarBytes = null;
        _avatarPreview = null;
        _editing = false;
      });
      AppToast.success(context, 'Profile updated successfully');
    } on TimeoutException {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.error(context, 'Upload timed out. Check your connection.');
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.error(context, 'Connection error: ${e.message}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.error(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.error(context, 'Failed to update profile');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final services = AppScope.of(context);
    final user = services.auth.user;

    if (user == null) {
      return const Center(
        child: AppEmptyState(
          title: 'Not signed in',
          message: 'Sign in to view your profile.',
          icon: Icons.person_off_outlined,
        ),
      );
    }
    if (_baseline?.id != user.id) {
      _hydrate(user);
    }

    return Column(
      children: [
        AppPageHeader(
          breadcrumb: const AppBreadcrumb(trail: ['Dashboard', 'Profile']),
          title: 'My Profile',
          subtitle: 'Manage your personal information and preferences',
          busy: _saving,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth > 760;
                  final avatar = _avatarCard(user, t, c);
                  final details = _detailsCard(user, t, c);
                  if (!wide) {
                    return Column(
                      children: [avatar, const SizedBox(height: 14), details],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 300, child: avatar),
                      const SizedBox(width: 14),
                      Expanded(child: details),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatarCard(AppUser user, TextTheme t, AppColors c) {
    final photo = _avatarPreview ?? user.userDp;
    final initials = user.userName.trim().isEmpty
        ? 'U'
        : user.userName.trim().substring(0, 1).toUpperCase();
    return AppCard(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 108,
                height: 108,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.success, c.success],
                  ),
                ),
                child: photo != null && photo.isNotEmpty
                    ? (_avatarBytes != null
                        ? Image.memory(_avatarBytes!, fit: BoxFit.cover)
                        : Image.network(photo, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Text(initials,
                                    style: t.headlineSmall
                                        ?.copyWith(color: Colors.white))))
                    : Center(
                        child: Text(
                          initials,
                          style: t.headlineSmall?.copyWith(color: Colors.white),
                        ),
                      ),
              ),
              if (_editing)
                Positioned.fill(
                  child: Material(
                    color: Colors.black38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _pickAvatar,
                      child: const Icon(Icons.photo_camera_outlined,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(user.userName, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          AppBadge(
            user.roleId.toUpperCase(),
            tone: user.isAdmin ? AppTone.warning : AppTone.brand,
          ),
          const SizedBox(height: 16),
          _idRow(Icons.badge_outlined, user.authId),
          if (user.employeeId != null && user.employeeId!.isNotEmpty)
            _idRow(Icons.person_outline, 'Employee ID: ${user.employeeId}'),
          const SizedBox(height: 18),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    block: true,
                    onPressed: _saving ? null : _reset,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Save',
                    icon: Icons.save_outlined,
                    variant: AppButtonVariant.primary,
                    block: true,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            )
          else
            AppButton(
              label: 'Edit Profile',
              variant: AppButtonVariant.secondary,
              block: true,
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
    );
  }

  Widget _idRow(IconData icon, String text) {
    final c = context.c;
    final t = context.texts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: c.fgMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: c.fg3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(AppUser user, TextTheme t, AppColors c) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Personal Information', style: t.titleSmall),
          const SizedBox(height: 14),
          AppField(
            label: 'Full name *',
            child: AppTextInput(
              controller: _name,
              hint: 'Enter your full name',
              enabled: _editing,
              textCapitalization: TextCapitalization.words,
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Bio / About',
            child: AppTextInput(
              controller: _bio,
              hint: 'Tell us about yourself',
              enabled: _editing,
              maxLines: 3,
              minLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Email address',
            child: AppTextInput(
              controller: _email,
              hint: 'your.email@example.com',
              enabled: _editing,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Mobile number',
            child: AppTextInput(
              controller: _mobile,
              hint: '+94 XX XXX XXXX',
              enabled: _editing,
              keyboardType: TextInputType.phone,
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 14),
            const AppNotice(
              tone: AppTone.success,
              message: 'Changes are saved to your account and reflected across '
                  'all services.',
            ),
          ],
        ],
      ),
    );
  }
}
