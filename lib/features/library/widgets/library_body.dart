import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/library/constants/library_screen_constants.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/helpers/library_filter_helper.dart';
import 'package:mangabaka_app/features/library/widgets/library_grid_list.dart';
import 'package:mangabaka_app/features/profile/widgets/login/mb_login_prompt.dart';
import 'package:mangabaka_app/features/series/widgets/series_list_skeleton.dart';
import 'package:mangabaka_app/features/series/models/series.dart' as api;
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';

class LibraryBody extends StatelessWidget {
  final bool loggedIn;
  final bool hasEntriesStream;
  final AsyncSnapshot<List<LibraryEntry>> snapshot;
  final LibraryFilterResult? result;
  final TabController tabController;
  final Map<String, ScrollController> scrollControllers;
  final RefreshCallback onRefresh;
  final VoidCallback onLogin;
  final Function(api.Series) onItemTap;

  const LibraryBody({
    super.key,
    required this.loggedIn,
    required this.hasEntriesStream,
    required this.snapshot,
    required this.result,
    required this.tabController,
    required this.scrollControllers,
    required this.onRefresh,
    required this.onLogin,
    required this.onItemTap,
  });

  Widget _buildErrorState(
    BuildContext context,
    LocalizationService l10n,
    Object error,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              '${l10n.translate('failed_to_load')}: $error',
              style: AppTypography.sans(
                color: MbPalette.ensureContrast(
                  context.colors.error,
                  context.colors.background,
                  minimum: 4.5,
                ),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLibraryState(
    BuildContext context,
    LocalizationService l10n,
  ) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    size: 48,
                    color: context.colors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.translate('empty_library'),
                    style: AppTypography.sans(
                      color: MbPalette.ensureContrast(
                        context.colors.textMuted,
                        context.colors.background,
                        minimum: 4.5,
                      ),
                      fontSize: 16,
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

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService();
    if (!loggedIn) {
      return MBLoginPrompt(
        onLogin: onLogin,
        message: l10n.translate('login_prompt_library'),
      );
    }

    if (!hasEntriesStream) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [Center(child: CircularProgressIndicator())],
        ),
      );
    }

    if (snapshot.hasError) {
      return _buildErrorState(context, l10n, snapshot.error!);
    }
    if (!snapshot.hasData) {
      return SeriesListSkeleton(
        isGrid: SettingsManager().resolvedLibraryListStyle.isGrid,
      );
    }
    if (snapshot.data!.isEmpty) {
      return _buildEmptyLibraryState(context, l10n);
    }

    return TabBarView(
      controller: tabController,
      children: [
        for (final tab in LibraryScreenConstants.tabs)
          LibraryGridList(
            key: PageStorageKey(tab.key),
            items: result!.getByTab(tab.key),
            tabKey: tab.key,
            scrollController: scrollControllers[tab.key]!,
            onRefresh: onRefresh,
            onItemTap: onItemTap,
          ),
      ],
    );
  }
}
