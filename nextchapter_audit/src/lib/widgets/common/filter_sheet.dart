import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../providers/browse_provider.dart';
import '../../theme/theme.dart';

class FilterSheet extends StatelessWidget {
  final BrowseProvider provider;

  const FilterSheet({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Row(
                children: [
                  Text('Filters', style: text.titleLarge),
                  const Spacer(),
                  if (provider.hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        provider.clearFilters();
                        Navigator.pop(context);
                      },
                      child: const Text('Clear All'),
                    ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                children: [
                  _SectionTitle(title: 'I want to find people for…', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  Wrap(
                    spacing: AppTheme.spacingSm,
                    runSpacing: AppTheme.spacingSm,
                    children: ModeOptions.all.map((m) => FilterChip(
                      label: Text(ModeOptions.label(m)),
                      selected: provider.modeFilters.contains(m),
                      onSelected: (_) => provider.toggleMode(m),
                      selectedColor: colors.primaryContainer,
                      checkmarkColor: colors.primary,
                    )).toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),

                  _SectionTitle(title: 'Location', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  DropdownButtonFormField<String>(
                    value: provider.stateFilter,
                    decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.map_outlined)),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All States')),
                      ...UsStates.fullNames.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: provider.setStateFilter,
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                  TextFormField(
                    initialValue: provider.cityFilter,
                    decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
                    onChanged: provider.setCityFilter,
                  ),
                  const SizedBox(height: AppTheme.spacingLg),

                  _SectionTitle(title: 'Age Range', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  RangeSlider(
                    values: provider.ageRange,
                    min: 18,
                    max: 100,
                    divisions: 82,
                    labels: RangeLabels(
                      provider.ageRange.start.round().toString(),
                      provider.ageRange.end.round().toString(),
                    ),
                    onChanged: (r) {
                      // Only push to server when the user lets go — onChanged
                      // fires continuously, so debounce via onChangeEnd below.
                    },
                    onChangeEnd: (r) => provider.setAgeRange(r),
                  ),
                  Center(
                    child: Text(
                      '${provider.ageRange.start.round()} — ${provider.ageRange.end.round()} years',
                      style: text.bodySmall,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),

                  _SectionTitle(title: 'Looking For', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  Wrap(
                    spacing: AppTheme.spacingSm,
                    runSpacing: AppTheme.spacingSm,
                    children: LookingForOptions.all.map((option) => FilterChip(
                      label: Text(option),
                      selected: provider.lookingForFilters.contains(option),
                      onSelected: (_) => provider.toggleLookingFor(option),
                      selectedColor: colors.primaryContainer,
                      checkmarkColor: colors.primary,
                    )).toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),

                  _SectionTitle(title: 'Interests', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  Wrap(
                    spacing: AppTheme.spacingSm,
                    runSpacing: AppTheme.spacingSm,
                    children: InterestOptions.all.map((interest) => FilterChip(
                      label: Text(interest),
                      selected: provider.interestFilters.contains(interest),
                      onSelected: (_) => provider.toggleInterest(interest),
                      selectedColor: colors.secondaryContainer,
                      checkmarkColor: colors.secondary,
                    )).toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),

                  _SectionTitle(title: 'Verification', text: text),
                  const SizedBox(height: AppTheme.spacingSm),
                  SwitchListTile(
                    value: provider.verifiedOnly,
                    onChanged: (v) => provider.setVerifiedOnly(v),
                    title: Text('Verified profiles only', style: text.bodyMedium),
                    subtitle: Text('Show only profiles with at least one verification', style: text.bodySmall),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: AppTheme.spacingXl),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Show ${provider.profiles.length} Results'),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final TextTheme text;

  const _SectionTitle({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: text.titleSmall);
  }
}
