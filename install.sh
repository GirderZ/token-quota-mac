#!/bin/bash
set -euo pipefail
repo="GirderZ/token-quota-mac"
destination="${HOME}/Applications/Token额度.app"
requested_version=""
open_after=1
replace=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --destination) [ "$#" -ge 2 ] || exit 2; destination="$2"; shift 2 ;;
    --version) [ "$#" -ge 2 ] || exit 2; requested_version="$2"; shift 2 ;;
    --no-open) open_after=0; shift ;;
    --replace) replace=1; shift ;;
    --help) echo '用法：bash install.sh [--destination /绝对路径/Token额度.app] [--version v1.5.1] [--no-open] [--replace]'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo '仅支持 macOS。' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo '预编译版本仅支持 Apple 芯片 Mac。' >&2; exit 1; }
major=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)
[ "$major" -ge 13 ] || { echo '需要 macOS 13 或更新版本。' >&2; exit 1; }
case "$destination" in /*.app) ;; *) echo '安装路径必须是以 .app 结尾的绝对路径。' >&2; exit 2 ;; esac
scratch=$(mktemp -d "${TMPDIR:-/tmp}/token-quota-install.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
fetch() { /usr/bin/curl --fail --silent --show-error --location --connect-timeout 15 --max-time 180 --retry 1 --proto '=https' --tlsv1.2 "$1" -o "$2"; }
if [ -z "$requested_version" ]; then
  fetch "https://api.github.com/repos/${repo}/releases/latest" "$scratch/latest.json"
  tag=$(/usr/bin/plutil -extract tag_name raw -o - "$scratch/latest.json")
else
  tag="v${requested_version#v}"
fi
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo '版本格式不合法。' >&2; exit 1; }
version="${tag#v}"
asset="TokenQuotaMac-${tag}-arm64.zip"
base="https://github.com/${repo}/releases/download/${tag}"
echo "正在下载 Token额度 ${tag}…"
fetch "$base/$asset" "$scratch/$asset"
fetch "$base/SHA256SUMS.txt" "$scratch/SHA256SUMS.txt"
expected=$(/usr/bin/awk -v name="$asset" '$2==name {print $1}' "$scratch/SHA256SUMS.txt")
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo '未找到有效校验值。' >&2; exit 1; }
actual=$(/usr/bin/shasum -a 256 "$scratch/$asset" | /usr/bin/awk '{print $1}')
[ "$actual" = "$expected" ] || { echo 'SHA-256 校验失败，未安装。' >&2; exit 1; }
/usr/bin/ditto -x -k "$scratch/$asset" "$scratch/unpacked"
app="$scratch/unpacked/Token额度.app"
plist="$app/Contents/Info.plist"
[ -f "$plist" ] || { echo '应用包缺失。' >&2; exit 1; }
[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")" = 'local.henry.CodexBadge' ] || exit 1
[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")" = "$version" ] || exit 1
/usr/bin/codesign --verify --deep --strict "$app"
if [ -e "$destination" ]; then
  [ -f "$destination/Contents/Info.plist" ] || { echo '目标不是有效应用，未覆盖。' >&2; exit 1; }
  [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")" = 'local.henry.CodexBadge' ] || { echo '目标是其他应用，未覆盖。' >&2; exit 1; }
  installed=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$destination/Contents/Info.plist")
  if [ "$installed" = "$version" ]; then
    echo "已经安装 ${tag}：$destination"
    [ "$open_after" -eq 0 ] || /usr/bin/open "$destination"
    exit 0
  fi
  [ "$replace" -eq 1 ] || { echo '已有其他版本。请先退出旧版，再加 --replace 升级。' >&2; exit 1; }
  if /usr/bin/pgrep -x CodexBadge >/dev/null; then echo '请先退出正在运行的 Token额度，再升级。' >&2; exit 1; fi
fi
mkdir -p "$(dirname "$destination")"
previous="$scratch/previous.app"
if [ -e "$destination" ]; then mv "$destination" "$previous"; fi
if ! /usr/bin/ditto "$app" "$destination"; then
  rm -rf "$destination"
  if [ -d "$previous" ]; then mv "$previous" "$destination"; fi
  echo '安装失败，已恢复旧版。' >&2; exit 1
fi
echo "安装完成：${destination}（${tag}）"
echo '请确认 Codex CLI 或包含 CLI 的桌面应用已登录；首次打开可能需要 macOS 手动确认。'
[ "$open_after" -eq 0 ] || /usr/bin/open "$destination"
