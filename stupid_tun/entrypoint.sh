#!/bin/sh

get_awg_template() {
cat << 'EOF'
# шаблон WireGuard
EOF
}

parse_awg_config() {
  local config_file="$1"
  local awg_name
  awg_name=$(basename "$config_file" .conf)

  local private_key=$(grep "^PrivateKey" "$config_file" | sed 's/^PrivateKey[[:space:]]*=[[:space:]]*//')
  local address=$(grep "^Address" "$config_file" | sed 's/^Address[[:space:]]*=[[:space:]]*//')
  address=$(echo "$address" | tr ',' '\n' | grep -v ':')
  local dns=$(grep "^DNS" "$config_file" | sed 's/^DNS[[:space:]]*=[[:space:]]*//')
  dns=$(echo "$dns" | tr ',' '\n' | grep -v ':' | sed 's/^ *//;s/ *$//' | paste -sd, -)
  local mtu=$(grep "^MTU" "$config_file" | sed 's/^MTU[[:space:]]*=[[:space:]]*//')

  local jc=$(grep "^Jc" "$config_file" | sed 's/^Jc[[:space:]]*=[[:space:]]*//')
  local jmin=$(grep "^Jmin" "$config_file" | sed 's/^Jmin[[:space:]]*=[[:space:]]*//')
  local jmax=$(grep "^Jmax" "$config_file" | sed 's/^Jmax[[:space:]]*=[[:space:]]*//')
  local s1=$(grep "^S1" "$config_file" | sed 's/^S1[[:space:]]*=[[:space:]]*//')
  local s2=$(grep "^S2" "$config_file" | sed 's/^S2[[:space:]]*=[[:space:]]*//')
  local h1=$(grep "^H1" "$config_file" | sed 's/^H1[[:space:]]*=[[:space:]]*//')
  local h2=$(grep "^H2" "$config_file" | sed 's/^H2[[:space:]]*=[[:space:]]*//')
  local h3=$(grep "^H3" "$config_file" | sed 's/^H3[[:space:]]*=[[:space:]]*//')
  local h4=$(grep "^H4" "$config_file" | sed 's/^H4[[:space:]]*=[[:space:]]*//')

  local public_key=$(grep "^PublicKey" "$config_file" | sed 's/^PublicKey[[:space:]]*=[[:space:]]*//')
  local psk=$(grep "^PresharedKey" "$config_file" | sed 's/^PresharedKey[[:space:]]*=[[:space:]]*//')
  local endpoint=$(grep "^Endpoint" "$config_file" | sed 's/^Endpoint[[:space:]]*=[[:space:]]*//')
  local server=$(echo "$endpoint" | cut -d':' -f1)
  local port=$(echo "$endpoint" | cut -d':' -f2)
  local ip=$(echo "$address" | head -n 1)

  cat <<EOF
  - name: "$awg_name"
    type: wireguard
    private-key: $private_key
    server: $server
    port: $port
    ip: $ip
    mtu: ${mtu:-1420}
    public-key: $public_key
    allowed-ips: ['0.0.0.0/0']
$(if [ -n "$psk" ]; then echo "    pre-shared-key: $psk"; fi)
    udp: true
    dns: [ $dns ]
    remote-dns-resolve: true
    amnezia-wg-option:
      jc: ${jc:-4}
      jmin: ${jmin:-40}
      jmax: ${jmax:-70}
      s1: ${s1:-0}
      s2: ${s2:-0}
      h1: ${h1:-1}
      h2: ${h2:-2}
      h3: ${h3:-3}
      h4: ${h4:-4}
EOF
}

generate_awg_yaml() {
  local output_file="/root/.config/mihomo/awg.yaml"
  echo "proxies:" > "$output_file"
  find /root/.config/mihomo/awg -name "*.conf" | while read -r conf; do
    parse_awg_config "$conf"
  done >> "$output_file"
}

config_file_mihomo() {
cat > /root/.config/mihomo/config.yaml <<EOF
log-level: ${LOG_LEVEL:-warning}
external-controller: 0.0.0.0:9090
external-ui: ui
external-ui-url: "${EXTERNAL_UI_URL:-https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip}"
unified-delay: true
ipv6: false
EOF

if [ -n "$FAKEIP" ]; then
cat >> /root/.config/mihomo/config.yaml <<EOF
dns:
  enable: true
  cache-algorithm: arc
  prefer-h3: false
  use-system-hosts: false
  respect-rules: false
  listen: 0.0.0.0:53
  ipv6: false
  default-nameserver:
    - 8.8.8.8
    - 9.9.9.9
    - 1.1.1.1
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  nameserver:
    - https://dns.google/dns-query
    - https://1.1.1.1/dns-query
    - https://dns.quad9.net/dns-query

hosts:
  dns.google: [8.8.8.8, 8.8.4.4]
  dns.quad9.net: [9.9.9.9, 149.112.112.112]
EOF
else
cat >> /root/.config/mihomo/config.yaml <<EOF
dns:
  enable: true
  use-system-hosts: false
EOF
fi

cat >> /root/.config/mihomo/config.yaml <<EOF

proxy-providers:
  links:
    type: file
    path: links.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: ${INTERVAL:-120}
      timeout: 5000
      lazy: false
      expected-status: 204
  awg:
    type: file
    path: awg.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: ${INTERVAL:-120}
      timeout: 5000
      lazy: false
      expected-status: 204
EOF

i=1
env | grep -E '^SUB_LINK[0-9]*=' | sort -t '=' -k1 | while read -r line; do
  value=$(echo "$line" | cut -d '=' -f2-)
  subname="sub_link$i"
  cat >> /root/.config/mihomo/config.yaml <<EOF
  $subname:
    url: "$value"
    type: http
    interval: 86400
    proxy: DIRECT
    health-check:
      enable: true
      url: "https://www.gstatic.com/generate_204"
      interval: ${INTERVAL:-120}
      lazy: false
EOF
  i=$((i + 1))
done

cat >> /root/.config/mihomo/config.yaml <<EOF

proxy-groups:
  - name: GLOBAL
    type: ${GROUP_TYPE:-select}
    use:
EOF

if [ -n "$PROXY_ORDER" ]; then
  echo "$PROXY_ORDER" | tr ',' '\n' | while read -r item; do
    echo "      - $item" >> /root/.config/mihomo/config.yaml
  done
else
  echo "      - links" >> /root/.config/mihomo/config.yaml
  echo "      - awg" >> /root/.config/mihomo/config.yaml
  i=1
  env | grep -E '^SUB_LINK[0-9]*=' | sort -t '=' -k1 | while read -r _; do
    echo "      - sub_link$i" >> /root/.config/mihomo/config.yaml
    i=$((i + 1))
  done
fi

cat >> /root/.config/mihomo/config.yaml <<EOF

  - name: quic
    type: select
    proxies:
      - PASS
      - REJECT

listeners:
  - name: tun-in
    type: tun
    stack: system
    auto-detect-interface: true
    auto-route: true
    auto-redirect: true
    inet4-address:
    - 198.19.0.1/30
  - name: mixed-in
    type: mixed
    port: 1080
    listen: 0.0.0.0
    udp: true

rules:
  - AND,((NETWORK,udp),(DST-PORT,443)),quic
  - MATCH,GLOBAL
EOF
}

link_file_mihomo() {
  [ -z "$LINK1" ] && [ -z "$SUB_LINK1" ] && ! find /root/.config/mihomo/awg -name "*.conf" | grep -q . && {
    echo "No LINK1, SUB_LINK1, or .conf file found."
    exit 1
  }

  > /root/.config/mihomo/links.yaml
  for i in $(env | grep -E '^LINK[0-9]*=' | sort -t '=' -k1 | cut -d '=' -f1); do
    eval "echo \"\$$i\"" >> /root/.config/mihomo/links.yaml
  done
}

run() {
  mkdir -p /root/.config/mihomo
  config_file_mihomo
  generate_awg_yaml
  link_file_mihomo
  ./mihomo
}

run || exit 1
