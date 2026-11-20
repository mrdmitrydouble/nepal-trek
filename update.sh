#!/usr/bin/env bash
# Обновляет страницу для родных из alinashikut/annapurna (ветка master) и публикует.
# Запуск: bash update.sh            — скачать, проверить, закоммитить, запушить
#         bash update.sh --no-push  — только скачать и проверить
set -euo pipefail
cd "$(dirname "$0")"

SRC_REPO="alinashikut/annapurna"
SRC_PATH="Система/рабочие/день_решений_16-11/итог_9_ночей/страница_родные/index.html"
MSG="${COMMIT_MSG:-Обновление страницы}"

ENC=$(python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$SRC_PATH")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

gh api "repos/$SRC_REPO/contents/$ENC?ref=master" -H "Accept: application/vnd.github.raw" > "$TMP/raw.html"

SIZE=$(wc -c < "$TMP/raw.html" | tr -d ' ')
[ "$SIZE" -gt 100000 ] || { echo "СТОП: файл слишком маленький ($SIZE байт)"; exit 1; }
grep -q "<title>" "$TMP/raw.html" || { echo "СТОП: нет <title>"; exit 1; }

# Проверка приватности: текст без встроенных картинок, финансовые слова.
# «долг» ищем как отдельное слово, чтобы не ловить «долго».
python3 -I - "$TMP/raw.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"data:[a-z]+/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+", "", t)
pat = re.compile(r"(?i)₨|₽|руб|kaspi|\bдолг(?!о)|баланс|подушк|бюджет|полис")
hits = []
for m in pat.finditer(t):
    ctx = re.sub(r"<[^>]+>", " ", t[max(0, m.start()-120):m.end()+80])
    hits.append(f"[{m.group()}] " + re.sub(r"\s+", " ", ctx))
if hits:
    print("СТОП: найдены финансовые слова, не публикую:")
    print("\n".join(hits))
    sys.exit(1)
phones = set(re.findall(r"\+(?:977|66)[0-9-]{8,}", t))
print(f"Приватность: финансовых слов нет; телефонов +977/+66: {len(phones)}")
PY

# Исходник — фрагмент без <!doctype>/<head>: добавляем каркас, meta robots и правило [hidden].
# Если в исходнике появится свой <head>, вставляем meta robots в него.
python3 -I - "$TMP/raw.html" index.html <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
robots = '<meta name="robots" content="noindex, nofollow">'
# В среде Claude, где делали страницу, [hidden] скрывается всегда; без этого правила
# классы с display:flex перебивают hidden и запасная схема карты ложится поверх 3D-карты.
fix = '<style>[hidden]{display:none!important}</style>'
if re.search(r'name=["\']robots["\']', src, re.I):
    out = src.replace("</title>", "</title>\n" + fix, 1)
elif re.search(r"<head(\s[^>]*)?>", src, re.I):
    out = re.sub(r"(<head(?:\s[^>]*)?>)", r"\1\n" + robots + "\n" + fix, src, count=1, flags=re.I)
else:
    out = ("<!doctype html>\n<html lang=\"ru\">\n<head>\n<meta charset=\"utf-8\">\n"
           "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
           + robots + "\n" + fix + "\n" + src)
open(sys.argv[2], "w", encoding="utf-8").write(out)
PY

echo "index.html: $(wc -c < index.html | tr -d ' ') байт"
[ "${1:-}" = "--no-push" ] && exit 0

git add index.html
if git diff --cached --quiet; then
  echo "Изменений нет — публиковать нечего."
  exit 0
fi
git commit -m "$MSG"
git push origin main
echo "Готово. Сайт обновится через 1–2 минуты: https://mrdmitrydouble.github.io/nepal-trek/"
