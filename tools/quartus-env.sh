# Put Quartus Prime Lite on PATH for this shell. Source it, do not run it:
#
#   . tools/quartus-env.sh
#
# Picks the newest installation found under ~/altera_lite, ~/intelFPGA_lite
# or /opt. Override with QUARTUS_BIN=/path/to/quartus/bin before sourcing.
# The other scripts in tools/ source this file themselves.

if [ -n "${QUARTUS_BIN:-}" ] && [ -x "$QUARTUS_BIN/quartus_sh" ]; then
  _qbin=$QUARTUS_BIN
else
  _qbin=""
  for _d in "$HOME"/altera_lite/*/quartus/bin \
            "$HOME"/intelFPGA_lite/*/quartus/bin \
            /opt/altera_lite/*/quartus/bin \
            /opt/intelFPGA_lite/*/quartus/bin; do
    [ -x "$_d/quartus_sh" ] && _qbin=$_d      # globs sort by version, last wins
  done
fi

if [ -z "$_qbin" ]; then
  echo "quartus-env: no Quartus installation found (looked in ~/altera_lite, ~/intelFPGA_lite, /opt)" >&2
else
  case ":$PATH:" in
    *":$_qbin:"*) ;;
    *) export PATH="$_qbin:$PATH" ;;
  esac
  export QUARTUS_ROOTDIR="${_qbin%/bin}"
fi
unset _qbin _d
