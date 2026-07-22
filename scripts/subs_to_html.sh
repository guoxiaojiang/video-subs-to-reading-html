#!/usr/bin/env bash
# video-subs-to-reading-html — 两阶段流程：
#   1) prepare : 仅拉取英文字幕，合并成阅读段，输出 segments.json
#   2) (agent) : 由调用方 Agent 阅读整篇后为每段填 zh（信达雅）
#   3) render  : 读取 segments.json，渲染中英对照阅读版 HTML
#
# 依赖: yt-dlp, python3（标准库即可）
#
# 用法：
#   ./subs_to_html.sh list    <youtube_url>
#   ./subs_to_html.sh prepare <youtube_url> [-o segments.json]
#   ./subs_to_html.sh render  <segments.json> [-o output.html]
#   ./subs_to_html.sh clean   [<video_id>]
#
# 默认输出目录：
#   ~/Downloads/subtitles_extract/<video_id>/
#     ├── <video_id>.segments.json
#     └── <video_id>.reading.html

set -euo pipefail

BASE_DIR="$HOME/Downloads/subtitles_extract"

check_deps() {
  for cmd in yt-dlp python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "缺少依赖: $cmd" >&2; exit 1; }
  done
}

video_id_of() {
  yt-dlp --no-update --print id "$1" | head -1
}

cmd_list() {
  local url="${1:-}"
  [[ -z "$url" ]] && { echo "用法: $0 list <youtube_url>" >&2; exit 1; }
  yt-dlp --no-update --list-subs "$url"
}

cmd_prepare() {
  local url="${1:-}"
  [[ -z "$url" ]] && { echo "用法: $0 prepare <youtube_url> [-o segments.json]" >&2; exit 1; }
  shift || true

  local output=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output) output="$2"; shift 2 ;;
      -*) echo "未知参数: $1" >&2; exit 1 ;;
      *)  echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done

  local vid title
  vid=$(video_id_of "$url")
  title=$(yt-dlp --no-update --print title "$url" | head -1)
  local out_dir="$BASE_DIR/$vid"
  mkdir -p "$out_dir"
  [[ -z "$output" ]] && output="$out_dir/$vid.segments.json"

  echo "==> 下载英文字幕: $vid" >&2
  # 优先人工字幕，回退自动字幕
  yt-dlp --no-update --skip-download \
    --write-subs --write-auto-subs \
    --sub-langs "en.*,en" --sub-format "vtt" \
    -o "$out_dir/%(id)s.%(ext)s" "$url" >/dev/null

  local vtt=""
  for cand in "$out_dir/$vid.en.vtt" "$out_dir/$vid.en-orig.vtt" "$out_dir/$vid.en-US.vtt" "$out_dir/$vid.en-GB.vtt"; do
    if [[ -f "$cand" ]]; then vtt="$cand"; break; fi
  done
  [[ -n "$vtt" ]] || { echo "未找到英文字幕文件（尝试过 en/en-orig/en-US/en-GB）" >&2; exit 2; }

  python3 - "$vtt" "$output" "$url" "$vid" "$title" <<'PY'
import json, re, sys
from pathlib import Path

vtt_path = Path(sys.argv[1])
output = Path(sys.argv[2])
url = sys.argv[3]
vid = sys.argv[4]
title = sys.argv[5]

cue_re = re.compile(r'^(\d\d:\d\d:\d\d\.\d+) --> (\d\d:\d\d:\d\d\.\d+)')
tag_re = re.compile(r'<[^>]+>')

def norm(s):
    s = tag_re.sub('', s)
    s = s.replace('&nbsp;', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def parse_vtt(path):
    lines = path.read_text(encoding='utf-8').splitlines()
    cues, i = [], 0
    while i < len(lines):
        m = cue_re.match(lines[i])
        if not m:
            i += 1
            continue
        start, end = m.group(1), m.group(2)
        i += 1
        texts = []
        while i < len(lines) and lines[i].strip() != '':
            t = norm(lines[i])
            if t: texts.append(t)
            i += 1
        text = ' '.join(texts).strip()
        if text:
            if cues and cues[-1]['text'] == text and cues[-1]['end'] == start:
                cues[-1]['end'] = end
            else:
                cues.append({'start': start, 'end': end, 'text': text})
        i += 1
    return cues

def word_overlap(prev, cur, max_k=20):
    if not prev or not cur: return 0
    if cur == prev or prev.endswith(cur): return len(cur.split(' '))
    wp, wc = prev.split(' '), cur.split(' ')
    best = 0
    for k in range(1, min(len(wp), len(wc), max_k)+1):
        if wp[-k:] == wc[:k]: best = k
    return best

def merge_text(prev, cur):
    prev, cur = norm(prev), norm(cur)
    if not prev: return cur
    if not cur: return prev
    if cur == prev: return prev
    if cur.startswith(prev): return cur
    if prev.endswith(cur): return prev
    wc = cur.split(' ')
    k = word_overlap(prev, cur)
    if k:
        return prev + ' ' + ' '.join(wc[k:])
    return prev + ' ' + cur

def strip_leading_overlap(prev, cur, min_k=2):
    prev, cur = norm(prev), norm(cur)
    if not prev or not cur: return cur
    wc = cur.split(' ')
    k = word_overlap(prev, cur)
    if k < min_k: return cur
    if k >= len(wc): return ''
    return ' '.join(wc[k:])

def is_end(s):
    return bool(re.search(r'[.!?。！？]$', s.strip()))

cues = parse_vtt(vtt_path)

merged, cur = [], None
for c in cues:
    if cur is None:
        cur = [c['start'], c['end'], c['text']]
        continue
    cand = merge_text(cur[2], c['text'])
    if len(cand) > 260 and is_end(cur[2]):
        merged.append(tuple(cur))
        new_text = strip_leading_overlap(cur[2], c['text'])
        cur = [c['start'], c['end'], new_text]
    else:
        cur[1] = c['end']
        cur[2] = cand
if cur is not None:
    merged.append(tuple(cur))

post = []
for item in merged:
    if post and len(item[2]) < 40:
        ps, _, pen = post[-1]
        post[-1] = (ps, item[1], merge_text(pen, item[2]))
    else:
        post.append(item)
merged = post

cleaned = []
for item in merged:
    if cleaned:
        prev = cleaned[-1]
        new_text = strip_leading_overlap(prev[2], item[2])
        if new_text.strip():
            cleaned.append((item[0], item[1], new_text))
        else:
            cleaned[-1] = (prev[0], item[1], prev[2])
    else:
        cleaned.append(item)
merged = cleaned

data = {
    'video_id': vid,
    'title': title,
    'url': url,
    'segments': [
        {'i': idx, 'start': s, 'end': e, 'en': t, 'zh': ''}
        for idx, (s, e, t) in enumerate(merged)
    ],
}
output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

# 删掉中间态 vtt
vtt_path.unlink(missing_ok=True)

print(output)
print(f'segments={len(merged)}')
PY

  echo ""
  echo "完成: $output"
  echo ""
  echo "下一步（由调用方 Agent 执行）："
  echo "  1) 通读全部 segments，理解主题、语域、术语。"
  echo "  2) 为每个 segment 的 zh 字段填入中文（信达雅，见 SKILL.md）。"
  echo "  3) 保存后运行：$0 render $output"
}

cmd_render() {
  local json="${1:-}"
  [[ -z "$json" ]] && { echo "用法: $0 render <segments.json> [-o out.html]" >&2; exit 1; }
  shift || true

  local output=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output) output="$2"; shift 2 ;;
      -*) echo "未知参数: $1" >&2; exit 1 ;;
      *)  echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done

  [[ -f "$json" ]] || { echo "未找到: $json" >&2; exit 2; }

  python3 - "$json" "$output" <<'PY'
import html, json, sys
from pathlib import Path

json_path = Path(sys.argv[1])
output_arg = sys.argv[2]

data = json.loads(json_path.read_text(encoding='utf-8'))
segments = data.get('segments', [])
title = data.get('title') or data.get('video_id') or 'Transcript'
url   = data.get('url', '')
vid   = data.get('video_id', 'transcript')

has_zh = any((s.get('zh') or '').strip() for s in segments)
missing = [s['i'] for s in segments if not (s.get('zh') or '').strip()] if has_zh else []

if output_arg:
    output = Path(output_arg)
else:
    output = json_path.parent / f'{vid}.reading.html'

css = '''
:root {
  --bg: #f6f2ea;
  --paper: #fffdf8;
  --text: #201d19;
  --muted: #6b655d;
  --rule: #e6ddd0;
  --accent: #8b6b43;
  --shadow: 0 6px 16px rgba(27, 21, 14, 0.05);
}
html, body { margin:0; padding:0; background:var(--bg); color:var(--text); font-family: ui-serif, Georgia, Cambria, "Times New Roman", serif; line-height:1.5; }
* { box-sizing:border-box; }
main { max-width: 820px; margin:0 auto; padding:20px 18px 32px; }
.header-card, .section { background:var(--paper); border:1px solid var(--rule); box-shadow:var(--shadow); }
.header-card { padding:14px 18px 12px; margin-bottom:14px; }
.kicker,.label,.meta,footer,.note { font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
h1 { margin:0 0 4px; font-size:clamp(18px,2.2vw,22px); line-height:1.25; font-weight:600; }
.meta { display:flex; flex-wrap:wrap; gap:4px 14px; padding-top:6px; margin-top:4px; border-top:1px solid var(--rule); font-size:11px; color:var(--muted); }
.note { margin-top:8px; padding:6px 10px; background:#faf6ef; border-left:2px solid #ccb08a; font-size:12px; color:#5d554b; }
.section-list { display:grid; gap:6px; }
.section { padding:8px 14px 10px; }
.time { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:10px; letter-spacing:.03em; color:var(--muted); margin-bottom:4px; }
.label { display:inline-block; font-size:9px; text-transform:uppercase; letter-spacing:.06em; color:var(--accent); margin-right:6px; vertical-align:2px; }
.en { font-size:13.5px; line-height:1.45; font-weight:500; margin:1px 0 0; display:inline; }
.zh { font-size:14px; line-height:1.6; color:#2b2825; margin:4px 0 0; font-family: "Songti SC", "Noto Serif SC", "Source Han Serif SC", "PingFang SC", "Hiragino Sans GB", ui-serif, serif; display:inline; }
.line { margin:2px 0 0; }
.single { font-size:14px; line-height:1.5; margin:2px 0 0; display:inline; }
.divider { display:none; }
footer { margin-top:14px; text-align:center; color:var(--muted); font-size:11px; }
@media (max-width: 720px) {
  main { padding:14px 10px 24px; }
  .header-card { padding:12px 14px 10px; }
  .section { padding:8px 12px 10px; }
}
@media print {
  @page { size: A4; margin: 12mm 10mm; }
  html, body { background:#fff; color:#000; }
  main { max-width:none; padding:0; }
  .header-card, .section { box-shadow:none; border-color:#bbb; }
  .header-card { margin-bottom:8px; padding:8px 10px; }
  .section-list { gap:4px; }
  .section { padding:5px 10px 6px; page-break-inside:avoid; break-inside:avoid; }
  .en { font-size:11pt; line-height:1.35; }
  .zh { font-size:11pt; line-height:1.5; }
  .single { font-size:11pt; line-height:1.35; }
  .time { font-size:8pt; margin-bottom:2px; }
  .label { font-size:7.5pt; }
  h1 { font-size:14pt; }
  .meta, .note, footer { font-size:8.5pt; }
}
'''

parts = []
for s in segments:
    start = s.get('start', '')
    end   = s.get('end', '')
    en    = s.get('en', '') or ''
    zh    = (s.get('zh') or '').strip()
    if has_zh and zh:
        parts.append(
            '<section class="section">'
            f'<div class="time">{html.escape(start)} — {html.escape(end)}</div>'
            f'<p class="line"><span class="label">EN</span><span class="en">{html.escape(en)}</span></p>'
            f'<p class="line"><span class="label">中文</span><span class="zh">{html.escape(zh)}</span></p>'
            '</section>'
        )
    else:
        parts.append(
            '<section class="section">'
            f'<div class="time">{html.escape(start)} — {html.escape(end)}</div>'
            f'<p class="line"><span class="label">EN</span><span class="single">{html.escape(en)}</span></p>'
            '</section>'
        )

note_html = ''
if has_zh and missing:
    note_html = f'<div class="note">注意：有 {len(missing)} 段未翻译（i={missing[:10]}{"..." if len(missing) > 10 else ""}），已回退为单语显示。</div>'

doc = f'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{css}</style>
</head>
<body>
<main>
  <header>
    <div class="header-card">
      <h1>{html.escape(title)}</h1>
      <div class="meta">
        <span>Video: <a href="{html.escape(url)}">{html.escape(url)}</a></span>
        <span>Segments: {len(segments)}</span>
        <span>Mode: {"bilingual" if has_zh else "english-only"}</span>
      </div>
      {note_html}
    </div>
  </header>
  <div class="section-list">{''.join(parts)}</div>
</main>
</body>
</html>'''

output.write_text(doc, encoding='utf-8')
print(output)

# 渲染成功后清理中间态 segments.json，只保留最终 HTML
try:
    json_path.unlink()
except Exception:
    pass
PY

  echo ""
  echo "完成: 已渲染 HTML（中间态 segments.json 已清理）"
}

cmd_clean() {
  local vid="${1:-}"
  if [[ -n "$vid" ]]; then
    rm -rf "$BASE_DIR/$vid"
    echo "已删除: $BASE_DIR/$vid"
  else
    rm -rf "$BASE_DIR"
    echo "已删除: $BASE_DIR"
  fi
}

check_deps
sub="${1:-}"; shift || true
case "$sub" in
  list)    cmd_list    "$@" ;;
  prepare) cmd_prepare "$@" ;;
  render)  cmd_render  "$@" ;;
  clean)   cmd_clean   "$@" ;;
  build)
    echo "[提示] build 已废弃：请分两步使用 prepare（拉英文字幕）+ 由 Agent 翻译 zh + render（生成 HTML）。见 SKILL.md" >&2
    cmd_prepare "$@"
    ;;
  -h|--help|help|"")
    sed -n '2,24p' "$0"
    ;;
  *)
    echo "未知子命令: $sub" >&2
    echo "用法: $0 {list|prepare|render|clean|help}" >&2
    exit 1
    ;;
esac
