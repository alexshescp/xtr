#!/usr/bin/env bash
set -euo pipefail

XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_SERVER_META="/usr/local/etc/xray/server_meta.json"
XRAY_CLIENTS_DIR="/usr/local/etc/xray/clients"
XRAY_CLIENTS_DB="${XRAY_CLIENTS_DIR}/clients.json"

log() {
  echo "[xray-add-client] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

timestamp_name() {
  date +"%H%M%S%d%m%Y"
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ensure_files() {
  [[ -f "$XRAY_CONFIG_FILE" ]] || { echo "Missing ${XRAY_CONFIG_FILE}" >&2; exit 1; }
  [[ -f "$XRAY_SERVER_META" ]] || { echo "Missing ${XRAY_SERVER_META}" >&2; exit 1; }

  mkdir -p "$XRAY_CLIENTS_DIR"
  chmod 700 "$XRAY_CLIENTS_DIR"

  if [[ ! -f "$XRAY_CLIENTS_DB" ]]; then
    echo "[]" > "$XRAY_CLIENTS_DB"
  fi
  chmod 600 "$XRAY_CLIENTS_DB"
}

generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

next_client_name() {
  echo "client-$(timestamp_name)"
}

add_client_to_xray_config() {
  local client_uuid="$1"
  local client_name="$2"

  python3 - "$XRAY_CONFIG_FILE" "$client_uuid" "$client_name" <<'PY'
import json
import sys

config_path, client_uuid, client_name = sys.argv[1], sys.argv[2], sys.argv[3]

with open(config_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

inbounds = cfg.get("inbounds", [])
if not inbounds:
    raise SystemExit("No inbounds found in Xray config")

settings = inbounds[0].setdefault("settings", {})
clients = settings.setdefault("clients", [])

for c in clients:
    if c.get("id") == client_uuid:
        raise SystemExit("Client UUID already exists in config")
    if c.get("email") == client_name:
        raise SystemExit("Client name already exists in config")

clients.append({
    "id": client_uuid,
    "flow": "xtls-rprx-vision",
    "email": client_name
})

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
}

append_client_to_db() {
  local entry_file="$1"

  python3 - "$XRAY_CLIENTS_DB" "$entry_file" <<'PY'
import json
import sys

db_path, entry_path = sys.argv[1], sys.argv[2]

with open(db_path, "r", encoding="utf-8") as f:
    db = json.load(f)

with open(entry_path, "r", encoding="utf-8") as f:
    entry = json.load(f)

db.append(entry)

with open(db_path, "w", encoding="utf-8") as f:
    json.dump(db, f, ensure_ascii=False, indent=2)
PY
}

read_meta_field() {
  local field="$1"
  python3 - "$XRAY_SERVER_META" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
value = data[field]
if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False))
else:
    print(value)
PY
}

validate_config() {
  xray run -test -config "$XRAY_CONFIG_FILE"
}

restart_xray() {
  systemctl restart xray
}

main() {
  need_cmd python3
  need_cmd systemctl
  need_cmd xray

  ensure_files

  local client_name client_uuid added_at added_at_compact
  local server_addr server_port server_name dest_domain public_key short_id
  local uri_file yaml_file uri entry_tmp_json fingerprint flow

  client_name="${1:-$(next_client_name)}"
  client_uuid="$(generate_uuid)"
  added_at="$(iso_now)"
  added_at_compact="$(timestamp_name)"

  server_addr="$(read_meta_field server_addr)"
  server_port="$(read_meta_field listen_port)"
  server_name="$(read_meta_field server_name)"
  dest_domain="$(read_meta_field dest_domain)"
  public_key="$(read_meta_field reality_public_key)"
  short_id="$(read_meta_field short_id)"

  fingerprint="chrome"
  flow="xtls-rprx-vision"

  log "Adding client ${client_name} (${client_uuid})"

  add_client_to_xray_config "$client_uuid" "$client_name"
  validate_config
  restart_xray

  uri="vless://${client_uuid}@${server_addr}:${server_port}?type=tcp&security=reality&pbk=${public_key}&fp=${fingerprint}&sni=${server_name}&sid=${short_id}&flow=${flow}#${client_name}"

  uri_file="${XRAY_CLIENTS_DIR}/${client_name}.txt"
  yaml_file="${XRAY_CLIENTS_DIR}/${client_name}.yaml"

  cat > "$uri_file" <<EOF
${uri}
EOF
  chmod 600 "$uri_file"

  cat > "$yaml_file" <<EOF
proxies:
  - name: ${client_name}
    type: vless
    server: ${server_addr}
    port: ${server_port}
    uuid: ${client_uuid}
    network: tcp
    tls: true
    udp: true
    servername: ${server_name}
    flow: ${flow}
    client-fingerprint: ${fingerprint}
    reality-opts:
      public-key: ${public_key}
      short-id: ${short_id}

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - ${client_name}

rules:
  - MATCH,Proxy
EOF
  chmod 600 "$yaml_file"

  entry_tmp_json="$(mktemp)"
  cat > "$entry_tmp_json" <<EOF
{
  "client_name": "${client_name}",
  "added_at": "${added_at}",
  "added_at_compact": "${added_at_compact}",
  "uuid": "${client_uuid}",
  "server_addr": "${server_addr}",
  "server_port": ${server_port},
  "server_name": "${server_name}",
  "dest_domain": "${dest_domain}",
  "public_key": "${public_key}",
  "short_id": "${short_id}",
  "flow": "${flow}",
  "fingerprint": "${fingerprint}",
  "uri_file": "${uri_file}",
  "yaml_file": "${yaml_file}"
}
EOF

  append_client_to_db "$entry_tmp_json"
  rm -f "$entry_tmp_json"

  log "Done"
  echo
  echo "Client:    ${client_name}"
  echo "UUID:      ${client_uuid}"
  echo "TXT file:  ${uri_file}"
  echo "YAML file: ${yaml_file}"
  echo "DB:        ${XRAY_CLIENTS_DB}"
  echo
  echo "URI:"
  cat "$uri_file"
  echo
  echo "Clash YAML created:"
  echo "  ${yaml_file}"
}

main "$@"