import 'editor_timeline.dart' show maxTimelineValue, validateTimelineInteger;

/// Exact frames/second. Frame boundaries round to the nearest microsecond;
/// ties round forward. Use 30000/1001 explicitly for NTSC, not 29.97.
final class EditorFrameRate {
  factory EditorFrameRate(int numerator, [int denominator = 1]) {
    validateTimelineInteger(numerator, 'frame-rate numerator', positive: true);
    validateTimelineInteger(
      denominator,
      'frame-rate denominator',
      positive: true,
    );
    if (BigInt.from(numerator) >
        BigInt.from(denominator) * BigInt.from(1000000)) {
      throw ArgumentError('Frame rate exceeds microsecond resolution.');
    }
    final divisor = numerator.gcd(denominator);
    return EditorFrameRate._(numerator ~/ divisor, denominator ~/ divisor);
  }

  factory EditorFrameRate.fromDouble(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('Invalid frame rate.');
    }
    final parts = value.toString().toLowerCase().split('e');
    final decimal = parts.first.split('.');
    var numerator = BigInt.parse(decimal.join());
    var denominator = BigInt.from(
      10,
    ).pow(decimal.length == 2 ? decimal.last.length : 0);
    final exponent = parts.length == 2 ? int.parse(parts.last) : 0;
    if (exponent > 0) numerator *= BigInt.from(10).pow(exponent);
    if (exponent < 0) denominator *= BigInt.from(10).pow(-exponent);
    final gcd = numerator.gcd(denominator);
    numerator ~/= gcd;
    denominator ~/= gcd;
    return EditorFrameRate(_bounded(numerator), _bounded(denominator));
  }

  const EditorFrameRate._(this.numerator, this.denominator);
  final int numerator;
  final int denominator;
  double get framesPerSecond => numerator / denominator;

  int timeAtFrame(int frame) {
    validateTimelineInteger(frame, 'frame');
    return _round(
      BigInt.from(frame) * BigInt.from(1000000) * BigInt.from(denominator),
      BigInt.from(numerator),
    );
  }

  int frameAtTime(int microseconds) {
    validateTimelineInteger(microseconds, 'microseconds');
    return _round(
      BigInt.from(microseconds) * BigInt.from(numerator),
      BigInt.from(1000000) * BigInt.from(denominator),
    );
  }

  int snap(int microseconds) => timeAtFrame(frameAtTime(microseconds));
}

int _round(BigInt value, BigInt divisor) =>
    _bounded((value * BigInt.two + divisor) ~/ (divisor * BigInt.two));

int _bounded(BigInt value) {
  if (value < BigInt.zero || value > BigInt.from(maxTimelineValue)) {
    throw ArgumentError('Frame time exceeds the supported range.');
  }
  return value.toInt();
}
