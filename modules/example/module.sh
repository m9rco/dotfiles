#!/usr/bin/env sh
#
# 最小示例模块。存在的意义是验证"新建目录即被发现"这一契约，
# 以及为新增模块提供可复制的模板。它不安装任何东西。
#
# shellcheck shell=sh

MODULE_DESC="Example module (template; installs nothing)"
MODULE_PLATFORMS="macos linux windows"
MODULE_TAGS="example"

install() {
    dot_info "example module ran; DOT_OS=$DOT_OS DOT_ARCH=$DOT_ARCH"
    dot_success "nothing to do"
}
