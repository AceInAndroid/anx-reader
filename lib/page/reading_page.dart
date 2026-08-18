import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/config/feature_flags.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/providers/ai_workspace.dart';
import 'package:anx_reader/providers/reading_coach.dart';
import 'package:anx_reader/service/ai/reading_coach_policy.dart';
import 'package:anx_reader/models/reading_coach.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/models/selection_snapshot.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/service/ai/reading_agent_repository.dart';
import 'package:anx_reader/service/ai/reading_agent_runtime.dart';
import 'package:anx_reader/service/ai/agent_action_service.dart';
import 'package:anx_reader/service/ai/reading_intervention_policy.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ui/status_bar.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/ai/ai_reading_workspace.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/reading_page/notes_widget.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/widgets/reading_page/progress_widget.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/reading_page/toc_widget.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/foundation.dart'
// show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({
    super.key,
    required this.book,
    this.cfi,
    required this.initialThemes,
    this.heroTag,
    this.initialShowCoach = false,
  });

  final Book book;
  final String? cfi;
  final List<ReadTheme> initialThemes;
  final String? heroTag;
  final bool initialShowCoach;

  @override
  ConsumerState<ReadingPage> createState() => ReadingPageState();
}

final GlobalKey<ReadingPageState> readingPageKey =
    GlobalKey<ReadingPageState>();
final epubPlayerKey = GlobalKey<EpubPlayerState>();

class ReadingPageState extends ConsumerState<ReadingPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const empty = SizedBox.shrink();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Book _book;
  late Widget _currentPage = empty;
  final Stopwatch _readTimeWatch = Stopwatch();
  DateTime? _sessionStart;
  Timer? _awakeTimer;
  bool bottomBarOffstage = true;
  late String heroTag;
  final aiChatKey = GlobalKey<AiChatStreamState>();
  late final AiWorkspaceController aiWorkspaceController;
  static const double _aiChatMinWidth = 240;
  late double _aiChatWidth;
  static const double _aiChatMinHeight = 200;
  late double _aiChatHeight;
  bool _isResizingAiChat = false;
  bool _inspectionReminderShown = false;
  bool bookmarkExists = false;
  bool _readingAgentCapsuleDismissed = false;
  static const _readingInterventionPolicy = ReadingInterventionPolicy();
  String? _lastReadingAgentSnackActionId;

  bool _usesAiSplitLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  double _effectiveAiPanelWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width * Prefs().aiPanelWidthRatio.factor;
  }

  late final FocusNode _readerFocusNode;
  // late final VolumeKeyBoard _volumeKeyBoard;
  // bool _volumeKeyListenerAttached = false;

  @override
  void initState() {
    _readerFocusNode = FocusNode(debugLabel: 'reading_page_focus');

    // Initialize AI panel sizes from persistent storage
    _aiChatWidth = Prefs().aiPanelWidth;
    _aiChatHeight = Prefs().aiPanelHeight;

    if (widget.book.isDeleted) {
      Navigator.pop(context);
      AnxToast.show(L10n.of(context).bookDeleted);
      return;
    }
    if (Prefs().hideStatusBar) {
      hideStatusBar();
    }

    WidgetsBinding.instance.addObserver(this);
    _readTimeWatch.start();
    _sessionStart = DateTime.now();
    setAwakeTimer(Prefs().awakeTime);

    _book = widget.book;
    readingAgentRuntime.addListener(_onReadingAgentChanged);
    aiWorkspaceController = AiWorkspaceController(bookId: _book.id);
    aiWorkspaceController.addListener(_onAiWorkspaceChanged);
    heroTag = widget.heroTag ?? 'preventHeroWhenStart';
    // _volumeKeyBoard = VolumeKeyBoard.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestReaderFocus();
        if (Prefs().readingAgentBetaEnabled) {
          unawaited(readingAgentRuntime.start(
            bookId: _book.id,
            bookTitle: _book.title,
          ));
          _registerReaderCommandGateway();
        }
        if (FeatureFlags.readingCoach && widget.initialShowCoach) {
          showReadingCoach();
        }
        // _attachVolumeKeyListener();
      }
    });
    // delay 1000ms to prevent hero animation
    if (widget.heroTag == null) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            heroTag = _book.coverFullPath;
          });
        }
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    ReaderCommandGateway.instance.unregister(_book.id);
    readingAgentRuntime.removeListener(_onReadingAgentChanged);
    unawaited(readingAgentRuntime.finish());
    Sync().syncData(SyncDirection.upload, ref, trigger: SyncTrigger.auto);
    _readTimeWatch.stop();
    _awakeTimer?.cancel();
    WakelockPlus.disable();
    showStatusBar();
    WidgetsBinding.instance.removeObserver(this);
    readingTimeDao.insertReadingTime(
      ReadingTime(
        bookId: _book.id,
        readingTime: _readTimeWatch.elapsed.inSeconds,
      ),
      startedAt: _sessionStart,
    );
    _sessionStart = null;
    audioHandler.stop();
    // if (_volumeKeyListenerAttached) {
    //   unawaited(_volumeKeyBoard.removeListener());
    // }
    _readerFocusNode.dispose();
    aiWorkspaceController.removeListener(_onAiWorkspaceChanged);
    aiWorkspaceController.dispose();
    super.dispose();
  }

  void _requestReaderFocus() {
    if (bottomBarOffstage && !_readerFocusNode.hasFocus) {
      _readerFocusNode.requestFocus();
    }
  }

  void _onReadingAgentChanged() {
    if (!mounted) return;
    setState(() {});
    final action = readingAgentRuntime.state.lastAgentAction;
    if (action == null || action.id == _lastReadingAgentSnackActionId) return;
    _lastReadingAgentSnackActionId = action.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showAgentUndoSnackBar(action);
    });
  }

  void _registerReaderCommandGateway() {
    ReaderCommandGateway.instance.register(
      bookId: _book.id,
      navigateToCfi: (cfi) => epubPlayerKey.currentState?.goToCfi(cfi),
      navigateToHref: (href) => epubPlayerKey.currentState?.goToHref(href),
      currentCfi: () => epubPlayerKey.currentState?.cfi,
      addAnnotation: (note) => epubPlayerKey.currentState?.addAnnotation(note),
      removeAnnotation: (key) =>
          epubPlayerKey.currentState?.removeAnnotation(key),
      addDifficultyAnnotation: ({required id, required cfi}) =>
          epubPlayerKey.currentState?.addDifficultyAnnotation(id: id, cfi: cfi),
      isValidHref: (href) {
        bool contains(List<TocItem> items) {
          for (final item in items) {
            if (item.href == href ||
                item.href.split('#').first == href.split('#').first) {
              return true;
            }
            if (contains(item.subitems)) return true;
          }
          return false;
        }

        return contains(ref.read(bookTocProvider));
      },
    );
  }

  void _releaseReaderFocus() {
    if (_readerFocusNode.hasFocus) {
      _readerFocusNode.unfocus();
    }
  }

  // Future<void> _attachVolumeKeyListener() async {
  //   if (defaultTargetPlatform != TargetPlatform.iOS ||
  //       _volumeKeyListenerAttached) {
  //     return;
  //   }

  //   try {
  //     await _volumeKeyBoard.addListener(_handleVolumeKeyEvent);
  //     _volumeKeyListenerAttached = true;
  //   } catch (error) {
  //     debugPrint('Failed to attach volume key listener: $error');
  //   }
  // }

  // void _handleVolumeKeyEvent(VolumeKey key) {
  //   if (!Prefs().volumeKeyTurnPage || !_readerFocusNode.hasFocus) {
  //     return;
  //   }

  //   if (key == VolumeKey.up) {
  //     epubPlayerKey.currentState?.prevPage();
  //   } else if (key == VolumeKey.down) {
  //     epubPlayerKey.currentState?.nextPage();
  //   }
  // }

  KeyEventResult _handleReaderKeyEvent(FocusNode node, KeyEvent event) {
    if (!_readerFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.pageDown ||
        logicalKey == LogicalKeyboardKey.space) {
      epubPlayerKey.currentState?.nextPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.pageUp) {
      epubPlayerKey.currentState?.prevPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.enter) {
      showOrHideAppBarAndBottomBar(true);
      return KeyEventResult.handled;
    }

    // Handle Ctrl+[ and Ctrl+] for page turning when keyboard shortcut is enabled
    if (Prefs().keyboardShortcutTurnPage) {
      final isControlPressed = HardwareKeyboard.instance.isControlPressed;
      if (isControlPressed && logicalKey == LogicalKeyboardKey.bracketLeft) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (isControlPressed && logicalKey == LogicalKeyboardKey.bracketRight) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
      final bool isSimulatedCtrlLeft = event.character == '\u001b';
      final bool isSimulatedCtrlRight = event.character == '\u001d';
      if (isSimulatedCtrlLeft) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (isSimulatedCtrlRight) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    if (Prefs().volumeKeyTurnPage) {
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_readTimeWatch.isRunning) {
          _readTimeWatch.start();
        }
        _sessionStart ??= DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_readTimeWatch.isRunning) {
          _readTimeWatch.stop();
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          final elapsedSeconds = _readTimeWatch.elapsed.inSeconds;
          if (elapsedSeconds > 5) {
            epubPlayerKey.currentState?.saveReadingProgress();
            readingTimeDao.insertReadingTime(
              ReadingTime(
                bookId: _book.id,
                readingTime: elapsedSeconds,
              ),
              startedAt: _sessionStart,
            );
          }
          _readTimeWatch.reset();
          _sessionStart = null;
        }
        break;
    }
  }

  Future<void> setAwakeTimer(int minutes) async {
    _awakeTimer?.cancel();
    _awakeTimer = null;
    WakelockPlus.enable();
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      WakelockPlus.disable();
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(Prefs().awakeTime);
  }

  void showBottomBar() {
    setState(() {
      showStatusBarWithoutResize();
      bottomBarOffstage = false;
      _releaseReaderFocus();
    });
  }

  void hideBottomBar() {
    setState(() {
      _currentPage = empty;
      bottomBarOffstage = true;
      if (Prefs().hideStatusBar) {
        hideStatusBar();
      }
      _requestReaderFocus();
    });
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  Future<void> tocHandler() async {
    hideBottomBar();
    _scaffoldKey.currentState?.openDrawer();
  }

  void noteHandler() {
    setState(() {
      _currentPage = ReadingNotes(book: _book);
    });
  }

  void progressHandler() {
    setState(() {
      _currentPage = ProgressWidget(
        epubPlayerKey: epubPlayerKey,
        showOrHideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> styleHandler(StateSetter modalSetState) async {
    List<ReadTheme> themes = await themeDao.selectThemes();
    setState(() {
      _currentPage = StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: (Widget page) {
          modalSetState(() {
            _currentPage = page;
          });
        },
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> ttsHandler() async {
    setState(() {
      _currentPage = TtsWidget(
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  double _aiChatMaxWidth(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final maxByPercentage = totalWidth * 0.65;
    final maxByRemaining = totalWidth - 320;
    final maxWidth = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinWidth, maxWidth);
  }

  double _aiChatMaxHeight(BuildContext context) {
    final totalHeight = MediaQuery.of(context).size.height;
    final maxByPercentage = totalHeight * 0.60;
    final maxByRemaining = totalHeight - 320;
    final maxHeight = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinHeight, maxHeight);
  }

  void _beginAiChatResize(double globalDx) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDelta(double delta, BuildContext context) {
    final maxWidth = _aiChatMaxWidth(context);
    final updated =
        (_aiChatWidth - delta).clamp(_aiChatMinWidth, maxWidth).toDouble();
    if (updated != _aiChatWidth) {
      setState(() {
        _aiChatWidth = updated;
      });
    }
  }

  void _endAiChatResize() {
    if (_isResizingAiChat) {
      setState(() {
        _isResizingAiChat = false;
      });
      // Save the panel sizes to persistent storage
      Prefs().aiPanelWidth = _aiChatWidth;
      Prefs().aiPanelHeight = _aiChatHeight;
    }
  }

  void _beginAiChatResizeVertical(double globalDy) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDeltaVertical(double delta, BuildContext context) {
    final maxHeight = _aiChatMaxHeight(context);
    final updated =
        (_aiChatHeight - delta).clamp(_aiChatMinHeight, maxHeight).toDouble();
    if (updated != _aiChatHeight) {
      setState(() {
        _aiChatHeight = updated;
      });
    }
  }

  Future<void> onLoadEnd() async {
    final coach = await ref.read(readingCoachProvider(_book.id).future);
    for (final difficulty in coach.difficulties.where(
      (item) => item.status == ReadingDifficultyStatus.unresolved,
    )) {
      epubPlayerKey.currentState?.addDifficultyAnnotation(
        id: difficulty.id,
        cfi: difficulty.cfi,
      );
    }
    if (FeatureFlags.readingCoach &&
        !_inspectionReminderShown &&
        coach.guide.status == InspectionGuideStatus.notStarted) {
      _inspectionReminderShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger
          ..clearMaterialBanners()
          ..showMaterialBanner(
            MaterialBanner(
              content: const Text('先用检视阅读快速判断本书主题和阅读目标？全程可只点选项。'),
              actions: [
                TextButton(
                  onPressed: messenger.hideCurrentMaterialBanner,
                  child: const Text('稍后'),
                ),
                TextButton(
                  onPressed: () async {
                    messenger.hideCurrentMaterialBanner();
                    await ref
                        .read(readingCoachProvider(_book.id).notifier)
                        .saveGuide(
                          coach.guide.copyWith(
                            status: InspectionGuideStatus.dismissed,
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                  },
                  child: const Text('不再提醒'),
                ),
                FilledButton(
                  onPressed: () async {
                    messenger.hideCurrentMaterialBanner();
                    await ref
                        .read(readingCoachProvider(_book.id).notifier)
                        .saveGuide(
                          coach.guide.copyWith(
                            status: InspectionGuideStatus.inProgress,
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                    await showReadingCoach();
                  },
                  child: const Text('开始检视'),
                ),
              ],
            ),
          );
      });
    }
    if (Prefs().autoSummaryPreviousContent) {
      final previousContent =
          await epubPlayerKey.currentState!.previousContent(2000);
      final prompt = generatePromptSummaryThePreviousContent(previousContent);
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).readingPageSummaryPreviousContent),
          content: AiStream(
            prompt: prompt,
          ),
        ),
        onDismiss: () {
          cancelActiveAiRequest();
        },
      );
    }
  }

  List<Widget> _buildAiChatTrailing(BuildContext context) {
    return [
      if (Prefs().readingAgentBetaEnabled)
        IconButton(
          onPressed: _showReadingAgentPanel,
          icon: const Icon(Icons.manage_history_outlined),
          tooltip: '阅读 Agent 动作记录',
        ),
      IconButton(
        onPressed: () {
          setState(() {
            Prefs().aiPanelPosition =
                Prefs().aiPanelPosition == AiPanelPositionEnum.right
                    ? AiPanelPositionEnum.bottom
                    : AiPanelPositionEnum.right;
          });
        },
        icon: Icon(
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? Icons.arrow_downward
              : Icons.arrow_forward,
        ),
        tooltip: Prefs().aiPanelPosition == AiPanelPositionEnum.right
            ? L10n.of(context).aiShowAtBottom
            : L10n.of(context).aiShowAtRight,
      ),
      IconButton(
        onPressed: () {
          aiWorkspaceController.hide();
        },
        icon: const Icon(Icons.close),
      ),
    ];
  }

  void _onAiWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildAiWorkspace({List<Widget>? trailing}) {
    final maxWidth = _aiChatMaxWidth(context);
    final maxHeight = _aiChatMaxHeight(context);
    _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
    _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
    return AiReadingWorkspace(
      key: const ValueKey('ai-reading-workspace'),
      controller: aiWorkspaceController,
      chatKey: aiChatKey,
      quickPromptChips: _getAiQuickPromptChips(),
      bookTitle: _book.title,
      bookAuthor: _book.author,
      bookDescription: _book.description,
      onRestoreReadingContext: _restoreAiReadingContext,
      onFetchChapter: (href) =>
          epubPlayerKey.currentState
              ?.chapterContentByHref(href, maxCharacters: 6000) ??
          Future.value(''),
      onFetchChapterSample: (href) =>
          epubPlayerKey.currentState?.chapterContentByHref(href) ??
          Future.value(''),
      onNavigateChapter: (target) {
        if (target.startsWith('epubcfi(')) {
          epubPlayerKey.currentState?.goToCfi(target);
        } else {
          epubPlayerKey.currentState?.goToHref(target);
        }
      },
      onDifficultySaved: (item) => epubPlayerKey.currentState
          ?.addDifficultyAnnotation(id: item.id, cfi: item.cfi),
      onDifficultyResolved: (item) =>
          epubPlayerKey.currentState?.removeAnnotation('difficulty:${item.id}'),
      trailing: trailing ?? _buildAiChatTrailing(context),
    );
  }

  Widget _buildReadingAgentCapsule() {
    final state = readingAgentRuntime.state;
    final goal = state.activeGoal;
    final pending = state.pendingProfileCount +
        state.pendingCheckpointCount +
        state.dueKnowledgeCardCount;
    final title = goal?.title ??
        (pending > 0
            ? '有 $pending 项待处理'
            : state.unresolvedDifficultyCount > 0
                ? '${state.unresolvedDifficultyCount} 个问题待解决'
                : '最近动作可撤销');
    final semantics = goal == null
        ? '阅读 Agent，$title'
        : '阅读目标：${goal.title}，进度 ${(goal.progress * 100).round()}%'
            '${pending > 0 ? '，$pending 项待处理' : ''}';
    return Align(
      alignment: Alignment.topCenter,
      child: Semantics(
        button: true,
        label: semantics,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () async {
              if (_usesAiSplitLayout(context)) {
                aiWorkspaceController.show(fullscreen: false);
                setState(() {});
              } else {
                await _showReadingAgentPanel();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 16),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(title, overflow: TextOverflow.ellipsis),
                  ),
                  if (goal != null) ...[
                    const SizedBox(width: 8),
                    Text('${(goal.progress * 100).round()}%'),
                  ],
                  if (pending > 0) ...[
                    const SizedBox(width: 8),
                    Badge(label: Text('$pending')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onChapterChanged({
    required String previousHref,
    required String previousTitle,
    required double highestProgress,
    required String currentHref,
  }) async {
    if (Prefs().readingAgentBetaEnabled) {
      readingAgentRuntime.observeChapterChanged(
        currentHref: currentHref,
        completedHref: previousHref,
        completedTitle: previousTitle,
        completedProgress: highestProgress,
      );
    }
    if (!FeatureFlags.readingCoach) return;
    final state = await ref.read(readingCoachProvider(_book.id).future);
    if (!shouldCreateChapterQuiz(
      previousHref: previousHref,
      currentHref: currentHref,
      highestProgress: highestProgress,
      existingChapterHrefs: state.quizzes.map((quiz) => quiz.chapterHref),
    )) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(readingCoachProvider(_book.id).notifier).saveQuiz(
          ChapterQuiz(
            id: '${_book.id}-${previousHref.hashCode}-$now',
            bookId: _book.id,
            chapterHref: previousHref,
            chapterTitle: previousTitle,
            updatedAt: now,
          ),
        );
  }

  List<AiQuickPromptChip> _getAiQuickPromptChips() {
    return [
      AiQuickPromptChip(
        icon: EvaIcons.book,
        label: L10n.of(context).settingsAiPromptSummaryTheChapter,
        prompt: generatePromptSummaryTheChapter().buildString(),
      ),
      AiQuickPromptChip(
        icon: Icons.menu_book_rounded,
        label: L10n.of(context).settingsAiPromptSummaryTheBook,
        prompt: generatePromptSummaryTheBook().buildString(),
      ),
      AiQuickPromptChip(
        icon: Icons.account_tree_outlined,
        label: L10n.of(context).settingsAiPromptMindmap,
        prompt: generatePromptMindmap().buildString(),
      ),
      // User custom prompts (enabled only)
      ...Prefs()
          .userPrompts
          .where((p) => p.enabled)
          .map((userPrompt) => AiQuickPromptChip(
                icon: Icons.person_outline,
                label: userPrompt.name,
                prompt: userPrompt.content,
              )),
    ];
  }

  Future<void> showAiChat({
    String? content,
    bool sendImmediate = false,
    ReadingContextSnapshot? selection,
  }) async {
    final workspaceContext = navigatorKey.currentContext!;
    final shouldShowFullscreen = !_usesAiSplitLayout(workspaceContext);

    final snapshot = selection;
    if (snapshot != null) {
      aiWorkspaceController.setPendingSelection(snapshot);
    }
    if (content != null && snapshot == null) {
      aiWorkspaceController.setDraft(content);
      aiChatKey.currentState?.setDraft(content);
    }

    if (!shouldShowFullscreen) {
      final maxWidth = _aiChatMaxWidth(navigatorKey.currentContext!);
      final maxHeight = _aiChatMaxHeight(navigatorKey.currentContext!);
      _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
      _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
    }
    aiWorkspaceController.show(fullscreen: shouldShowFullscreen);
    if (sendImmediate && content != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        aiChatKey.currentState?.sendPrompt(content);
      });
    }
  }

  Future<void> showReadingCoach() async {
    if (!FeatureFlags.readingCoach) return;
    aiWorkspaceController.showCoach();
    await showAiChat();
  }

  Future<void> saveReadingDifficulty(ReadingContextSnapshot snapshot) async {
    final text = snapshot.selectedText?.trim() ?? '';
    final cfi = snapshot.metadata['cfi']?.toString() ?? '';
    if (text.isEmpty || cfi.isEmpty) {
      AnxToast.show('无法读取选区位置');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final difficulty = ReadingDifficulty(
      id: '${_book.id}-$now',
      bookId: _book.id,
      cfi: cfi,
      text: text,
      chapterHref: snapshot.chapterHref,
      chapterTitle: snapshot.chapterTitle,
      context: snapshot.surroundingText,
      createdAt: now,
      updatedAt: now,
    );
    final saved = await ref
        .read(readingCoachProvider(_book.id).notifier)
        .saveDifficulty(difficulty);
    epubPlayerKey.currentState?.addDifficultyAnnotation(
      id: saved.id,
      cfi: saved.cfi,
    );
    AnxToast.show(saved.id == difficulty.id ? '已暂存难点' : '该难点已存在');
  }

  Future<void> _restoreAiReadingContext(AiChatHistoryEntry entry) async {
    if (entry.bookId != _book.id) return;
    final cfi = entry.contextSnapshot?['metadata'] is Map
        ? (entry.contextSnapshot!['metadata'] as Map)['cfi']?.toString()
        : null;
    if (cfi != null && cfi.isNotEmpty) {
      epubPlayerKey.currentState?.goToCfi(cfi);
    } else if (entry.chapterHref?.isNotEmpty == true) {
      epubPlayerKey.currentState?.goToHref(entry.chapterHref!);
    }
  }

  Future<void> _finishChapterCheckpoint(
      ReadingChapterCheckpoint checkpoint) async {
    final reflection = TextEditingController();
    MasteryLevel level = MasteryLevel.familiar;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('完成检查 · ${checkpoint.chapterTitle}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<MasteryLevel>(
                initialValue: level,
                decoration: const InputDecoration(labelText: '当前掌握度'),
                items: const [
                  DropdownMenuItem(
                      value: MasteryLevel.emerging, child: Text('初步理解')),
                  DropdownMenuItem(
                      value: MasteryLevel.familiar, child: Text('基本掌握')),
                  DropdownMenuItem(
                      value: MasteryLevel.mastered, child: Text('可以解释或应用')),
                ],
                onChanged: (value) =>
                    setDialogState(() => level = value ?? level),
              ),
              TextField(
                controller: reflection,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '一句话回忆（可选）',
                  helperText: '填写后会生成一张明日到期的本地知识卡片',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('稍后')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('完成检查')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await readingAgentRepository.completeCheckpoint(checkpoint,
        completed: true, reflection: reflection.text.trim());
    await readingAgentRepository.saveMastery(MasteryState(
        id: '${checkpoint.bookId}-${checkpoint.chapterHref.hashCode}',
        bookId: checkpoint.bookId,
        chapterHref: checkpoint.chapterHref,
        topic: checkpoint.chapterTitle.isEmpty
            ? checkpoint.chapterHref
            : checkpoint.chapterTitle,
        level: level,
        score: level.index / (MasteryLevel.values.length - 1),
        nextReviewAt: now + const Duration(days: 1).inMilliseconds,
        updatedAt: now));
    if (reflection.text.trim().isNotEmpty) {
      await readingAgentRepository.saveKnowledgeCard(KnowledgeCard(
          id: '${checkpoint.id}-recall',
          bookId: checkpoint.bookId,
          front: '请回忆：${checkpoint.chapterTitle}',
          back: reflection.text.trim(),
          chapterHref: checkpoint.chapterHref,
          dueAt: now + const Duration(days: 1).inMilliseconds,
          createdAt: now,
          updatedAt: now));
    }
    readingAgentRuntime.checkpointResolved();
  }

  Future<void> _reviewKnowledgeCard(KnowledgeCard card, bool remembered) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final interval = remembered ? (card.intervalDays * 2).clamp(2, 60) : 1;
    await readingAgentRepository.saveKnowledgeCard(card.copyWith(
        intervalDays: interval,
        repetitions: card.repetitions + 1,
        dueAt: now + Duration(days: interval).inMilliseconds,
        updatedAt: now));
    readingAgentRuntime.knowledgeCardReviewed();
  }

  Future<void> _createMarkdownMemory() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建 Markdown 记忆'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '标题')),
            TextField(
                controller: body,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Markdown 内容')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (save != true || title.text.trim().isEmpty || body.text.trim().isEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await agentActionService.appendMemory(ReadingMemoryDocument(
      id: '${_book.id}-$now',
      bookId: _book.id,
      title: title.text.trim(),
      markdown: body.text.trim(),
      sourceRefs: [
        if (readingAgentRuntime.state.chapterHref case final href?) href,
      ],
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> _showReadingAgentPanel() async {
    final goalTitleController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final state = readingAgentRuntime.state;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '阅读 Agent',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _readingAgentCapsuleDismissed = true;
                            Navigator.pop(sheetContext);
                            setState(() {});
                          },
                          child: const Text('本次会话隐藏'),
                        ),
                      ],
                    ),
                    const Text('所有阅读事件均在本地处理；只有你主动使用 AI 时才调用模型。'),
                    const SizedBox(height: 16),
                    if (state.activeGoal case final goal?) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(goal.title),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: goal.progress,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${(goal.progress * 100).round()}%'),
                          ],
                        ),
                        trailing: PopupMenuButton<ReadingGoalStatus>(
                          tooltip: '更新目标状态',
                          onSelected: (status) async {
                            await agentActionService.saveGoal(
                              goal.copyWith(
                                status: status,
                                progress: status == ReadingGoalStatus.completed
                                    ? 1
                                    : goal.progress,
                                updatedAt:
                                    DateTime.now().millisecondsSinceEpoch,
                              ),
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: ReadingGoalStatus.completed,
                              child: Text('标记完成'),
                            ),
                            PopupMenuItem(
                              value: ReadingGoalStatus.abandoned,
                              child: Text('放弃目标'),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Text('创建阅读目标'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final title in const [
                            '理解本章',
                            '完成指定范围',
                            '形成阅读输出',
                          ])
                            ActionChip(
                              label: Text(title),
                              onPressed: () {
                                goalTitleController.text = title;
                                setSheetState(() {});
                              },
                            ),
                        ],
                      ),
                      TextField(
                        controller: goalTitleController,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: '目标描述',
                          helperText: '先预览，确认后才保存',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () async {
                            final title = goalTitleController.text.trim();
                            if (title.isEmpty) return;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('确认阅读目标'),
                                content: Text(title),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            final now = DateTime.now().millisecondsSinceEpoch;
                            final goal = ReadingGoal(
                              id: '${_book.id}-$now',
                              bookId: _book.id,
                              title: title,
                              range: {
                                'startCfi': readingAgentRuntime.state.cfi,
                                'chapterHref':
                                    readingAgentRuntime.state.chapterHref,
                              },
                              criteria: const [],
                              createdAt: now,
                              updatedAt: now,
                            );
                            await agentActionService.saveGoal(goal);
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('预览并保存'),
                        ),
                      ),
                    ],
                    if (state.pendingCheckpointCount > 0) ...[
                      const Divider(height: 32),
                      const Text('章节完成检查',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      FutureBuilder<List<ReadingChapterCheckpoint>>(
                        future:
                            readingAgentRepository.pendingCheckpoints(_book.id),
                        builder: (context, snapshot) => Column(
                          children: [
                            for (final checkpoint
                                in (snapshot.data ?? const []).take(3))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.fact_check_outlined),
                                title: Text(checkpoint.chapterTitle.isEmpty
                                    ? checkpoint.chapterHref
                                    : checkpoint.chapterTitle),
                                subtitle: Text(
                                    '${(checkpoint.progress * 100).round()}% · 点击后再开始检查'),
                                trailing: FilledButton.tonal(
                                  onPressed: () async {
                                    await _finishChapterCheckpoint(checkpoint);
                                    setSheetState(() {});
                                  },
                                  child: const Text('检查'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (state.unresolvedDifficultyCount > 0) ...[
                      const Divider(height: 32),
                      const Text('跨章节未解决问题',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      FutureBuilder<ReadingCoachState>(
                        future: ref.read(readingCoachProvider(_book.id).future),
                        builder: (context, snapshot) {
                          final items = (snapshot.data?.difficulties ??
                                  const <ReadingDifficulty>[])
                              .where((item) =>
                                  item.status ==
                                  ReadingDifficultyStatus.unresolved)
                              .take(5);
                          return Column(children: [
                            for (final item in items)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.help_outline),
                                title: Text(item.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(item.chapterTitle ?? '未知章节'),
                                onTap: () => ReaderCommandGateway.instance
                                    .navigateToCfi(
                                        bookId: _book.id, cfi: item.cfi),
                                trailing: IconButton(
                                  tooltip: '标记已解决',
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () async {
                                    await ref
                                        .read(readingCoachProvider(_book.id)
                                            .notifier)
                                        .updateDifficulty(item.copyWith(
                                            status: ReadingDifficultyStatus
                                                .resolved,
                                            updatedAt: DateTime.now()
                                                .millisecondsSinceEpoch));
                                    readingAgentRuntime.difficultyResolved();
                                    setSheetState(() {});
                                  },
                                ),
                              ),
                          ]);
                        },
                      ),
                    ],
                    if (state.dueKnowledgeCardCount > 0) ...[
                      const Divider(height: 32),
                      const Text('到期知识卡片',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      FutureBuilder<List<KnowledgeCard>>(
                        future:
                            readingAgentRepository.dueKnowledgeCards(_book.id),
                        builder: (context, snapshot) => Column(
                          children: [
                            for (final card
                                in (snapshot.data ?? const []).take(3))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.style_outlined),
                                title: Text(card.front),
                                subtitle: Text(card.back,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                        tooltip: '再学习',
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () async {
                                          await _reviewKnowledgeCard(
                                              card, false);
                                          setSheetState(() {});
                                        }),
                                    IconButton(
                                        tooltip: '记住了',
                                        icon: const Icon(Icons.check),
                                        onPressed: () async {
                                          await _reviewKnowledgeCard(
                                              card, true);
                                          setSheetState(() {});
                                        }),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    Row(children: [
                      const Expanded(
                        child: Text('本书 Markdown 记忆',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _createMarkdownMemory();
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('新建'),
                      ),
                    ]),
                    if (state.markdownMemorySummary.isNotEmpty) ...[
                      for (final title in state.markdownMemorySummary)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.description_outlined),
                            title: Text(title)),
                    ],
                    if (state.pendingProfileCount > 0) ...[
                      const Divider(height: 32),
                      const Text(
                        '待确认的阅读偏好',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      FutureBuilder<List<ReaderProfileItem>>(
                        future: readingAgentRepository.profileCandidates(),
                        builder: (context, snapshot) {
                          final candidates = (snapshot.data ?? const [])
                              .where((item) =>
                                  item.evidenceCount >= 3 ||
                                  item.confidence >= 1)
                              .toList(growable: false);
                          return Column(
                            children: [
                              for (final item in candidates)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.key),
                                  subtitle: Text(item.value.toString()),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: '拒绝，90 天内不再建议',
                                        onPressed: () async {
                                          await agentActionService
                                              .setProfileStatus(
                                            key: item.key,
                                            status:
                                                ReaderProfileStatus.rejected,
                                          );
                                          readingAgentRuntime
                                              .profileCandidateResolved();
                                          setSheetState(() {});
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                      IconButton(
                                        tooltip: '确认偏好',
                                        onPressed: () async {
                                          await agentActionService
                                              .setProfileStatus(
                                            key: item.key,
                                            status:
                                                ReaderProfileStatus.confirmed,
                                          );
                                          readingAgentRuntime
                                              .profileCandidateResolved();
                                          setSheetState(() {});
                                        },
                                        icon: const Icon(Icons.check),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                    const Divider(height: 32),
                    const Text(
                      '最近 30 天动作',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    FutureBuilder<List<AgentAction>>(
                      future: readingAgentRepository.recentActions(
                        bookId: _book.id,
                      ),
                      builder: (context, snapshot) {
                        final actions = snapshot.data ?? const [];
                        if (actions.isEmpty) {
                          return const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('暂无动作'),
                          );
                        }
                        return Column(
                          children: [
                            for (final action in actions)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.history),
                                title: Text(_agentActionLabel(action.type)),
                                subtitle: Text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    action.createdAt,
                                  ).toLocal().toString(),
                                ),
                                trailing:
                                    action.status == AgentActionStatus.applied
                                        ? TextButton(
                                            onPressed: () async {
                                              final result =
                                                  await agentActionService
                                                      .undo(action);
                                              if (!context.mounted) return;
                                              AnxToast.show(
                                                  _undoResultLabel(result));
                                              setSheetState(() {});
                                            },
                                            child: const Text('撤销'),
                                          )
                                        : Text(action.status.name),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    goalTitleController.dispose();
  }

  void _showAgentUndoSnackBar(AgentAction action) {
    if (!mounted) return;
    _lastReadingAgentSnackActionId = action.id;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_agentActionLabel(action.type)}已完成'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            final result = await agentActionService.undo(action);
            if (mounted) AnxToast.show(_undoResultLabel(result));
          },
        ),
      ),
    );
  }

  String _agentActionLabel(AgentActionType type) => switch (type) {
        AgentActionType.goal => '阅读目标',
        AgentActionType.profile => '阅读偏好',
        AgentActionType.note => 'AI 笔记',
        AgentActionType.difficulty => '阅读难点',
        AgentActionType.memory => 'Markdown 记忆',
      };

  String _undoResultLabel(UndoResult result) => switch (result) {
        UndoResult.undone => '已撤销',
        UndoResult.alreadyUndone => '该动作已撤销',
        UndoResult.expired => '撤销期限已过',
        UndoResult.conflict => '内容之后已被修改，未覆盖你的修改',
        UndoResult.missing => '找不到该动作',
      };

  void updateState() {
    if (mounted) {
      setState(() {
        bookmarkExists = epubPlayerKey.currentState!.bookmarkExists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var aiButton = IconButton(
      tooltip: L10n.of(context).aiChat,
      icon: const Icon(Icons.auto_awesome),
      onPressed: () async {
        final shouldShowAsSplit = _usesAiSplitLayout(context);

        if (shouldShowAsSplit && aiWorkspaceController.visible) {
          aiWorkspaceController.hide();
          return;
        }

        showOrHideAppBarAndBottomBar(false);
        showAiChat();
      },
    );
    Offstage controller = Offstage(
      offstage: bottomBarOffstage,
      child: PointerInterceptor(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                  onTap: () {
                    showOrHideAppBarAndBottomBar(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {},
                  onVerticalDragEnd: (details) {},
                  child: Container(
                    color: Colors.black.withAlpha(30),
                  )),
            ),
            Column(
              children: [
                AppBar(
                  title: Text(_book.title, overflow: TextOverflow.ellipsis),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      // close reading page
                      Navigator.pop(context);
                    },
                  ),
                  actions: [
                    if (EnvVar.enableAIFeature) aiButton,
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: L10n.of(context).readingPageCopyChapterContent,
                      onPressed: () async {
                        try {
                          var content = await epubPlayerKey.currentState
                              ?.theChapterContent();
                          var len = content?.length ?? 0;
                          if (len > 0) {
                            await Clipboard.setData(
                                ClipboardData(text: content!));
                          }
                          if (!context.mounted) return;
                          AnxToast.show(L10n.of(context)
                              .readingPageCopiedCharacters(len));
                        } catch (e) {
                          if (!context.mounted) return;
                          AnxToast.show(
                              L10n.of(context).readingPageErrorCopyingContent);
                        }
                      },
                    ),
                    IconButton(
                        tooltip: L10n.of(context).readingPageBookmark,
                        onPressed: () {
                          if (bookmarkExists) {
                            epubPlayerKey.currentState!.removeAnnotation(
                              epubPlayerKey.currentState!.bookmarkCfi,
                            );
                          } else {
                            epubPlayerKey.currentState!.addBookmarkHere();
                          }
                        },
                        icon: bookmarkExists
                            ? const Icon(Icons.bookmark)
                            : const Icon(Icons.bookmark_border)),
                    IconButton(
                      tooltip: L10n.of(context).readingPageBookDetails,
                      icon: const Icon(EvaIcons.more_vertical),
                      onPressed: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => BookDetail(book: widget.book),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (Prefs().readingAgentBetaEnabled &&
                    _readingInterventionPolicy.decide(
                          state: readingAgentRuntime.state,
                          controlsVisible: true,
                          dismissedForSession: _readingAgentCapsuleDismissed,
                        ) ==
                        ReadingIntervention.passiveCapsule)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildReadingAgentCapsule(),
                  ),
                const Spacer(),
                BottomSheet(
                  onClosing: () {},
                  enableDrag: false,
                  builder: (context) => SafeArea(
                    top: false,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState) {
                          final hasContent = !identical(_currentPage, empty);
                          return IntrinsicHeight(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasContent)
                                  Expanded(
                                    child: _currentPage,
                                  ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.toc),
                                      onPressed: tocHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(EvaIcons.edit),
                                      onPressed: noteHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.data_usage),
                                      onPressed: progressHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.color_lens),
                                      onPressed: () {
                                        styleHandler(setState);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(EvaIcons.headphones),
                                      onPressed: ttsHandler,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final isMobileAiVisible =
        !_usesAiSplitLayout(context) && aiWorkspaceController.visible;
    return PopScope<void>(
      canPop: !isMobileAiVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isMobileAiVisible) aiWorkspaceController.hide();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Hero(
          tag: widget.heroTag ??
              (Prefs().openBookAnimation ? _book.coverFullPath : heroTag),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: Scaffold(
                key: _scaffoldKey,
                resizeToAvoidBottomInset: false,
                drawer: PointerInterceptor(
                  child: Drawer(
                    width: math.min(
                      MediaQuery.of(context).size.width * 0.8,
                      420,
                    ),
                    child: SafeArea(
                      child: TocWidget(
                        epubPlayerKey: epubPlayerKey,
                        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
                        closeDrawer: () {
                          _scaffoldKey.currentState?.closeDrawer();
                        },
                      ),
                    ),
                  ),
                ),
                body: Stack(
                  children: [
                    AxisFlex(
                      axis: Prefs().aiPanelPosition == AiPanelPositionEnum.right
                          ? Axis.horizontal
                          : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: MouseRegion(
                            onHover: (PointerHoverEvent detail) {
                              if (!Prefs().showMenuOnHover) return;
                              var y = detail.position.dy;
                              if (y < 30 ||
                                  y > MediaQuery.of(context).size.height - 30) {
                                showOrHideAppBarAndBottomBar(true);
                              }
                            },
                            child: Focus(
                              focusNode: _readerFocusNode,
                              onKeyEvent: _handleReaderKeyEvent,
                              child: Stack(
                                children: [
                                  EpubPlayer(
                                    key: epubPlayerKey,
                                    book: _book,
                                    cfi: widget.cfi,
                                    showOrHideAppBarAndBottomBar:
                                        showOrHideAppBarAndBottomBar,
                                    onLoadEnd: onLoadEnd,
                                    initialThemes: widget.initialThemes,
                                    updateParent: updateState,
                                    onChapterChanged: _onChapterChanged,
                                    onReadingLocationChanged: ({
                                      required cfi,
                                      required chapterHref,
                                      required chapterTitle,
                                      required totalProgress,
                                      required chapterProgress,
                                    }) {
                                      if (!Prefs().readingAgentBetaEnabled) {
                                        return;
                                      }
                                      readingAgentRuntime.observeLocation(
                                        cfi: cfi,
                                        chapterHref: chapterHref,
                                        chapterTitle: chapterTitle,
                                        totalProgress: totalProgress,
                                        chapterProgress: chapterProgress,
                                      );
                                    },
                                    onSelectionCreated:
                                        (SelectionSnapshot selection) {
                                      if (!Prefs().readingAgentBetaEnabled) {
                                        return;
                                      }
                                      readingAgentRuntime.selectionCreated(
                                        ReadingSelectionState(
                                          text: selection.text,
                                          cfi: selection.cfi,
                                          surroundingText:
                                              selection.contextText,
                                        ),
                                      );
                                    },
                                    onSelectionCleared: () {
                                      if (Prefs().readingAgentBetaEnabled) {
                                        readingAgentRuntime.selectionCleared();
                                      }
                                    },
                                  ),
                                  if (_isResizingAiChat)
                                    SizedBox.expand(
                                      child: Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withAlpha(1),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_usesAiSplitLayout(context) &&
                            aiWorkspaceController.visible)
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? (details) {
                                    _beginAiChatResize(
                                        details.globalPosition.dx);
                                  }
                                : null,
                            onHorizontalDragUpdate: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? (details) {
                                    _applyAiChatResizeDelta(
                                      details.delta.dx,
                                      context,
                                    );
                                  }
                                : null,
                            onHorizontalDragEnd: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? (_) {
                                    _endAiChatResize();
                                  }
                                : null,
                            onHorizontalDragCancel: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? () {
                                    _endAiChatResize();
                                  }
                                : null,
                            onVerticalDragStart: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.bottom
                                ? (details) {
                                    _beginAiChatResizeVertical(
                                        details.globalPosition.dy);
                                  }
                                : null,
                            onVerticalDragUpdate: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.bottom
                                ? (details) {
                                    _applyAiChatResizeDeltaVertical(
                                      details.delta.dy,
                                      context,
                                    );
                                  }
                                : null,
                            onVerticalDragEnd: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.bottom
                                ? (_) {
                                    _endAiChatResize();
                                  }
                                : null,
                            onVerticalDragCancel: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.bottom
                                ? () {
                                    _endAiChatResize();
                                  }
                                : null,
                            child: MouseRegion(
                              cursor: Prefs().aiPanelPosition ==
                                      AiPanelPositionEnum.right
                                  ? SystemMouseCursors.resizeColumn
                                  : SystemMouseCursors.resizeRow,
                              child: Prefs().aiPanelPosition ==
                                      AiPanelPositionEnum.right
                                  ? VerticalDivider(
                                      width: 2,
                                      thickness: 1,
                                    )
                                  : Divider(
                                      height: 2,
                                      thickness: 1,
                                    ),
                            ),
                          ),
                        if (_usesAiSplitLayout(context))
                          Offstage(
                            offstage: !aiWorkspaceController.visible,
                            child: SizedBox(
                              key: const ValueKey('ai-chat-panel'),
                              width: Prefs().aiPanelPosition ==
                                      AiPanelPositionEnum.right
                                  ? _effectiveAiPanelWidth(context)
                                  : null,
                              height: Prefs().aiPanelPosition ==
                                      AiPanelPositionEnum.bottom
                                  ? _aiChatHeight
                                  : null,
                              child: _buildAiWorkspace(),
                            ),
                          ),
                      ],
                    ),
                    if (!_usesAiSplitLayout(context))
                      Positioned.fill(
                        child: Offstage(
                          offstage: !aiWorkspaceController.visible,
                          child: PointerInterceptor(
                            child: _buildAiWorkspace(
                              trailing: [
                                if (Prefs().readingAgentBetaEnabled)
                                  IconButton(
                                    onPressed: _showReadingAgentPanel,
                                    icon: const Icon(
                                      Icons.manage_history_outlined,
                                    ),
                                    tooltip: '阅读 Agent 动作记录',
                                  ),
                                IconButton(
                                  onPressed: aiWorkspaceController.hide,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    controller,
                    // TTS floating action button: always in the tree when toolbar
                    // is hidden; TtsFab handles its own show/hide internally so
                    // its State (expanded flag) is never destroyed mid-session.
                    if (bottomBarOffstage)
                      const Positioned(
                        right: 16,
                        bottom: 24,
                        child: TtsFab(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
