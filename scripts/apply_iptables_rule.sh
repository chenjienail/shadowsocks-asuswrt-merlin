#!/bin/sh

SS_MERLIN_HOME=/opt/share/ss-merlin

echo "Apply ipset rule..."

modprobe ip_set
modprobe ip_set_hash_net
modprobe ip_set_hash_ip
modprobe xt_set
ipset -N CHINAIPS hash:net
ipset -N CHINAIP hash:ip

OLDIFS="$IFS" && IFS=$'\n'
if ipset -L CHINAIPS &> /dev/null; then
  count=$(ipset -L CHINAIPS | wc -l)
  if [[ "$count" -lt "8000" ]]; then
    echo "Applying China ipset rule, it maybe take several minute to finish..."

    for ip in $(cat ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt | grep -v '^#'); do
      ipset add CHINAIPS ${ip}
    done

    for ip in $(cat ${SS_MERLIN_HOME}/rules/localips | grep -v '^#'); do
      ipset add CHINAIPS ${ip}
    done
  fi
fi

remote_server_ip=$(cat ${SS_MERLIN_HOME}/etc/shadowsocks/config.json | grep 'server"' | cut -d ':' -f 2 | cut -d '"' -f 2)

if ipset -L CHINAIP; then
  ipset add CHINAIP 202.12.29.205 # ftp.apnic.net
  ipset add CHINAIP ${remote_server_ip} # vps ip address

  # user_ip_whitelist.txt
  if [[ -e ${SS_MERLIN_HOME}/rules/user_ip_whitelist.txt ]]; then
    for ip in $(cat ${SS_MERLIN_HOME}/rules/user_ip_whitelist.txt | grep -v '^#'); do
      ipset add CHINAIP ${ip}
    done
  fi
fi
IFS=${OLDIFS}

echo "Apply ipset rule done."

echo "Apply iptables rule..."

local_redir_port=$(cat ${SS_MERLIN_HOME}/etc/shadowsocks/config.json | grep 'local_port' | cut -d ':' -f 2 | grep -o '[0-9]*')

# TCP rules
iptables -t nat -N SHADOWSOCKS_TCP
iptables -t nat -A SHADOWSOCKS_TCP -m set --match-set CHINAIP dst -j RETURN
iptables -t nat -A SHADOWSOCKS_TCP -m set --match-set CHINAIPS dst -j RETURN
iptables -t nat -A SHADOWSOCKS_TCP -p tcp -j REDIRECT --to-ports ${local_redir_port}

# Apply TCP rules
iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS_TCP

# UDP rules
modprobe xt_TPROXY
ip route add local default dev lo table 100
ip rule add fwmark 1 lookup 100

iptables -t mangle -N SHADOWSOCKS_UDP
iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set CHINAIPS dst -j RETURN
iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set CHINAIP dst -j RETURN
iptables -t mangle -A SHADOWSOCKS_UDP -p udp -j TPROXY --on-port ${local_redir_port} --tproxy-mark 0x01/0x01

# Apply for udp
iptables -t mangle -A PREROUTING -p udp -j SHADOWSOCKS_UDP

echo "Apply iptables rule done."