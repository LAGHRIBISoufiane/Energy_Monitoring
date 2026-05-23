import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, FirebaseAuthException, Persistence;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import '../main.dart' show kTeal, QuickSettingsBar;
import '../l10n/app_strings.dart';

// ── File-level helpers ────────────────────────────────────────────────────────

Widget _label(String text, AppColors c) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
            color: c.textPri, fontWeight: FontWeight.w500, fontSize: 13),
      ),
    );

InputDecoration _inputDeco(String hint, IconData icon, AppColors c, {Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.textSec, fontSize: 13),
      prefixIcon: Icon(icon, color: c.textSec, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: c.inputFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kTeal, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE74C3C))),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
      errorStyle: const TextStyle(color: Color(0xFFE74C3C), fontSize: 11),
    );

TextFormField _field({
  required AppColors c,
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  bool obscure = false,
  TextInputAction textInputAction = TextInputAction.next,
  Widget? suffix,
  String? Function(String?)? validator,
  void Function(String)? onSubmitted,
  TextInputType keyboardType = TextInputType.text,
}) =>
    TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: TextStyle(color: c.textPri, fontSize: 14),
      decoration: _inputDeco(hint, icon, c, suffix: suffix),
    );

Widget _errorBanner(String message) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFE74C3C).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFE74C3C), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: Color(0xFFE74C3C), fontSize: 13)),
          ),
        ],
      ),
    );

String _authErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'email-already-in-use':
      return 'Cette adresse email est déjà utilisée.';
    case 'invalid-email':
      return 'Adresse email invalide.';
    case 'weak-password':
      return 'Mot de passe trop faible (minimum 6 caractères).';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email ou mot de passe incorrect.';
    case 'user-disabled':
      return 'Ce compte a été désactivé.';
    case 'too-many-requests':
      return 'Trop de tentatives. Veuillez réessayer plus tard.';
    case 'operation-not-allowed':
      return 'La connexion par email/mot de passe n\'est pas activée dans Firebase Console.';
    case 'network-request-failed':
      return 'Erreur réseau. Vérifiez votre connexion internet.';
    default:
      return '[${e.code}] ${e.message ?? 'Une erreur est survenue.'}';
  }
}

// ── LoginScreen ───────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showSignup = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Row(
            children: [
              const _LeftPanel(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _showSignup
                      ? _SignupForm(
                          key: const ValueKey('signup'),
                          onSwitchToLogin: () =>
                              setState(() => _showSignup = false),
                        )
                      : _LoginForm(
                          key: const ValueKey('login'),
                          onSwitchToSignup: () =>
                              setState(() => _showSignup = true),
                        ),
                ),
              ),
            ],
          ),
          const Positioned(
            top: 12,
            right: 12,
            child: QuickSettingsBar(),
          ),
        ],
      ),
    );
  }
}

// ── Left branding panel ───────────────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  const _LeftPanel();

  Widget _bullet(IconData icon, String text, AppColors c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kTeal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: kTeal, size: 18),
            ),
            const SizedBox(width: 12),
            Text(text,
                style: TextStyle(color: c.textPri, fontSize: 13.5)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 360,
      color: c.sidebar,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: kTeal.withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 4),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child:
                Image.asset('assets/images/ocp_logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(height: 28),
          Text(
            'OCP Group',
            style: TextStyle(
                color: c.textPri,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.t('kofert_subtitle'),
            style:
                TextStyle(color: c.textSec, fontSize: 13, letterSpacing: 0.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 44),
          _bullet(Icons.bolt_rounded, AppStrings.t('real_time_data'), c),
          const SizedBox(height: 14),
          _bullet(Icons.bar_chart_rounded, AppStrings.t('history_stats'), c),
          const SizedBox(height: 14),
          _bullet(Icons.warning_amber_rounded, AppStrings.t('smart_alerts'), c),
          const SizedBox(height: 36),
          // ── QR code — scan to open on mobile ──────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Builder(builder: (_) {
              final url = html.window.location.href;
              return Column(children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: kTeal.withValues(alpha: 0.25),
                          blurRadius: 16)
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 130,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 8),
                Text(AppStrings.t('scan_mobile'),
                    style: TextStyle(
                        color: c.textSec,
                        fontSize: 11,
                        letterSpacing: 0.3)),
              ]);
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Login form ────────────────────────────────────────────────────────────────

class _LoginForm extends StatefulWidget {
  final VoidCallback onSwitchToSignup;
  const _LoginForm({super.key, required this.onSwitchToSignup});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _pwVisible = false;
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _rememberMe = prefs.getBool('rememberMe') ?? true);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', _rememberMe);
      await FirebaseAuth.instance.setPersistence(
        _rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // StreamBuilder in main.dart handles routing
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _authErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erreur inattendue: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('sign_in'),
                    style: TextStyle(
                        color: c.textPri,
                        fontWeight: FontWeight.bold,
                        fontSize: 28)),
                const SizedBox(height: 6),
                Text(
                  AppStrings.t('login_subtitle'),
                  style: TextStyle(color: c.textSec, fontSize: 14),
                ),
                const SizedBox(height: 36),
                _label(AppStrings.t('email'), c),
                _field(c: c, controller: _emailCtrl,
                  hint: 'votre@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return AppStrings.t('field_required');
                    if (!v.contains('@')) return AppStrings.t('invalid_email_short');
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _label(AppStrings.t('password'), c),
                _field(c: c, controller: _passwordCtrl,
                  hint: 'Votre mot de passe',
                  icon: Icons.lock_outline_rounded,
                  obscure: !_pwVisible,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _onLogin(),
                  suffix: IconButton(
                    onPressed: () =>
                        setState(() => _pwVisible = !_pwVisible),
                    icon: Icon(
                      _pwVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: c.textSec,
                      size: 20,
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Champ requis' : null,
                ),
                if (_errorMessage != null) _errorBanner(_errorMessage!),
                const SizedBox(height: 16),
                // ── Remember me ──────────────────────────────────
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? true),
                        activeColor: kTeal,
                        checkColor: Colors.black87,
                        side: BorderSide(
                            color: c.textSec.withValues(alpha: 0.5), width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _rememberMe = !_rememberMe),
                      child: Text(
                        AppStrings.t('remember_me'),
                        style: TextStyle(color: c.textSec, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor:
                          kTeal.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black54),
                          )
                        : Text(AppStrings.t('sign_in'),
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${AppStrings.t('no_account')} ',
                          style: TextStyle(color: c.textSec, fontSize: 13)),
                      GestureDetector(
                        onTap: widget.onSwitchToSignup,
                        child: Text(AppStrings.t('create_account'),
                            style: TextStyle(
                                color: kTeal,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Signup form ───────────────────────────────────────────────────────────────

class _SignupForm extends StatefulWidget {
  final VoidCallback onSwitchToLogin;
  const _SignupForm({super.key, required this.onSwitchToLogin});

  @override
  State<_SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<_SignupForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _posteCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  DateTime? _dateOfBirth;
  bool _pwVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _dobCtrl.dispose();
    _posteCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      builder: (ctx, child) => Theme(
        data: isDark
            ? ThemeData.dark().copyWith(
                colorScheme: ColorScheme.dark(primary: kTeal, surface: c.card),
              )
            : ThemeData.light().copyWith(
                colorScheme: ColorScheme.light(
                  primary: kTeal,
                  onPrimary: Colors.white,
                  surface: c.card,
                  onSurface: c.textPri,
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: kTeal),
                ),
              ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dobCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _onSignup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final user = cred.user!;
      // Send verification email immediately — before anything else
      await user.sendEmailVerification();
      // Non-blocking: update display name and save profile to Firestore
      // Failures here do NOT prevent the user from proceeding
      try {
        await user.updateDisplayName(
            '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}');
        const idChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        final rng = Random.secure();
        final newCustomId = List.generate(8, (_) => idChars[rng.nextInt(idChars.length)]).join();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'firstName': _firstNameCtrl.text.trim(),
          'lastName': _lastNameCtrl.text.trim(),
          'dateOfBirth': _dateOfBirth != null
              ? DateFormat('yyyy-MM-dd').format(_dateOfBirth!)
              : null,
          'poste': _posteCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phoneNumber': _phoneCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'emailVerified': false,
          'customId': newCustomId,
        });
      } catch (_) {
        // Profile save failed (e.g. Firestore rules) — user + email are fine
      }
      // StreamBuilder in main.dart will route to VerifyEmailScreen
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _authErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erreur inattendue: $e';
      });
    }
  }

  Widget _row(Widget left, Widget right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      );

  Widget _labelled({required String label, required Widget field}) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_label(label, c), field],
    );
  }

  Widget _datePickerField() {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: _pickDate,
      child: AbsorbPointer(
        child: _field(c: c, controller: _dobCtrl,
          hint: 'JJ/MM/AAAA',
          icon: Icons.calendar_today_outlined,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requis' : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('signup_title'),
                    style: TextStyle(
                        color: c.textPri,
                        fontWeight: FontWeight.bold,
                        fontSize: 28)),
                const SizedBox(height: 6),
                Text(
                  AppStrings.t('signup_subtitle'),
                  style: TextStyle(color: c.textSec, fontSize: 14),
                ),
                const SizedBox(height: 32),

                // Row 1 – Prénom | Nom de famille
                _row(
                  _labelled(
                    label: AppStrings.t('first_name'),
                    field: _field(c: c, controller: _firstNameCtrl,
                      hint: 'Jean',
                      icon: Icons.person_outline_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? AppStrings.t('field_required') : null,
                    ),
                  ),
                  _labelled(
                    label: AppStrings.t('last_name_full'),
                    field: _field(c: c, controller: _lastNameCtrl,
                      hint: 'Dupont',
                      icon: Icons.person_outline_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? AppStrings.t('field_required') : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Row 2 – Date de naissance | Poste / Fonction
                _row(
                  _labelled(
                    label: AppStrings.t('date_of_birth'),
                    field: _datePickerField(),
                  ),
                  _labelled(
                    label: AppStrings.t('job_title'),
                    field: _field(c: c, controller: _posteCtrl,
                      hint: 'Ingénieur',
                      icon: Icons.work_outline_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? AppStrings.t('field_required') : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Row 3 – Adresse email (full width)
                _labelled(
                  label: AppStrings.t('email'),
                  field: _field(c: c, controller: _emailCtrl,
                    hint: 'votre@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return AppStrings.t('field_required');
                      if (!v.contains('@') || !v.contains('.')) {
                        return AppStrings.t('invalid_email_short');
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),

                // Row 4 – Numéro de téléphone (full width)
                _labelled(
                  label: AppStrings.t('phone_number'),
                  field: _field(c: c, controller: _phoneCtrl,
                    hint: '+212 6 XX XX XX XX',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? AppStrings.t('field_required') : null,
                  ),
                ),
                const SizedBox(height: 18),

                // Row 5 – Mot de passe | Confirmation
                _row(
                  _labelled(
                    label: AppStrings.t('password'),
                    field: _field(c: c, controller: _passwordCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      obscure: !_pwVisible,
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _pwVisible = !_pwVisible),
                        icon: Icon(
                          _pwVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: c.textSec,
                          size: 20,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return AppStrings.t('field_required');
                        if (v.length < 8) return AppStrings.t('pw_min_8_err');
                        if (!v.contains(RegExp(r'[A-Z]'))) return AppStrings.t('pw_uppercase_err');
                        if (!v.contains(RegExp(r'[a-z]'))) return AppStrings.t('pw_lowercase_err');
                        if (!v.contains(RegExp(r'[0-9]'))) return AppStrings.t('pw_digit_err');
                        if (!v.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]'))) {
                          return AppStrings.t('pw_special_err');
                        }
                        return null;
                      },
                      onSubmitted: (_) {},
                    ),
                  ),
                  _labelled(
                    label: AppStrings.t('confirm_pw'),
                    field: _field(c: c, controller: _confirmCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      obscure: !_confirmVisible,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onSignup(),
                      suffix: IconButton(
                        onPressed: () => setState(
                            () => _confirmVisible = !_confirmVisible),
                        icon: Icon(
                          _confirmVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: c.textSec,
                          size: 20,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return AppStrings.t('field_required');
                        if (v != _passwordCtrl.text) {
                          return AppStrings.t('pw_no_match');
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                // ── Password strength rules ──────────────────────────────
                const SizedBox(height: 10),
                _PasswordRules(password: _passwordCtrl.text),

                if (_errorMessage != null) _errorBanner(_errorMessage!),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor:
                          kTeal.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black54),
                          )
                        : Text(AppStrings.t('sign_up'),
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${AppStrings.t('already_account')} ',
                          style: TextStyle(color: c.textSec, fontSize: 13)),
                      GestureDetector(
                        onTap: widget.onSwitchToLogin,
                        child: Text(AppStrings.t('sign_in'),
                            style: TextStyle(
                                color: kTeal,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Password Rules Widget ─────────────────────────────────────────────────────

class _PasswordRules extends StatelessWidget {
  final String password;
  const _PasswordRules({required this.password});

  bool _has(String pattern) =>
      RegExp(pattern).hasMatch(password);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (password.isEmpty) return const SizedBox.shrink();

    final rules = [
      (password.length >= 8,        AppStrings.t('pw_min_8')),
      (_has(r'[A-Z]'),              AppStrings.t('pw_uppercase')),
      (_has(r'[a-z]'),              AppStrings.t('pw_lowercase')),
      (_has(r'[0-9]'),              AppStrings.t('pw_digit')),
      (_has(r'[!@#\$%^&*(),.?":{}|<>_\-]'),
                                    AppStrings.t('pw_special')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.t('pw_rules'),
              style: TextStyle(
                  color: c.textSec,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
          const SizedBox(height: 6),
          ...rules.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(
                    r.$1
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 14,
                    color: r.$1
                        ? kTeal
                        : c.textSec.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(r.$2,
                      style: TextStyle(
                          color: r.$1 ? kTeal : c.textSec,
                          fontSize: 11)),
                ]),
              )),
        ],
      ),
    );
  }
}

