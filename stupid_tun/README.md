Контейнер на основе mihomo для Mikrotik RouterOS, которая не поддерживает nftables. Установлена переменная окружения DISABLE_NFTABLES=1 для mihomo отключающая nftables. Контейнер собран на базе alpine linux 3.18 где по умолчанию используется iptables-legacy (нужно для работы переменной auto-redirect: true на tun интерфейсе, которая сильно ускоряет обработку tcp трафика).

- Контейнер создаёт tun-интерфейс в который можно направлять трафик средствами RouterOS. 
- Контейнер создаёт socks/http прокси на порту 1080.
- Поддерживает добавление ссылок на прокси и прокси-подписки через переменные.
- Может прочитать конфиг AmneziaWG из файла и добавить в список прокси.
- Можно добавлять несколько прокси/подписок и переключаться между ними в панельке (http://container_ip:9090/ui)
- Можно с помошью переменной менять тип прокси-группы чтобы автоматизировать выбор прокси.
- Можно с помошью переменной менять порядок прокси в прокси-группе.
#
# Доступные переменные:
- LOG_LEVEL Доступные значения: silent, error, warning, info, debug (по умолчанию warning)
- LINK№ (LINK1 LINK2 итд)
- SUB_LINK№ (SUB_LINK1 SUB_LINK2 итд)
- GROUP_TYPE Доступные значения: select, url-test, fallback (по умолчанию select)
- GROUP_ORDER Меняет порядок прокси в группе, полезно при использовании GROUP_TYPE=fallback. Доступные значения: links,sub_link№,awg. Например при указании значения links,awg первыми в группе будут прокси добавленные ссылками в порядке добавления, затем AWG. Можно не указывать.
- INTERVAL Интервал проверки работоспособности прокси. (По умолчанию 120сек). Значение 0 отключает проверку.
- EXTERNAL_UI_URL (по умолчанию https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip)
#
# Пример конфигурации роутера:

- Пакет containers должен быть установлен и активирован в /system/device-mode. В примере использовался hap ax lite. Версия RouterOS 7.19.4 Mihomo 1.19.12
- RouterOS сброшена до дефолтной конфигурации (не пустой конфиг).
#
Записи в DNS-static будут создавать динамический address-list с ip адресами, которые будут маркироваться и перенаправляться в контейнер с mihomo.

1: Создадим tmpfs для временных файлов:
```
/disk add type=tmpfs tmpfs-max-size=50M
```
2: Задаём директорию для временных файлов:
```
/container config set tmpdir=/tmp1
```
3: Создаём виртуальный интерфейс для контейнера mihomo, назначаем адрес и шлюз:
```
/interface veth add address=10.10.10.2/24 gateway=10.10.10.1
```
4: Создаём бридж для контейнеров и добавляем в него виртуальные интерфейсы контейнеров:
```
/interface bridge add name=dockers
/interface bridge port add bridge=dockers interface=veth1
```
5: Назначаем адрес бридж интерфейсу:
```
/ip address add address=10.10.10.1/24 interface=dockers network=10.10.10.0
```
6: Создаём переменные с ссылками на прокси/подписки:
```
/container envs
add key=LINK1 name=mihomo value="vless://xxx"
add key=SUB_LINK1 name=mihomo value=https://xxxx
add key=GROUP_TYPE name=mihomo value=select
```
7: создаём маунт для конфига AWG: (если требуется добавить AWG в список прокси, то следует поместить конфиг AWG в директорию /awg самого роутера и контейнер сам добавит AWG в список прокси.)
```
/container mounts
add dst=/root/.config/mihomo/awg name=awg src=/awg
```
8: Создаём контейнер:
```
/container
add envlist=mihomo interface=veth1 logging=yes mounts=awg start-on-boot=yes remote-image=registry-1.docker.io/vanes32/mihomo_stupid_tun:1.19.12
```
9: Создадим таблицу маршрутизации и маршрут этой таблицы в контейнер:
```
/routing table
add disabled=no fib name=to_mihomo
```
```
/ip route
add disabled=no distance=1 dst-address=0.0.0.0/0 gateway=10.10.10.2 routing-table=to_mihomo scope=30 suppress-hw-offload=no target-scope=10
```
10: Создадим правила маркировки соединений:
```
/ip firewall mangle
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=to_mihomo in-interface-list=LAN new-connection-mark=to_mihomo
```
11: Назначим этим соединениям таблицу маршрутизации:
```
/ip firewall mangle
add action=mark-routing chain=prerouting connection-mark=to_mihomo in-interface-list=LAN new-routing-mark=to_mihomo
```
12: Исключим промаркированные соединения из fasttrack:
```
:foreach i in=[/ip firewall filter find where (comment~"fasttrack" && !dynamic)] do={/ip firewall filter set $i connection-mark=no-mark}
```
13: Создадим DNS-forwarder:
```
/ip dns forwarders
add doh-servers=https://dns.google/dns-query name=google verify-doh-cert=yes 
```
14: Активируем встроенные сертификаты для рабыты DOH:
```
/certificate/settings/set builtin-trust-anchors=trusted
```
15: Добавим доп. время к жизни адрестистов:
```
/ip/dns/set address-list-extra-time=1h
```
16: Увеличим размер DNS кэша чтобы влезало много DNS static записей:
```
/ip/dns/set cache-size=4096
```
17: Выключим ipv6
```
/ipv6/settings/set disable-ipv6=yes
```
18: Добавим нужные домены в DNS-static нужными доменами:
```
/ip dns static
add address-list=to_mihomo forward-to=google match-subdomain=yes name=showip.net type=FWD
```

# Скрипт-генератор списков в DNS-static:
- Скрипт скачивает с гитхаба нужный рулсэт и конвертирует его в записи DNS-static. Название нужного рулсэт выбираем по ссылке https://github.com/MetaCubeX/meta-rules-dat/tree/meta/geo/geosite и вставляем в переменную "ruleset" скрипта. Также переменными можно задавать значения "address-list=" и "forward-to="
```
:local ruleset "openai"
:local addressList "to_mihomo"
:local forwardTo "google"

:local url ("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/geosite/" . $ruleset . ".list")
:local fileName ("ruleset-" . $ruleset . ".txt")

/tool fetch url=$url dst-path=$fileName mode=https keep-result=yes

:local content [/file get $fileName contents]
:local line ""
:local char ""
:local length [:len $content]
:local i 0


:while ($i < $length) do={
    :set char [:pick $content $i ($i + 1)]

    :if ($char = "\r") do={} else={
        :if ($char = "\n") do={

            :if (([:len $line] > 0) && ([:pick $line 0 1] != "#")) do={

                :local matchSubdomain "no"
                :local domainName $line

                :if ([:pick $line 0 1] = "+") do={
                    :set matchSubdomain "yes"
                    :set domainName [:pick $line 1 [:len $line]]


                    :while ([:len $domainName] > 0 && [:pick $domainName 0 1] = ".") do={
                        :set domainName [:pick $domainName 1 [:len $domainName]]
                    }
                }

                :if ([:len $domainName] > 0) do={
                    /ip dns static add address-list=$addressList forward-to=$forwardTo match-subdomain=$matchSubdomain name=$domainName type=FWD comment=$ruleset
                }
            }

            :set line ""
        } else={
            :set line ($line . $char)
        }
    }

    :set i ($i + 1)
}

:if ([:len $line] > 0 && [:pick $line 0 1] != "#") do={

    :local matchSubdomain "no"
    :local domainName $line

    :if ([:pick $line 0 1] = "+") do={
        :set matchSubdomain "yes"
        :set domainName [:pick $line 1 [:len $line]]

        :while ([:len $domainName] > 0 && [:pick $domainName 0 1] = ".") do={
            :set domainName [:pick $domainName 1 [:len $domainName]]
        }
    }

    :if ([:len $domainName] > 0) do={
        /ip dns static add address-list=$addressList forward-to=$forwardTo match-subdomain=$matchSubdomain name=$domainName type=FWD comment=$ruleset
    }
}

/file remove $fileName
```