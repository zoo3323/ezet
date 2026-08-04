#!/usr/bin/env python3
"""실제 터미널 출력(ANSI)을 docs 용 SVG 스크린샷으로 변환한다.

사용법: ansi2svg.py <캡처파일> <프레임번호> <창 제목> <출력.svg>

캡처 파일은 tools/capture-screens.sh 가 expect 로 만든 원본 출력이다. 프레임은
화면 지움(ESC[2J) 또는 커서-업 재그리기(ESC[<n>A) 를 경계로 나눈다.
글자마다 격자 좌표(8.6px x 19px)를 직접 지정해, 보는 쪽 폰트 메트릭과 무관하게
터미널과 같은 정렬을 유지한다(textLength 로 늘리면 글자 간격이 벌어진다).
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
    """ANSI 문자열 → [[(col, text, style), ...], ...] (줄 단위 스타일 런)"""
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
    # 오른쪽 여백을 넉넉히 둔다: ← 처럼 글꼴 대체가 일어나는 글자는 격자보다 넓게 그려진다.
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
    # 선택 행 배경을 먼저 깔고 그 위에 글자를 얹는다.
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
            # 앞뒤 패딩 공백은 버리고, 남은 글자마다 격자 좌표를 직접 지정한다.
            # (textLength 로 늘리면 글자 간격이 벌어져 터미널과 달라진다.)
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
    # newline="" : 유니버설 개행 변환이 커서-업 재그리기의 \r 를 \n 으로 바꿔 프레임 경계를 지운다.
    raw = open(raw_path, encoding="utf-8", errors="replace", newline="").read()
    frames = re.split(r"\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J", raw)
    frame = frames[int(frame_idx)]
    lines = [ln for ln in parse(frame)]

    def blank_or_noise(ln):
        text = "".join(t for _, t, _ in ln).strip()
        return text == "" or text in ("취소됨.", "Cancelled.")

    while lines and blank_or_noise(lines[0]):
        lines.pop(0)
    while lines and blank_or_noise(lines[-1]):
        lines.pop()
    open(out_path, "w", encoding="utf-8").write(to_svg(lines, title))
    print(f"{out_path}: {len(lines)} lines")


if __name__ == "__main__":
    main()
