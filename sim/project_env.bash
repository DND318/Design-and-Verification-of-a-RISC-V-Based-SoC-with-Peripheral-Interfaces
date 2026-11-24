# Source once per terminal:  source sim/project_env.bash
# Sets PROJ_ROOT and loads Vivado (XSim) if it is installed.
export PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-$(ls -d "$HOME"/tools/Xilinx/*/Vivado/settings64.sh "$HOME"/tools/Xilinx/Vivado/*/settings64.sh 2>/dev/null | tail -n1)}"
if [ -n "$VIVADO_SETTINGS" ] && [ -f "$VIVADO_SETTINGS" ]; then
  source "$VIVADO_SETTINGS"
  echo "Vivado loaded from $VIVADO_SETTINGS"
else
  echo "Vivado settings64.sh not found; set VIVADO_SETTINGS=/path/to/settings64.sh"
fi
echo "PROJ_ROOT=$PROJ_ROOT"
