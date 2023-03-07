import 'package:flutter/widgets.dart';

class RotateIconController {
  VoidCallback? forward;
  VoidCallback? reverse;
  VoidCallback? reset;
}

class RotateIcon extends StatefulWidget {
  const RotateIcon({
    Key? key,
    required this.icon,
    required this.curve,
    this.controller,
    this.animationDurationMultiplier = 1.0,
    this.rotationPercent = 0.5,
  }) : super(key: key);

  final Widget icon;
  final Curve curve;
  final RotateIconController? controller;
  final double animationDurationMultiplier;
  final double rotationPercent;

  @override
  State<RotateIcon> createState() => _RotateIconState();
}

class _RotateIconState extends State<RotateIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<double> animation;
  late final Duration duration;

  @override
  void initState() {
    duration = Duration(
      milliseconds: (500 * widget.animationDurationMultiplier).toInt(),
    );
    animationController = AnimationController(
      vsync: this,
      duration: duration,
    );
    animation = Tween<double>(
      begin: 0.0,
      end: widget.rotationPercent,
    ).animate(
      CurvedAnimation(
        curve: widget.curve,
        parent: animationController,
      ),
    );

    widget.controller?.forward = animationController.forward;
    widget.controller?.reverse = animationController.reverse;
    widget.controller?.reset = animationController.reset;

    super.initState();
  }

  @override
  void dispose() {
    animationController.dispose();
    widget.controller?.forward = null;
    widget.controller?.reverse = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: animation,
      child: widget.icon,
    );
  }
}