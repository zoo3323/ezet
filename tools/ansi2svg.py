#!/usr/bin/env python3
"""Turn real terminal output (ANSI) into an SVG screenshot for the docs.

Usage: ansi2svg.py <capture-file> <frame-index> <window-title> <out.svg>

The capture file is raw output recorded by tools/capture-screens.sh through
expect. Frames are split on a screen clear (ESC[2J) or a cursor-up redraw
(ESC[<n>A). Every glyph gets an explicit grid coordinate (8.6px x 19px), so the
alignment matches the terminal regardless of the viewer's font metrics
(stretching with textLength would spread the glyphs apart instead).
"""
import re
import sys
import unicodedata

CW, LH, X0, TITLEBAR, PAD = 8.6, 19.0, 18.0, 34.0, 12.0
FONT = "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
FS = 14.5

FG_DEFAULT = "#c3ccd8"
PALETTE = {31: "#e06c75", 32: "#98c379", 33: "#e5c07b", 36: "#56b6c2"}
PALETTE_256 = {240: "#5a6472", 245: "#6b7684", 237: "#333b47"}


def dwidth(ch):
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def parse(raw):
    """ANSI text -> [[(col, text, style), ...], ...] (per-line style runs)."""
    lines, run, cur = [], [], []
    st = {"fg": None, "bold": False, "dim": False, "bg": None}
    col = 0

    def flush():
        nonlocal run
        if run:
            cur.append(run)
            run = []

    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\x1b":
            m = re.match(r"\x1b\[([0-9;?]*)([a-zA-Z])", raw[i:])
            if not m:
                i += 1
                continue
            args, fin = m.group(1), m.group(2)
            if fin == "m":
                flush()
                codes = [int(x) for x in args.split(";") if x != ""] or [0]
                j = 0
                while j < len(codes):
                    c = codes[j]
                    if c == 0:
                        st = {"fg": None, "bold": False, "dim": False, "bg": None}
                    elif c == 1:
                        st = dict(st, bold=True)
                    elif c == 2:
                        st = dict(st, dim=True)
                    elif c == 22:
                        st = dict(st, bold=False, dim=False)
                    elif c == 39:
                        st = dict(st, fg=None)
                    elif c == 49:
                        st = dict(st, bg=None)
                    elif c in PALETTE:
                        st = dict(st, fg=PALETTE[c])
                    elif c in (38, 48) and codes[j + 1 : j + 2] == [5]:
                        color = PALETTE_256.get(codes[j + 2], FG_DEFAULT)
                        st = dict(st, **({"fg": color} if c == 38 else {"bg": color}))
                        j += 2
                    j += 1
            i += m.end()
            continue
        if ch == "\n":
            flush()
            lines.append(cur)
            cur, col = [], 0
            i += 1
            continue
        if ch == "\r":
            i += 1
            continue
        if not run:
            run = [col, "", dict(st)]
        elif run[2] != st:
            flush()
            run = [col, "", dict(st)]
        run[1] += ch
        col += dwidth(ch)
        i += 1
    flush()
    if cur:
        lines.append(cur)
    return lines


def to_svg(lines, title):
    cols = max((sum(dwidth(c) for _, t, _ in ln for c in t) for ln in lines), default=80)
    # Keep a generous right margin: glyphs that fall back to another font (← for
    # one) are drawn wider than their grid cell.
    w = round(X0 * 2 + cols * CW + 24, 1)
    h = round(TITLEBAR + PAD * 2 + len(lines) * LH, 1)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" font-family="{FONT}" xml:space="preserve">',
        f'<rect width="{w}" height="{h}" rx="10" fill="#0f141a"/>',
        f'<rect y="{TITLEBAR}" width="{w}" height="{round(h - TITLEBAR, 1)}" fill="#151a21"/>',
        '<circle cx="20" cy="17" r="5.5" fill="#ff5f57"/>',
        '<circle cx="38" cy="17" r="5.5" fill="#febc2e"/>',
        '<circle cx="56" cy="17" r="5.5" fill="#28c840"/>',
        f'<text x="{round(w / 2, 1)}" y="21.5" fill="#6b7684" font-size="11.5" '
        f'text-anchor="middle">{esc(title)}</text>',
    ]
    # Lay the selected-row background down first, then the glyphs on top.
    for idx, ln in enumerate(lines):
        top = TITLEBAR + PAD + idx * LH
        for col, text, st in ln:
            if not st["bg"]:
                continue
            width = sum(dwidth(c) for c in text) * CW
            out.append(
                f'<rect x="{round(X0 + col * CW, 1)}" y="{round(top, 1)}" '
                f'width="{round(width, 1)}" height="{LH}" fill="{st["bg"]}"/>'
            )
    for idx, ln in enumerate(lines):
        base = TITLEBAR + PAD + idx * LH + 13.3
        for col, text, st in ln:
            if not text.strip():
                continue
            # Drop the surrounding padding and place every remaining glyph on the
            # grid (textLength would stretch the spacing away from the terminal).
            lead = len(text) - len(text.lstrip(" "))
            col += sum(dwidth(c) for c in text[:lead])
            body = text.strip(" ")
            xs, cur_col = [], col
            for ch in body:
                xs.append(f"{round(X0 + cur_col * CW, 1):g}")
                cur_col += dwidth(ch)
            attrs = [
                f'x="{" ".join(xs)}"',
                f'y="{round(base, 1)}"',
                f'fill="{st["fg"] or FG_DEFAULT}"',
                f'font-size="{FS}"',
                'xml:space="preserve"',
            ]
            if st["bold"]:
                attrs.append('font-weight="600"')
            if st["dim"]:
                attrs.append('opacity="0.55"')
            out.append(f'<text {" ".join(attrs)}>{esc(body)}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def main():
    raw_path, frame_idx, title, out_path = sys.argv[1:5]
    # newline="": universal newlines would turn the \r of a cursor-up redraw into
    # \n and erase the frame boundary.
    raw = open(raw_path, encoding="utf-8", errors="replace", newline="").read()
    frames = re.split(r"\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J", raw)
    frame = frames[int(frame_idx)]
    lines = [ln for ln in parse(frame)]

    def blank_or_noise(ln):
        text = "".join(t for _, t, _ in ln).strip()
        return text == "" or text == "Cancelled."

    while lines and blank_or_noise(lines[0]):
        lines.pop(0)
    while lines and blank_or_noise(lines[-1]):
        lines.pop()
    open(out_path, "w", encoding="utf-8").write(to_svg(lines, title))
    print(f"{out_path}: {len(lines)} lines")


if __name__ == "__main__":
    main()
