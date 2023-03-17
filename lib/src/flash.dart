import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flash_controller.dart';

const double _kMinFlingVelocity = 700.0;
const double _kDismissThreshold = 0.5;

/// A highly customizable widget so you can notify your user when you fell like he needs a beautiful explanation.
class Flash<T> extends StatefulWidget {
  const Flash({
    Key? key,
    required this.controller,
    required this.child,
    this.position = FlashPosition.bottom,
    this.enableVerticalDrag = true,
    this.enableHorizontalDrag = true,
    this.forwardAnimationCurve = Curves.easeOut,
    this.reverseAnimationCurve = Curves.fastOutSlowIn,
  }) : super(key: key);

  final FlashController<T> controller;

  /// The widget below this widget in the tree.
  ///
  /// {@macro flutter.widgets.child}
  final Widget child;

  /// Flash can be based on [FlashPosition.top] or on [FlashPosition.bottom] of your screen.
  final FlashPosition? position;

  /// Determines if the user can swipe vertically to dismiss the bar.
  final bool enableVerticalDrag;

  /// Determines if the user can swipe horizontally to dismiss the bar.
  final bool enableHorizontalDrag;

  /// The [Curve] animation used when show() is called. [Curves.fastOutSlowIn] is default.
  final Curve forwardAnimationCurve;

  /// The [Curve] animation used when dismiss() is called. [Curves.fastOutSlowIn] is default.
  final Curve reverseAnimationCurve;

  @override
  State createState() => _FlashState<T>();
}

class _FlashState<T> extends State<Flash<T>> {
  final GlobalKey _childKey = GlobalKey(debugLabel: 'flash');

  double get _childWidth {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox;
    return box.size.width;
  }

  double get _childHeight {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox;
    return box.size.height;
  }

  bool get enableVerticalDrag => widget.enableVerticalDrag;

  bool get enableHorizontalDrag => widget.enableHorizontalDrag;

  FlashController get controller => widget.controller;

  AnimationController get animationController => controller.controller;

  late Animation<Offset> _animation;

  late Animation<Offset> _moveAnimation;

  bool _isDragging = false;

  double _dragExtent = 0.0;

  bool _isHorizontalDragging = false;

  @override
  void initState() {
    super.initState();
    animationController.addStatusListener(_handleStatusChanged);
    _moveAnimation = _animation = _createAnimation();
  }

  @override
  void dispose() {
    animationController.removeStatusListener(_handleStatusChanged);
    super.dispose();
  }

  bool get _dismissUnderway =>
      animationController.status == AnimationStatus.reverse || animationController.status == AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      key: _childKey,
      position: _moveAnimation,
      child: FadeTransition(
        opacity: animationController.drive(
          Tween<double>(begin: 0.0, end: 1.0),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: enableHorizontalDrag ? _handleHorizontalDragUpdate : null,
          onHorizontalDragEnd: enableHorizontalDrag ? _handleHorizontalDragEnd : null,
          onVerticalDragUpdate: enableVerticalDrag ? _handleVerticalDragUpdate : null,
          onVerticalDragEnd: enableVerticalDrag ? _handleVerticalDragEnd : null,
          child: widget.child,
          excludeFromSemantics: true,
        ),
      ),
    );
  }

  /// Called to create the animation that exposes the current progress of
  /// the transition controlled by the animation controller created by
  /// [DefaultFlashController.createAnimationController].
  Animation<Offset> _createAnimation() {
    Animatable<Offset> animatable;
    if (widget.position == FlashPosition.top) {
      animatable = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero);
    } else if (widget.position == FlashPosition.bottom) {
      animatable = Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero);
    } else {
      animatable = Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero);
    }
    return CurvedAnimation(
      parent: animationController,
      curve: widget.forwardAnimationCurve,
      reverseCurve: widget.reverseAnimationCurve,
    ).drive(animatable);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    assert(widget.enableVerticalDrag);
    if (_dismissUnderway) return;
    _isDragging = true;
    _isHorizontalDragging = true;
    final double delta = details.primaryDelta!;
    final double oldDragExtent = _dragExtent;
    _dragExtent += delta;
    if (oldDragExtent.sign != _dragExtent.sign) {
      setState(() => _updateMoveAnimation());
    }
    if (_dragExtent > 0) {
      animationController.value -= (_dragExtent - oldDragExtent) / _childWidth;
    } else {
      animationController.value += (_dragExtent - oldDragExtent) / _childWidth;
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    assert(enableHorizontalDrag);
    if (_dismissUnderway) return;
    _isDragging = false;
    _dragExtent = 0.0;
    _isHorizontalDragging = false;
    if (animationController.status == AnimationStatus.completed) {
      setState(() => _moveAnimation = _animation);
    }
    if (details.velocity.pixelsPerSecond.dx.abs() > _kMinFlingVelocity) {
      final double flingVelocity = details.velocity.pixelsPerSecond.dx / _childHeight;
      switch (_describeFlingGesture(details.velocity.pixelsPerSecond.dx)) {
        case _FlingGestureKind.none:
          animationController.forward();
          break;
        case _FlingGestureKind.forward:
          animationController.fling(velocity: -flingVelocity);
          controller.deactivate();
          break;
        case _FlingGestureKind.reverse:
          animationController.fling(velocity: flingVelocity);
          controller.deactivate();
          break;
      }
    } else if (animationController.value < _kDismissThreshold) {
      animationController.fling(velocity: -1.0);
      controller.deactivate();
    } else {
      animationController.forward();
    }
  }

  _FlingGestureKind _describeFlingGesture(double dragExtent) {
    _FlingGestureKind kind = _FlingGestureKind.none;
    if (dragExtent > 0) {
      kind = _FlingGestureKind.forward;
    } else {
      kind = _FlingGestureKind.reverse;
    }
    return kind;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    assert(widget.enableVerticalDrag);
    if (_dismissUnderway) return;
    _isDragging = true;
    if (widget.position == FlashPosition.top) {
      animationController.value += details.primaryDelta! / _childHeight;
    } else {
      animationController.value -= details.primaryDelta! / _childHeight;
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    assert(widget.enableVerticalDrag);
    if (_dismissUnderway) return;
    _isDragging = false;
    _dragExtent = 0.0;
    _isHorizontalDragging = false;
    if (animationController.status == AnimationStatus.completed) {
      setState(() => _moveAnimation = _animation);
    }
    if (details.velocity.pixelsPerSecond.dy.abs() > _kMinFlingVelocity) {
      final double flingVelocity = details.velocity.pixelsPerSecond.dy / _childHeight;
      if (widget.position == FlashPosition.top) {
        animationController.fling(velocity: flingVelocity);
        if (flingVelocity < 0) controller.deactivate();
      } else {
        animationController.fling(velocity: -flingVelocity);
        if (flingVelocity > 0) controller.deactivate();
      }
    } else if (animationController.value < _kDismissThreshold) {
      animationController.fling(velocity: -1.0);
      controller.deactivate();
    } else {
      animationController.forward();
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        if (!_isDragging) {
          setState(() => _moveAnimation = _animation);
        }
        break;
      case AnimationStatus.forward:
      case AnimationStatus.reverse:
        if (_isDragging) {
          setState(() => _updateMoveAnimation());
        }
        break;
      case AnimationStatus.dismissed:
        break;
    }
  }

  void _updateMoveAnimation() {
    Animatable<Offset> animatable;
    if (_isHorizontalDragging == true) {
      final double end = _dragExtent.sign;
      animatable = Tween<Offset>(begin: Offset(end, 0.0), end: Offset.zero);
    } else {
      if (widget.position == FlashPosition.top) {
        animatable = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero);
      } else {
        animatable = Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero);
      }
    }
    _moveAnimation = animationController.drive(animatable);
  }
}

/// Indicates if flash is going to start at the [top] or at the [bottom].
enum FlashPosition { top, bottom }

/// Indicates if flash will be attached to the edge of the screen or not.
enum FlashBehavior { floating, fixed }

enum _FlingGestureKind { none, forward, reverse }

class FlashBar<T> extends StatefulWidget {
  const FlashBar({
    Key? key,
    required this.controller,
    this.position = FlashPosition.bottom,
    this.behavior = FlashBehavior.fixed,
    this.enableVerticalDrag = true,
    this.enableHorizontalDrag = true,
    this.forwardAnimationCurve = Curves.easeOut,
    this.reverseAnimationCurve = Curves.fastOutSlowIn,
    this.margin,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape,
    this.clipBehavior = Clip.none,
    this.iconColor,
    this.titleTextStyle,
    this.contentTextStyle,
    this.insetAnimationDuration = const Duration(milliseconds: 100),
    this.insetAnimationCurve = Curves.fastOutSlowIn,
    this.padding,
    this.title,
    required this.content,
    this.icon,
    this.shouldIconPulse = true,
    this.indicatorColor,
    this.primaryAction,
    this.actions,
    this.showProgressIndicator = false,
    this.progressIndicatorValue,
    this.progressIndicatorBackgroundColor,
    this.progressIndicatorValueColor,
  }) : super(key: key);

  final FlashController<T> controller;

  /// Flash can be based on [FlashPosition.top] or on [FlashPosition.bottom] of your screen.
  final FlashPosition position;

  /// Flash can be floating or be grounded to the edge of the screen.
  final FlashBehavior? behavior;

  final bool enableVerticalDrag;

  final bool enableHorizontalDrag;

  final Curve forwardAnimationCurve;

  final Curve reverseAnimationCurve;

  final EdgeInsets? margin;

  final Color? backgroundColor;

  final double? elevation;

  final Color? shadowColor;

  final Color? surfaceTintColor;

  final ShapeBorder? shape;

  final Clip clipBehavior;

  final EdgeInsets? padding;

  final Color? iconColor;

  final TextStyle? titleTextStyle;

  final TextStyle? contentTextStyle;

  /// The duration of the animation to show when the system keyboard intrudes
  /// into the space that the dialog is placed in.
  ///
  /// Defaults to 100 milliseconds.
  final Duration insetAnimationDuration;

  /// The curve to use for the animation shown when the system keyboard intrudes
  /// into the space that the dialog is placed in.
  ///
  /// Defaults to [Curves.fastOutSlowIn].
  final Curve insetAnimationCurve;

  /// The (optional) title of the flashbar is displayed in a large font at the top
  /// of the flashbar.
  ///
  /// Typically a [Text] widget.
  final Widget? title;

  /// The message of the flashbar is displayed in the center of the flashbar in
  /// a lighter font.
  ///
  /// Typically a [Text] widget.
  final Widget content;

  /// If not null, shows a left vertical bar to better indicate the humor of the notification.
  /// It is not possible to use it with a [Form] and I do not recommend using it with [LinearProgressIndicator]
  final Color? indicatorColor;

  /// You can use any widget here, but I recommend [Icon] or [Image] as indication of what kind
  /// of message you are displaying. Other widgets may break the layout
  final Widget? icon;

  /// An option to animate the icon (if present). Defaults to true.
  final bool shouldIconPulse;

  /// A widget if you need an action from the user.
  final Widget? primaryAction;

  /// The (optional) set of actions that are displayed at the bottom of the flashbar.
  ///
  /// Typically this is a list of [TextButton] widgets.
  ///
  /// These widgets will be wrapped in a [ButtonBar], which introduces 8 pixels
  /// of padding on each side.
  final List<Widget>? actions;

  /// True if you want to show a [LinearProgressIndicator].
  final bool showProgressIndicator;

  /// An optional [Animation] when you want to control the progress of your [LinearProgressIndicator].
  final Animation<double>? progressIndicatorValue;

  /// A [LinearProgressIndicator] configuration parameter.
  final Color? progressIndicatorBackgroundColor;

  /// A [LinearProgressIndicator] configuration parameter.
  final Animation<Color>? progressIndicatorValueColor;

  @override
  State<FlashBar> createState() => _FlashBarState();
}

class _FlashBarState extends State<FlashBar> with SingleTickerProviderStateMixin {
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;

  final double _initialOpacity = 1.0;
  final double _finalOpacity = 0.4;

  final Duration _pulseAnimationDuration = Duration(seconds: 1);

  bool get _isTitlePresent => widget.title != null;

  bool get _isActionsPresent => widget.actions?.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (widget.icon != null && widget.shouldIconPulse) {
      _configurePulseAnimation();
      _fadeController!.forward();
    }
  }

  void _configurePulseAnimation() {
    _fadeController = AnimationController(vsync: this, duration: _pulseAnimationDuration);
    _fadeAnimation = Tween(begin: _initialOpacity, end: _finalOpacity).animate(
      CurvedAnimation(
        parent: _fadeController!,
        curve: Curves.linear,
      ),
    );

    _fadeController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _fadeController!.reverse();
      }
      if (status == AnimationStatus.dismissed) {
        _fadeController!.forward();
      }
    });

    _fadeController!.forward();
  }

  @override
  void dispose() {
    _fadeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barTheme = theme.extension<FlashBarTheme>()!;
    final position = widget.position;
    final behavior = widget.behavior;
    final padding = widget.padding ?? barTheme.padding;
    final backgroundColor = widget.backgroundColor ?? barTheme.backgroundColor ?? theme.cardColor;

    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showProgressIndicator)
          if (widget.progressIndicatorValue == null)
            LinearProgressIndicator(
              backgroundColor: widget.progressIndicatorBackgroundColor,
              valueColor: widget.progressIndicatorValueColor,
            )
          else
            AnimatedBuilder(
              animation: widget.progressIndicatorValue!,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: widget.progressIndicatorValue!.value,
                  backgroundColor: widget.progressIndicatorBackgroundColor,
                  valueColor: widget.progressIndicatorValueColor,
                );
              },
            ),
        IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _getAppropriateRowLayout(theme, barTheme, padding),
          ),
        ),
      ],
    );

    if (behavior == FlashBehavior.fixed) {
      child = SafeArea(
        bottom: position == FlashPosition.bottom,
        top: position == FlashPosition.top,
        child: child,
      );
    }

    if (widget.position == FlashPosition.top) {
      final brightness = ThemeData.estimateBrightnessForColor(backgroundColor);
      child = AnnotatedRegion<SystemUiOverlayStyle>(
        value: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: child,
      );
    }

    child = Flash(
      controller: widget.controller,
      position: position,
      enableVerticalDrag: widget.enableVerticalDrag,
      enableHorizontalDrag: widget.enableHorizontalDrag,
      forwardAnimationCurve: widget.forwardAnimationCurve,
      reverseAnimationCurve: widget.reverseAnimationCurve,
      child: Material(
        color: backgroundColor,
        elevation: widget.elevation ?? barTheme.elevation,
        shadowColor: widget.shadowColor ?? barTheme.shadowColor,
        surfaceTintColor: widget.surfaceTintColor ?? barTheme.surfaceTintColor,
        shape: widget.shape ?? barTheme.shape,
        type: MaterialType.card,
        clipBehavior: widget.clipBehavior,
        child: child,
      ),
    );

    if (behavior == FlashBehavior.floating) {
      child = SafeArea(
        bottom: position == FlashPosition.bottom,
        top: position == FlashPosition.top,
        child: child,
      );
    }

    return Align(
      alignment: position == FlashPosition.top ? Alignment.topCenter : Alignment.bottomCenter,
      child: AnimatedPadding(
        padding: MediaQuery.of(context).viewInsets + (widget.margin ?? barTheme.margin),
        duration: widget.insetAnimationDuration,
        curve: widget.insetAnimationCurve,
        child: child,
      ),
    );
  }

  List<Widget> _getAppropriateRowLayout(ThemeData theme, FlashBarTheme barTheme, EdgeInsets padding) {
    final messageTopMargin = _isTitlePresent ? 6.0 : padding.top;
    final messageBottomMargin = _isActionsPresent ? 6.0 : padding.bottom;
    final titleTextStyle = widget.titleTextStyle ?? barTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
    final contentTextStyle = widget.contentTextStyle ?? barTheme.contentTextStyle ?? theme.textTheme.titleMedium!;
    final iconColor = widget.iconColor ?? barTheme.iconColor;
    double buttonRightPadding;
    double iconPadding = 0;
    if (padding.right - 12 < 0) {
      buttonRightPadding = 4;
    } else {
      buttonRightPadding = padding.right - 12;
    }

    if (padding.left > 16.0) {
      iconPadding = padding.left;
    }

    if (widget.icon == null && widget.primaryAction == null) {
      return [
        if (widget.indicatorColor != null)
          Container(
            color: widget.indicatorColor,
            width: 5.0,
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_isTitlePresent)
                Padding(
                  padding: EdgeInsets.only(
                    top: padding.top,
                    left: padding.left,
                    right: padding.right,
                  ),
                  child: _getTitle(titleTextStyle),
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: messageTopMargin,
                  left: padding.left,
                  right: padding.right,
                  bottom: messageBottomMargin,
                ),
                child: _getMessage(contentTextStyle),
              ),
              if (_isActionsPresent)
                ButtonTheme(
                  padding: EdgeInsets.symmetric(horizontal: buttonRightPadding),
                  child: ButtonBar(
                    children: widget.actions!,
                  ),
                ),
            ],
          ),
        ),
      ];
    } else if (widget.icon != null && widget.primaryAction == null) {
      return <Widget>[
        if (widget.indicatorColor != null)
          Container(
            color: widget.indicatorColor,
            width: 5.0,
          ),
        Expanded(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 42.0 + iconPadding),
                    child: _getIcon(iconColor),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_isTitlePresent)
                          Padding(
                            padding: EdgeInsets.only(
                              top: padding.top,
                              left: 4.0,
                              right: padding.left,
                            ),
                            child: _getTitle(titleTextStyle),
                          ),
                        Padding(
                          padding: EdgeInsets.only(
                            top: messageTopMargin,
                            left: 4.0,
                            right: padding.right,
                            bottom: messageBottomMargin,
                          ),
                          child: _getMessage(contentTextStyle),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isActionsPresent)
                ButtonTheme(
                  padding: EdgeInsets.symmetric(horizontal: buttonRightPadding),
                  child: ButtonBar(
                    children: widget.actions!,
                  ),
                ),
            ],
          ),
        ),
      ];
    } else if (widget.icon == null && widget.primaryAction != null) {
      return <Widget>[
        if (widget.indicatorColor != null)
          Container(
            color: widget.indicatorColor,
            width: 5.0,
          ),
        Expanded(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_isTitlePresent)
                          Padding(
                            padding: EdgeInsets.only(
                              top: padding.top,
                              left: padding.left,
                              right: padding.right,
                            ),
                            child: _getTitle(titleTextStyle),
                          ),
                        Padding(
                          padding: EdgeInsets.only(
                            top: messageTopMargin,
                            left: padding.left,
                            right: 4.0,
                            bottom: messageBottomMargin,
                          ),
                          child: _getMessage(contentTextStyle),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: buttonRightPadding),
                    child: _getPrimaryAction(),
                  ),
                ],
              ),
              if (_isActionsPresent)
                ButtonTheme(
                  padding: EdgeInsets.symmetric(horizontal: buttonRightPadding),
                  child: ButtonBar(
                    children: widget.actions!,
                  ),
                ),
            ],
          ),
        ),
      ];
    } else {
      return <Widget>[
        if (widget.indicatorColor != null)
          Container(
            color: widget.indicatorColor,
            width: 5.0,
          ),
        Expanded(
          child: Column(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: 42.0 + iconPadding),
                      child: _getIcon(iconColor),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_isTitlePresent)
                            Padding(
                              padding: EdgeInsets.only(
                                top: padding.top,
                                left: 4.0,
                                right: 4.0,
                              ),
                              child: _getTitle(titleTextStyle),
                            ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: messageTopMargin,
                              left: 4.0,
                              right: 4.0,
                              bottom: messageBottomMargin,
                            ),
                            child: _getMessage(contentTextStyle),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(right: buttonRightPadding),
                      child: _getPrimaryAction(),
                    ),
                  ],
                ),
              ),
              if (_isActionsPresent)
                ButtonTheme(
                  padding: EdgeInsets.symmetric(horizontal: buttonRightPadding),
                  child: ButtonBar(
                    children: widget.actions!,
                  ),
                ),
            ],
          ),
        ),
      ];
    }
  }

  Widget _getIcon(Color? iconColor) {
    assert(widget.icon != null);
    Widget child;
    if (widget.shouldIconPulse) {
      child = FadeTransition(
        opacity: _fadeAnimation!,
        child: widget.icon,
      );
    } else {
      child = widget.icon!;
    }
    return IconTheme(
      data: IconThemeData(color: iconColor),
      child: child,
    );
  }

  Widget _getTitle(TextStyle textStyle) {
    return Semantics(
      child: DefaultTextStyle(
        style: textStyle,
        child: widget.title!,
      ),
      namesRoute: true,
      container: true,
    );
  }

  Widget _getMessage(TextStyle textStyle) {
    return DefaultTextStyle(
      style: textStyle,
      child: widget.content,
    );
  }

  Widget _getPrimaryAction() {
    assert(widget.primaryAction != null);
    final buttonTheme = ButtonTheme.of(context);
    return ButtonTheme(
      textTheme: ButtonTextTheme.primary,
      child: IconTheme(
        data: Theme.of(context).iconTheme.copyWith(color: buttonTheme.colorScheme?.primary),
        child: widget.primaryAction!,
      ),
    );
  }
}

@immutable
class FlashToastTheme extends ThemeExtension<FlashToastTheme> {
  const FlashToastTheme({
    this.backgroundColor,
    this.elevation = 4.0,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape = const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4.0))),
    this.alignment = const Alignment(0.0, 0.5),
    this.iconColor,
    this.textStyle,
    this.margin = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  });

  final Color? backgroundColor;

  final double elevation;

  final Color? shadowColor;

  final Color? surfaceTintColor;

  final ShapeBorder? shape;

  final AlignmentGeometry alignment;

  final Color? iconColor;

  final TextStyle? textStyle;

  final EdgeInsets margin;

  final EdgeInsets padding;

  @override
  FlashToastTheme copyWith({
    Color? backgroundColor,
    double? elevation,
    Color? shadowColor,
    Color? surfaceTintColor,
    ShapeBorder? shape,
    AlignmentGeometry? alignment,
    Color? iconColor,
    TextStyle? textStyle,
    EdgeInsets? margin,
    EdgeInsets? padding,
  }) {
    return FlashToastTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      elevation: elevation ?? this.elevation,
      shadowColor: shadowColor ?? this.shadowColor,
      surfaceTintColor: surfaceTintColor ?? this.surfaceTintColor,
      shape: shape ?? this.shape,
      alignment: alignment ?? this.alignment,
      iconColor: iconColor ?? this.iconColor,
      textStyle: textStyle ?? this.textStyle,
      margin: margin ?? this.margin,
      padding: padding ?? this.padding,
    );
  }

  @override
  FlashToastTheme lerp(covariant FlashToastTheme? other, double t) {
    return FlashToastTheme(
      backgroundColor: Color.lerp(backgroundColor, other?.backgroundColor, t),
      elevation: lerpDouble(elevation, other?.elevation, t)!,
      shadowColor: Color.lerp(shadowColor, other?.shadowColor, t),
      surfaceTintColor: Color.lerp(surfaceTintColor, other?.surfaceTintColor, t),
      shape: ShapeBorder.lerp(shape, other?.shape, t),
      alignment: AlignmentGeometry.lerp(alignment, other?.alignment, t)!,
      iconColor: Color.lerp(iconColor, other?.iconColor, t),
      textStyle: TextStyle.lerp(textStyle, other?.textStyle, t),
      margin: EdgeInsets.lerp(margin, other?.margin, t)!,
      padding: EdgeInsets.lerp(padding, other?.padding, t)!,
    );
  }
}

@immutable
class FlashBarTheme extends ThemeExtension<FlashBarTheme> {
  const FlashBarTheme({
    this.margin = EdgeInsets.zero,
    this.backgroundColor,
    this.elevation = 8.0,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape,
    this.padding = const EdgeInsets.all(16.0),
    this.iconColor,
    this.titleTextStyle,
    this.contentTextStyle,
  });

  /// Default is zero.
  final EdgeInsets margin;

  final Color? backgroundColor;

  /// Default is 8.0 .
  final double elevation;

  final Color? shadowColor;

  final Color? surfaceTintColor;

  final ShapeBorder? shape;

  final EdgeInsets padding;

  final Color? iconColor;

  final TextStyle? titleTextStyle;

  final TextStyle? contentTextStyle;

  @override
  FlashBarTheme copyWith({
    FlashPosition? position,
    FlashBehavior? behavior,
    EdgeInsets? margin,
    bool? enableVerticalDrag,
    bool? enableHorizontalDrag,
    Curve? forwardAnimationCurve,
    Curve? reverseAnimationCurve,
    Color? backgroundColor,
    double? elevation,
    Color? shadowColor,
    Color? surfaceTintColor,
    ShapeBorder? shape,
    EdgeInsets? padding,
    Color? iconColor,
    TextStyle? titleTextStyle,
    TextStyle? contentTextStyle,
  }) {
    return FlashBarTheme(
      margin: margin ?? this.margin,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      elevation: elevation ?? this.elevation,
      shadowColor: shadowColor ?? this.shadowColor,
      surfaceTintColor: surfaceTintColor ?? this.surfaceTintColor,
      shape: shape ?? this.shape,
      padding: padding ?? this.padding,
      iconColor: iconColor ?? this.iconColor,
      titleTextStyle: titleTextStyle ?? this.titleTextStyle,
      contentTextStyle: contentTextStyle ?? this.contentTextStyle,
    );
  }

  @override
  FlashBarTheme lerp(covariant FlashBarTheme? other, double t) {
    return FlashBarTheme(
      margin: EdgeInsets.lerp(margin, other?.margin, t)!,
      backgroundColor: Color.lerp(backgroundColor, other?.backgroundColor, t),
      elevation: lerpDouble(elevation, other?.elevation, t)!,
      shadowColor: Color.lerp(shadowColor, other?.shadowColor, t),
      surfaceTintColor: Color.lerp(surfaceTintColor, other?.surfaceTintColor, t),
      shape: ShapeBorder.lerp(shape, other?.shape, t),
      padding: EdgeInsets.lerp(padding, other?.padding, t)!,
      iconColor: Color.lerp(iconColor, other?.iconColor, t),
      titleTextStyle: TextStyle.lerp(titleTextStyle, other?.titleTextStyle, t),
      contentTextStyle: TextStyle.lerp(contentTextStyle, other?.contentTextStyle, t),
    );
  }
}