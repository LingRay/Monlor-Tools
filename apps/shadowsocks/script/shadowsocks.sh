#!/bin/ash /etc/rc.common
monlorpath=$(uci -q get monlor.tools.path)
[ $? -eq 0 ] && source "$monlorpath"/scripts/base.sh || exit

START=95
SERVICE_USE_PID=1
SERVICE_WRITE_PID=1
SERVICE_DAEMONIZE=1

wan_mode=`ifconfig | grep pppoe-wan | wc -l`
if [ "$wan_mode" = '1' ];then
	wanip=$(ifconfig pppoe-wan | grep "inet addr:" | cut -d: -f2 | awk '{print$1}')
else
	wanip=$(ifconfig | grep -A 6 "^eth" | grep "inet addr:" | cut -d: -f2 | awk '{print$1}' | head -1)
fi
lanip=$(uci get network.lan.ipaddr)
redip=$lanip
service=ShadowSocks
appname=shadowsocks
EXTRA_COMMANDS=" status backup recover"
EXTRA_HELP="        status  Get $appname status"
SER_CONF=$monlorpath/apps/$appname/config/ssserver.conf
CONFIG=$monlorpath/apps/$appname/config/ss.conf
DNSCONF=$monlorpath/apps/$appname/config/dns2socks.conf
SSGCONF=$monlorpath/apps/$appname/config/ssg.conf
chnroute=$monlorpath/apps/$appname/config/chnroute.conf
gfwlist=$monlorpath/apps/$appname/config/gfwlist.conf
customize_black=$monlorpath/apps/$appname/config/customize_black.conf
customize_white=$monlorpath/apps/$appname/config/customize_white.conf
APPPATH=$monlorpath/apps/$appname/bin/ss-redir
SSGBIN=$monlorpath/apps/$appname/bin/ssg-redir
LOCALPATH=$monlorpath/apps/$appname/bin/ss-local
DNSPATH=$monlorpath/apps/$appname/bin/dns2socks
id=`uci -q get monlor.$appname.id`
ssgid=`uci -q get monlor.$appname.ssgid`
ss_mode=$(uci -q get monlor.$appname.ss_mode)
ssg_mode=$(uci -q get monlor.$appname.ssg_mode)
ssg_enable=$(uci -q get monlor.$appname.ssgena)

get_config() {
    
	logsh "【$service】" "创建ss节点配置文件..."
	[ -z "$id" ] && logsh "【$service】" "未配置$appname运行节点！" && exit
	local_ip=0.0.0.0
	idinfo=`cat $SER_CONF | grep $id | head -1`
	ss_name=`cutsh $idinfo 1`
	ss_server=`cutsh $idinfo 2`
	ss_server_port=`cutsh $idinfo 3`
	ss_password=`cutsh $idinfo 4`
	ss_method=`cutsh $idinfo 5`
	ssr_protocol=`cutsh $idinfo 6`
	ssr_obfs=`cutsh $idinfo 7`
	ssr_obfs_param=`cutsh $idinfo 8`
	ss_server=`resolveip $ss_server` 
	[ $? -ne 0 ] && logsh "【$service】" "ss服务器地址解析失败" && exit
   	if [ ! -z "$ssr_obfs" -a ! -z "$ssr_protocol" ];then
		APPPATH=$monlorpath/apps/$appname/bin/ssr-redir
		LOCALPATH=$monlorpath/apps/$appname/bin/ssr-local
	fi
	#生成配置文件
	echo -e '{\n  "server":"'$ss_server'",\n  "server_port":'$ss_server_port',\n  "local_port":'1081',\n  "local_address":"'$local_ip'",\n  "password":"'$ss_password'",\n  "timeout":600,\n  "method":"'$ss_method'",\n  "protocol":"'$ssr_protocol'",\n  "obfs":"'$ssr_obfs'",\n  "obfs_param":"'$ssr_obfs_param'"\n}' > $CONFIG
	cp $CONFIG $DNSCONF && sed -i 's/1081/1082/g' $DNSCONF

	if [ "$ssg_enable" == '1' -a "$ssgid" != "$id" ]; then
		[ -z "$ssgid" ] && logsh "【$service】" "未配置$appname游戏运行节点！" && exit
		idinfo=`cat $SER_CONF | grep $ssgid | head -1`
    	ssg_name=`cutsh $idinfo 1`
    	ssg_server=`cutsh $idinfo 2`
    	ssg_server_port=`cutsh $idinfo 3`
    	ssg_password=`cutsh $idinfo 4`
    	ssg_method=`cutsh $idinfo 5`
    	ssg_protocol=`cutsh $idinfo 6`
		ssg_obfs=`cutsh $idinfo 7`
		ssg_obfs_param=`cutsh $idinfo 8`
		if [ ! -z "$ssg_obfs" -a ! -z "$ssg_protocol" ]; then
			cp $monlorpath/apps/$appname/bin/ssr-redir $SSGBIN
		else
			cp $monlorpath/apps/$appname/bin/ss-redir $SSGBIN
		fi

		ssg_server=`resolveip $ssg_server` 
    		[ $? -ne 0 ] && logsh "【$service】" "ss游戏服务器地址解析失败" && exit
		echo -e '{\n  "server":"'$ssg_server'",\n  "server_port":'$ssg_server_port',\n  "local_port":'1085',\n  "local_address":"'$local_ip'",\n  "password":"'$ssg_password'",\n  "timeout":600,\n  "method":"'$ssg_method'",\n  "protocol":"'$ssg_protocol'",\n  "obfs":"'$ssg_obfs'",\n  "obfs_param":"'$ssg_obfs_param'"\n}' > $SSGCONF
	fi

}

dnsconfig() {

	insmod ipt_REDIRECT 2>/dev/null
	service_start $LOCALPATH -c $DNSCONF
	killall dns2socks > /dev/null 2>&1
	iptables -t nat -D PREROUTING -s $lanip/24 -p udp --dport 53 -j DNAT --to $redip > /dev/null 2>&1
	logsh "【$service】" "开启dns2socks进程..."
	DNS_SERVER=$(uci -q get monlor.$appname.dns_server) || DNS_SERVER=8.8.8.8
	DNS_SERVER_PORT=$(uci -q get monlor.$appname.dns_port) || DNS_SERVER_PORT=53
	service_start $DNSPATH 127.0.0.1:1082 $DNS_SERVER:$DNS_SERVER_PORT 127.0.0.1:15353 
	if [ $? -ne 0 ]; then
	    	logsh "【$service】" "启动失败！"
	    	exit
	fi
    
}

get_mode_name() {
	case "$1" in
		0)
			echo "不走代理"
		;;
		1)
			echo "科学上网"
		;;
	esac
}

get_game_mode() {
	case "$1" in
		0)
			echo "不走游戏"
		;;
		1)
			echo "游戏加速"
		;;
	esac
}

get_jump_mode(){
	case "$1" in
		0)
			echo "-j"
		;;
		*)
			echo "-g"
		;;
	esac
}

get_action_chain() {
	case "$1" in
		0)
			echo "RETURN"
		;;
		1)
			echo "SHADOWSOCK"
		;;
	esac
}

load_nat() {

	logsh "【$service】" "加载iptables的nat规则..."
	iptables -t nat -N SHADOWSOCKS
	iptables -t nat -N SHADOWSOCK
	iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d $lanip/24 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d $wanip/16 -j RETURN
	iptables -t nat -A SHADOWSOCKS -d $ss_server -j RETURN
	[ "$ssg_enable" == '1' -a "$ssgid" != "$id" ] && iptables -t nat -A SHADOWSOCKS -d $ssg_server -j RETURN 

	if [ "$ssg_enable" == '1' ]; then
		logsh "【$service】" "添加iptables的udp规则..."
		ip rule add fwmark 0x01/0x01 table 300
		ip route add local 0.0.0.0/0 dev lo table 300
		iptables -t mangle -N SHADOWSOCKS
		iptables -t mangle -N SHADOWSOCK
		iptables -t mangle -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
		iptables -t mangle -A SHADOWSOCKS -d 127.0.0.1/16 -j RETURN
		iptables -t mangle -A SHADOWSOCKS -d $lanip/16 -j RETURN
		iptables -t mangle -A SHADOWSOCKS -d $wanip/16 -j RETURN
		iptables -t mangle -A SHADOWSOCKS -d $ss_server -j RETURN
		[ "$ssgid" != "$id" ] && iptables -t mangle -A SHADOWSOCKS -d $ssg_server -j RETURN

		chmod -x /opt/filetunnel/stunserver > /dev/null 2>&1
		killall -9 stunserver > /dev/null 2>&1
	fi
	#lan access control
	[ ! -f $monlorpath/apps/shadowsocks/config/sscontrol.conf ] && touch $monlorpath/apps/shadowsocks/config/sscontrol.conf
	cat $monlorpath/apps/$appname/config/sscontrol.conf | while read line
	do
		mac=$(cutsh $line 2)
		proxy_name=$(cutsh $line 1)
		proxy_mode=$(cutsh $line 3)
		game_mode=$(cutsh $line 4)
		[ -z "$game_mode" ] && game_mode="$proxy_mode"		
		iptables -t nat -A SHADOWSOCKS -m mac --mac-source $mac $(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)
		if [ "$ssg_enable" == '1' ]; then
			iptables -t mangle -A SHADOWSOCKS -m mac --mac-source $mac $(get_jump_mode $game_mode) $(get_action_chain $game_mode)
			args="[$(get_game_mode $game_mode)]"
		else
			args=""
		fi
		logsh "【$service】" "加载ACL规则:[$proxy_name]代理模式为:[$(get_mode_name $proxy_mode)]$args"
	done
	#default alc mode
	ss_proxy_default_mode=$(uci -q get monlor.$appname.ss_proxy_default_mode) || ss_proxy_default_mode=1
	ss_game_default_mode=$(uci -q get monlor.$appname.ss_game_default_mode) || ss_game_default_mode=0
	result=$(cat $monlorpath/apps/$appname/config/sscontrol.conf | wc -l)
	[ "$result" == '0' ] && flag="全部主机" || flag="其余主机"
	[ "$ssg_enable" == '1' ] && args="[$(get_game_mode $ss_game_default_mode)]" || args=""
	logsh "【$service】" "加载ACL规则:[$flag]代理模式为:[$(get_mode_name $ss_proxy_default_mode)]$args"
	iptables -t nat -A SHADOWSOCKS -p tcp -j $(get_action_chain $ss_proxy_default_mode)
	[ "$ssg_enable" == '1' ] && iptables -t mangle -A SHADOWSOCKS -p udp -j $(get_action_chain $ss_game_default_mode)
	[ ! -f $customize_black ] && touch $customize_black
	[ ! -f $customize_white ] && touch $customize_white
	rm -rf /tmp/customize_*.conf
	cat $customize_black | while read line                                                                   
	do         
		[ -z "$line" ] && continue                                                                                     
		echo "server=/.$line/127.0.0.1#15353" >> /tmp/customize_black.conf  
		echo "ipset=/.$line/customize_black" >> /tmp/customize_black.conf                     
	done
	ln -s /tmp/customize_black.conf /etc/dnsmasq.d/customize_black.conf
	cat $customize_white | while read line
	do
		[ -z "$line" ] && continue
		echo "ipset=/.$line/customize_white" >> /tmp/customize_white.conf
	done              
	ln -s /tmp/customize_white.conf /etc/dnsmasq.d/customize_white.conf                                                 
	ipset -N customize_black iphash -!  
	ipset -N customize_white iphash -!
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set customize_white dst -j RETURN
	[ "$ssg_enable" == '1' ] && iptables -t mangle -A SHADOWSOCK -p udp -m set --match-set customize_white dst -j RETURN

}


start() {

	[ ! -s $SER_CONF ] && logsh "【$service】" "没有添加ss服务器!" && exit 
	result=$(ps | grep -E 'ss-redir|ssr-redir' | grep -v grep | wc -l)
	if [ "$result" != '0'  ];then
		logsh "【$service】" "SS已经在运行！"	
		exit
	fi
	#添加定时更新规则
	cru a $appname "20 5 * * * $monlorpath/apps/$appname/script/updaterules.sh"

	get_config

	dnsconfig            

	load_nat
    	
	logsh "【$service】" "启动ss主进程($id)..."
	[ -z "$ss_mode" ] && logsh "【$service】" "未配置$appname运行模式！" && exit
	service_start $APPPATH -b 0.0.0.0 -u -c $CONFIG 
	if [ $? -ne 0 ]; then
		logsh "【$service】" "启动失败！"
		exit
	fi
	case $ss_mode in
		"gfwlist") ss_gfwlist ;;
		"whitelist") ss_whitelist ;;
		"wholemode") ss_wholemode ;;
		"homemode") ss_homemode ;;
		*) logsh "【$service】" "ss运行模式错误！" ;;
	esac

	if [ "$ssg_enable" == 1 ]; then             
		logsh "【$service】" "启动ss游戏进程($ssgid)..."
		[ -z "$ssg_mode" ] && logsh "【$service】" "未配置$appname游戏运行模式！" && exit
		if [ "$ssgid" != "$id" ]; then
			service_start $SSGBIN -b 0.0.0.0 -u -c $SSGCONF
                	if [ $? -ne 0 ]; then
                       	 	logsh "【$service】" "启动失败！"
                        	exit
                	fi
                	ssg_port=1085
                else
                	ssg_port=1081
                fi	
		case $ssg_mode in
		"cngame") ss_cngame ;;
		"frgame") ss_frgame ;;
		*) logsh "【$service】" "ss游戏模式错误！" ;;
		esac
	fi
	
  	iptablenu=$(iptables -nvL PREROUTING -t nat | sed 1,2d | sed -n '/KOOLPROXY/=' | head -n1)
	if [ -z "$iptablenu" ];then
	# 	let iptablenu=$iptablenu-1
	# else
		iptablenu=2
	fi
	iptables -t nat -I PREROUTING "$iptablenu" -p tcp -j SHADOWSOCKS
	[ "$ssg_enable" == '1' ] && iptables -t mangle -A PREROUTING -p udp -j SHADOWSOCKS

	/etc/init.d/dnsmasq restart
	logsh "【$service】" "启动$appname服务完成！"

}

gfwlist_ipset() {
	rm -rf /tmp/gfwlist_ipset.conf
	cat $gfwlist | while read line                                             
	do                  
		[ -z "$line" ] && continue                                                       
		echo "server=/.$line/127.0.0.1#15353" >> /tmp/gfwlist_ipset.conf
		echo "ipset=/.$line/gfwlist" >> /tmp/gfwlist_ipset.conf  
	done    
	ln -s /tmp/gfwlist_ipset.conf /etc/dnsmasq.d/gfwlist_ipset.conf
	ipset -N gfwlist iphash -!
}

chnroute_ipset() {
	sed -e "s/^/-A nogfwnet &/g" -e "1 i\-N nogfwnet hash:net" $chnroute | ipset -R -!
}

ss_gfwlist() {

	logsh "【$service】" "添加国外黑名单规则..."
	gfwlist_ipset
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set customize_black dst -j REDIRECT --to-port 1081
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port 1081

}

ss_whitelist() {

	logsh "【$service】" "添加国外白名单规则..."                                    
	chnroute_ipset
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set customize_black dst -j REDIRECT --to-ports 1081
	iptables -t nat -A SHADOWSOCK -p tcp -m set ! --match-set nogfwnet dst -j REDIRECT --to-ports 1081 
}

ss_cngame() {

	logsh "【$service】" "添加国内游戏iptables规则..."
	[ "$ss_mode" != "gfwlist" ] && gfwlist_ipset
	iptables -t mangle -A SHADOWSOCK -p udp -m set ! --match-set gfwlist dst -j TPROXY --on-port "$ssg_port" --tproxy-mark 0x01/0x01         

}

ss_frgame() {

	logsh "【$service】" "添加国外游戏iptables规则..."
	[ "$ss_mode" != "whitelist" ] && chnroute_ipset
	iptables -t mangle -A SHADOWSOCK -p udp -m set ! --match-set nogfwnet dst -j TPROXY --on-port "$ssg_port" --tproxy-mark 0x01/0x01

}

ss_wholemode() {

	logsh "【$service】" "添加全局模式iptables规则..."
	iptables -t nat -A SHADOWSOCK -p tcp -j REDIRECT --to-ports 1081

}

ss_homemode() {

	logsh "【$service】" "添加回国模式规则..."
	[ "$ss_mode" != "whitelist" ] && chnroute_ipset
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set customize_black dst -j REDIRECT --to-ports 1081
	iptables -t nat -A SHADOWSOCK -p tcp -m set --match-set nogfwnet dst -j REDIRECT --to-ports 1081 

}


stop() {
	
	logsh "【$service】" "关闭ss主进程..."
	killall ss-redir > /dev/null 2>&1
	killall ssr-redir > /dev/null 2>&1
	killall ssg-redir > /dev/null 2>&1
	killall ss-local > /dev/null 2>&1
	killall ssr-local > /dev/null 2>&1
	killall dns2socks > /dev/null 2>&1
	#删除定时规则
	cru d $appname
	#ps | grep dns2socks | grep -v grep | xargs kill -9 > /dev/null 2>&1
	stop_ss_rules

}

stop_ss_rules() {

	logsh "【$service】" "清除iptables规则..."
	cd /tmp
	iptables -t nat -S | grep -E 'SHADOWSOCK|SHADOWSOCKS'| sed 's/-A/iptables -t nat -D/g'|sed 1,2d > clean.sh && chmod 777 clean.sh && ./clean.sh && rm clean.sh
	ip rule del fwmark 0x01/0x01 table 300 &> /dev/null
	ip route del local 0.0.0.0/0 dev lo table 300 &> /dev/null
	iptables -t mangle -D PREROUTING -p udp -j SHADOWSOCKS &> /dev/null
	iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS &> /dev/null
	iptables -t mangle -F SHADOWSOCKS &> /dev/null
	iptables -t mangle -X SHADOWSOCKS &> /dev/null
	iptables -t mangle -F SHADOWSOCK &> /dev/null
	iptables -t mangle -X SHADOWSOCK &> /dev/null
	iptables -t nat -F SHADOWSOCK &> /dev/null
	iptables -t nat -X SHADOWSOCK &> /dev/null
	iptables -t nat -F SHADOWSOCKS &> /dev/null
	iptables -t nat -X SHADOWSOCKS &> /dev/null
	ipset destroy nogfwnet &> /dev/null
	ipset destroy gfwlist &> /dev/null
	ipset destroy customize_black &> /dev/null
	ipset destroy customize_white &> /dev/null
	iptables -t nat -D PREROUTING -s $lanip/24 -p udp --dport 53 -j DNAT --to $redip > /dev/null 2>&1
	chmod +x /opt/filetunnel/stunserver > /dev/null 2>&1
	rm -rf $CONFIG
	rm -rf $DNSCONF
	rm -rf $SSGCONF
	rm -rf $SSGBIN
	rm -rf /tmp/customize_*.conf
	rm -rf /tmp/gfwlist_ipset.conf
	rm -rf /etc/dnsmasq.d/gfwlist_ipset.conf > /dev/null 2>&1
	rm -rf /etc/dnsmasq.d/customize_*.conf > /dev/null 2>&1
	# /etc/init.d/dnsmasq restart
}


restart() 
{
	stop
	sleep 1
	start

}

status() {

	result1=$(pssh | grep $monlorpath/apps/$appname/bin | grep -v grep | wc -l)
	#http_status=`curl  -s -w %{http_code} https://www.google.com.hk/images/branding/googlelogo/1x/googlelogo_color_116x41dp.png -k -o /dev/null --socks5 127.0.0.1:1082`
	#if [ "$result" == '0' ] || [ "$http_status" != "200" ]; then
	result2=$(iptables -t nat -S | grep -c SHADOWSOCK)
	[ "$ssg_enable" == '1' ] && ssgflag=", 游戏节点: $ssgid($ssg_mode)"
	if [ "$result1" -ge "3" ]; then
		if [ "$result2" -ge 10 ]; then
			echo "运行节点: $id($ss_mode)$ssgflag" 
			echo "1"
		else
			echo "ss链路异常，可以尝试重启服务！"
			echo "0"
		fi
	else
		echo "未运行"
		echo "0"
	fi

}

backup() {

	mkdir -p $monlorbackup/$appname
	cp -rf $SER_CONF $monlorbackup/$appname/$appname.conf
	cp -rf $monlorpath/apps/shadowsocks/config/sscontrol.conf $monlorbackup/$appname/sscontrol.conf

}

recover() {

	cp -rf $monlorbackup/$appname/$appname.conf $SER_CONF
	cp -rf $monlorbackup/$appname/sscontrol.conf $monlorpath/apps/shadowsocks/config/sscontrol.conf

}