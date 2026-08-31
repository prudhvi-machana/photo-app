import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reusable grid gesture shell.
///
/// The pinch behavior intentionally mirrors the proven Photos screen:
/// - one finger remains normal scrolling/tapping
/// - two fingers enter pinch mode
/// - 10% movement is required before locking the pinch direction
/// - 2..6 columns
/// - scrolling is disabled while pinching
class PinchZoomGrid extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final int initialCrossAxisCount;
  final ScrollController? controller;
  final ScrollPhysics physics;
  final bool showFastScrollbar;

  const PinchZoomGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.crossAxisSpacing = 2,
    this.mainAxisSpacing = 2,
    this.childAspectRatio = 1,
    this.initialCrossAxisCount = 3,
    this.controller,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.showFastScrollbar = true,
  });

  @override
  State<PinchZoomGrid> createState() => _PinchZoomGridState();
}

class _PinchZoomGridState extends State<PinchZoomGrid> {
  late int _crossAxisCount = widget.initialCrossAxisCount.clamp(2, 6);
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  int _pinchStartColumns = 3;
  bool _isPinching = false;
  bool _pinchDirectionLocked = false;
  double _lastPinchRatio = 1.0;
  static const double _pinchThreshold = 0.10;

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _distanceBetweenPointers();
      _pinchStartColumns = _crossAxisCount;
      _lastPinchRatio = 1.0;
      _pinchDirectionLocked = false;
      setState(() => _isPinching = true);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (!_isPinching || _pointers.length != 2 || _pinchStartDistance == null) return;

    final distance = _distanceBetweenPointers();
    if (distance <= 0) return;

    final ratio = _pinchStartDistance! / distance;
    if (!_pinchDirectionLocked) {
      if ((ratio - 1).abs() < _pinchThreshold) return;
      _pinchDirectionLocked = true;
    }

    if ((_lastPinchRatio - ratio).abs() < 0.025) return;
    _lastPinchRatio = ratio;

    final next = (_pinchStartColumns * ratio).round().clamp(2, 6);
    if (next != _crossAxisCount) setState(() => _crossAxisCount = next);
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _isPinching) {
      _pinchStartDistance = null;
      _pinchDirectionLocked = false;
      setState(() => _isPinching = false);
    }
  }

  double _distanceBetweenPointers() {
    if (_pointers.length < 2) return 0;
    final values = _pointers.values.toList();
    final dx = values[0].dx - values[1].dx;
    final dy = values[0].dy - values[1].dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      controller: widget.controller,
      physics: _isPinching ? const NeverScrollableScrollPhysics() : widget.physics,
      padding: widget.padding,
      itemCount: widget.itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
        childAspectRatio: widget.childAspectRatio,
      ),
      itemBuilder: widget.itemBuilder,
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: widget.showFastScrollbar
          ? Scrollbar(interactive: true, child: grid)
          : grid,
    );
  }
}
