# Timeline surface

Scope: extend the existing editor, not a visual redesign. Operate mode: mobile creators select placements, inspect time, trim, and undo edits. The SDK remains reusable on Android and iOS.

## Direction contract

THESIS: a timeline is a measuring and editing surface, with real placement durations and visible trim affordances.

OWN-WORLD: inherit Flutter Material components and the host theme's semantic color roles. The user explicitly chose host light/dark theming. Use system type, tabular time, and no new fonts or runtime dependencies.

STORY: preview the edited cuts, inspect real thumbnails and audio peaks, select a placement, navigate time, trim or move, and undo the committed edit. Source time and project time stay distinct; transport labels identify the active mode.

FIRST VIEWPORT: preview above transport, timeline ruler and track rows below. Selection and trim controls use the theme primary color. Zoom and undo/redo remain discoverable toolbar actions. Empty tracks explain how to populate them.

FORM: an extension of the existing editor layout, specified by the roadmap and user confirmation; no new-world concept seed applies. Drag feedback is immediate and commits one history entry on release. No decorative animation.

FINISH: this extension ends with a scoped finish review and verdict, verification evidence, and a documentation pass preserving the existing host-theme contract. It does not introduce a fixed SDK design system. Example media provenance is recorded in PHASE_2_FIXTURES.md.

This extension preserves the incumbent component system; existing system documentation is not replaced. No new shipping raster is authored. Native thumbnail extraction and waveforms use actual source data, never decorative placeholders. Media-strip text, retry/error icons and waveform strokes use the foreground paired with the clip's selected/unselected container role. Extraction work belongs to the controller/native service, not the widget; unmounted clips cancel their requests.
