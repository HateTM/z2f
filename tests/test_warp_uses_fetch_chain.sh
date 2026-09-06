#!/bin/sh
# tests/test_warp_uses_fetch_chain.sh — установка WARP обязана ходить через
# общую цепочку загрузки, а не голым curl.
#
# Повод: 06.09.2026, «не могу поставить WARP». В логе задачи ровно одна строка
# отказа: `curl: (28) Timed out after 180001 milliseconds`. Три минуты — это
# один `--max-time 180`, то есть ни одного запасного пути не пробовалось.
#
# Причина: files/z2k-warp.sh не подключал lib/utils.sh вовсе. Значит z2k_fetch
# там не существовал, проверка `command -v z2k_fetch` всегда была ложной, и
# загрузка сразу падала на голый curl к raw.githubusercontent.com — мимо слоя
# через наш узел, мимо jsdelivr и gh-proxy.
#
# Тем же махом молча пропускалась и сверка суммы: z2k_sha256_file вызывается
# там через тот же `command -v`, то есть движок ставился без проверки.
#
# Тест ИСПОЛНЯЕТ скрипт (штатным Z2K_WARP_SOURCE_ONLY) и смотрит, доступны ли
# функции в его собственном окружении. Проверять наличие строки `. utils.sh`
# грепом мало: она может стоять там, где до неё не доходит выполнение.
# POSIX sh (busybox ash).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }

W="$ROOT/files/z2k-warp.sh"
[ -f "$W" ] || { echo "нет $W"; exit 1; }
[ -f "$ROOT/lib/utils.sh" ] || { echo "нет lib/utils.sh"; exit 1; }

for fn in z2k_fetch z2k_sha256_file; do
    if Z2K_WARP_SOURCE_ONLY=1 ZAPRET2_DIR="$ROOT" sh -c \
         ". \"$W\" >/dev/null 2>&1; command -v $fn >/dev/null 2>&1"; then
        ok "$fn доступна внутри z2k-warp.sh"
    else
        bad "$fn недоступна — установка уйдёт голым curl мимо узла и зеркал"
    fi
done

# Загрузка обязана СНАЧАЛА пробовать общую цепочку. Голый curl допустим только
# как последняя попытка после неё.
_body=$(awk '/^warp_fetch_engine\(\)/{f=1} f{print} f && /^\}/{exit}' "$W")
_chain=$(printf '%s\n' "$_body" | grep -n 'z2k_fetch' | head -1 | cut -d: -f1)
_curl=$(printf '%s\n' "$_body" | grep -n 'curl -sSL' | head -1 | cut -d: -f1)
if [ -n "$_chain" ] && [ -n "$_curl" ] && [ "$_chain" -lt "$_curl" ]; then
    ok "цепочка пробуется раньше голого curl"
else
    bad "голый curl стоит раньше цепочки — запасные пути не пробуются"
fi

echo
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
