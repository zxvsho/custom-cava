#!/usr/bin/env bash
# custom-cava: mini visualizador de audio para Waybar que solo trabaja mientras suena algo.
#
# Uso:
#   waybar-cava          arranca el módulo (lo lanza Waybar con "exec")
#   waybar-cava toggle   activa/desactiva el visualizador (clic derecho en Waybar)

rt=${XDG_RUNTIME_DIR:-/tmp}
cfg=$rt/cava-waybar.conf
flag=$rt/waybar-cava.disabled
pidfile=$rt/waybar-cava.pid
off_text=${CAVA_OFF_TEXT:-▁▁▁}

# Modo toggle: cambia el estado y avisa a la instancia que está corriendo.
if [[ $1 == toggle ]]; then
  if [[ -e $flag ]]; then rm -f "$flag"; else touch "$flag"; fi
  [[ -r $pidfile ]] && kill -USR1 "$(cat "$pidfile")" 2>/dev/null
  exit 0
fi

echo $$ > "$pidfile"

cat > "$cfg" <<'EOF'
[general]
bars = 8
framerate = 15
sleep_timer = 1

[input]
method = pipewire
source = auto

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
bar_delimiter = 59
EOF

start() {
  pgrep -f "cava -p $cfg" >/dev/null && return
  # un solo sed en streaming: traduce 0-7 a bloques y quita los ';'
  cava -p "$cfg" | sed -u 's/;//g; y/01234567/▁▂▃▄▅▆▇█/' &
}

stop() {
  pkill -f "cava -p $cfg" 2>/dev/null
  # Desactivado: muestra un marcador para poder reactivarlo con clic derecho.
  # Activado y sin música: texto vacío, Waybar oculta el módulo.
  if [[ -e $flag ]]; then echo "$off_text"; else echo ""; fi
}

# Reevalúa el estado (arranque y señal USR1 del toggle).
refresh() {
  if [[ -e $flag ]]; then
    stop
  elif playerctl -a status 2>/dev/null | grep -q Playing; then
    start
  else
    stop
  fi
}

cleanup() {
  trap - EXIT INT TERM USR1
  pkill -P $$ 2>/dev/null
  pkill -f "cava -p $cfg" 2>/dev/null
  rm -f "$pidfile"
  exit
}
trap cleanup INT TERM EXIT
trap refresh USR1

refresh

# Eventos MPRIS por D-Bus: el bucle duerme hasta que cambia el estado.
playerctl --follow status 2>/dev/null | while read -r s; do
  if [[ $s == Playing && ! -e $flag ]]; then start; else stop; fi
done &
loop=$!

# wait se interrumpe con USR1; el bucle lo reanuda mientras siga vivo el pipeline.
while kill -0 "$loop" 2>/dev/null; do wait "$loop"; done
