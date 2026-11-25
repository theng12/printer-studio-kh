# Sourced by every script the packaging path runs. A gate step, a launchd job or any other
# non-login shell has no Homebrew in its PATH, so `python3` is the 3.9 system stub and
# `pkg-config` is missing (row 20261122-318). Homebrew first, then its newest python@3
# ahead of the stub. Sourcing twice adds nothing.
for _p in /opt/homebrew/bin /usr/local/bin; do
  if [ -d "$_p" ] && [[ ":$PATH:" != *":$_p:"* ]]; then PATH="$_p:$PATH"; fi
done
_hb_py=$(ls -d /opt/homebrew/opt/python@3*/libexec/bin 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$_hb_py" ] && [[ ":$PATH:" != *":$_hb_py:"* ]]; then PATH="$_hb_py:$PATH"; fi
export PATH
unset _p _hb_py

# A tool the packaging path needs that is not there stops it here, naming the PATH searched and
# the version it needs — never a traceback from inside a later script (the row's own check).
toolchain_require_python() {   # toolchain_require_python 3.9
  local min="$1" found ver
  found=$(command -v python3 2>/dev/null || true)
  ver=$([ -n "$found" ] && python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)
  if [ -z "$found" ] || ! /usr/bin/printf '%s\n%s\n' "$min" "$ver" | /usr/bin/sort -V -C; then
    printf 'toolchain: Python %s or later is required; found %s at %s\nPATH searched: %s\n' \
      "$min" "${ver:-nothing}" "${found:-nowhere}" "$PATH" >&2
    exit 1
  fi
}
