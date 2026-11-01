# DevCat v5 — asset intake and quality report

Status: **review package only; not production-ready**. Assessed against `DevCat_Mascot_Senior_Spec_v5` and the user's `DevCat_Review_v5.zip`. This report describes the uploaded archive, not files already shipped inside the Flutter application.

## Reproducible intake check

Run `python scripts/validate_mascot_v5.py /path/to/DevCat_Review_v5.zip` (or the extracted package folder). This performs structural integrity checks. Use `--require-production` to enforce the release gate. It intentionally fails until the missing visual/animation requirements are met. Python standard library only.

Observed on the provided v5 archive:
- 285 files, including SHA256SUMS.txt; **284/284 referenced payloads match their SHA-256 digests**.
- 15 individual appearance masters (6 evolution stages, 9 costumes).
- 31 student animation clips / **152 PNG frames**; 8 separate views (and an additional eight-frame orientations preview in the contract).
- 18 WAV files have 32 kHz mono, 16-bit uncompressed format, audio SHA-256 matches catalog; event/voice references resolve.
- 84 **missing core clips**: six mandatory states each for the 14 non-student appearances.
- Structural validation passed. Production gate failed because frames do not use the required 128×128 release canvas and the supplied artwork is explicitly marked `productionReady: false`.

Note: the ZIP includes **160 files referenced under the contract's `states`**: 152 animation frames plus 8 orientation frames. The orientation set is not a motion clip.

## Remaining work (must not be misrepresented)

1. Manual pixel-level sprite cleanup: true binary alpha/anti-halo assessment, edge inspection on light/dark/checkerboard, coherent head/eyes/scarf/feet and no cropped costume pieces. The source QA report already identifies alpha halos and frame geometry drift, especially jump, sleeping, failure. Large generated masters must not simply be resized to 128×128 and declared hand-authored pixel art.
2. Complete the 14 other appearances' idle, blink, talk, happy, thinking, error clips before enabling animated costume transitions. Preserve current appearance during fallback instead of displaying student.
3. Visually approve both-sided walk/run cycles; jump-to-land; A/O/E mouth phases and proper speech cancellation; typing/reading/explaining props.
4. Integrate the *approved* assets into the Flutter app using an explicit asset manifest and typed animation controller. The current `pubspec.yaml` does not declare a v5 mascot asset directory. The uploaded ZIP is not part of the repository.
5. Wire real events and sound channels; check no duplicate UI sounds, no overlapping voice syllables, cancellation with correlation IDs, reduced-motion and lifecycle handling.
6. Finish Flutter integration and end-to-end tests, then verify `flutter analyze`, `flutter test`, Android and desktop builds. The Flutter SDK is available in GitHub Actions but not in this local execution environment.
7. Prepare platform-specific adaptive / monochrome launcher icons and desktop exports, then perform a visual release review.

## Validation scope

The validator checks manifest references, frame counts/names, dimensions in PNG headers, timing, coverage, audio file format and hashes, and archive safety (duplicate paths/traversal/symlinks). It **does not** substitute for manual visual approval, decoded pixel-alpha analysis, audible playback, end-to-end dialogue verification, or build checks. Structural success is not a production approval.

This branch deliberately adds **no unapproved visual assets** to the app and does **not** change `main`. The next integration stage should begin only after visual acceptance of at least the initial student clips.

## Implemented in PR #1 (not yet a v5 visual release)

- `apps/devcat_flutter/lib/core/mascot_appearance.dart`: six canonical level brackets (Senior through 100, Architect from 101), nine cosmetic IDs, cosmetic choice independent from progress. This is a typed model; there is no costume store UI yet.
- `apps/devcat_flutter/lib/core/mascot_playback.dart`: timing by frame duration, state priorities, speech 0→1→2 / 2→3→4→5→6 / 6→7, pause/resume/cancel/dispose, correlation IDs, same-appearance idle fallback. The catalog deliberately excludes every `productionReady: false` clip.
- `apps/devcat_flutter/lib/core/mascot_speech.dart` and existing `ui/companion.dart`/`ui/cat_actor.dart`: progressively reveal dialogue text; stop mouth movement when text finishes, is skipped, is hidden or the app backgrounds; respect reduced motion. Until sprites are approved, the visible cat still uses the older six-mood, two-mouth-position atlas.
- `scripts/mascot_review_gallery.py`: local loopback-only clip gallery with per-frame stepping, exact manifest timing, light/dark/checkerboard/contrasting backgrounds, 15 static-appearance previews and WAV playback. The server never uploads archive contents.
- Unit/widget tests are included for animation timing/transitions, character reveal, fallback, reduced motion, lifecycle and gallery HTTP behavior. CI outcomes must be verified separately; Python structural tests passed on the supplied ZIP.

### Open the gallery

```bash
python3 scripts/mascot_review_gallery.py "/path/to/DevCat_Review_v5.zip"
# Open http://127.0.0.1:8765
```

The gallery requires the original user-supplied ZIP or extracted folder. Do not turn on the v5 production renderer merely because a clip plays in the gallery. The original source archive is not committed to GitHub.

### Integration boundary

The `MascotPlaybackController` is ready for consumption by a future Flutter PNG-frame renderer after pixel QA; it is **not** yet wired into `CatActor`. The current visible-text synchronization is a transitional improvement using the existing verified branding atlas, not a claim of 8-mouth-shape v5 visual animation or phoneme-level lip sync. Audio remains on the existing `SoftSounds` backend until the 18 WAV files and their explicit event bindings can be safely imported.
