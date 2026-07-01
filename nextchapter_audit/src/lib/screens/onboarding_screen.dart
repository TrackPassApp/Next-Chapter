import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../repositories/profile_repository.dart';

/// Multi-step onboarding wizard. Drives a new user from "just confirmed email"
/// to a fully complete profile that the rest of the app can render.
///
/// After the bootstrap trigger creates the profile row in B1, the wizard fills
/// in every required field and flips `is_complete = true` at the end.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _totalSteps = 9;
  final PageController _pc = PageController();
  int _step = 0;
  bool _saving = false;
  String? _error;

  // Form state
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  DateTime? _dob;
  String? _stateCode;
  String? _gender;
  String? _relationshipStatus;
  final Set<String> _modes = {'date'};
  final Set<String> _lookingFor = {};
  final Set<String> _lifeSituation = {};
  final Set<String> _interests = {};

  @override
  void initState() {
    super.initState();
    // Pre-fill from any partial profile that already exists (e.g. signup DoB).
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    final auth = context.read<AuthProvider>();
    final profileProvider = context.read<ProfileProvider>();
    final uid = auth.userId;
    if (uid == null) return;
    if (profileProvider.profile == null) {
      await profileProvider.loadProfile(uid);
    }
    final p = profileProvider.profile;
    if (p == null) return;
    setState(() {
      if (p.firstName.isNotEmpty) _nameCtrl.text = p.firstName;
      if (p.city.isNotEmpty) _cityCtrl.text = p.city;
      if (p.aboutMe.isNotEmpty) _aboutCtrl.text = p.aboutMe;
      if (p.dateOfBirth.year > 1900) _dob = p.dateOfBirth;
      if (p.state.isNotEmpty) _stateCode = p.state;
      if (p.gender.isNotEmpty) _gender = p.gender;
      if (p.relationshipStatus.isNotEmpty) _relationshipStatus = p.relationshipStatus;
      if (p.modes.isNotEmpty) {
        _modes
          ..clear()
          ..addAll(p.modes);
      }
      _lookingFor.addAll(p.lookingFor);
      _lifeSituation.addAll(p.lifeSituation);
      _interests.addAll(p.interests);
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  bool get _canAdvance {
    switch (_step) {
      case 0: return true;
      case 1: return _nameCtrl.text.trim().isNotEmpty && _dob != null && _age18Plus(_dob!);
      case 2: return _modes.isNotEmpty;
      case 3: return _cityCtrl.text.trim().isNotEmpty && _stateCode != null;
      case 4: return _gender != null && _relationshipStatus != null;
      case 5: return _lookingFor.isNotEmpty;
      case 6: return true; // life situation optional
      case 7: return _interests.length >= 3;
      case 8: return _aboutCtrl.text.trim().length >= 20;
      default: return false;
    }
  }

  bool _age18Plus(DateTime dob) {
    final now = DateTime.now();
    int a = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
    return a >= 18;
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _pc.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pc.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    final auth = context.read<AuthProvider>();
    final profileProvider = context.read<ProfileProvider>();
    final userId = auth.userId;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ProfileRepository.instance;
      final profileId = await repo.upsertProfile(
        userId: userId,
        firstName: _nameCtrl.text.trim(),
        dateOfBirth: _dob!,
        city: _cityCtrl.text.trim(),
        state: _stateCode!,
        gender: _gender!,
        relationshipStatus: _relationshipStatus!,
        aboutMe: _aboutCtrl.text.trim(),
        modes: _modes.toList(),
      );
      if (profileId != null) {
        await Future.wait([
          repo.saveInterests(profileId, _interests.toList()),
          repo.saveLookingFor(profileId, _lookingFor.toList()),
          repo.saveLifeSituation(profileId, _lifeSituation.toList()),
        ]);
        await repo.markComplete(userId, completenessScore: _computeScore());
      }

      await profileProvider.loadProfile(userId);
      if (!mounted) return;

      // Show the one-time Founder Letter after the very first onboarding
      // completion. Keyed by user_id so it never re-shows for this user on
      // this device.
      final prefs = await SharedPreferences.getInstance();
      final key = 'founder_letter_seen_$userId';
      final alreadySeen = prefs.getBool(key) ?? false;
      if (!alreadySeen) {
        await prefs.setBool(key, true);
        if (!mounted) return;
        context.go('/welcome-letter');
        return;
      }
      context.go('/browse');
    } catch (e) {
      setState(() => _error = 'Could not save your profile. $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _computeScore() {
    int s = 0;
    if (_nameCtrl.text.isNotEmpty) s += 10;
    if (_dob != null) s += 10;
    if (_cityCtrl.text.isNotEmpty && _stateCode != null) s += 10;
    if (_gender != null && _relationshipStatus != null) s += 10;
    if (_modes.isNotEmpty) s += 10;
    if (_lookingFor.isNotEmpty) s += 10;
    if (_interests.length >= 3) s += 10;
    if (_aboutCtrl.text.length >= 20) s += 10;
    if (_lifeSituation.isNotEmpty) s += 10;
    // Photos add their +10 once added in Edit Profile (B3 feature)
    return s;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _Header(step: _step, totalSteps: _totalSteps, onBack: _step == 0 ? null : _back),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _step0Welcome(),
                  _step1NameDob(),
                  _step2Modes(),
                  _step3Location(),
                  _step4Identity(),
                  _step5LookingFor(),
                  _step6LifeSituation(),
                  _step7Interests(),
                  _step8About(),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            _Footer(
              canAdvance: _canAdvance && !_saving,
              saving: _saving,
              isLast: _step == _totalSteps - 1,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }

  // ── Pages ──────────────────────────────────────────────────────────────────

  Widget _step0Welcome() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Welcome to Next Chapter.', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(
            'A few quick questions to set up your profile. This takes about a minute, '
            'and everything you share is in your control. You can refine any of it later.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'No swipes. No paywalls. No games.',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _step1NameDob() {
    return _Page(
      title: 'What should we call you?',
      subtitle: 'Your first name shows on your profile. Your date of birth confirms you are 18 or older — it is never shown publicly.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'First name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_dob == null
                ? 'Choose your date of birth'
                : '${_dob!.month}/${_dob!.day}/${_dob!.year}'),
            onPressed: _pickDob,
          ),
          if (_dob != null && !_age18Plus(_dob!))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You must be 18 or older to use Next Chapter.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 35, now.month, now.day),
      firstDate: DateTime(now.year - 100, 1, 1),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select your date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Widget _step2Modes() {
    return _Page(
      title: 'What are you here for?',
      subtitle: 'Pick one or more. You can be open to all three. We never charge for messaging in any of them.',
      child: Column(
        children: ModeOptions.all.map((m) {
          final selected = _modes.contains(m);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                if (selected) {
                  if (_modes.length > 1) _modes.remove(m);
                } else {
                  _modes.add(m);
                }
              }),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ModeOptions.label(m),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(ModeOptions.description(m),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _step3Location() {
    return _Page(
      title: 'Where are you?',
      subtitle: 'Used to surface people near you. You can change this later.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _stateCode,
            decoration: const InputDecoration(labelText: 'State'),
            items: UsStates.all
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _stateCode = v),
          ),
        ],
      ),
    );
  }

  Widget _step4Identity() {
    return _Page(
      title: 'A little about you',
      subtitle: 'These help other members understand who you are. Pick what fits.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('I am a…', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: GenderOptions.all
                .map((g) => ChoiceChip(
                      label: Text(g),
                      selected: _gender == g,
                      onSelected: (_) => setState(() => _gender = g),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Relationship status', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: RelationshipStatusOptions.all
                .map((r) => ChoiceChip(
                      label: Text(r),
                      selected: _relationshipStatus == r,
                      onSelected: (_) => setState(() => _relationshipStatus = r),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _step5LookingFor() {
    return _Page(
      title: 'What are you looking for?',
      subtitle: 'Pick anything that resonates. Multi-select.',
      child: _ChipMultiSelect(
        options: LookingForOptions.all,
        selected: _lookingFor,
        onChange: (s) => setState(() {}),
      ),
    );
  }

  Widget _step6LifeSituation() {
    return _Page(
      title: 'Life chapter (optional)',
      subtitle: 'Helps connect you with people on a similar journey. Totally optional.',
      child: _ChipMultiSelect(
        options: LifeSituationOptions.all,
        selected: _lifeSituation,
        onChange: (s) => setState(() {}),
      ),
    );
  }

  Widget _step7Interests() {
    return _Page(
      title: 'What do you enjoy?',
      subtitle: 'Pick at least three. We use these to surface common ground.',
      child: _ChipMultiSelect(
        options: InterestOptions.all,
        selected: _interests,
        onChange: (s) => setState(() {}),
      ),
    );
  }

  Widget _step8About() {
    return _Page(
      title: 'A short note about you',
      subtitle: 'Two or three sentences is plenty. Write like you would to a new neighbor.',
      child: TextField(
        controller: _aboutCtrl,
        maxLines: 6,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'About me',
          hintText: 'What makes you, you? What kind of connections are you hoping for?',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;
  const _Header({required this.step, required this.totalSteps, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / totalSteps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
          ),
          const SizedBox(width: 12),
          Text('${step + 1} / $totalSteps',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool canAdvance;
  final bool saving;
  final bool isLast;
  final VoidCallback onNext;
  const _Footer({
    required this.canAdvance,
    required this.saving,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: canAdvance ? onNext : null,
          child: saving
              ? const SizedBox(
                  height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isLast ? 'Finish & Continue' : 'Continue'),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Page({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _ChipMultiSelect extends StatefulWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChange;
  const _ChipMultiSelect({
    required this.options,
    required this.selected,
    required this.onChange,
  });

  @override
  State<_ChipMultiSelect> createState() => _ChipMultiSelectState();
}

class _ChipMultiSelectState extends State<_ChipMultiSelect> {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.options.map((opt) {
        final on = widget.selected.contains(opt);
        return FilterChip(
          label: Text(opt),
          selected: on,
          onSelected: (_) {
            setState(() {
              if (on) {
                widget.selected.remove(opt);
              } else {
                widget.selected.add(opt);
              }
            });
            widget.onChange(widget.selected);
          },
        );
      }).toList(),
    );
  }
}
