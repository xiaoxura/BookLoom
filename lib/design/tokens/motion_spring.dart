import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion primitives we did not have before. Adapted from `prism_ui`
/// (`lib/motion.dart`, chen08209/prism_ui, GPL-3.0) as used by FlClash, which
/// ships the same spring feel on Windows. Kept dependency-free so any widget
/// can opt in without dragging the whole design system along.
///
/// Why springs instead of curves: the shell used to avoid animating the
/// selected indicator because a 120ms `Curves` fade lagged behind the page and
/// read as a flicker. A spring that settles in ~360ms with a little bounce is
/// read as the indicator *arriving*, not as the UI trailing the tap.

/// Plays [spring] over the first [seconds] of an animation, easing out the
/// remaining residual so the curve still ends exactly at 1.
///
/// `SpringSimulation` overshoots its target; without the residual term the
/// animation would jump when the controller completes.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  final double seconds;
  final SpringSimulation _simulation;

  late final double _residual = 1 - _simulation.x(seconds);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}

/// Ends [simulation] at [end], where a controller would hold an overshoot.
class ArrivingSimulation extends Simulation {
  ArrivingSimulation(this.simulation, {required this.end})
    : _start = simulation.x(0),
      super(tolerance: simulation.tolerance);

  final Simulation simulation;
  final double end;
  final double _start;

  @override
  double x(double time) => simulation.x(time);

  @override
  double dx(double time) => simulation.dx(time);

  @override
  bool isDone(double time) =>
      simulation.isDone(time) ||
      (_start != end && (x(time) - end) * (_start - end) <= 0);
}

/// Rises to 1 at [peak] and back, for emphasis pulses that should not loop.
double riseAndFall(double time, double peak, double sharpness) {
  if (time <= 0) {
    return 0;
  }
  final double x = time / peak;
  return math.pow(x, sharpness) * math.exp(sharpness * (1 - x));
}

/// Spring for press/release weight; the ratio keeps a slight overshoot.
final SpringDescription dropletSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 165,
  ratio: 0.8,
);

/// Spring for things that appear and disappear, matching the 416ms / 0.25
/// bounce FlClash uses for its bar items.
final SpringDescription presenceSpring =
    SpringDescription.withDurationAndBounce(
      duration: const Duration(milliseconds: 416),
      bounce: 0.25,
    );

/// Frame interval of the current display, so 120Hz screens do not get
/// animations tuned for 60Hz.
Duration frameIntervalOf(BuildContext context) {
  final double rate = View.maybeOf(context)?.display.refreshRate ?? 0;
  return rate > 0
      ? Duration(microseconds: Duration.microsecondsPerSecond ~/ rate)
      : Duration.zero;
}
