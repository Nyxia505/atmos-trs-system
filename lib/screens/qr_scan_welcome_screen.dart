import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_welcome_destination_context.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_logo.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Welcome shown after a new visitor scans an LGU or spot QR without an account.
///
/// Asks party size + gender split (pila kabook / baye / laki) before signup.
/// Persisted with the pending QR payload for LGU analytics after verify.
class QrScanWelcomeScreen extends StatefulWidget {
  const QrScanWelcomeScreen({super.key});

  @override
  State<QrScanWelcomeScreen> createState() => _QrScanWelcomeScreenState();
}

class _QrScanWelcomeScreenState extends State<QrScanWelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _pageBg = Color(0xFFF8FAFC);
  static const Color _cardBg = Colors.white;
  static const Color _bodyText = Color(0xFF475569);
  static const Color _titleText = Color(0xFF0F172A);
  static const Color _mutedText = Color(0xFF64748B);
  static const double _cardRadius = 18;

  QrWelcomeDestinationContext? _destination;
  bool _loading = true;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  final TextEditingController _partyController =
      TextEditingController(text: '1');
  final TextEditingController _femaleController =
      TextEditingController(text: '0');
  final TextEditingController _maleController =
      TextEditingController(text: '0');

  int _parseCount(TextEditingController c, {int fallback = 0}) {
    final n = int.tryParse(c.text.trim());
    if (n == null || n < 0) return fallback;
    return n > 99 ? 99 : n;
  }

  /// Total people in the party (including the scanner).
  int get _partySize {
    final n = _parseCount(_partyController, fallback: 1);
    return n < 1 ? 1 : n;
  }

  int get _femaleCount => _parseCount(_femaleController);
  int get _maleCount => _parseCount(_maleController);

  String? get _partyValidationError {
    if (_femaleCount + _maleCount != _partySize) {
      return 'Baye + laki should equal total party ($_partySize). '
          'Now: ${_femaleCount + _maleCount}.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    void refresh() {
      if (mounted) setState(() {});
    }

    _partyController.addListener(refresh);
    _femaleController.addListener(refresh);
    _maleController.addListener(refresh);
    _loadContext();
  }

  @override
  void dispose() {
    _partyController.dispose();
    _femaleController.dispose();
    _maleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<bool> _persistPartyDemographics() async {
    final err = _partyValidationError;
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    }
    await PendingSpotCheckInStorage.setPartyDemographics(
      partySize: _partySize,
      femaleCount: _femaleCount,
      maleCount: _maleCount,
    );
    await PendingLguCheckInStorage.setPartyDemographics(
      partySize: _partySize,
      femaleCount: _femaleCount,
      maleCount: _maleCount,
    );
    return true;
  }

  Future<void> _loadContext() async {
    if (FirebaseAuth.instance.currentUser != null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/landing');
      }
      return;
    }

    final destination =
        await QrWelcomeDestinationResolver.resolveFromPendingScan();

    if (!mounted) return;

    if (destination == null) {
      Navigator.pushReplacementNamed(context, '/landing');
      return;
    }

    setState(() {
      _destination = destination;
      _loading = false;
    });
    _fadeController.forward();
  }

  Future<void> _goToSignup() async {
    if (!await _persistPartyDemographics()) return;
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/signup');
  }

  Future<void> _goToLogin() async {
    if (!await _persistPartyDemographics()) return;
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _continueAsGuest() async {
    if (!await _persistPartyDemographics()) return;
    if (!mounted) return;
    final destination = _destination;
    Navigator.pushReplacementNamed(
      context,
      '/landing',
      arguments: destination == null
          ? null
          : <String, dynamic>{
              'fromQrWelcomeGuest': true,
              'welcomeMessage':
                  'Welcome to ${destination.name}! Browse destinations and '
                  'tourism info — create a free account anytime for QR check-ins '
                  'and your Digital Tourist ID.',
            },
    );
  }

  void _exploreAsGuest() {
    _continueAsGuest();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.brandOrange),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeroBanner()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, -28),
                            child: _buildDestinationCard(),
                          ),
                          const SizedBox(height: 4),
                          _buildPartySizeCard(),
                          const SizedBox(height: 24),
                          _buildSectionTitle('Explore Before You Register'),
                          const SizedBox(height: 12),
                          _buildExploreGrid(),
                          const SizedBox(height: 28),
                          _buildBenefitsCard(),
                          const SizedBox(height: 28),
                          _buildPrimaryCta(),
                          const SizedBox(height: 12),
                          _buildGuestButton(),
                          const SizedBox(height: 8),
                          _buildSignInLink(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroBanner() {
    final destination = _destination!;
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SpotImage(
            imageUrl: destination.imageUrl,
            spotId: destination.spotId,
            municipalityId: destination.municipalityId,
            spotName: destination.name,
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AtmosBrandLogo(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    borderRadius: 10,
                    elevation: 2,
                  ),
                  const Spacer(),
                  Text(
                    '👋 Welcome to ATMOS TRS!',
                    style: AtmosBrandTypography.heroHeadline(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(
                          color: Colors.black38,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Welcome to one of Misamis Occidental\'s amazing destinations. '
                    'We\'re excited to be part of your journey.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationCard() {
    final destination = _destination!;
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(_cardRadius),
            ),
            child: SizedBox(
              height: 160,
              child: SpotImage(
                imageUrl: destination.imageUrl,
                spotId: destination.spotId,
                municipalityId: destination.municipalityId,
                spotName: destination.name,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (destination.isMunicipalityScan)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Municipality',
                      style: TextStyle(
                        color: AppTheme.brandOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Destination',
                      style: TextStyle(
                        color: AppTheme.brandOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  destination.name,
                  style: AtmosBrandTypography.displayTitle(
                    color: _titleText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: AppTheme.brandOrange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        destination.municipality,
                        style: const TextStyle(
                          color: _mutedText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  destination.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _bodyText,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AtmosBrandTypography.displayTitle(
        color: _titleText,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildExploreGrid() {
    const items = <_ExploreFeature>[
      _ExploreFeature(
        emoji: '📍',
        title: 'Discover nearby attractions',
        icon: Icons.near_me_rounded,
      ),
      _ExploreFeature(
        emoji: '📝',
        title: 'Learn about the destination',
        icon: Icons.menu_book_rounded,
      ),
      _ExploreFeature(
        emoji: '🌄',
        title: 'View beautiful photos',
        icon: Icons.photo_library_rounded,
      ),
      _ExploreFeature(
        emoji: '🗺',
        title: 'Explore tourist information',
        icon: Icons.map_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 520 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 4 ? 0.95 : 1.05,
          ),
          itemBuilder: (context, index) => _ExploreFeatureCard(
            item: items[index],
            onTap: _exploreAsGuest,
          ),
        );
      },
    );
  }

  Widget _buildPartySizeCard() {
    final genderSum = _femaleCount + _maleCount;
    final mismatch = genderSum != _partySize;

    InputDecoration fieldDecoration(String label, String hint) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppTheme.brandOrange,
            width: 1.5,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pila sila kabook?',
            style: AtmosBrandTypography.displayTitle(
              color: _titleText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your total party size, then how many females (baye) '
            'and males (laki). Include yourself in the total.',
            style: TextStyle(
              color: _bodyText,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _partyController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: fieldDecoration('Total party (kabook)', 'e.g. 5'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _femaleController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: fieldDecoration('Baye (female)', 'e.g. 2'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maleController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: fieldDecoration('Laki (male)', 'e.g. 3'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (mismatch ? Colors.red : AppTheme.brandOrange)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              mismatch
                  ? 'Baye ($_femaleCount) + laki ($_maleCount) = $genderSum — '
                      'should equal total $_partySize'
                  : 'Total visitors: $_partySize '
                      '($_femaleCount baye · $_maleCount laki)',
              style: TextStyle(
                color: mismatch ? Colors.red.shade700 : AppTheme.brandOrange,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitsCard() {
    const benefits = [
      'Faster QR check-ins at destinations',
      'Digital Tourist ID',
      'After signup: VR Tour, Trip Planner, or continue on the website / in the app',
      'Save your travel history',
      'Receive tourism announcements and updates',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandOrange.withValues(alpha: 0.1),
            const Color(0xFFFFF7ED),
          ],
        ),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(
          color: AppTheme.brandOrange.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandOrange.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why Create an Account?',
            style: AtmosBrandTypography.displayTitle(
              color: _titleText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...benefits.map(
            (benefit) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppTheme.brandOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      benefit,
                      style: const TextStyle(
                        color: _bodyText,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryCta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: _goToSignup,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
            shadowColor: AppTheme.brandOrange.withValues(alpha: 0.35),
          ),
          child: const Text(
            'Create Free Account',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Register to check in, then choose VR Tour or Trip Planner — '
          'continue on the website or get the ATMOS app for VR on your phone.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _mutedText.withValues(alpha: 0.95),
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildGuestButton() {
    return OutlinedButton(
      onPressed: _continueAsGuest,
      style: OutlinedButton.styleFrom(
        foregroundColor: _titleText,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Text(
        'Continue as Guest',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  Widget _buildSignInLink() {
    return Center(
      child: TextButton(
        onPressed: _goToLogin,
        child: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 14, color: _mutedText),
            children: [
              TextSpan(text: 'Already have an account? '),
              TextSpan(
                text: 'Sign In',
                style: TextStyle(
                  color: AppTheme.brandOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreFeature {
  const _ExploreFeature({
    required this.emoji,
    required this.title,
    required this.icon,
  });

  final String emoji;
  final String title;
  final IconData icon;
}

class _ExploreFeatureCard extends StatelessWidget {
  const _ExploreFeatureCard({
    required this.item,
    required this.onTap,
  });

  final _ExploreFeature item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.brandOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        item.icon,
                        size: 18,
                        color: AppTheme.brandOrange,
                      ),
                    ),
                    const Spacer(),
                    Text(item.emoji, style: const TextStyle(fontSize: 18)),
                  ],
                ),
                const Spacer(),
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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
