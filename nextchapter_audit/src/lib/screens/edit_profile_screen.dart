import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../data/prompts_catalog.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/browse_provider.dart';
import '../providers/profile_provider.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import '../widgets/common/completeness_ring.dart';
import '../widgets/profile/submit_story_dialog.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _aboutMeCtrl = TextEditingController();

  String? _selectedState;
  String? _selectedGender;
  String? _selectedRelationshipStatus;
  DateTime? _dateOfBirth;

  final List<String> _selectedLookingFor = [];
  final List<String> _selectedInterests = [];
  final List<String> _selectedLifeSituation = [];
  final List<String> _selectedModes = [];

  // 3 prompt slots — each can be null or {key, answer}.
  final List<_PromptDraft> _promptDrafts = [
    _PromptDraft(),
    _PromptDraft(),
    _PromptDraft(),
  ];

  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _errorMessage;

  static const List<String> _genderOptions = [
    'Male', 'Female', 'Non-binary', 'Prefer not to say',
  ];
  static const List<String> _relationshipOptions = [
    'Single', 'Divorced', 'Widowed', 'Separated', "It's complicated",
  ];

  @override
  void initState() {
    super.initState();
    _prefillFromExistingProfile();
  }

  void _prefillFromExistingProfile() {
    final profile = context.read<ProfileProvider>().profile;
    if (profile == null) return;

    _firstNameCtrl.text = profile.firstName;
    _cityCtrl.text = profile.city;
    _aboutMeCtrl.text = profile.aboutMe;
    _selectedState = profile.state.isEmpty ? null : profile.state;
    _selectedGender = profile.gender.isEmpty ? null : profile.gender;
    _selectedRelationshipStatus =
        profile.relationshipStatus.isEmpty ? null : profile.relationshipStatus;
    _dateOfBirth = profile.dateOfBirth.year > 1900 ? profile.dateOfBirth : null;
    _selectedLookingFor.addAll(profile.lookingFor);
    _selectedInterests.addAll(profile.interests);
    _selectedLifeSituation.addAll(profile.lifeSituation);
    _selectedModes.addAll(profile.modes.isEmpty ? ['date'] : profile.modes);

    for (int i = 0; i < profile.prompts.length && i < 3; i++) {
      _promptDrafts[i].key = profile.prompts[i].promptKey;
      _promptDrafts[i].controller.text = profile.prompts[i].answer;
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _cityCtrl.dispose();
    _aboutMeCtrl.dispose();
    for (final p in _promptDrafts) {
      p.controller.dispose();
    }
    super.dispose();
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  List<PromptAnswer> _collectedPrompts() {
    final list = <PromptAnswer>[];
    for (int i = 0; i < _promptDrafts.length; i++) {
      final d = _promptDrafts[i];
      final answer = d.controller.text.trim();
      if (d.key != null && answer.isNotEmpty) {
        list.add(PromptAnswer(promptKey: d.key!, answer: answer, position: i));
      }
    }
    return list;
  }

  int _liveCompleteness(int photoCount) {
    return UserProfile.computeCompleteness(
      firstName: _firstNameCtrl.text,
      dateOfBirth: _dateOfBirth,
      city: _cityCtrl.text,
      state: _selectedState ?? '',
      gender: _selectedGender ?? '',
      relationshipStatus: _selectedRelationshipStatus ?? '',
      aboutMe: _aboutMeCtrl.text,
      modes: _selectedModes,
      lookingFor: _selectedLookingFor,
      interests: _selectedInterests,
      lifeSituation: _selectedLifeSituation,
      prompts: _collectedPrompts(),
      photoCount: photoCount,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      setState(() => _errorMessage = 'Please enter your date of birth.');
      return;
    }
    if (_selectedState == null) {
      setState(() => _errorMessage = 'Please select your state.');
      return;
    }
    if (_selectedGender == null) {
      setState(() => _errorMessage = 'Please select your gender.');
      return;
    }
    if (_selectedModes.isEmpty) {
      setState(() => _errorMessage = 'Pick at least one mode (Dating, Friendship, or Activity).');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    final profileProvider = context.read<ProfileProvider>();

    if (!SupabaseService.isConfigured || SupabaseService.client == null) {
      setState(() {
        _saving = false;
        _errorMessage =
            'Cannot save — Supabase is not connected.\n'
            'Reason: ${SupabaseService.configurationError ?? SupabaseService.initError ?? "Unknown error"}\n'
            'Fix lib/config/app_config.dart and rebuild.';
      });
      return;
    }

    final userId = auth.userId;
    if (userId == null) {
      setState(() {
        _saving = false;
        _errorMessage = 'Not logged in.';
      });
      return;
    }

    final success = await profileProvider.saveProfile(
      userId: userId,
      firstName: _firstNameCtrl.text.trim(),
      dateOfBirth: _dateOfBirth!,
      city: _cityCtrl.text.trim(),
      state: _selectedState!,
      gender: _selectedGender!,
      relationshipStatus: _selectedRelationshipStatus ?? '',
      aboutMe: _aboutMeCtrl.text.trim(),
      lookingFor: List.from(_selectedLookingFor),
      interests: List.from(_selectedInterests),
      lifeSituation: List.from(_selectedLifeSituation),
      modes: List.from(_selectedModes),
      prompts: _collectedPrompts(),
      isEmailVerified: auth.isEmailVerified,
    );

    setState(() => _saving = false);

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully!')),
      );
      context.pop();
    } else {
      setState(() => _errorMessage = profileProvider.error ?? 'Save failed. Please try again.');
    }
  }

  // ─── Photo upload ────────────────────────────────────────────────────────

  Future<void> _pickAndUploadPhoto() async {
    final auth = context.read<AuthProvider>();
    final profileProvider = context.read<ProfileProvider>();

    if (profileProvider.profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save your profile first before uploading photos.')),
      );
      return;
    }

    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    final Uint8List bytes = await file.readAsBytes();
    final String mimeType = file.mimeType ?? 'image/jpeg';

    setState(() => _uploadingPhoto = true);

    final success = await profileProvider.uploadPhoto(
      userId: auth.userId!,
      bytes: bytes,
      mimeType: mimeType,
    );

    setState(() => _uploadingPhoto = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success
            ? 'Photo uploaded!'
            : (profileProvider.error ?? 'Upload failed. Please try again.'))),
      );
    }
  }

  Future<void> _deletePhoto(String photoId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text('This photo will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).extension<AppColorsExtension>()!.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final profileProvider = context.read<ProfileProvider>();
    final deleted = await profileProvider.deletePhoto(photoId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(deleted
          ? 'Photo deleted.'
          : (profileProvider.error ?? 'Could not delete photo.')),
    ));
    if (deleted && mounted) {
      await context.read<BrowseProvider>().loadProfiles();
    }
  }

  Future<void> _setPrimaryPhoto(String photoId) async {
    final profileProvider = context.read<ProfileProvider>();
    final ok = await profileProvider.setPrimaryPhoto(photoId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Main photo updated.'
          : (profileProvider.error ?? 'Could not update main photo.')),
    ));
    // Force the browse feed to re-fetch so the new main photo shows on
    // profile cards elsewhere in the app.
    if (!mounted) return;
    await context.read<BrowseProvider>().loadProfiles();
  }


  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final profileProvider = context.watch<ProfileProvider>();
    final photoCount = profileProvider.photoRecords.length;
    // Single source of truth for the completion percentage: the value stored
    // on profiles.completeness_score (trigger-maintained on the server).
    // My Profile card + Profile Detail read the same field.
    final completeness = profileProvider.profile?.completenessScore
        ?? _liveCompleteness(photoCount);

    return Scaffold(
      appBar: AppBar(
        title: Text(profileProvider.hasProfile ? 'Edit Profile' : 'Create Profile'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: AppTheme.spacingMd),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text('Save', style: text.labelLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              children: [
                _CompletenessHeader(score: completeness, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingMd),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingMd),
                    decoration: BoxDecoration(
                      color: appColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: appColors.danger.withOpacity(0.3)),
                    ),
                    child: Text(_errorMessage!, style: text.bodySmall?.copyWith(color: appColors.danger)),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                ],

                // ── Photos ─────────────────────────────────────────────
                _SectionHeader(title: 'Profile Photos', icon: Icons.photo_library_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                _PhotoGrid(
                  photoRecords: profileProvider.photoRecords,
                  uploading: _uploadingPhoto,
                  onUpload: _pickAndUploadPhoto,
                  onDelete: _deletePhoto,
                  onSetPrimary: _setPrimaryPhoto,
                  colors: colors,
                  appColors: appColors,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Modes ──────────────────────────────────────────────
                _SectionHeader(title: 'I am here to…', icon: Icons.tune, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                _ModesSelector(
                  selected: _selectedModes,
                  onToggle: (m) => setState(() {
                    if (_selectedModes.contains(m)) {
                      _selectedModes.remove(m);
                    } else {
                      _selectedModes.add(m);
                    }
                  }),
                  colors: colors,
                  text: text,
                  appColors: appColors,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Basic info ─────────────────────────────────────────
                _SectionHeader(title: 'Basic Info', icon: Icons.person_outline, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                TextFormField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(labelText: 'First Name', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppTheme.spacingMd),
                GestureDetector(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
                      firstDate: DateTime(1920),
                      lastDate: DateTime(now.year - 18, now.month, now.day),
                      helpText: 'You must be 18 or older',
                    );
                    if (picked != null) setState(() => _dateOfBirth = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _dateOfBirth != null
                          ? '${_dateOfBirth!.month}/${_dateOfBirth!.day}/${_dateOfBirth!.year}'
                          : 'Select your date of birth',
                      style: text.bodyMedium?.copyWith(
                        color: _dateOfBirth != null ? colors.onSurface : appColors.subtleText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.people_outline)),
                  items: _genderOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setState(() => _selectedGender = v),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                DropdownButtonFormField<String>(
                  value: _selectedRelationshipStatus,
                  decoration: const InputDecoration(labelText: 'Relationship Status', prefixIcon: Icon(Icons.favorite_border)),
                  items: _relationshipOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState(() => _selectedRelationshipStatus = v),
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Location ──────────────────────────────────────────
                _SectionHeader(title: 'Location', icon: Icons.location_on_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                DropdownButtonFormField<String>(
                  value: _selectedState,
                  decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.map_outlined)),
                  isExpanded: true,
                  items: _usStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _selectedState = v),
                ),
                const SizedBox(height: AppTheme.spacingMd),
                TextFormField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── About Me ──────────────────────────────────────────
                _SectionHeader(title: 'About Me', icon: Icons.info_outline, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                TextFormField(
                  controller: _aboutMeCtrl,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Tell people about yourself (≥30 chars)',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: AppTheme.spacingXxl),
                      child: Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Prompts ───────────────────────────────────────────
                _SectionHeader(
                  title: 'Your Story (up to 3 prompts)',
                  icon: Icons.format_quote_outlined,
                  colors: colors,
                  text: text,
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Text(
                  'Pick prompts that help people understand who you are.',
                  style: text.bodySmall?.copyWith(color: appColors.subtleText),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                for (int i = 0; i < _promptDrafts.length; i++) ...[
                  _PromptEditor(
                    index: i,
                    draft: _promptDrafts[i],
                    usedKeys: _promptDrafts
                        .where((d) => d != _promptDrafts[i])
                        .map((d) => d.key)
                        .whereType<String>()
                        .toSet(),
                    onChanged: () => setState(() {}),
                    colors: colors,
                    appColors: appColors,
                    text: text,
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                ],
                const SizedBox(height: AppTheme.spacingSm),

                // ── Looking For ───────────────────────────────────────
                _SectionHeader(title: 'Looking For', icon: Icons.search_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                _ChipSelector(
                  options: LookingForOptions.all,
                  selected: _selectedLookingFor,
                  onToggle: (v) => setState(() {
                    _selectedLookingFor.contains(v)
                        ? _selectedLookingFor.remove(v)
                        : _selectedLookingFor.add(v);
                  }),
                  colors: colors,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Interests ─────────────────────────────────────────
                _SectionHeader(title: 'Interests', icon: Icons.interests_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                _ChipSelector(
                  options: InterestOptions.all,
                  selected: _selectedInterests,
                  onToggle: (v) => setState(() {
                    _selectedInterests.contains(v)
                        ? _selectedInterests.remove(v)
                        : _selectedInterests.add(v);
                  }),
                  colors: colors,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Life Situation ────────────────────────────────────
                _SectionHeader(title: 'Life Situation', icon: Icons.timeline_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                _ChipSelector(
                  options: LifeSituationOptions.all,
                  selected: _selectedLifeSituation,
                  onToggle: (v) => setState(() {
                    _selectedLifeSituation.contains(v)
                        ? _selectedLifeSituation.remove(v)
                        : _selectedLifeSituation.add(v);
                  }),
                  colors: colors,
                ),
                const SizedBox(height: AppTheme.spacingLg),

                // ── Success Story ─────────────────────────────────────
                _SectionHeader(title: 'Success Story', icon: Icons.stars_outlined, colors: colors, text: text),
                const SizedBox(height: AppTheme.spacingSm),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.auto_stories_outlined,
                        color: colors.primary),
                    title: const Text('Share your Next Chapter story'),
                    subtitle: const Text(
                      'Met someone through Next Chapter? Share it. '
                      'An admin will review before it goes public.',
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const SubmitStoryDialog(),
                      ),
                      child: const Text('Share'),
                    ),
                    isThreeLine: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd, vertical: 4),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXxl),

                // ── Save button ───────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save Profile'),
                ),
                const SizedBox(height: AppTheme.spacingLg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Prompt draft holder ─────────────────────────────────────────────────────

class _PromptDraft {
  String? key;
  final TextEditingController controller = TextEditingController();
}

// ─── Helper widgets ──────────────────────────────────────────────────────────

class _CompletenessHeader extends StatelessWidget {
  final int score;
  final ColorScheme colors;
  final TextTheme text;

  const _CompletenessHeader({required this.score, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          CompletenessRing(score: score, size: 64),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile completeness', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Looking great! Your profile stands out.'
                      : score >= 50
                          ? 'Good start — add photos and prompts to boost it.'
                          : 'Add more details to attract better matches.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModesSelector extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final ColorScheme colors;
  final TextTheme text;
  final AppColorsExtension appColors;

  const _ModesSelector({
    required this.selected,
    required this.onToggle,
    required this.colors,
    required this.text,
    required this.appColors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: ModeOptions.all.map((mode) {
        final isSel = selected.contains(mode);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            onTap: () => onToggle(mode),
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: isSel ? colors.primaryContainer.withOpacity(0.4) : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: isSel ? colors.primary : colors.outlineVariant,
                  width: isSel ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSel ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSel ? colors.primary : appColors.subtleText,
                  ),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ModeOptions.label(mode), style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          ModeOptions.description(mode),
                          style: text.bodySmall?.copyWith(color: appColors.subtleText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PromptEditor extends StatelessWidget {
  final int index;
  final _PromptDraft draft;
  final Set<String> usedKeys;
  final VoidCallback onChanged;
  final ColorScheme colors;
  final AppColorsExtension appColors;
  final TextTheme text;

  const _PromptEditor({
    required this.index,
    required this.draft,
    required this.usedKeys,
    required this.onChanged,
    required this.colors,
    required this.appColors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final available = PromptCatalog.all
        .where((p) => !usedKeys.contains(p))
        .toList();

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, size: AppTheme.iconSm, color: colors.primary),
              const SizedBox(width: AppTheme.spacingXs),
              Text('Prompt ${index + 1}', style: text.labelLarge?.copyWith(color: colors.primary)),
              const Spacer(),
              if (draft.key != null)
                IconButton(
                  tooltip: 'Clear prompt',
                  icon: Icon(Icons.close, size: 18, color: appColors.subtleText),
                  onPressed: () {
                    draft.key = null;
                    draft.controller.clear();
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          DropdownButtonFormField<String>(
            value: draft.key,
            isExpanded: true,
            itemHeight: 72,
            menuMaxHeight: 380,
            decoration: const InputDecoration(labelText: 'Choose a prompt'),
            selectedItemBuilder: (context) {
              final all = <String>[
                if (draft.key != null && !available.contains(draft.key)) draft.key!,
                ...available,
              ];
              return all
                  .map((p) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(p,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList();
            },
            items: [
              if (draft.key != null && !available.contains(draft.key))
                DropdownMenuItem(
                  value: draft.key,
                  child: Text(draft.key!,
                      softWrap: true,
                      maxLines: 3,
                      style: const TextStyle(height: 1.2)),
                ),
              ...available.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p,
                        softWrap: true,
                        maxLines: 3,
                        style: const TextStyle(height: 1.2)),
                  )),
            ],
            onChanged: (v) {
              draft.key = v;
              onChanged();
            },
          ),
          if (draft.key != null) ...[
            const SizedBox(height: AppTheme.spacingSm),
            TextField(
              controller: draft.controller,
              maxLength: 150,
              maxLines: 3,
              minLines: 2,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Your answer',
                hintText: 'Keep it real — 150 chars max',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ColorScheme colors;
  final TextTheme text;

  const _SectionHeader({required this.title, required this.icon, required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppTheme.iconMd, color: colors.primary),
        const SizedBox(width: AppTheme.spacingSm),
        Text(title, style: text.titleMedium?.copyWith(color: colors.primary)),
      ],
    );
  }
}

class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final ColorScheme colors;

  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: AppTheme.spacingSm,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) => onToggle(option),
          selectedColor: colors.primaryContainer,
          checkmarkColor: colors.primary,
        );
      }).toList(),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<Map<String, dynamic>> photoRecords;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSetPrimary;
  final ColorScheme colors;
  final AppColorsExtension appColors;

  const _PhotoGrid({
    required this.photoRecords,
    required this.uploading,
    required this.onUpload,
    required this.onDelete,
    required this.onSetPrimary,
    required this.colors,
    required this.appColors,
  });

  @override
  Widget build(BuildContext context) {
    final photoTiles = List<Widget>.generate(photoRecords.length, (index) {
      final record = photoRecords[index];
      final photoId = record['id'] as String;
      final url = record['display_url'] as String;
      return _PhotoTile(
        key: ValueKey<String>('photo-tile-$photoId'),
        photoId: photoId,
        url: url,
        isPrimary: index == 0,
        onDelete: onDelete,
        onSetPrimary: index == 0 ? null : onSetPrimary,
        colors: colors,
        appColors: appColors,
      );
    }, growable: false);

    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: AppTheme.spacingSm,
      children: [
        ...photoTiles,
        GestureDetector(
          onTap: uploading ? null : onUpload,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: uploading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: colors.primary, size: AppTheme.iconLg),
                      const SizedBox(height: AppTheme.spacingXs),
                      Text('Add Photo', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.primary)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String photoId;
  final String url;
  final bool isPrimary;
  final ValueChanged<String> onDelete;
  final ValueChanged<String>? onSetPrimary;
  final ColorScheme colors;
  final AppColorsExtension appColors;

  const _PhotoTile({
    super.key,
    required this.photoId,
    required this.url,
    required this.isPrimary,
    required this.onDelete,
    required this.onSetPrimary,
    required this.colors,
    required this.appColors,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Image.network(
            url,
            key: ValueKey<String>('photo-image-$photoId-$url'),
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            errorBuilder: (_, __, ___) => Container(
              width: 100,
              height: 100,
              color: colors.surfaceContainerLow,
              child: Icon(Icons.broken_image_outlined, color: appColors.subtleText),
            ),
          ),
        ),
        if (isPrimary)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('MAIN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  )),
            ),
          ),
        if (!isPrimary && onSetPrimary != null)
          Positioned(
            left: 4,
            bottom: 4,
            child: GestureDetector(
              onTap: () => onSetPrimary?.call(photoId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Set as main',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => onDelete(photoId),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: appColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}


const _usStates = <String>[
  'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA','KS','KY','LA','ME','MD',
  'MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC',
  'SD','TN','TX','UT','VT','VA','WA','WV','WI','WY','DC',
];
