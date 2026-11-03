import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A draggable deck for browsing pending members. Swipes only change the card.
class PendingMemberCards extends StatefulWidget {
  final List<String> memberIds;
  final IndexedWidgetBuilder cardBuilder;

  const PendingMemberCards({
    super.key,
    required this.memberIds,
    required this.cardBuilder,
  }) : assert(memberIds.length > 0);

  @override
  State<PendingMemberCards> createState() => _PendingMemberCardsState();
}

class _PendingMemberCardsState extends State<PendingMemberCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  int _index = 0;
  late List<String> _deckIds;
  final List<String> _swipedIds = [];
  int _revision = 0;
  bool _finished = false;
  double _width = 1;

  Offset get _offset => _animation.isAnimating
      ? Offset.lerp(_from, _to, Curves.easeOut.transform(_animation.value))!
      : _drag;

  @override
  void initState() {
    super.initState();
    _deckIds = List.of(widget.memberIds);
  }

  @override
  void didUpdateWidget(covariant PendingMemberCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = widget.memberIds.toSet();
    final previousIds = _deckIds.toSet();
    final addedIds = widget.memberIds
        .where((id) => !previousIds.contains(id))
        .toList();
    final updated = [..._deckIds.where(liveIds.contains), ...addedIds];
    // Dues can change priority after a partial payment. Keep the review order
    // stable so members ahead of the current card cannot be skipped.
    final membershipChanged =
        updated.length != _deckIds.length ||
        updated.asMap().entries.any(
          (entry) => _deckIds[entry.key] != entry.value,
        );
    if (!membershipChanged) return;

    final currentId = _deckIds[_index];
    final wasFinished = _finished;
    _revision++;
    _animation.stop();
    _drag = Offset.zero;
    _deckIds = updated;
    _swipedIds.removeWhere((id) => !liveIds.contains(id));
    final retained = _deckIds.indexOf(currentId);
    _index = wasFinished && addedIds.isNotEmpty
        ? _deckIds.indexOf(addedIds.first)
        : retained >= 0
        ? retained
        : _index.clamp(0, _deckIds.length - 1);
    final allRemainingViewed =
        retained < 0 && _deckIds.every(_swipedIds.contains);
    _finished = (wasFinished && addedIds.isEmpty) || allRemainingViewed;
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Future<void> _animateTo(Offset target, {bool advance = false}) async {
    final revision = _revision;
    _from = _drag;
    _to = target;
    try {
      final animation = _animation.forward(from: 0);
      setState(() {});
      await animation.orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _drag = Offset.zero;
      if (advance) {
        _swipedIds.add(_deckIds[_index]);
        if (_index < _deckIds.length - 1) {
          _index++;
        } else {
          _finished = true;
        }
      }
    });
  }

  void _swipe(double direction) {
    if (_animation.isAnimating) return;
    _animateTo(Offset(direction * (_width + 100), 0), advance: true);
  }

  void _restorePrevious() {
    if (_animation.isAnimating || _swipedIds.isEmpty) return;
    final previous = _deckIds.indexOf(_swipedIds.removeLast());
    if (previous < 0) return;
    setState(() {
      _index = previous;
      _finished = false;
      _drag = Offset(-(_width + 100), 0);
    });
    _animateTo(Offset.zero);
  }

  Widget _restoreButton() => IconButton.filled(
    tooltip: 'Bring back previous card',
    onPressed: !_animation.isAnimating && _swipedIds.isNotEmpty
        ? _restorePrevious
        : null,
    style: IconButton.styleFrom(
      backgroundColor: AppColors.surfaceElevated,
      foregroundColor: AppColors.primary,
      disabledBackgroundColor: AppColors.surfaceElevated,
      disabledForegroundColor: AppColors.textMuted.withValues(alpha: 0.45),
      minimumSize: const Size(40, 40),
      maximumSize: const Size(40, 40),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      side: BorderSide(color: AppColors.surfaceBorder),
      shape: const CircleBorder(),
    ),
    icon: const Icon(Icons.arrow_back_rounded, size: 21),
  );

  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_drag.dx.abs() >= _width * 0.25 || velocity.abs() > 700) {
      final direction = velocity.abs() > 700 ? velocity.sign : _drag.dx.sign;
      _swipe(direction);
    } else {
      _animateTo(Offset.zero);
    }
  }

  Widget _card(int index, {bool interactive = false}) => Material(
    color: interactive
        ? AppColors.surface
        : Color.alphaBlend(
            AppColors.primary.withValues(alpha: 0.10),
            AppColors.surface,
          ),
    elevation: interactive ? 8 : 4,
    shadowColor: Colors.black.withValues(alpha: 0.18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: interactive
            ? AppColors.surfaceBorder
            : AppColors.primary.withValues(alpha: 0.32),
        width: interactive ? 1 : 1.5,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            child: KeyedSubtree(
              key: ValueKey('pending-card-${_deckIds[index]}'),
              child: widget.cardBuilder(
                context,
                widget.memberIds.indexOf(_deckIds[index]),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 36, 40, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 400,
                            maxHeight:
                                (constraints.maxWidth - 72).clamp(0.0, 400.0) *
                                1.65,
                          ),
                          child: _finished
                              ? _buildFinished()
                              : AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, _) {
                                    final offset = _offset;
                                    final progress =
                                        (offset.dx.abs() / (_width * 0.5))
                                            .clamp(0.0, 1.0);
                                    return Stack(
                                      fit: StackFit.expand,
                                      clipBehavior: Clip.none,
                                      children: [
                                        for (var depth = 2; depth >= 1; depth--)
                                          if (_index + depth < _deckIds.length)
                                            Transform.translate(
                                              offset: Offset(
                                                (depth - progress) * 10,
                                                (depth - progress) * -20,
                                              ),
                                              child: Transform.rotate(
                                                angle:
                                                    (depth - progress) * 0.028,
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: Transform.scale(
                                                  scale:
                                                      1 -
                                                      (depth - progress) * 0.02,
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: ExcludeSemantics(
                                                    child: IgnorePointer(
                                                      child: _card(
                                                        _index + depth,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        Transform.translate(
                                          offset: offset,
                                          child: Transform.rotate(
                                            angle: offset.dx / _width * 0.28,
                                            alignment: Alignment.bottomCenter,
                                            child: GestureDetector(
                                              key: const ValueKey(
                                                'pending-card-drag',
                                              ),
                                              onHorizontalDragStart: (_) {
                                                if (_animation.isAnimating) {
                                                  return;
                                                }
                                                _drag = Offset.zero;
                                              },
                                              onHorizontalDragUpdate:
                                                  (details) {
                                                    if (_animation
                                                        .isAnimating) {
                                                      return;
                                                    }
                                                    setState(
                                                      () => _drag += Offset(
                                                        details.primaryDelta ??
                                                            0,
                                                        0,
                                                      ),
                                                    );
                                                  },
                                              onHorizontalDragEnd:
                                                  _animation.isAnimating
                                                  ? null
                                                  : _endDrag,
                                              onHorizontalDragCancel: () {
                                                if (!_animation.isAnimating &&
                                                    _drag != Offset.zero) {
                                                  _animateTo(Offset.zero);
                                                }
                                              },
                                              child: AbsorbPointer(
                                                absorbing:
                                                    _animation.isAnimating,
                                                child: _card(
                                                  _index,
                                                  interactive: true,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!_finished)
                    Positioned(
                      left:
                          12 +
                          (constraints.maxWidth - 472).clamp(
                                0.0,
                                double.infinity,
                              ) /
                              2,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _restoreButton()),
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_finished) _restoreButton() else const SizedBox(width: 48),
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _finished
                        ? '${_deckIds.length} members viewed'
                        : '${_index + 1} of ${_deckIds.length} · Swipe to browse',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next member',
                onPressed: !_finished && !_animation.isAnimating
                    ? () => _swipe(-1)
                    : null,
                icon: const Icon(Icons.swipe_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinished() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all_rounded, color: AppColors.primary, size: 40),
          const SizedBox(height: 12),
          const Text(
            'You’ve viewed all pending members',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() {
              _index = 0;
              _finished = false;
              _swipedIds.clear();
            }),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Review again'),
          ),
        ],
      ),
    ),
  );
}
