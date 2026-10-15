import 'package:flutter/material.dart';
import '../controller/editor_controller.dart';
import '../effects/editor_effect_registry.dart';
import '../models/editor_effect.dart';

/// A focused clip adjustment tool; project/history/native work stay controller-owned.
class EditorEffectPanel extends StatefulWidget {
  const EditorEffectPanel({
    super.key,
    required this.controller,
    required this.clipId,
  });
  final EditorController controller;
  final String clipId;
  @override
  State<EditorEffectPanel> createState() => _EditorEffectPanelState();
}

class _EditorEffectPanelState extends State<EditorEffectPanel> {
  static const instanceId = 'editor-adjustment';
  List<String>? supported;
  String? selected;
  Map<String, double> parameters = {};
  double intensity = 1;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final effects = widget.controller.project.tracks
        .expand((t) => t.clips)
        .where((c) => c.id == widget.clipId)
        .expand((c) => c.effects)
        .where((e) => e.id == instanceId);
    if (effects.isNotEmpty) {
      selected = effects.first.effectId;
      parameters = Map.of(effects.first.parameters);
      intensity = effects.first.intensity;
    }
    loadCapabilities();
  }

  Future<void> loadCapabilities() async {
    try {
      final ids = await widget.controller.supportedEffects();
      if (mounted) {
        setState(() {
          supported = ids;
          if (selected != null &&
              (!ids.contains(selected) ||
                  !EditorEffectRegistry.definitions.any(
                    (d) => d.id == selected,
                  ))) {
            selected = null;
            parameters = {};
            error =
                'The saved adjustment is unavailable. Choose an effect to replace it, or None to remove it.';
          } else {
            error = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'GPU capabilities unavailable. Close and reopen the editor.',
        );
      }
    }
  }

  Future<void> commit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.editEffect(
        widget.clipId,
        selected == null
            ? null
            : EditorEffect(
                id: instanceId,
                effectId: selected!,
                parameters: parameters,
                intensity: intensity,
              ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Preview could not update. Check the clip and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition =
        selected == null ||
            !EditorEffectRegistry.definitions.any((d) => d.id == selected)
        ? null
        : EditorEffectRegistry.definition(selected!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Effects · ${widget.clipId}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close effects',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (supported == null && error == null)
              const LinearProgressIndicator(
                semanticsLabel: 'Checking GPU support',
              ),
            if (supported?.isEmpty ?? false)
              const Text('GPU effects are unavailable on this device.'),
            if (supported?.isNotEmpty ?? false) ...[
              DropdownButtonFormField<String>(
                initialValue: selected ?? '',
                decoration: const InputDecoration(labelText: 'Effect'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  for (final d in EditorEffectRegistry.definitions.where(
                    (d) => supported!.contains(d.id),
                  ))
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          selected = value == '' ? null : value;
                          parameters = {};
                          intensity = 1;
                        });
                        commit();
                      },
              ),
              if (definition != null) ...[
                slider('Intensity', intensity, 0, 1, (v) => intensity = v),
                for (final p in definition.parameters.entries)
                  slider(
                    p.key == 'preset' ? 'LUT' : p.key,
                    parameters[p.key] ?? p.value.defaultValue,
                    p.value.min,
                    p.value.max,
                    (v) => parameters[p.key] = v,
                    divisions: p.key == 'preset' ? 3 : null,
                    format: p.key == 'preset' ? lutName : null,
                  ),
              ],
            ],
            if (busy)
              const LinearProgressIndicator(semanticsLabel: 'Updating preview'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              'Changes are undoable. Drag a slider, then release to update the native preview.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) update, {
    int? divisions,
    String Function(double)? format,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${format?.call(value) ?? value.toStringAsFixed(2)}'),
      Slider(
        label: '$label ${format?.call(value) ?? value.toStringAsFixed(2)}',
        semanticFormatterCallback: format,
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: busy ? null : (v) => setState(() => update(v)),
        onChangeEnd: busy ? null : (_) => commit(),
      ),
    ],
  );

  static String lutName(double value) =>
      const ['Warm', 'Cool', 'Vintage', 'Cinema'][value.round().clamp(0, 3)];
}
