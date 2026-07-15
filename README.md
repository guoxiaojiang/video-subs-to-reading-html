# video-subs-to-reading-html

Generate a polished, reading-friendly HTML transcript from YouTube subtitles.

This tool is for people who do **not** want raw `.vtt` files, subtitle editors, or AI-looking output. It converts video subtitle tracks into a quiet, editorial reading page — suitable for reading, review, sharing, or archiving.

## What it does

- Downloads subtitle tracks only (no video)
- Supports **single-language** and **bilingual** output
- Merges overly fragmented subtitle cues into larger reading blocks
- Produces a restrained HTML page designed for long-form reading
- Deletes intermediate `.vtt` files by default

## Why this exists

Subtitles are usually optimized for playback:
- too fragmented
- too repetitive
- hard to read outside the video player

This tool turns them into something closer to a readable transcript while preserving timeline anchors.

## Output style

The HTML intentionally avoids a typical AI-generated visual style.

No:
- gradients
- glowing borders
- dashboards
- glassmorphism
- ornamental motion

Yes:
- paper-like background
- serif body text
- quiet metadata treatment
- readable bilingual structure
- restrained spacing and typography

## Requirements

- `yt-dlp`
- `python3`

No third-party Python libraries are required.

## Commands

### 1) See available subtitle tracks

```bash
scripts/subs_to_html.sh list <youtube_url>
```

Example:

```bash
scripts/subs_to_html.sh list "https://www.youtube.com/watch?v=az6OEZV8iHw"
```

### 2) Build a single-language reading transcript

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en
```

### 3) Build a bilingual reading transcript

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en --bilingual zh-Hans
```

Other target-language examples:
- `zh-Hant`
- `ja`
- `ko`
- `fr`
- `de`

assuming YouTube exposes that subtitle track.

### 4) Write to a specific file

```bash
scripts/subs_to_html.sh build <youtube_url> \
  --lang en \
  --bilingual zh-Hans \
  -o ~/Downloads/my-transcript.html
```

### 5) Keep intermediate files

```bash
scripts/subs_to_html.sh build <youtube_url> --lang en --bilingual zh-Hans --keep-intermediate
```

This preserves:
- downloaded `.vtt`
- generated `.txt` side output

### 6) Clean one transcript directory

```bash
scripts/subs_to_html.sh clean az6OEZV8iHw
```

### 7) Clean everything this skill generated

```bash
scripts/subs_to_html.sh clean
```

## Default output location

If `-o` is not provided, output goes to:

```bash
~/Downloads/subtitles_extract/<video_id>/<video_id>.reading.html
```

Example:

```bash
~/Downloads/subtitles_extract/az6OEZV8iHw/az6OEZV8iHw.reading.html
```

## Bilingual layout

In bilingual mode each reading block contains:
- source language on top
- target language below
- time range header

This is optimized for:
- comparing meaning
- reviewing translations
- learning from a talk
- sharing readable bilingual notes

## How text merging works

The tool is not a subtitle editor. It applies lightweight restructuring so the page reads naturally:

- removes inline VTT timing tags
- collapses repeated cue fragments
- merges very short adjacent subtitle segments
- groups text into larger reading blocks
- preserves start/end timestamps for each merged block

## Limitations

- Depends on YouTube subtitle availability
- Best when subtitle tracks are already time-aligned by YouTube
- Automatic captions may still contain:
  - incorrect names
  - weak punctuation
  - translation errors
  - odd sentence boundaries
- This is a **reading** transcript, not a cinema-grade subtitle file

## Good use cases

- “Extract subtitles from this YouTube talk into a nice HTML page.”
- “Make me an English/Chinese side-by-side transcript I can read.”
- “Turn the subtitles into something I can share with a team.”
- “I want the transcript, but not in raw subtitle format.”

## Less suitable use cases

- precise subtitle timing correction
- subtitle authoring for a media player
- OCR from burned-in captions inside the video image
- transcripts from platforms other than YouTube (without adaptation)

## Directory structure

```text
video-subs-to-reading-html/
├── README.md
├── SKILL.md
└── scripts/
    └── subs_to_html.sh
```

## Suggested Claude usage

After installing under `~/.claude/skills/`, tell Claude:

- “Extract the subtitles from this video and output a reading HTML.”
- “Make a bilingual English/Chinese transcript from this YouTube video.”
- “Turn this talk’s subtitles into a polished HTML document.”

Claude should choose this skill automatically.
