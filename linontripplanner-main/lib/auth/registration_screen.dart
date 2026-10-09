import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data.dart';
import '../firestore_loader.dart';
import '../services/storage_image_upload.dart';
import '../services/tourism_session.dart';
import 'auth_navigation.dart';
import 'auth_widgets.dart';
import 'registration_form_cache.dart';

class RegistrationScreen extends StatefulWidget {
  static const routeName = '/register';

  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _ChildControllers {
  final TextEditingController name = TextEditingController();
  final TextEditingController age = TextEditingController();
  String? gender;

  void dispose() {
    name.dispose();
    age.dispose();
  }
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKeyPersonal = GlobalKey<FormState>();
  final _formKeyTravel = GlobalKey<FormState>();

  int _step = 0;
  bool _busy = false;

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  String? _suffix;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String? _sex;
  String? _civil;
  String? _nationality;
  int? _dobMonth;
  int? _dobDay;
  int? _dobYear;

  final List<_ChildControllers> _children = [];

  final _dest1 = TextEditingController();
  final _dest2 = TextEditingController();
  final _dest3 = TextEditingController();
  final _heard = TextEditingController();
  String? _transport;
  String? _visitorType;

  XFile? _facePhoto;
  bool _marketing = false;
  bool _terms = false;

  @override
  void initState() {
    super.initState();
    RegistrationFormCache.warmUp();
  }

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _dest1.dispose();
    _dest2.dispose();
    _dest3.dispose();
    _heard.dispose();
    for (final c in _children) {
      c.dispose();
    }
    super.dispose();
  }

  void _addChild() {
    setState(() => _children.add(_ChildControllers()));
  }

  bool _validatePersonal() {
    if (_dobMonth == null || _dobDay == null || _dobYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete your date of birth.')),
      );
      return false;
    }
    return _formKeyPersonal.currentState?.validate() ?? false;
  }

  bool _validateTravel() => _formKeyTravel.currentState?.validate() ?? false;

  bool _validateUpload() {
    if (_facePhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a close-up photo of your face.'),
        ),
      );
      return false;
    }
    if (!_terms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Terms and Privacy Policy.'),
        ),
      );
      return false;
    }
    return true;
  }

  void _next() {
    if (_step == 0) {
      if (!_validatePersonal()) return;
    } else if (_step == 1) {
      if (!_validateTravel()) return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step -= 1);
    }
  }

  String _fullLegalName() {
    final parts = [
      _first.text.trim(),
      _middle.text.trim(),
      _last.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    final suf = (_suffix ?? '').trim();
    if (suf.isNotEmpty) return '$parts $suf';
    return parts;
  }

  String? _dobIso() {
    if (_dobYear == null || _dobMonth == null || _dobDay == null) {
      return null;
    }
    final m = _dobMonth.toString().padLeft(2, '0');
    final d = _dobDay.toString().padLeft(2, '0');
    return '$_dobYear-$m-$d';
  }

  Future<String?> _uploadPhoto(String uid) async {
    final file = _facePhoto;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      // Firebase Storage billing is closed — profile photos go to Supabase.
      return await uploadUserProfileImage(bytes, 'user_profiles/$uid');
    } catch (e) {
      debugPrint('Face photo upload failed: $e');
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_validateUpload()) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final password = _password.text;
      final displayName = _fullLegalName();

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) throw StateError('No user after registration');

      if (displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      final uid = user.uid;
      final photoUrl = await _uploadPhoto(uid);
      if (photoUrl != null && photoUrl.trim().isNotEmpty) {
        await user.updatePhotoURL(photoUrl.trim());
      }

      final childrenPayload = _children
          .map((c) {
            return {
              'fullName': c.name.text.trim(),
              'age': c.age.text.trim(),
              'gender': c.gender,
            };
          })
          .where((m) => (m['fullName'] as String).isNotEmpty)
          .toList();

      final travelHistory = <String>[
        _dest1.text.trim(),
        _dest2.text.trim(),
        _dest3.text.trim(),
      ].where((d) => d.isNotEmpty).toList();

      final questionnaire = <String, dynamic>{
        'firstName': _first.text.trim(),
        'middleName': _middle.text.trim(),
        'lastName': _last.text.trim(),
        'nameSuffix': _suffix,
        'sex': _sex,
        'civilStatus': _civil,
        'nationality': _nationality,
        'dateOfBirth': _dobIso(),
        'travelPartyChildren': childrenPayload,
        'lastDestination1': _dest1.text.trim(),
        'lastDestination2': _dest2.text.trim(),
        'lastDestination3': _dest3.text.trim(),
        'travelHistory': travelHistory,
        'heardAboutMisamisOccidental': _heard.text.trim(),
        'transportMode': _transport,
        'visitorType': _visitorType,
        'marketingOptIn': _marketing,
        'termsAccepted': _terms,
        'termsAcceptedAt': DateTime.now().toIso8601String(),
      };

      await saveTouristRegistrationToFirestore(
        uid: uid,
        fullName: displayName.isNotEmpty ? displayName : email,
        email: email,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        profilePhotoUrl: photoUrl,
        registration: questionnaire,
      );

      try {
        await syncAccountAfterLogin();
        await loadTourismDataForSession();
      } catch (e, st) {
        debugPrint('Post-registration sync failed: $e\n$st');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration complete. Welcome!')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Registration failed (${e.code})')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _nestedSection({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AuthDesign.inputFill.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuthDesign.inputBorder.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  Widget _personalStep() {
    return Form(
      key: _formKeyPersonal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthCardHeroIcon(icon: Icons.person_outline_rounded),
          const SizedBox(height: 12),
          const Text(
            'Basic Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Let's start with your name. This will be used for your tourist ID.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AuthDesign.secondaryText.withValues(alpha: 0.95),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('First Name', required: true),
          ),
          AuthTextField(
            controller: _first,
            hint: 'e.g. Juan',
            icon: Icons.badge_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Middle Name'),
          ),
          AuthTextField(
            controller: _middle,
            hint: 'e.g. Dela (Optional)',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Last Name', required: true),
          ),
          AuthTextField(
            controller: _last,
            hint: 'e.g. Cruz',
            icon: Icons.badge_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Suffix'),
          ),
          AuthDropdownField<String>(
            value: (_suffix == null || _suffix!.isEmpty) ? null : _suffix,
            hint: 'e.g. Jr., Sr., III (Optional)',
            icon: Icons.more_horiz_rounded,
            items: RegistrationFormCache.suffixItems,
            onChanged: (v) => setState(() => _suffix = v),
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Email', required: true),
          ),
          AuthTextField(
            controller: _email,
            hint: 'Enter email address',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return 'Required';
              if (!s.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Mobile number'),
          ),
          AuthTextField(
            controller: _phone,
            hint: '09xx xxx xxxx',
            icon: Icons.phone_android_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Password', required: true),
          ),
          AuthTextField(
            controller: _password,
            hint: 'At least 6 characters',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            validator: (v) {
              if (v == null || v.length < 6) {
                return 'Use at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Confirm password', required: true),
          ),
          AuthTextField(
            controller: _confirm,
            hint: 'Re-enter password',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            validator: (v) {
              if (v != _password.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 22),
          const AuthCardHeroIcon(icon: Icons.groups_2_outlined),
          const SizedBox(height: 12),
          const Text(
            'Family / travel party',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Optional: add children traveling with you. Party size for LGU reports = 1 (you) + each child listed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AuthDesign.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Reported party size: 1 (1 adult + ${_children.length} children)',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          ..._children.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            return _nestedSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Child ${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const AuthFieldLabel('Full name'),
                  AuthTextField(
                    controller: c.name,
                    hint: 'Name',
                    icon: Icons.child_care_outlined,
                  ),
                  const SizedBox(height: 10),
                  AuthResponsivePair(
                    first: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AuthFieldLabel('Age'),
                        AuthTextField(
                          controller: c.age,
                          hint: 'Age',
                          icon: Icons.cake_outlined,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    second: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AuthFieldLabel('Gender'),
                        AuthDropdownField<String>(
                          value: c.gender,
                          hint: 'Select',
                          icon: Icons.wc_rounded,
                          items: RegistrationFormCache.sexItems,
                          onChanged: (v) => setState(() => c.gender = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Center(child: AuthOutlineButton(
            label: 'Add child',
            icon: Icons.add,
            onPressed: _addChild,
          )),
          const SizedBox(height: 22),
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tell us more about yourself. This helps us personalize your experience.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AuthDesign.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _nestedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AuthFieldLabel('Sex', required: true),
                AuthDropdownField<String>(
                  value: _sex,
                  hint: 'Select your sex',
                  icon: Icons.wc_rounded,
                  items: RegistrationFormCache.sexItems,
                  onChanged: (v) => setState(() => _sex = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                const AuthFieldLabel('Civil Status', required: true),
                AuthDropdownField<String>(
                  value: _civil,
                  hint: 'Select civil status',
                  icon: Icons.favorite_outline,
                  items: RegistrationFormCache.civilItems,
                  onChanged: (v) => setState(() => _civil = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                const AuthFieldLabel('Nationality', required: true),
                AuthDropdownField<String>(
                  value: _nationality,
                  hint: 'Select nationality',
                  icon: Icons.flag_outlined,
                  items: RegistrationFormCache.nationItems,
                  onChanged: (v) => setState(() => _nationality = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                const AuthFieldLabel('Date of Birth', required: true),
                const SizedBox(height: 6),
                AuthDropdownField<int>(
                  value: _dobMonth,
                  hint: 'Month',
                  icon: Icons.calendar_month_outlined,
                  items: RegistrationFormCache.monthItems,
                  onChanged: (v) => setState(() => _dobMonth = v),
                ),
                const SizedBox(height: 10),
                AuthResponsivePair(
                  breakpoint: 360,
                  first: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthFieldLabel('Day'),
                      AuthDropdownField<int>(
                        value: _dobDay,
                        hint: 'Day',
                        icon: Icons.event_rounded,
                        items: RegistrationFormCache.dayItems,
                        onChanged: (v) => setState(() => _dobDay = v),
                      ),
                    ],
                  ),
                  second: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthFieldLabel('Year'),
                      AuthDropdownField<int>(
                        value: _dobYear,
                        hint: 'Year',
                        icon: Icons.date_range_outlined,
                        items: RegistrationFormCache.yearItems,
                        onChanged: (v) => setState(() => _dobYear = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _stepFooter(
            forwardLabel: 'Continue',
            forwardIcon: Icons.check_rounded,
            onForward: _busy ? null : _next,
          ),
        ],
      ),
    );
  }

  Widget _travelStep() {
    return Form(
      key: _formKeyTravel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Travel details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please indicate the last 3 tourist destinations you have visited.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AuthDesign.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('1st destination you have visited',
                required: true),
          ),
          AuthTextField(
            controller: _dest1,
            hint: 'e.g. Boracay, Aklan',
            icon: Icons.location_on_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('2nd destination you have visited',
                required: true),
          ),
          AuthTextField(
            controller: _dest2,
            hint: 'e.g. Cebu City',
            icon: Icons.location_on_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('3rd destination you have visited',
                required: true),
          ),
          AuthTextField(
            controller: _dest3,
            hint: 'e.g. Palawan',
            icon: Icons.location_on_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel(
              'How did you hear about Misamis Occidental?',
              required: true,
            ),
          ),
          AuthTextField(
            controller: _heard,
            hint: 'e.g. Social media, friend, news…',
            icon: Icons.info_outline_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel(
              'What mode of transportation will you take?',
              required: true,
            ),
          ),
          AuthDropdownField<String>(
            value: _transport,
            hint: 'Select',
            icon: Icons.directions_car_outlined,
            items: RegistrationFormCache.transportItems,
            onChanged: (v) => setState(() => _transport = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: AuthFieldLabel('Local or Foreign', required: true),
          ),
          AuthDropdownField<String>(
            value: _visitorType,
            hint: 'Select',
            icon: Icons.person_outline_rounded,
            items: RegistrationFormCache.visitorItems,
            onChanged: (v) => setState(() => _visitorType = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          _stepFooter(
            forwardLabel: 'Proceed',
            forwardIcon: Icons.arrow_forward_rounded,
            onForward: _busy ? null : _next,
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (x != null) setState(() => _facePhoto = x);
  }

  Widget _uploadStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Uploads',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 14),
        const Align(
          alignment: Alignment.centerLeft,
          child: AuthFieldLabel('Upload a close-up photo of your face',
              required: true),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: AuthDesign.inputFill,
            borderRadius: BorderRadius.circular(AuthDesign.fieldRadius),
            border: Border.all(color: AuthDesign.inputBorder),
          ),
          child: Column(
            children: [
              Icon(Icons.photo_camera_outlined,
                  size: 40, color: AuthDesign.secondaryText),
              const SizedBox(height: 8),
              Text(
                _facePhoto == null ? 'No file chosen' : _facePhoto!.name,
                style: const TextStyle(
                  color: AuthDesign.placeholder,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AuthPrimaryButton(
          label: 'Upload',
          icon: Icons.file_upload_outlined,
          onPressed: _busy ? null : _pickPhoto,
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          value: _marketing,
          onChanged: _busy
              ? null
              : (v) => setState(() => _marketing = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I would like to receive updates and promotions',
            softWrap: true,
            style: TextStyle(fontSize: 14, color: AppColors.textDark),
          ),
          checkColor: Colors.white,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return null;
          }),
        ),
        CheckboxListTile(
          value: _terms,
          onChanged: _busy ? null : (v) => setState(() => _terms = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I agree to the Terms and Conditions and Data Privacy Policy.',
            softWrap: true,
            style: TextStyle(fontSize: 14, color: AppColors.textDark),
          ),
          checkColor: Colors.white,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return null;
          }),
        ),
        _stepFooter(
          forwardLabel: _busy ? 'Submitting…' : 'Submit Registration',
          forwardIcon: Icons.check_rounded,
          onForward: _busy ? null : _submit,
        ),
      ],
    );
  }

  Widget _stepFooter({
    required String forwardLabel,
    IconData? forwardIcon,
    VoidCallback? onForward,
  }) {
    return AuthNavFooter(
      onBack: _busy ? null : _back,
      forwardLabel: forwardLabel,
      forwardIcon: forwardIcon,
      onForward: onForward,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthDesign.creamBackground,
      body: AuthCenteredScrollPage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RegistrationHeader(
              stepOneBased: _step + 1,
              onBack: _busy ? null : _back,
            ),
            const SizedBox(height: 12),
            RegistrationStepper(currentIndex: _step),
            InstructionWithAuthLink(
              onLoginTap: () => pushLoginScreen(context),
            ),
            const SizedBox(height: 4),
            AuthWhiteCard(
              child: _step == 0
                  ? _personalStep()
                  : _step == 1
                      ? _travelStep()
                      : _uploadStep(),
            ),
          ],
        ),
      ),
    );
  }
}
