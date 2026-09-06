#!/bin/sh
# tests/test_warp_arch_parity.sh — WARP собирается и опознаётся под те же арки,
# что и остальной проект.
#
# Повод: 06.09.2026, жалоба «не могу поставить WARP». Движок собирался под пять
# арок, клиент туннеля — под девять. На остальных установка отвечала
# `unsupported architecture` — строкой, из которой человек не может понять, что
# дело не в его роутере, а в том, что сборки под него нет вовсе. Разница была
# случайной: движок на Go и кросс-компилируется всюду, где и всё остальное.
#
# Здесь сторожатся ОБА конца: и наличие файла сборки, и то, что опознание арки
# в него попадает. Одного без другого мало — сборка, до которой не доходит
# опознание, так же бесполезна, как её отсутствие.
# POSIX sh (busybox ash).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }

TG="$ROOT/mtproxy-client/builds"
WD="$ROOT/z2k-warpd/builds"
[ -d "$TG" ] && [ -d "$WD" ] || { echo "нет каталогов сборок"; exit 1; }

# Эталон — набор арок клиента туннеля. Синонимы имён (mipsle/mips64le/386)
# исключаются: это временные копии, а не отдельные цели.
_ref=$(ls "$TG" | sed -n 's/^tg-mtproxy-client-linux-//p' \
       | grep -vxE 'mipsle|mips64le|386' | sort)
[ -n "$_ref" ] || { echo "не нашёл сборок клиента туннеля"; exit 1; }

_miss=""
for a in $_ref; do
    [ -f "$WD/z2k-warpd-linux-$a" ] || _miss="$_miss $a"
done
if [ -z "$_miss" ]; then
    ok "движок WARP собран под все арки, что и клиент туннеля ($(echo $_ref | wc -w | tr -d ' ') штук)"
else
    bad "движка WARP нет под:$_miss — там установка ответит «unsupported architecture»"
fi

# Опознание арки обязано попадать в существующий файл. Берём НАСТОЯЩУЮ функцию
# из files/z2k-warp.sh, подставляя железо через uname (opkg.conf в песочнице
# нет, функция сама уходит на uname -m).
_fn=$(awk '/^warp_arch\(\)/{f=1} f{print} f && /^\}/{exit}' "$ROOT/files/z2k-warp.sh")
if [ -z "$_fn" ]; then
    bad "не нашёл warp_arch в files/z2k-warp.sh — проверка ослепла"
else
    _bad=""
    for hw in aarch64 armv7l mipsel mips mips64el i686 x86_64 ppc64 riscv64; do
        _got=$(printf '%s\nuname() { echo "%s"; }\nwarp_arch\n' "$_fn" "$hw" | sh 2>/dev/null)
        if [ -z "$_got" ]; then
            _bad="$_bad $hw(не опознана)"
        elif [ ! -f "$WD/z2k-warpd-linux-$_got" ]; then
            _bad="$_bad $hw(->$_got, файла нет)"
        fi
    done
    if [ -z "$_bad" ]; then
        ok "опознание арки для каждой железки попадает в существующую сборку"
    else
        bad "опознание не даёт рабочей сборки для:$_bad"
    fi
fi

echo
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
