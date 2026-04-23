#!/usr/bin/env bash
set -euo pipefail

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
XRAY_CLIENTS_DIR="${XRAY_CONFIG_DIR}/clients"
XRAY_SERVER_META="${XRAY_CONFIG_DIR}/server_meta.json"

DEST_DOMAIN="${DEST_DOMAIN:-yandex.ru}"
SERVER_NAME="${SERVER_NAME:-$DEST_DOMAIN}"
XRAY_PORT="${XRAY_PORT:-443}"
FINGERPRINT="${FINGERPRINT:-chrome}"
FIRST_CLIENT_NAME="${FIRST_CLIENT_NAME:-client-$(date +"%H%M%S%d%m%Y")}"

log() {
  echo "[xray-install] $*"
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

rand_hex() {
  local n="${1:-16}"
  python3 - "$n" <<'PY'
import secrets, sys
n = int(sys.argv[1])
print(secrets.token_hex((n + 1)//2)[:n])
PY
}

detect_public_ip() {
  ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
}

install_packages() {
  log "Installing required packages"
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y curl unzip jq python3 ca-certificates
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then
    log "Xray already installed"
    return
  fi

  log "Installing Xray"
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
}

generate_keys() {
  log "Generating Reality keys"
  local key_output
  key_output="$(xray x25519)"

  XRAY_PRIVATE_KEY="$(printf '%s\n' "$key_output" | sed -n 's/^PrivateKey: //p')"
  XRAY_PUBLIC_KEY="$(printf '%s\n' "$key_output" | sed -n 's/^Password (PublicKey): //p')"

  if [[ -z "${XRAY_PRIVATE_KEY:-}" ]]; then
    XRAY_PRIVATE_KEY="$(printf '%s\n' "$key_output" | sed -n 's/^Private key: //p')"
  fi
  if [[ -z "${XRAY_PUBLIC_KEY:-}" ]]; then
    XRAY_PUBLIC_KEY="$(printf '%s\n' "$key_output" | sed -n 's/^Public key: //p')"
  fi

  if [[ -z "${XRAY_PRIVATE_KEY:-}" || -z "${XRAY_PUBLIC_KEY:-}" ]]; then
    echo "Failed to parse Xray x25519 output:" >&2
    printf '%s\n' "$key_output" >&2
    exit 1
  fi
}

generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

prepare_dirs() {
  mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_CLIENTS_DIR"
  chmod 755 "$XRAY_CONFIG_DIR"
  chmod 700 "$XRAY_CLIENTS_DIR"
}

write_config() {
  local first_uuid="$1"
  local short_id="$2"

  cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${first_uuid}",
            "flow": "xtls-rprx-vision",
            "email": "${FIRST_CLIENT_NAME}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_DOMAIN}:443",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${XRAY_PRIVATE_KEY}",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "${short_id}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

  chown root:root "$XRAY_CONFIG_FILE"
  chmod 644 "$XRAY_CONFIG_FILE"
}

write_server_meta() {
  local server_addr="$1"
  local first_uuid="$2"
  local short_id="$3"
  local installed_at installed_compact

  installed_at="$(iso_now)"
  installed_compact="$(timestamp_name)"

  cat > "$XRAY_SERVER_META" <<EOF
{
  "installed_at": "${installed_at}",
  "installed_at_compact": "${installed_compact}",
  "server_addr": "${server_addr}",
  "listen_port": ${XRAY_PORT},
  "dest_domain": "${DEST_DOMAIN}",
  "server_name": "${SERVER_NAME}",
  "reality_private_key": "${XRAY_PRIVATE_KEY}",
  "reality_public_key": "${XRAY_PUBLIC_KEY}",
  "short_id": "${short_id}",
  "config_path": "${XRAY_CONFIG_FILE}",
  "clients_dir": "${XRAY_CLIENTS_DIR}",
  "fingerprint": "${FINGERPRINT}",
  "first_client": {
    "uuid": "${first_uuid}",
    "email": "${FIRST_CLIENT_NAME}"
  }
}
EOF

  chown root:root "$XRAY_SERVER_META"
  chmod 600 "$XRAY_SERVER_META"
}

write_first_client_files() {
  local server_addr="$1"
  local first_uuid="$2"
  local short_id="$3"
  local flow uri uri_file yaml_file db_file added_at added_at_compact

  flow="xtls-rprx-vision"
  added_at="$(iso_now)"
  added_at_compact="$(timestamp_name)"
  uri_file="${XRAY_CLIENTS_DIR}/${FIRST_CLIENT_NAME}.txt"
  yaml_file="${XRAY_CLIENTS_DIR}/${FIRST_CLIENT_NAME}.yaml"
  db_file="${XRAY_CLIENTS_DIR}/clients.json"

  uri="vless://${first_uuid}@${server_addr}:${XRAY_PORT}?type=tcp&security=reality&pbk=${XRAY_PUBLIC_KEY}&fp=${FINGERPRINT}&sni=${SERVER_NAME}&sid=${short_id}&flow=${flow}#${FIRST_CLIENT_NAME}"

  cat > "$uri_file" <<EOF
${uri}
EOF

  cat > "$yaml_file" <<EOF
proxies:
  - name: ${FIRST_CLIENT_NAME}
    type: vless
    server: ${server_addr}
    port: ${XRAY_PORT}
    uuid: ${first_uuid}
    network: tcp
    tls: true
    udp: true
    servername: ${SERVER_NAME}
    flow: ${flow}
    client-fingerprint: ${FINGERPRINT}
    reality-opts:
      public-key: ${XRAY_PUBLIC_KEY}
      short-id: ${short_id}

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - ${FIRST_CLIENT_NAME}

rules:
  - MATCH,Proxy
EOF

  cat > "$db_file" <<EOF
[
  {
    "client_name": "${FIRST_CLIENT_NAME}",
    "added_at": "${added_at}",
    "added_at_compact": "${added_at_compact}",
    "uuid": "${first_uuid}",
    "server_addr": "${server_addr}",
    "server_port": ${XRAY_PORT},
    "server_name": "${SERVER_NAME}",
    "dest_domain": "${DEST_DOMAIN}",
    "public_key": "${XRAY_PUBLIC_KEY}",
    "short_id": "${short_id}",
    "flow": "${flow}",
    "fingerprint": "${FINGERPRINT}",
    "uri_file": "${uri_file}",
    "yaml_file": "${yaml_file}"
  }
]
EOF

  chown root:root "$uri_file" "$yaml_file" "$db_file"
  chmod 600 "$uri_file" "$yaml_file" "$db_file"
}

validate_config() {
  log "Validating Xray config"
  xray run -test -config "$XRAY_CONFIG_FILE"
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "Opening TCP ${XRAY_PORT} in UFW"
    ufw allow "${XRAY_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

restart_service() {
  log "Restarting Xray"
  systemctl daemon-reload
  systemctl enable xray >/dev/null
  systemctl restart xray
}

check_service() {
  log "Checking service status"
  systemctl is-active --quiet xray || {
    echo "Xray failed to start" >&2
    systemctl status xray --no-pager -l || true
    journalctl -u xray -n 50 --no-pager -l || true
    exit 1
  }
}

main() {
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd ip
  need_cmd python3
  need_cmd systemctl
  need_cmd apt

  install_packages
  install_xray
  need_cmd xray

  prepare_dirs
  generate_keys

  local first_uuid short_id server_addr
  first_uuid="$(generate_uuid)"
  short_id="$(rand_hex 16)"
  server_addr="${XRAY_SERVER_ADDR:-$(detect_public_ip)}"

  if [[ -z "$server_addr" ]]; then
    echo "Could not detect public IP. Set XRAY_SERVER_ADDR manually." >&2
    exit 1
  fi

  write_config "$first_uuid" "$short_id"
  write_server_meta "$server_addr" "$first_uuid" "$short_id"
  write_first_client_files "$server_addr" "$first_uuid" "$short_id"

  validate_config
  open_firewall
  restart_service
  check_service

  log "Done"
  echo
  echo "Xray is running."
  echo "Config:       ${XRAY_CONFIG_FILE}"
  echo "Server meta:  ${XRAY_SERVER_META}"
  echo "Clients DB:   ${XRAY_CLIENTS_DIR}/clients.json"
  echo "Client TXT:   ${XRAY_CLIENTS_DIR}/${FIRST_CLIENT_NAME}.txt"
  echo "Client YAML:  ${XRAY_CLIENTS_DIR}/${FIRST_CLIENT_NAME}.yaml"
  echo
  echo "Reality public key:"
  echo "  ${XRAY_PUBLIC_KEY}"
  echo
  echo "First client URI:"
  cat "${XRAY_CLIENTS_DIR}/${FIRST_CLIENT_NAME}.txt"
}

main "$@"