/// A data-driven color treatment resolved by the native renderer.
final class EditorFilter {
  EditorFilter({
    required this.id,
    required this.name,
    required this.shaderId,
    Map<String, double> parameters = const {},
    this.intensity = 1,
  }) : parameters = Map.unmodifiable(parameters) {
    if (name.trim().isEmpty || shaderId.trim().isEmpty) {
      throw ArgumentError('Filter name and shader ID are required.');
    }
    _validateEffect(id, parameters, intensity);
  }

  final String id;
  final String name;
  final String shaderId;
  final Map<String, double> parameters;
  final double intensity;
}

/// A visual effect resolved by the native renderer.
final class EditorEffect {
  EditorEffect({
    required this.id,
    required this.effectId,
    Map<String, double> parameters = const {},
    this.intensity = 1,
  }) : parameters = Map.unmodifiable(parameters) {
    if (effectId.trim().isEmpty) {
      throw ArgumentError('Effect definition ID must not be empty.');
    }
    _validateEffect(id, parameters, intensity);
  }

  final String id;
  final String effectId;
  final Map<String, double> parameters;
  final double intensity;
}

void _validateEffect(
  String id,
  Map<String, double> parameters,
  double intensity,
) {
  if (id.trim().isEmpty ||
      parameters.entries.any(
        (entry) => entry.key.trim().isEmpty || !entry.value.isFinite,
      )) {
    throw ArgumentError('Effect ID and finite named parameters are required.');
  }
  if (!intensity.isFinite || intensity < 0 || intensity > 1) {
    throw ArgumentError.value(
      intensity,
      'intensity',
      'Must be finite and between 0 and 1.',
    );
  }
}
