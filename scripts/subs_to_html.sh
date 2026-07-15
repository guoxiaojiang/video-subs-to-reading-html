#!/usr/bin/env bash
# video-subs-to-reading-html — 从 YouTube 视频字幕生成适合阅读的 HTML
#
# 依赖: yt-dlp, python3
# Python 标准库即可，无额外依赖
#
# 用法:
#   1) 查看可用字幕:
#      ./subs_to_html.sh list <youtube_url>
#
#   2) 生成阅读版 HTML:
#      ./subs_to_html.sh build <youtube_url> [选项]
#        --lang en                    仅导出单语 (默认 en)
#        --bilingual zh-Hans          生成双语对照 (例如 zh-Hans / zh-Hant / ja / ko ...)
#        -o FILE                      输出 HTML 路径
#        --keep-intermediate          保留中间 .vtt / .md / .txt 文件
#
#   3) 清理:
#      ./subs_to_html.sh clean [video_id]
#
# 输出默认目录:
#   ~/Downloads/subtitles_extract/<video_id>/<video_id>.reading.html

set -euo pipefail

BASE_DIR="$HOME/Downloads/subtitles_extract"
WORKDIR=""
KEEP_INTERMEDIATE=0

cleanup() {
  if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

check_deps() {
  for cmd in yt-dlp python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "缺少依赖: $cmd" >&2; exit 1; }
  done
}

video_id_of() {
  local url="$1"
  yt-dlp --no-update --print id "$url" | head -1
}

cmd_list() {
  local url="${1:-}"
  [[ -z "$url" ]] && { echo "用法: $0 list <youtube_url>" >&2; exit 1; }
  yt-dlp --no-update --list-subs "$url"
}

cmd_build() {
  local url="${1:-}"
  [[ -z "$url" ]] && { echo "用法: $0 build <youtube_url> [选项]" >&2; exit 1; }
  shift || true

  local src_lang="en"
  local tgt_lang=""
  local output=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)               src_lang="$2"; shift 2 ;;
      --bilingual)          tgt_lang="$2"; shift 2 ;;
      -o|--output)          output="$2"; shift 2 ;;
      --keep-intermediate)  KEEP_INTERMEDIATE=1; shift ;;
      -*)                   echo "未知参数: $1" >&2; exit 1 ;;
      *)                    echo "未知参数或多余输入: $1" >&2; exit 1 ;;
    esac
  done

  local vid; vid=$(video_id_of "$url")
  local out_dir="$BASE_DIR/$vid"
  mkdir -p "$out_dir"

  if [[ -z "$output" ]]; then
    output="$out_dir/$vid.reading.html"
  fi

  local langs="$src_lang"
  if [[ -n "$tgt_lang" ]]; then langs="$src_lang,$tgt_lang"; fi

  echo "==> 下载字幕轨道: $langs" >&2
  yt-dlp --no-update --skip-download --write-auto-subs --sub-langs "$langs" --sub-format "vtt" \
    -o "$out_dir/%(id)s.%(ext)s" "$url" >/dev/null

  local src_vtt="$out_dir/$vid.$src_lang.vtt"
  local tgt_vtt=""
  [[ -n "$tgt_lang" ]] && tgt_vtt="$out_dir/$vid.$tgt_lang.vtt"

  [[ -f "$src_vtt" ]] || { echo "没有找到源字幕: $src_vtt" >&2; exit 2; }
  if [[ -n "$tgt_lang" && ! -f "$tgt_vtt" ]]; then
    echo "没有找到目标字幕: $tgt_vtt" >&2
    exit 2
  fi

  python3 - <<'PY' "$src_vtt" "$tgt_vtt" "$output" "$url" "$src_lang" "$tgt_lang" "$out_dir" "$vid" "$KEEP_INTERMEDIATE"
import re, html, sys
from pathlib import Path

src_vtt = Path(sys.argv[1])
tgt_vtt = Path(sys.argv[2]) if sys.argv[2] else None
output  = Path(sys.argv[3])
url     = sys.argv[4]
src_lang = sys.argv[5]
tgt_lang = sys.argv[6]
out_dir = Path(sys.argv[7])
vid     = sys.argv[8]
keep_intermediate = sys.argv[9] == '1'

cue_re = re.compile(r'^(\d\d:\d\d:\d\d\.\d+) --> (\d\d:\d\d:\d\d\.\d+)')
tag_re = re.compile(r'<[^>]+>')

def norm(s):
    s = tag_re.sub('', s)
    s = s.replace('&nbsp;', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def parse_vtt(path: Path):
    lines = path.read_text(encoding='utf-8').splitlines()
    cues = []
    i = 0
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

def merge_text(prev, cur):
    prev, cur = norm(prev), norm(cur)
    if not prev: return cur
    if not cur: return prev
    if cur == prev: return prev
    if cur.startswith(prev): return cur
    if prev.endswith(cur): return prev
    wp, wc = prev.split(' '), cur.split(' ')
    overlap = 0
    for k in range(1, min(len(wp), len(wc), 12)+1):
        if wp[-k:] == wc[:k]: overlap = k
    if overlap:
        return prev + ' ' + ' '.join(wc[overlap:])
    return prev + ' ' + cur

def is_end(s):
    return bool(re.search(r'[.!?。！？]$' , s.strip()))

src = parse_vtt(src_vtt)
tgt = parse_vtt(tgt_vtt) if tgt_vtt else []

pairs = []
if tgt_vtt:
    tgt_idx = 0
    for s in src:
        best = None; best_j = None
        for j in range(max(0, tgt_idx-3), min(len(tgt), tgt_idx+8)):
            z = tgt[j]
            if z['start'] == s['start']:
                best, best_j = z, j
                break
        if best is None:
            for j in range(max(0, tgt_idx-3), min(len(tgt), tgt_idx+8)):
                z = tgt[j]
                overlap = not (z['end'] < s['start'] or z['start'] > s['end'])
                if overlap:
                    best, best_j = z, j
                    break
        tgt_idx = best_j if best_j is not None else tgt_idx
        pairs.append((s['start'], s['end'], s['text'], best['text'] if best else ''))
else:
    pairs = [(s['start'], s['end'], s['text'], '') for s in src]

merged = []
cur = None
for start, end, st, tt in pairs:
    if cur is None:
        cur = [start, end, st, tt]
        continue
    cand_src = merge_text(cur[2], st)
    cand_tgt = merge_text(cur[3], tt)
    if len(cand_src) > 260 and is_end(cur[2]):
        merged.append(tuple(cur))
        cur = [start, end, st, tt]
    else:
        cur[1] = end
        cur[2] = cand_src
        cur[3] = cand_tgt
if cur is not None:
    merged.append(tuple(cur))

post = []
for item in merged:
    if post and len(item[2]) < 40:
        ps, pe, pen, ptgt = post[-1]
        post[-1] = (ps, item[1], merge_text(pen, item[2]), merge_text(ptgt, item[3]))
    else:
        post.append(item)
merged = post

lang_title = f"{src_lang} transcript" if not tgt_lang else f"{src_lang} / {tgt_lang} reading transcript"
css = '''
:root {
  --bg: #f6f2ea;
  --paper: #fffdf8;
  --text: #201d19;
  --muted: #6b655d;
  --rule: #e6ddd0;
  --accent: #8b6b43;
  --shadow: 0 18px 45px rgba(27, 21, 14, 0.08);
}
html, body { margin:0; padding:0; background:var(--bg); color:var(--text); font-family: ui-serif, Georgia, Cambria, "Times New Roman", serif; line-height:1.75; }
* { box-sizing:border-box; }
main { max-width: 920px; margin:0 auto; padding:64px 24px 120px; }
.header-card, .section { background:var(--paper); border:1px solid var(--rule); box-shadow:var(--shadow); }
.header-card { padding:40px 44px 32px; margin-bottom:38px; }
.kicker,.label,.meta,footer,.note { font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.kicker { text-transform:uppercase; letter-spacing:.12em; font-size:12px; color:var(--accent); margin-bottom:14px; }
h1 { margin:0 0 10px; font-size:clamp(30px,4vw,44px); line-height:1.15; font-weight:600; }
.subtitle { margin:0 0 18px; font-size:17px; color:var(--muted); font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.meta { display:flex; flex-wrap:wrap; gap:10px 20px; padding-top:18px; border-top:1px solid var(--rule); font-size:13px; color:var(--muted); }
.note { margin-top:18px; padding:14px 16px; background:#faf6ef; border-left:3px solid #ccb08a; font-size:14px; color:#5d554b; }
.section-list { display:grid; gap:18px; }
.section { padding:26px 30px 28px; }
.time { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px; letter-spacing:.04em; color:var(--muted); margin-bottom:16px; }
.label { font-size:12px; text-transform:uppercase; letter-spacing:.08em; color:var(--accent); }
.en { font-size:24px; line-height:1.55; font-weight:500; margin:6px 0 0; }
.zh { font-size:18px; line-height:1.8; color:#35302b; margin:6px 0 0; }
.single { font-size:22px; line-height:1.7; margin:8px 0 0; }
.divider { height:1px; background:var(--rule); margin:18px 0 8px; }
footer { margin-top:28px; text-align:center; color:var(--muted); font-size:13px; }
@media (max-width:720px) {{ main {{ padding:24px 14px 72px; }} .header-card {{ padding:28px 22px 22px; }} .section {{ padding:20px 18px 20px; }} .en {{ font-size:20px; }} .zh {{ font-size:16px; }} .single {{ font-size:18px; }} }}
'''

parts = []
for start, end, en, zh in merged:
    if tgt_lang:
        parts.append(f'''<section class="section"><div class="time">{html.escape(start)} — {html.escape(end)}</div><div class="label">{html.escape(src_lang)}</div><p class="en">{html.escape(en)}</p><div class="divider"></div><div class="label">{html.escape(tgt_lang)}</div><p class="zh">{html.escape(zh)}</p></section>''')
    else:
        parts.append(f'''<section class="section"><div class="time">{html.escape(start)} — {html.escape(end)}</div><div class="label">{html.escape(src_lang)}</div><p class="single">{html.escape(en)}</p></section>''')

html_doc = f'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(vid)} — {html.escape(lang_title)}</title>
<style>{css}</style>
</head>
<body>
<main>
  <header>
    <div class="header-card">
      <div class="kicker">Reading Transcript</div>
      <h1>{html.escape(vid)}</h1>
      <p class="subtitle">{html.escape(lang_title)}</p>
      <div class="meta">
        <span>Video: <a href="{url}">{url}</a></span>
        <span>Segments: {len(merged)}</span>
        <span>Source: YouTube auto captions</span>
      </div>
      <div class="note">这是为阅读重排过的版本：已合并过碎字幕块、去除部分重复。若启用了双语，会按时间轴对齐。自动字幕与自动翻译可能存在专有名词、断句和标点误差。</div>
    </div>
  </header>
  <div class="section-list">{''.join(parts)}</div>
  <footer>Clean editorial layout. No glossy / "AI aesthetic" treatment.</footer>
</main>
</body>
</html>'''

output.write_text(html_doc, encoding='utf-8')

# 中间态: 默认删掉 vtt；如果 keep_intermediate 就额外保留一个 txt 摘要
if keep_intermediate:
    lines = []
    for start, end, en, zh in merged:
        lines.append(f'[{start} - {end}]')
        lines.append(f'{src_lang.upper()}: {en}')
        if tgt_lang:
            lines.append(f'{tgt_lang}: {zh}')
        lines.append('')
    (out_dir / f'{vid}.reading.txt').write_text('\n'.join(lines), encoding='utf-8')
else:
    src_vtt.unlink(missing_ok=True)
    if tgt_vtt:
        tgt_vtt.unlink(missing_ok=True)

print(output)
print(f'segments={len(merged)}')
PY

  echo ""
  echo "完成: $output"
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
  list)   cmd_list  "$@" ;;
  build)  cmd_build "$@" ;;
  clean)  cmd_clean "$@" ;;
  -h|--help|help|"")
    sed -n '2,24p' "$0"
    ;;
  *)
    echo "未知子命令: $sub" >&2
    echo "用法: $0 {list|build|clean|help}" >&2
    exit 1
    ;;
esac
