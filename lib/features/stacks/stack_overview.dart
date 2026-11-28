part of 'stack_ui.dart';

class StackOverview extends StatefulWidget {
  const StackOverview({
    super.key,
    required this.controller,
    required this.search,
    required this.active,
  });

  final StackController controller;
  final CollectionHeaderSearch search;
  final bool active;

  @override
  State<StackOverview> createState() => StackOverviewState();
}

class StackOverviewState extends State<StackOverview> {
  StackController get _controller => widget.controller;
  StackAccess? _loadedFor;
  String? _loadedRatings;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_check);
    SettingsManager().addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(StackOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  @override
  void dispose() {
    _controller.removeListener(_check);
    SettingsManager().removeListener(_check);
    super.dispose();
  }

  void _check() {
    final access = _controller.authorization;
    if (!_controller.canRead) _loadedFor = null;
    final ratings = _previewRatings().join(',');
    if (!widget.active ||
        access == null ||
        !_controller.canRead ||
        _refreshScheduled ||
        (access == _loadedFor && ratings == _loadedRatings)) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted && widget.active) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final access = _controller.authorization;
    if (access == null || !_controller.canRead) return;
    final ratings = _previewRatings();
    _loadedFor = access;
    _loadedRatings = ratings.join(',');
    await _controller.refresh(access, ratings);
  }

  Future<void> _open(StackAccess access, StackSummary stack) async {
    if (!_controller.liveAccess(access)) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _StackDetailPage(_controller, access, stack),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _controller,
      widget.search.text,
      SettingsManager(),
      LocalizationService(),
    ]),
    builder: (context, _) {
      final owner = _controller.lease;
      final access = _controller.authorization;
      if (owner == null) {
        return Center(child: Text(_t('stack_session_changed')));
      }
      final query = widget.search.text.text.trim().toLowerCase();
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          key: const PageStorageKey('stack_overview'),
          padding: const EdgeInsets.only(top: 8, bottom: 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (access == null || !_controller.canRead)
              _StackPermission(_controller, owner)
            else ...[
              if (!_controller.canWrite)
                _StackPermission(_controller, owner, write: true),
              for (final section in StackSection.values)
                _section(context, access, section, query),
            ],
          ],
        ),
      );
    },
  );

  Widget _section(
    BuildContext context,
    StackAccess access,
    StackSection kind,
    String query,
  ) {
    final section = _controller.section(kind);
    final items = section.items
        .where((stack) {
          if (query.isEmpty || stack.title.toLowerCase().contains(query)) {
            return true;
          }
          if (!_showRating(stack.rating.name) || stack.spoiler) return false;
          return _controller.detail(stack.id)?.entries.any((entry) {
                final series = entry.series;
                return series != null &&
                    _showRating(series.contentRating) &&
                    [
                      series.title,
                      series.nativeTitle,
                      series.romanizedTitle,
                    ].any((title) => title.toLowerCase().contains(query));
              }) ??
              false;
        })
        .toList(growable: false);
    final heading = _t('stack_${kind.name}');
    final more = section.next != null && !section.loading && !section.stale;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    Future<void> load({bool more = false}) =>
        _controller.loadSection(access, kind, _previewRatings(), more: more);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      heading,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                if (kind == StackSection.created)
                  IconButton(
                    tooltip: _t('stack_create_title'),
                    color: context.colors.accentForeground,
                    onPressed:
                        !_controller.canWrite || _controller.createUncertain
                        ? null
                        : () async {
                            final draft = await _sheet<StackDetail>(
                              context,
                              _StackEditor(_controller, access),
                            );
                            if (draft != null && mounted) {
                              await _open(access, draft.summary);
                            }
                          },
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
          ),
          if (section.stale) _StackNotice(_t('stack_stale')),
          if (section.error case final error?)
            _StackNotice(_t(error), retry: () => load()),
          if (section.loading) const LinearProgressIndicator(),
          if (items.isEmpty && section.loaded && !section.stale)
            _StackNotice(
              _t(query.isEmpty ? 'stack_no_${kind.name}' : 'stack_no_matches'),
            ),
          if (items.isNotEmpty)
            SizedBox(
              height: 140 + math.max(88, 76 * scale),
              child: ListView.separated(
                key: PageStorageKey('stack_section_${kind.name}'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length + (more ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => index == items.length
                    ? Center(
                        child: OutlinedButton(
                          onPressed: () => load(more: true),
                          child: Text(_t('stack_load_more')),
                        ),
                      )
                    : _StackCard(
                        stack: items[index],
                        viewer: _controller.viewer(items[index].id),
                        detail: _controller.detail(items[index].id),
                        trustedPreview: _controller.hasVerifiedCovers(
                          items[index],
                          _previewRatings(),
                        ),
                        onTap: () => _open(access, items[index]),
                      ),
              ),
            ),
          if (items.isEmpty && more)
            _StackNotice(
              '',
              retry: () => load(more: true),
              label: 'stack_load_more',
            ),
        ],
      ),
    );
  }
}

class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.stack,
    required this.viewer,
    required this.detail,
    required this.trustedPreview,
    required this.onTap,
  });

  final StackSummary stack;
  final StackViewer? viewer;
  final StackDetail? detail;
  final bool trustedPreview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ratings = _previewRatings();
    final showCovers = ratings.contains(stack.rating.name) && !stack.spoiler;
    final safeIds = {
      for (final entry in detail?.entries ?? const <StackEntry>[])
        if (ratings.contains(entry.series?.contentRating)) entry.id,
    };
    final width = math.min(270.0, MediaQuery.sizeOf(context).width - 36);
    return SizedBox(
      width: width,
      child: Card(
        color: colors.surfaceRaised,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 4,
                  children: List.generate(4, (index) {
                    final cover = showCovers && index < stack.covers.length
                        ? stack.covers[index]
                        : null;
                    final url =
                        cover != null &&
                            (trustedPreview || safeIds.contains(cover.seriesId))
                        ? cover.url
                        : null;
                    return Expanded(
                      child: ExcludeSemantics(
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: LayoutBuilder(
                            builder: (_, constraints) => _cover(
                              context,
                              url,
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  stack.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    [
                      _t('stack_${stack.visibility.name}'),
                      _count('stack_series_count', stack.entryCount),
                      _count(
                        'stack_save_count',
                        viewer?.saveCount ?? stack.saveCount,
                      ),
                      if (viewer?.libraryCount case final count?)
                        _count('stack_in_library', count),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 4,
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

Widget _cover(
  BuildContext context,
  String? url,
  double width,
  double height, {
  String rating = '',
}) => url != null && url.isNotEmpty
    ? MbCover(
        url: url,
        width: width,
        height: height,
        radius: 7,
        contentRating: rating,
      )
    : DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(7),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Icon(Icons.photo_outlined, color: context.colors.textMuted),
        ),
      );
