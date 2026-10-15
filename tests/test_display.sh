#!/usr/bin/env bash
# Width helpers behind the tables: they return what the old $(...) versions
# printed (expected values taken from 1.1.1), and the brief switch to the C
# locale for counting bytes leaves the caller's locale as it was. The helpers
# are evaluated straight from bin/ezet.
# shellcheck disable=SC2016  # the bash -c body is single-quoted on purpose
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
section=$(awk '/^# Display width in terminal cells/,/^# Real terminal width/' "$ROOT/bin/ezet" | sed '$d')

utf8=""
for loc in C.UTF-8 en_US.UTF-8 C.utf8 en_US.utf8; do
  if [ "$(LC_ALL=$loc bash -c 's="한글"; printf %s "${#s}"' 2>/dev/null)" = 2 ]; then utf8=$loc; break; fi
done
if [ -z "$utf8" ]; then printf 'display tests skipped: no UTF-8 locale\n'; exit 0; fi

checks='
  set -euo pipefail
  eval "$1"
  BD=""; RESET=""; SEL=""; HINT=""; INNER_W=20
  want() { [ "$2" = "$3" ] || { printf "FAIL %s (%s): got [%s] want [%s]\n" "$1" "$LOCALE_MODE" "$2" "$3" >&2; exit 1; }; }

  disp_width_v "pole-claude";                         want width-ascii "$DW" 11
  disp_width_v "아주긴세션이름이에요-한글-테스트";    want width-hangul "$DW" 32
  disp_width_v "a·b…c";                               want width-marks "$DW" 5
  disp_width_v "日本語テキストと…記号·混在";          want width-mixed "$DW" 26
  disp_width_v "";                                    want width-empty "$DW" 0
  want width-print "$(disp_width "한글abc")" 7

  trunc_v "pole-claude" 8;                            want trunc-ascii "$TR" "pole-cl~"
  trunc_v "pole-claude" 12;                           want trunc-fits "$TR" "pole-claude"
  trunc_v "아주긴세션이름이에요-한글-테스트" 12;      want trunc-hangul "$TR" "아주긴세션~"
  trunc_v "日本語テキストと…記号·混在" 12;            want trunc-mixed "$TR" "日本語テキ~"
  want trunc-print "$(trunc "/opt/very/long/path/without/home/at/all/xxxxxxxxxxxx" 12)" "/opt/very/l~"

  fmt_dir_v "/home/silla/silla/parking-lot/2.5D-OD/footprint-od" 28
  want dir-tail "$FD" "…ng-lot/2.5D-OD/footprint-od"
  fmt_dir_v "/home/silla/silla/parking-lot/2.5D-OD/footprint-od" 8
  want dir-base "$FD" "footpri~"
  fmt_dir_v "/home/silla/한글/경로/아주/깊은/폴더이름" 12
  want dir-hangul "$FD" "…은/폴더이름"
  fmt_dir_v "/opt/very/long/path/without/home/at/all/xxxxxxxxxxxx" 28
  want dir-nohome "$FD" "…ut/home/at/all/xxxxxxxxxxxx"
  fmt_dir_v "/root/x" 8;                              want dir-root "$FD" "~/x"
  fmt_dir_v "/home/silla" 8;                          want dir-home "$FD" "~"

  fmt_idle_v -1;    want idle-unknown "$FI" "?"
  fmt_idle_v 59;    want idle-now "$FI" now
  fmt_idle_v 120;   want idle-min "$FI" 2m
  want idle-hour "$(fmt_idle_v 7200; printf %s "$FI")" 2h
  fmt_idle_v 90000; want idle-day "$FI" 1d

  # Padding goes by display width: two Hangul syllables take four cells.
  want pad "$(box_line_wide "한글" "한글")" "│  한글$(printf "%15s" "") │"
  want pad-sel "$(box_line_wide_sel "ab" "ab")" "│› ab$(printf "%17s" "") │"

  # The locale is back to the callers: two syllables count as two characters.
  s="한글"; want locale-kept "${#s}" 2
'

LOCALE_MODE="LC_ALL=$utf8" LC_ALL="$utf8" bash -c "$checks" _ "$section"
env -u LC_ALL -u LC_CTYPE LOCALE_MODE="LANG=$utf8" LANG="$utf8" bash -c "$checks" _ "$section"

printf 'display tests passed\n'
