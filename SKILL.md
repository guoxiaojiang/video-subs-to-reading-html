---
name: video-subs-to-reading-html
description: Turn YouTube auto subtitles (or translated subtitles) into a polished, reading-friendly HTML transcript. Supports single-language and bilingual layouts, merges overly fragmented caption lines into readable sections, and deletes intermediate VTT files by default. Use whenever the user asks to "extract subtitles", "make a bilingual transcript", or "turn subtitles into a nice HTML / reading page".
---

# video-subs-to-reading-html

## What this skill does

Given a YouTube video URL, download the available subtitle tracks, align them on the timeline, and render a **clean, editorial-style HTML transcript** optimized for reading rather than playback.

The output is intentionally not “AI shiny”:
- no gradients
- no glow
- no glassmorphism
- no dashboard widgets
- no decorative motion

Instead, it uses a quiet serif/sans-serif reading layout, good spacing, and restrained typographic hierarchy.

## Supported modes

### 1) Single-language reading transcript

Use one subtitle track (default `en`) and produce a clean reading page.

### 2) Bilingual reading transcript

Take a source subtitle track and a second language track, then align them into an English/Chinese (or any supported pair) reading layout.

This works best when both tracks are time-aligned subtitle streams from YouTube.

## Dependencies

- `yt-dlp`
- `python3`
- Python standard library only (no third-party package required)

## Script location

`skills/video-subs-to-reading-html/scripts/subs_to_html.sh`

## Usage

### List available subtitle tracks

```bash
scripts/subs_to_html.sh list <youtube_url>
```

### Build single-language HTML

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en
```

### Build bilingual HTML

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en --bilingual zh-Hans
```

### Custom output path

```bash
scripts/subs_to_html.sh build <youtube_url> \
  --lang en \
  --bilingual zh-Hans \
  -o ~/Downloads/my-transcript.html
```

### Keep intermediate subtitle files

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en --bilingual zh-Hans --keep-intermediate
```

### Clean generated files

```bash
scripts/subs_to_html.sh clean <video_id>
```

Or remove all generated transcript directories:

```bash
scripts/subs_to_html.sh clean
```

## Output defaults

By default, files go to:

```bash
~/Downloads/subtitles_extract/<video_id>/<video_id>.reading.html
```

Intermediate `.vtt` files are **deleted automatically** unless `--keep-intermediate` is passed.

## Recommended workflow when invoked

1. Run `list` first if subtitle languages are unknown.
2. Prefer existing subtitle tracks over machine-translating yourself.
3. If the user asked for Chinese/English comparison, choose:
   - `--lang en`
   - `--bilingual zh-Hans` or `zh-Hant`
4. Generate the HTML.
5. Remove intermediate files unless the user explicitly asks to keep them.
6. Tell the user the final `.html` path only.

## What the script does internally

1. Uses `yt-dlp --skip-download --write-auto-subs` to fetch subtitle tracks only.
2. Parses VTT cues.
3. Removes VTT timestamp markup and repeated fragments.
4. Merges overly short subtitle chunks into larger reading sections.
5. Aligns source/target tracks by timestamp overlap.
6. Renders an HTML page with:
   - title block
   - source URL
   - source language metadata
   - readable section cards
   - English on top / target language below (bilingual mode)
7. Deletes intermediate files by default.

## Limitations

- Works on **YouTube subtitle tracks**, not arbitrary local subtitle formats.
- Alignment assumes both language tracks are already broadly synchronized by YouTube.
- Automatic subtitles can still contain:
  - bad punctuation
  - wrong names
  - awkward segmentation
  - mistranslation in the secondary language
- This is a **reading transcript**, not frame-accurate subtitle authoring.

## Style guarantee

When using this skill, the output should feel like:
- an editorial transcript page
- a readable handout
- a polished article layout

and **not** like:
- an AI landing page
- a startup dashboard
- a neon demo page
- a toy design system showcase
