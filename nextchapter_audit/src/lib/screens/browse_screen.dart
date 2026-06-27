import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/browse_provider.dart';
import '../theme/theme.dart';
import '../widgets/common/profile_card.dart';
import '../widgets/common/filter_sheet.dart';
import '../widgets/common/ad_placeholder.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().userId;
      // Block list will be populated in Batch B6 once the user_blocks table lands.
      context.read<BrowseProvider>().loadProfiles(currentUserId: userId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<BrowseProvider>(),
        child: Consumer<BrowseProvider>(
          builder: (_, provider, __) => FilterSheet(provider: provider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final appColors = theme.extension<AppColorsExtension>()!;
    final provider = context.watch<BrowseProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    int crossAxisCount;
    if (width < 500) {
      crossAxisCount = 2;
    } else if (width < 900) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 4;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Profiles'),
        actions: [
          if (provider.hasActiveFilters)
            TextButton.icon(
              onPressed: provider.clearFilters,
              icon: Icon(Icons.clear, size: AppTheme.iconSm, color: appColors.danger),
              label: Text('Clear', style: text.labelMedium?.copyWith(color: appColors.danger)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name, city, or state...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                provider.setSearchQuery('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                    ),
                    onChanged: provider.setSearchQuery,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Badge(
                  isLabelVisible: provider.hasActiveFilters,
                  backgroundColor: colors.primary,
                  child: IconButton.filled(
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune),
                    style: IconButton.styleFrom(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (provider.hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.spacingMd, AppTheme.spacingSm, AppTheme.spacingMd, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (provider.stateFilter != null)
                      _ActiveFilterChip(
                        label: provider.stateFilter!,
                        onRemove: () => provider.setStateFilter(null),
                        colors: colors,
                      ),
                    if (provider.cityFilter != null)
                      _ActiveFilterChip(
                        label: 'City: ${provider.cityFilter}',
                        onRemove: () => provider.setCityFilter(null),
                        colors: colors,
                      ),
                    if (provider.ageRange.start != 18 || provider.ageRange.end != 100)
                      _ActiveFilterChip(
                        label: '${provider.ageRange.start.round()}–${provider.ageRange.end.round()} yrs',
                        onRemove: () => provider.setAgeRange(const RangeValues(18, 100)),
                        colors: colors,
                      ),
                    ...provider.modeFilters.map((m) => _ActiveFilterChip(
                          label: ModeOptions.label(m),
                          onRemove: () => provider.toggleMode(m),
                          colors: colors,
                        )),
                    if (provider.verifiedOnly)
                      _ActiveFilterChip(
                        label: 'Verified Only',
                        onRemove: () => provider.setVerifiedOnly(false),
                        colors: colors,
                      ),
                    ...provider.lookingForFilters.map((f) => _ActiveFilterChip(
                          label: f,
                          onRemove: () => provider.toggleLookingFor(f),
                          colors: colors,
                        )),
                    ...provider.interestFilters.map((f) => _ActiveFilterChip(
                          label: f,
                          onRemove: () => provider.toggleInterest(f),
                          colors: colors,
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppTheme.spacingSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Row(
              children: [
                Text(
                  provider.isLoading
                      ? 'Loading…'
                      : '${provider.profiles.length} profile${provider.profiles.length == 1 ? "" : "s"} found',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingLg),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: appColors.danger),
                              const SizedBox(height: AppTheme.spacingMd),
                              Text(provider.error!, style: text.bodyMedium, textAlign: TextAlign.center),
                              const SizedBox(height: AppTheme.spacingMd),
                              ElevatedButton(
                                onPressed: () {
                                  final userId = context.read<AuthProvider>().userId;
                                  provider.loadProfiles(currentUserId: userId);
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : provider.profiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: AppTheme.spacingXxl, color: appColors.subtleText),
                                const SizedBox(height: AppTheme.spacingMd),
                                Text('No profiles match your filters', style: text.titleMedium),
                                const SizedBox(height: AppTheme.spacingSm),
                                TextButton(onPressed: provider.clearFilters, child: const Text('Clear Filters')),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              final userId = context.read<AuthProvider>().userId;
                              await provider.loadProfiles(currentUserId: userId);
                            },
                            child: CustomScrollView(
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                                  sliver: SliverGrid(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        if (index == 4 && provider.profiles.length > 4) {
                                          return const AdPlaceholder(height: double.infinity);
                                        }
                                        final profileIndex = index > 4 ? index - 1 : index;
                                        if (profileIndex >= provider.profiles.length) return null;
                                        final profile = provider.profiles[profileIndex];
                                        return ProfileCard(
                                          profile: profile,
                                          onTap: () => context.go('/profile/${profile.id}'),
                                        );
                                      },
                                      childCount: provider.profiles.length + (provider.profiles.length > 4 ? 1 : 0),
                                    ),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: AppTheme.spacingMd,
                                      crossAxisSpacing: AppTheme.spacingMd,
                                      childAspectRatio: isMobile ? 0.62 : 0.68,
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
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final ColorScheme colors;

  const _ActiveFilterChip({required this.label, required this.onRemove, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.spacingSm),
      child: Chip(
        label: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.primary)),
        deleteIcon: Icon(Icons.close, size: AppTheme.iconSm - 2, color: colors.primary),
        onDeleted: onRemove,
        backgroundColor: colors.primaryContainer.withOpacity(0.5),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
