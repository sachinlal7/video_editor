/// Center position is normalized to canvas dimensions (may be off-canvas).
/// Scale is relative to the source; rotation is radians, opacity is [0, 1].
final class EditorTransform {
  EditorTransform({
    this.x = 0.5,
    this.y = 0.5,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.opacity = 1,
  }) {
    if (![x, y, scaleX, scaleY, rotation, opacity].every((v) => v.isFinite) ||
        scaleX <= 0 ||
        scaleY <= 0 ||
        opacity < 0 ||
        opacity > 1) {
      throw ArgumentError(
        'Transform must be finite with positive scale and opacity in [0, 1].',
      );
    }
  }

  const EditorTransform._identity()
    : x = 0.5,
      y = 0.5,
      scaleX = 1,
      scaleY = 1,
      rotation = 0,
      opacity = 1;
  static const identity = EditorTransform._identity();
  final double x, y, scaleX, scaleY, rotation, opacity;

  @override
  bool operator ==(Object other) =>
      other is EditorTransform &&
      x == other.x &&
      y == other.y &&
      scaleX == other.scaleX &&
      scaleY == other.scaleY &&
      rotation == other.rotation &&
      opacity == other.opacity;
  @override
  int get hashCode => Object.hash(x, y, scaleX, scaleY, rotation, opacity);

  EditorTransform copyWith({
    double? x,
    double? y,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? opacity,
  }) => EditorTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    scaleX: scaleX ?? this.scaleX,
    scaleY: scaleY ?? this.scaleY,
    rotation: rotation ?? this.rotation,
    opacity: opacity ?? this.opacity,
  );
}
