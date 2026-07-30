---
name: video-subs-to-reading-html
description: Turn a YouTube video into a polished, reading-friendly bilingual (EN/中文) HTML transcript. This skill runs in TWO STAGES — a shell prepare step downloads only the English subtitles and outputs segments.json; the invoking Agent then reads the entire transcript, produces high-quality Chinese translations (信达雅) with full context, writes them back into the same JSON, and calls the render step. Use whenever the user asks to "extract subtitles", "make a bilingual transcript", or "turn subtitles into a nice HTML / reading page".
---

# video-subs-to-reading-html

## What this skill does

Given a YouTube video URL, produce a **clean, editorial-style HTML transcript** with English source text and Chinese translation, optimized for reading.

The translation is NOT delegated to YouTube's auto-translated CC. Instead, this skill deliberately runs in two stages so the invoking Agent (you) can translate with full context:

1. **prepare (shell)** — download only the English subtitle track, clean and merge caption fragments into readable segments, output `segments.json` with `zh` fields left empty.
2. **translate (Agent)** — you read the whole transcript, understand topic / register / recurring terms, then fill each segment's `zh` field with a faithful, natural, and elegant (信 · 达 · 雅) Chinese translation.
3. **render (shell)** — read the completed `segments.json` and emit the final HTML.

The output is intentionally not "AI shiny": no gradients, no glow, no glassmorphism, no dashboard widgets, no decorative motion. Quiet serif reading layout, restrained hierarchy.

## Dependencies

- `yt-dlp`
- `python3` (standard library only)

## Script location

`scripts/subs_to_html.sh`

## Usage

### List available subtitle tracks

```bash
scripts/subs_to_html.sh list <youtube_url>
```

### Stage 1 — prepare English segments

```bash
scripts/subs_to_html.sh prepare <youtube_url>
```

Output: `~/Downloads/subtitles_extract/<video_id>/<video_id>.segments.json`

Structure:

```json
{
  "video_id": "...",
  "title": "...",
  "url": "...",
  "segments": [
    { "i": 0, "start": "00:00:00.000", "end": "00:00:12.480", "en": "...", "zh": "" },
    ...
  ]
}
```

### Stage 2 — Agent translates (this is the important part)

The invoking Agent must:

1. **Read all `en` segments end-to-end first.** Do not translate one-by-one before understanding the whole. Prefer `scripts/subs_to_html.sh view <segments.json>` — it emits a compact EN-only view (about 1/3 the tokens of the raw JSON) suitable for a full read. Identify:
   - the topic and speaker(s)
   - the register (academic / conversational / promotional / technical)
   - recurring proper nouns, product names, jargon — decide a consistent Chinese rendering
   - rhetorical devices worth preserving (metaphors, callbacks, repetitions)
2. **Translate each segment into the `zh` field**, following 信 · 达 · 雅:
   - **信 (faithful)** — no invented content, no dropped meaning, numbers/entities preserved
   - **达 (fluent)** — read as native, idiomatic Chinese; break long English sentences into natural Chinese clauses; convert English discourse markers ("you know", "I mean", "so basically") into appropriate Chinese connectives or drop them
   - **雅 (elegant)** — match the source's register; keep metaphors alive where possible; do not over-formalize casual speech, do not over-colloquialize formal speech
3. **Keep segment boundaries.** Do not merge or split segments across the JSON — the HTML aligns EN and 中文 per segment.
4. **Choose your write mechanism by transcript size.** After `prepare`, look at `segments=N` from the output (or run `status`):
   - **N ≤ ~40 segments (short video / short talk)** — one shot is fine. Read the file, translate all `zh` inline, and write the whole `segments.json` back with `Write`. Fewer tool calls, simpler.
   - **N > ~40 segments (long talk, workshop, podcast)** — DO NOT rewrite the whole file with Write. The raw file is 30k–60k+ tokens; a single Write reproducing all the English is slow, hits output caps, and can be truncated. Use the **batch-and-apply** workflow below.
   - Borderline (say 30–50): if the source is verbose (dense captions per segment), lean toward batching; if segments are short one-liners, one shot is still fine.

   Whichever path you take, preserve `i`, `start`, `end`, `en` exactly. `apply` guarantees this; if you go one-shot, be careful not to alter them.
5. **Batch size when batching.** ~25–35 segments per batch. Fewer → too many round-trips; more → single-response output gets uncomfortably large.

If a segment's `en` is a partial phrase left over from caption merging (rare after cleanup), still translate it faithfully as a fragment — do not fabricate a complete sentence.

### Stage 2.5 — batch-and-apply (write mechanism for long transcripts)

**Only needed when N > ~40 segments.** For short transcripts, just Write the whole `segments.json` back after filling `zh` inline.

For each batch, write a small file containing ONLY translations, keyed by segment index:

```json
{
  "0": "……",
  "1": "……",
  "2": "……"
}
```

Then merge it into `segments.json` with:

```bash
scripts/subs_to_html.sh apply <segments.json> <batch1.json> [batch2.json ...]
```

`apply` sets `zh` for every listed index and leaves `i` / `start` / `end` / `en` untouched. You can pass multiple batch files in a single call. It also accepts an array shape `[{"i": 0, "zh": "..."}, ...]` if that's more convenient.

Check progress at any time with:

```bash
scripts/subs_to_html.sh status <segments.json>
scripts/subs_to_html.sh view   <segments.json> --missing   # show only untranslated segments
```

**Why this workflow, in one line:** the raw `segments.json` is large, so streaming the whole file through a single Write is fragile; batches keep each tool call small, `apply` is idempotent, and `--missing` lets you resume cleanly if a batch is skipped.

### Stage 3 — render HTML

```bash
scripts/subs_to_html.sh render <segments.json>
```

Output: `~/Downloads/subtitles_extract/<video_id>/<video_id>.reading.html`

Custom output:

```bash
scripts/subs_to_html.sh render <segments.json> -o ~/Downloads/my-transcript.html
```

**Cleanup**: After a successful render, the intermediate `segments.json` is automatically deleted. The **only artifact left on disk is the final `.reading.html`** — the raw `.vtt` was already removed at the end of `prepare`, and `segments.json` is removed at the end of `render`. This is intentional so the user ends up with one clean file to share/read.

If some `zh` fields are still empty at render time, the page falls back gracefully — those segments render as English-only, and a note is shown at the top indicating how many are missing.

### Clean generated files

```bash
scripts/subs_to_html.sh clean <video_id>
scripts/subs_to_html.sh clean            # remove all
```

## Recommended workflow when invoked

1. If subtitle availability is unknown, run `list` first — but for English videos you can usually skip this and go straight to `prepare`.
2. Run `prepare <url>`. The script auto-selects `en` / `en-orig` / `en-US` / `en-GB` and deletes the intermediate `.vtt`. Note the `segments=N` printed at the end.
3. Read the transcript. For short ones you can just Read the JSON directly; for anything meatier, prefer `view <segments.json>` (compact, EN-only). Plan terminology and a small glossary.
4. Fill translations, branching by size:
   - **N ≤ ~40**: translate everything inline, then `Write` the whole `segments.json` back (one shot).
   - **N > ~40**: translate in batches of ~30 segments. For each batch, write a `{"<i>": "<zh>", ...}` file (e.g. `/tmp/zh_batchN.json`) and run `apply <segments.json> <batch.json>`. Use `status` between batches and `view <segments.json> --missing` to resume.
5. Run `render <segments.json>` — this also deletes the intermediate JSON, leaving only the final HTML.
6. Report the final `.html` path to the user.

## What the prepare step does internally

1. `yt-dlp --skip-download --write-subs --write-auto-subs --sub-langs "en.*,en"` — prefers manual captions, falls back to auto.
2. Parses VTT cues, strips inline timestamp tags and `&nbsp;`.
3. Merges very short caption chunks into ~260-char reading segments, respecting sentence boundaries.
4. Removes YouTube's rolling-caption word overlap between adjacent cues (and across segment boundaries).
5. Emits `segments.json`.
6. Deletes the raw `.vtt`.

## What the render step does

1. Loads `segments.json`.
2. If any `zh` is filled, renders bilingual layout (EN on top, 中文 below, with a divider).
3. If no `zh` is filled anywhere, renders English-only.
4. If some `zh` are missing, renders bilingual for those that have translations and English-only for the rest, plus a small notice.

## Limitations

- Works on **YouTube subtitle tracks** for the English source only. Chinese comes from the Agent, not from YouTube's auto-translated CC.
- Alignment quality depends on the source captions. Auto-captions may contain wrong names, bad punctuation, or awkward segmentation — worth fixing lightly in the `en` field if you notice obvious errors while translating (but avoid rewriting).
- This is a **reading transcript**, not frame-accurate subtitle authoring.

## Style guarantee

Output should feel like an editorial transcript page, a readable handout, a polished article layout — never like an AI landing page, a dashboard, or a neon demo.
