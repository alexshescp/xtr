#!/usr/bin/env bash
set -euo pipefail

XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_SERVER_META="/usr/local/etc/xray/server_meta.json"

log() {
  echo "[xray-change-mask] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

usage() {
  cat <<EOF
Usage:
  $0 <new_domain> [fingerprint]

Examples:
  $0 www.microsoft.com
  $0 www.apple.com chrome
  $0 www.amazon.com firefox

Notes:
  - new_domain is used for:
      realitySettings.dest      => <new_domain>:443
      realitySettings.serverNames => [<new_domain>]
      server_meta.json fields
  - fingerprint is optional, default: chrome
EOF
}

validate_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || {
    echo "Invalid domain: $domain" >&2
    exit 1
  }
}

ensure_files() {
  [[ -f "$XRAY_CONFIG_FILE" ]] || { echo "Missing ${XRAY_CONFIG_FILE}" >&2; exit 1; }
  [[ -f "$XRAY_SERVER_META" ]] || { echo "Missing ${XRAY_SERVER_META}" >&2; exit 1; }
}

update_config() {
  local new_domain="$1"
  local fingerprint="$2"

  python3 - "$XRAY_CONFIG_FILE" "$new_domain" "$fingerprint" <<'PY'
import json
import sys

config_path, new_domain, fingerprint = sys.argv[1], sys.argv[2], sys.argv[3]

with open(config_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

inbounds = cfg.get("inbounds", [])
if not inbounds:
    raise SystemExit("No inbounds found in config")

inb = inbounds[0]
stream = inb.setdefault("streamSettings", {})
if stream.get("security") != "reality":
    raise SystemExit("Inbound is not using Reality")

reality = stream.setdefault("realitySettings", {})
reality["dest"] = f"{new_domain}:443"
reality["serverNames"] = [new_domain]

# Optional: keep a client-side hint inside config for convenience
stream.setdefault("sockopt", {})

# Update sniffing block only if missing? no need

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
}

update_meta() {
  local new_domain="$1"

  python3 - "$XRAY_SERVER_META" "$new_domain" <<'PY'
import json
import sys

meta_path, new_domain = sys.argv[1], sys.argv[2]

with open(meta_path, "r", encoding="utf-8") as f:
    meta = json.load(f)

meta["dest_domain"] = new_domain
meta["server_name"] = new_domain

with open(meta_path, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)
PY
}

rewrite_client_uris() {
  local fingerprint="$1"

  python3 - "$XRAY_SERVER_META" "$fingerprint" <<'PY'
import json
import os
import sys
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

meta_path, fingerprint = sys.argv[1], sys.argv[2]

with open(meta_path, "r", encoding="utf-8") as f:
    meta = json.load(f)

clients_dir = meta["clients_dir"]
server_addr = meta["server_addr"]
server_port = meta["listen_port"]
server_name = meta["server_name"]
public_key = meta["reality_public_key"]
short_id = meta["short_id"]

db_path = os.path.join(clients_dir, "clients.json")
if not os.path.exists(db_path):
    raise SystemExit(0)

with open(db_path, "r", encoding="utf-8") as f:
    clients = json.load(f)

for client in clients:
    client_name = client["client_name"]
    client_uuid = client["uuid"]
    uri_file = client.get("uri_file") or os.path.join(clients_dir, f"{client_name}.txt")

    uri = (
        f"vless://{client_uuid}@{server_addr}:{server_port}"
        f"?type=tcp&security=reality&pbk={public_key}"
        f"&fp={fingerprint}&sni={server_name}&sid={short_id}"
        f"&flow=xtls-rprx-vision#{client_name}"
    )

    with open(uri_file, "w", encoding="utf-8") as f:
        f.write(uri + "\n")

    client["server_name"] = server_name
    client["dest_domain"] = server_name
    client["public_key"] = public_key
    client["short_id"] = short_id

with open(db_path, "w", encoding="utf-8") as f:
    json.dump(clients, f, ensure_ascii=False, indent=2)
PY
}

validate_config() {
  xray run -test -config "$XRAY_CONFIG_FILE"
}

restart_xray() {
  systemctl restart xray
}

main() {
  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  local new_domain="$1"
  local fingerprint="${2:-chrome}"

  need_cmd python3
  need_cmd xray
  need_cmd systemctl

  validate_domain "$new_domain"
  ensure_files

  log "Updating mask domain to: $new_domain"
  update_config "$new_domain" "$fingerprint"
  update_meta "$new_domain"
  rewrite_client_uris "$fingerprint"
  validate_config
  restart_xray

  log "Done"
  echo "New domain: $new_domain"
  echo "Fingerprint: $fingerprint"
  echo "Config: $XRAY_CONFIG_FILE"
  echo "Meta:   $XRAY_SERVER_META"
  echo "Client URIs rewritten in clients/*.txt"
}

main "$@"