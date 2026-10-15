import '../models/editor_effect.dart';
part 'catalog.g.dart';

/// Version 1 uses SDR encoded RGB, ordered filters then effects, and
/// mix(original, processed, intensity) per stage. At most eight GPU stages.
abstract final class EditorEffectRegistry {
  static const version = 1;
  static const definitions = _definitions;
  static EditorEffectDefinition definition(String id) => definitions.firstWhere(
    (d) => d.id == id,
    orElse: () => throw UnsupportedError('Unknown GPU effect: $id'),
  );
  static void validate(EditorEffect effect) {
    final spec = definition(effect.effectId);
    for (final entry in effect.parameters.entries) {
      final parameter = spec.parameters[entry.key];
      if (parameter == null ||
          !entry.value.isFinite ||
          entry.value < parameter.min ||
          entry.value > parameter.max ||
          (effect.effectId == 'lut' &&
              entry.value != entry.value.roundToDouble())) {
        throw ArgumentError(
          'Invalid ${effect.effectId}.${entry.key}: ${entry.value}',
        );
      }
    }
  }

  static List<EditorEffect> chain(
    List<EditorFilter> filters,
    List<EditorEffect> effects,
  ) {
    final result = [
      for (final f in filters)
        EditorEffect(
          id: f.id,
          effectId: f.shaderId,
          parameters: f.parameters,
          intensity: f.intensity,
        ),
      ...effects,
    ];
    if (result.length > 8) {
      throw UnsupportedError('At most eight GPU effect stages per clip.');
    }
    for (final effect in result) {
      validate(effect);
    }
    return List.unmodifiable(result);
  }
}

final class EditorEffectDefinition {
  const EditorEffectDefinition(this.id, this.name, this.parameters);
  final String id, name;
  final Map<String, EffectParameter> parameters;
  EditorEffect create({
    String? instanceId,
    double intensity = 1,
    Map<String, double> parameters = const {},
  }) {
    final result = EditorEffect(
      id: instanceId ?? id,
      effectId: id,
      intensity: intensity,
      parameters: parameters,
    );
    EditorEffectRegistry.validate(result);
    return result;
  }
}

final class EffectParameter {
  const EffectParameter(this.min, this.max, this.defaultValue);
  final double min, max, defaultValue;
}
