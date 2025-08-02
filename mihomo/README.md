- MiHoMo — это один из форков Clash, точнее, форк Clash.Meta, который сам является более продвинутым ответвлением оригинального Clash. Его полное название обычно — Clash.Meta-Mihomo. (ChatGPT)
- mihomo это прокси-комбайн, как xray и sing-box, mihomo это tun интерфейс, днс-сервер, поддержка подписок, поддержка множества различных протоколов таких как vless, amnezia-wg и многих других, балансировщик, поддержка базы ASN, MMDB, Geoip, Geosite, Rulesets.
# Описание контейнера:
Контейнер для Mikrotik RouterOS, которая не поддерживает nftables. Контейнер собран на базе alpine linux 3.18 где по умолчанию используется iptables-legacy. Установлена переменная окружения DISABLE_NFTABLES=1 для mihomo отключающая nftables.

# Пример использования mihomo вместе с контейнером byedpi и маршрутизацией "Fakeip":
Контейнер mihomo используется dhcp клиентами роутера как dns сервер, он резолвит нужные нам домены в "фейковые" адреса из подсети 198.18.0.0/15 которые мы маршрутизируем в этот же контейнер mihomo силами RouterOS. Далее пройдя маршрутизацию mihomo внутри контейнера соединения попадут в нужный нам outbound. Одним из этих outbound будет отдельный контейнер с byedpi.

# Конфигурация роутера:

- Пакет containers должен быть установлен и активирован в /system/device-mode. В примере использовался hap ax lite. Версия RouterOS 7.19.3 Mihomo 1.19.12
- RouterOS сброшена до дефолтной конфигурации (не пустой конфиг).

1: Создадим tmpfs для временных файлов:
```
/disk add type=tmpfs tmpfs-max-size=50M
```
2: Задаём директорию для временных файлов:
```
/container config set tmpdir=/tmp1
```
3: Создаём виртуальный интерфейс для контейнеров mihomo и byedpi, назначаем адресa и шлюз:
```
/interface veth add address=10.10.10.2/24 gateway=10.10.10.1
/interface veth add address=10.10.10.3/24 gateway=10.10.10.1
```
4: Создаём бридж для контейнеров и добавляем в него виртуальные интерфейсы контейнеров:
```
/interface bridge add name=dockers
/interface bridge port add bridge=dockers interface=veth1
/interface bridge port add bridge=dockers interface=veth2
```
5: Назначаем адрес бридж интерфейсу:
```
/ip address add address=10.10.10.1/24 interface=dockers network=10.10.10.0
```
6: Создаём маршрут который будет направлять fakeip в контейнер:
```
/ip route add comment="fake-ip cidr to container" disabled=no distance=1 dst-address=198.18.0.0/15 gateway=10.10.10.2 routing-table=main scope=30 suppress-hw-offload=no target-scope=10
```
7: создаём маунт для конфига:
```
/container mounts add dst=/root/.config/mihomo name=mihomo src=/config/mihomo
```
8: Создаём контейнеры byedpi и mihomo:
```
/container add interface=veth1 logging=yes mounts=mihomo root-dir=containers/mihomo start-on-boot=yes workdir=/ remote-image=registry-1.docker.io/vanes32/mihomo_nonft:1.19.12
/container add cmd="-Kt,h -s0+s -s3+s -s6+s -s9+s -s12+s -s15+s -s20+s -s30+s -An -Ku -a5 -An" dns=10.10.10.1 interface=veth2 logging=yes root-dir=containers/byedpi start-on-boot=yes workdir=/ remote-image="registry-1.docker.io/wiktorbgu/byedpi-mikrotik:latest"
```
9: Назначаем контейнер dns-сервером для всех dhcp клиентов:
```
/ip dhcp-server network set dns-server=10.10.10.2 numbers=0
```
10: Запускаем и останавливаем контейнер чтобы он создал директорию /mihomo/config и мы убедились что он запускается:

11: Выключим ipv6:
```
/ipv6/settings/set disable-ipv6=yes
```
12: Включим DOH на роутере, его будет использовать сам роутер и byedpi-контейнер.
```
ip/dns/set use-doh-server=https://dns.google/dns-query verify-doh-cert=yes allow-remote-requests=yes
```
Разрешим использовать встроенные сертификаты
```
certificate/settings/set builtin-trust-anchors=trusted
```
13: Разрешим контейнерам доступ к dns самого роутера
```
ip/firewall/filter/add place-before=[find comment="defconf: drop all not coming from LAN"] chain=input in-interface=dockers protocol=udp dst-port=53 action=accept comment="dockers dns"
```

# Конфигурация mihomo:
13: Отредактируем конфиг-файл mihomo /mihomo/config/config.yaml:
- Пример конфигурации. Изучаем https://wiki.metacubex.one/ru/config/ и настраиваем под себя.
```
log-level: warning
profile:
  store-selected: true
  store-fake-ip: false
external-controller: 0.0.0.0:9090
external-ui: ui
external-ui-url: "https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip" # Get from GitHub Pages branch
ipv6: false
unified-delay: true

proxy-providers:
  sub:
    url: "https://xxxx" # Ссылка на подписку (Для примера)
    type: http
    interval: 86400
    proxy: DIRECT
    health-check:
      {
        enable: true,
        url: "https://www.gstatic.com/generate_204",
        interval: 86400,
      }
  links:
    type: file
    path: links.yaml # Файл со ссылками типа vless://.. ss://.., находится в директории конфига mihomo. Одна стройчка - одна ссылка.
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300
      timeout: 5000
      lazy: true
      expected-status: 204

proxies:
  - name: "⛓️‍💥byedpi" # соседний контейнер с byedpi
    type: socks5
    server: 10.10.10.3 # адрес контейнера byedpi
    port: 1080 # socks5 порт
    udp: true

  - name: "warp" # AWG интерфейс до warp (Для примера)
    type: wireguard
    private-key: xxxx
    server: engage.cloudflareclient.com
    port: 2408
    ip: 172.16.0.2/32
    mtu: 1280
    public-key: xxxx
    allowed-ips: ['0.0.0.0/0']
    udp: true
    amnezia-wg-option:
        jc: 5
        jmin: 500
        jmax: 501
      # s1: 30
      # s2: 40
      # h1: 123456
      # h2: 67543
      # h4: 32345
      # h3: 123123

proxy-groups:
  - name: PROXY
    type: select
    exclude-filter: "🇷🇺"
    use:
      - sub
      - links

  - name: YouTube
    type: select
    proxies:
      - PROXY
      - warp
      - ⛓️‍💥byedpi
      - DIRECT
    filter: "🇷🇺"
    use:
      - sub
      - links

  - name: Discord
    type: select
    proxies:
      - PROXY
      - warp
      - ⛓️‍💥byedpi
      - DIRECT
    filter: "🇷🇺"
    use:
      - sub
      - links

  - name: cloudflare
    type: select
    proxies:
      - DIRECT
      - PROXY
      - warp
      - ⛓️‍💥byedpi
    filter: "🇷🇺"
    use:
      - sub
      - links

  - name: telegram
    type: select
    proxies:
      - DIRECT
      - PROXY
      - warp
      - ⛓️‍💥byedpi
    filter: "🇷🇺"
    use:
      - sub
      - links

  - name: quic # Блокируем или пропускаем quic
    type: select
    proxies:
      - PASS
      - REJECT

dns:
  enable: true
  listen: 0.0.0.0:53
  ipv6: false
  enhanced-mode: fake-ip
  respect-rules: true
  default-nameserver:
    - tls://9.9.9.9
  proxy-server-nameserver:
    - tls://9.9.9.9
  nameserver:
    - https://dns.adguard-dns.com/dns-query
  fake-ip-range: 198.18.0.1/15
  fake-ip-filter-mode: whitelist
  fake-ip-filter:
    - "RULE-SET:youtube"
    - "RULE-SET:x"
    - "RULE-SET:instagram"
    - "RULE-SET:facebook"
    - "RULE-SET:netflix"
    - "RULE-SET:openai"
    - "RULE-SET:discord"
    - "RULE-SET:tmdb"
    - "RULE-SET:intel"
    - "RULE-SET:google-deepmind"
    - "RULE-SET:medium"
    - "+.2ip.io"
    - "+.browserleaks.com"
    - "+.kinozal.tv"
    - "+.rutracker.org"
    - "+.rutracker.cc"
    - "+.nnmclub.to"
    - "+.rutor.org"
    - "+.servarr.com"
    - "+.prowlarr.com"
    - "+.clamav.net"
    - "+.strava.com"
    - "+.veeam.com"
    - "+.ntc.party"
    - "+.remna.st"
  nameserver-policy:
    "rule-set:category-gov-ru":
      - tls://77.88.8.8

listeners:
  - name: tun-in
    type: tun
    stack: system
    dns-hijack:
      - 0.0.0.0:53
    auto-detect-interface: true
    auto-route: true
    strict-route: true
    auto-redirect: true
    inet4-address:
      - 198.19.0.1/30

rules:
  - AND,((NETWORK,udp),(DST-PORT,443)),quic

  - DOMAIN,proactivebackend-pa.googleapis.com,DIRECT

  - DOMAIN-SUFFIX,2ip.io,PROXY
  - DOMAIN-SUFFIX,browserleaks.com,PROXY

  - RULE-SET,youtube,YouTube

  - RULE-SET,tmdb,PROXY
  - RULE-SET,medium,PROXY
  - RULE-SET,intel,PROXY
  - RULE-SET,netflix,PROXY
  - RULE-SET,openai,PROXY
  - RULE-SET,google-deepmind,PROXY
  - DOMAIN-SUFFIX,servarr.com,PROXY
  - DOMAIN-SUFFIX,prowlarr.com,PROXY
  - DOMAIN-SUFFIX,clamav.net,PROXY
  - DOMAIN-SUFFIX,strava.com,PROXY
  - DOMAIN-SUFFIX,veeam.com,PROXY

  - RULE-SET,x,PROXY
  - RULE-SET,facebook,PROXY
  - RULE-SET,instagram,PROXY
  - DOMAIN-SUFFIX,kinozal.tv,PROXY
  - DOMAIN-SUFFIX,rutracker.org,PROXY
  - DOMAIN-SUFFIX,rutracker.cc,PROXY
  - DOMAIN-SUFFIX,nnmclub.to,PROXY
  - DOMAIN-SUFFIX,rutor.org,PROXY
  - DOMAIN-SUFFIX,ntc.party,PROXY
  - DOMAIN-SUFFIX,remna.st,PROXY

# Discord
  - RULE-SET,discord,Discord
  - AND,((RULE-SET,discord_voice),(NETWORK,UDP),(DST-PORT,50000-50050)),Discord

# Cloudflare
  - RULE-SET,cloudflare,cloudflare

# Telegram
  - OR,((RULE-SET,telegram-cidr),(RULE-SET,telegram-domains)),telegram

rule-providers:
  facebook:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/facebook.mrs"
  instagram:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/instagram.mrs"
  x:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/x.mrs"
  netflix:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/netflix.mrs"
  openai:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/openai.mrs"
  discord:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/discord.mrs"
  tmdb:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/tmdb.mrs"
  medium:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/medium.mrs"
  youtube:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/youtube.mrs"
  intel:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/intel.mrs"
  google-deepmind:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/google-deepmind.mrs"
  discord_voice:
    type: http
    behavior: classical
    format: text
    url: "https://iplist.opencck.org/?format=clashx&data=cidr4&site=discord.gg"

  cloudflare:
    type: http
    behavior: ipcidr
    format: text
    url: "https://www.cloudflare.com/ips-v4/"

  telegram-cidr:
    type: http
    behavior: ipcidr
    format: text
    url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/geoip/telegram.list"

  telegram-domains: # Для web-клиента
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/telegram.mrs"

  category-gov-ru:
    type: http
    behavior: domain
    format: mrs
    url: "https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/meta/geo/geosite/category-gov-ru.mrs"
```
# Encrypted Client Hello (ECH)
Иногда сайты с включенной технологией ECH перестают открываться, но если отключить/сломать эту технологию, то сайты начинают работать. К сожалению mihomo не умеет фильтровать dns запросы по типу записей (или я не понял как это делается). Эта технология работает через dns запросы и файрвол routeros может такие запросы ловить и дропать.
```
/ip/firewall/filter/add action=drop chain=forward comment="drop dns type65" content="\00A\00\01" disabled=no dst-address=10.10.10.2 dst-port=53 in-interface-list=LAN protocol=udp place-before=[find comment="defconf: drop all from WAN not DSTNATed"]
```
После добавления такого правила ECH перестаёт работать. Автор методики @Medium_csgo


# Discord/Cloudflare/Telegram и прочие сервисы которые работают по ip адресам.

Так как fakeip-роутинг работает только с доменами иногда требуется перенаправить ip адреса или целые подсети в mihomo, например для discord и telegram. Для этого:
1. Cоздадим отдельную таблицу маршрутизации:
```
/routing/table/add name=to_mihomo fib
```
2. с помошью mangle будем маркировать нужные нам соединения:
```
/ip firewall mangle
add action=mark-routing chain=prerouting connection-mark=to_mihomo in-interface-list=LAN new-routing-mark=to_mihomo
```
3. Исключим маркированные соединения из fasttrack:
```
:foreach i in=[/ip firewall filter find where (comment~"fasttrack" && !dynamic)] do={/ip firewall filter set $i connection-mark=no-mark}
```
4. Добавим маршрут для промаркированного трафика.
```
/ip/route/add dst-address=0.0.0.0/0 routing-table=to_mihomo gateway=10.10.10.2 comment="discord voice to mihomo"
```

# Голосовые вызовы Discord:

1. Создадим скрипт, который будет скачивать адреслист с подсетями дискорда с сервиса https://iplist.opencck.org/:
```
/system script
add dont-require-permissions=no name=discord_voice owner=vanes policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source=\
    "/tool/fetch mode=https url=\"https://iplist.opencck.org/\?format=mikrotik&data=cidr4&site=discord.gg\" dst-path=/tmp1/discord_voice.rsc;\r\
    \nimport /tmp1/discord_voice.rsc"
```
2. Выполним скрипт, он создаст адрес лист discord_cidr4 с голосовыми подсетями дискорда:
```
/system/script/run discord_voice
```
3. Создадим планировщик который будет раз в день обновлять список:
```
/system scheduler
add interval=1d name=discord_voice on-event=discord_voice policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup
```
4: Маркируем udp соединения на определённых портах к голосовым подсетям дискорда:
```
/ip firewall mangle
add action=mark-connection chain=prerouting comment="discord voice to mihomo" connection-mark=no-mark dst-address-list=discord_cidr4 dst-port=50000-50050 in-interface-list=LAN new-connection-mark=to_mihomo protocol=udp place-before=[find action=mark-routing]
```

# Cloudflare

Направим все подсети Cloudflare в mihomo чтобы при возникновении проблем (а они возникают) был выбор куда их перенаправлять. В конфиге-примере для этого создан селектор, с помошью которого можно выбирать куда направлять cloudflare.
1. Создадим скрипт который создаст адрес-лист из подсетей cloudflare:
```
/system script
add dont-require-permissions=no name=cloudflare policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="/ip firewall address-list remove [find list=cloudflare]\r\
    \n/tool fetch url=\"https://www.cloudflare.com/ips-v4\" dst-path=\"tmp1/cloudflare.txt\" mode=https\r\
    \n:local fileName tmp1/cloudflare.txt\r\
    \n:local fileContent [/file get \$fileName contents]\r\
    \n:if ([:pick \$fileContent ([:len \$fileContent] - 1)] != \"\\n\") do={\r\
    \n    :set fileContent \"\$fileContent\\n\"\r\
    \n}\r\
    \n:local start 0\r\
    \n:local end 0\r\
    \n:local line \"\"\r\
    \n:local fileLength [:len \$fileContent]\r\
    \n:while (\$start < \$fileLength) do={\r\
    \n    :set end [:find \$fileContent \"\\n\" \$start]\r\
    \n    :if (\$end = -1) do={\r\
    \n        :set end \$fileLength\r\
    \n    }\r\
    \n\r\
    \n    :set line [:pick \$fileContent \$start \$end]\r\
    \n    :set start (\$end + 1)\r\
    \n    :if (\$line != \"\" && [:len \$line] > 0) do={\r\
    \n        /ip firewall address-list add list=cloudflare address=\$line comment=\"cloudflare\"\r\
    \n    }\r\
    \n}\r\
    \n/file remove \$fileName\r\
    \n"
```
2. Выполним скрипт, он создаст адрес лист c подсетями cloudflare:
```
/system/script/run cloudflare
```
3. Создадим задание планировщику обновлять адреса cloudflare
```
/system scheduler
add interval=1w name=cloudflare on-event=cloudflare policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup
```
4. Добавим правило mangle которое будет маркировать трафик до нужных нам подсетей
```
/ip firewall mangle
add action=mark-connection chain=prerouting comment="cloudflare to_mihomo" connection-mark=no-mark dst-address-list=cloudflare in-interface-list=LAN new-connection-mark=to_mihomo place-before=[find action=mark-routing]
```

# Telegram

1. Скрипт создающий address-list с подсетями telegram
```
/system script
add dont-require-permissions=no name=telegram policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source=":local ruleset \"telegram\"\r\
    \n:local addressList \$ruleset\r\
    \n\r\
    \n:local url (\"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/geoip/\" . \$ruleset . \".list\")\r\
    \n:local fileName (\"geoip-\" . \$ruleset . \".txt\")\r\
    \n\r\
    \n/tool fetch url=\$url dst-path=\$fileName mode=https keep-result=yes\r\
    \n\r\
    \n:local content [/file get \$fileName contents]\r\
    \n:local line \"\"\r\
    \n:local char \"\"\r\
    \n:local length [:len \$content]\r\
    \n:local i 0\r\
    \n\r\
    \n:while (\$i < \$length) do={\r\
    \n    :set char [:pick \$content \$i (\$i + 1)]\r\
    \n\r\
    \n    :if (\$char = \"\\r\") do={} else={\r\
    \n        :if (\$char = \"\\n\") do={\r\
    \n\r\
    \n            :if (([:len \$line] > 0) && ([:pick \$line 0 1] != \"#\") && ([:find \$line \":\"] = [:nothing])) do={\r\
    \n                /ip firewall address-list add address=\$line list=\$addressList comment=\$ruleset\r\
    \n            }\r\
    \n\r\
    \n            :set line \"\"\r\
    \n        } else={\r\
    \n            :set line (\$line . \$char)\r\
    \n        }\r\
    \n    }\r\
    \n\r\
    \n    :set i (\$i + 1)\r\
    \n}\r\
    \n\r\
    \n:if (([:len \$line] > 0) && ([:pick \$line 0 1] != \"#\") && ([:find \$line \":\"] = [:nothing])) do={\r\
    \n    /ip firewall address-list add address=\$line list=\$addressList comment=\$ruleset\r\
    \n}\r\
    \n\r\
    \n/file remove \$fileName\r\
    \n"
```
2. Выполним скрипт, он создаст адрес лист c подсетями telegram:
```
/system/script/run telegram
```
3. Создадим планировщик который будет раз в день обновлять список:
```
/system scheduler
add interval=1d name=telegram on-event=telegram policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup
```
4. Правило маркировки соединений для telegram
```
/ip firewall mangle
add action=mark-connection chain=prerouting comment="telegram to_mihomo" connection-mark=no-mark disabled=no dst-address-list=telegram in-interface-list=LAN new-connection-mark=to_mihomo place-before=[find action=mark-routing]
```