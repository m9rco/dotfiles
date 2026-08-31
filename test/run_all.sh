#!/usr/bin/env sh
#
# 跑全部测试。CI 与本地都用这个入口。
#
#   sh test/run_all.sh              # 用默认 sh
#   DOT_TEST_SHELL=dash sh test/run_all.sh   # 指定 shell 验证 POSIX 兼容性
#
# shellcheck shell=sh

set -u

DOT_TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SH=${DOT_TEST_SHELL:-sh}

_failed=''

for _t in "$DOT_TEST_DIR"/*_test.sh; do
    _name=$(basename -- "$_t")
    printf '\n########## %s (%s) ##########\n' "$_name" "$SH"
    if "$SH" "$_t"; then
        :
    else
        _failed="$_failed $_name"
    fi
done

printf '\n==================================\n'
if [ -n "$_failed" ]; then
    printf 'FAILING SUITES:%s\n' "$_failed"
    exit 1
fi
printf 'all suites passed (%s)\n' "$SH"
