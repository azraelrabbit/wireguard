#!/bin/bash

mpath="$PWD"

#vname=wg0
vnetPrefix=10.168.12

echo -e "\033[37;41m给服务端起个名字(或要管理的服务端)，只能使用英文字符和数字,且不能以数字开头\033[0m"
read -p "请输入服务端名字：(默认wg0)" vname

if [ "$vname"=="" ]
then 
    vname=wg0
fi

    
#echo -e "\033[37;41m设置虚拟内网地址前缀，前三段即可,例如:192.168.1 \033[0m"
#read -p "请输虚拟内网前缀：(默认:10.168.12)" vnetPrefix

#if [ "$vnetPrefix"=="" ]
#then 
#    vnetPrefix=10.168.12
#fi
 
 
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_install(){
    version=$(cat /etc/os-release | awk -F '[".]' '$1=="VERSION="{print $2}')
    if [ $version == 18 ]
    then
        sudo apt-get update -y
        sudo apt-get install -y software-properties-common
        sudo apt-get install -y openresolv
    else
        sudo apt-get update -y
        sudo apt-get install -y software-properties-common
    fi
    
    sudo apt-get install -y wget curl git libmnl-dev libelf-dev build-essential pkg-config
    apt autoremove golang

   mkdir -p /tmp/wginstall
  cd /tmp/wginstall

    sudo wget https://dl.google.com/go/go1.12.6.linux-amd64.tar.gz
    sudo tar xzfv go1.12.6.linux-amd64.tar.gz
    sudo cp -r ./go /usr/bin/
    sudo echo "export PATH=/usr/bin/go/bin:$PATH" >> /etc/profile
    sudo echo "export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1" >> /etc/profile
    source /etc/profile
    
    sudo git clone https://git.zx2c4.com/wireguard-go
    cd wireguard-go
    make 
    sudo cp wireguard-go /usr/sbin/
    cd ..
    sudo git clone https://git.zx2c4.com/WireGuard
    cd WireGuard/src/tools
    sudo make && make install
    cd ..
    sudo export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
    sudo wireguard-go $vname
    
    
    sudo echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
    sysctl -p
    echo "1"> /proc/sys/net/ipv4/ip_forward
    
    mkdir /etc/wireguard
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=$(rand 10000 60000)
    eth=$(ls /sys/class/net | awk '/^v/{print}')

sudo cat > /etc/wireguard/$vname.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = $vnetPrefix.1/24 
PostUp   = iptables -A FORWARD -i $vname -j ACCEPT; iptables -A FORWARD -o $vname -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
PostDown = iptables -D FORWARD -i $vname -j ACCEPT; iptables -D FORWARD -o $vname -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = $port
DNS = 8.8.8.8
MTU = 1420
[Peer]
PublicKey = $c2
AllowedIPs = $vnetPrefix.2/32
EOF


sudo cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = $vnetPrefix.2/24 
DNS = 8.8.8.8
MTU = 1320
[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

    sudo apt-get install -y qrencode

sudo cat > /etc/systemd/system/$vname.service <<-EOF
[Unit]
Description=wireguard $vname Service
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=simple
Environment="WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1"
ExecStart=/usr/bin/wg-quick up $vname
ExecStop=/usr/bin/wg-quick down $vname
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $vname.service
sudo systemctl start $vname.service
   

    content=$(cat /etc/wireguard/client.conf)
    echo -e "\033[43;42m电脑端请下载/etc/wireguard/client.conf，手机端可直接使用软件扫码\033[0m"
    echo "${content}" | qrencode -o - -t UTF8

 cd "$mpath"
 sudo rm -rf  /tmp/wginstall
}

wireguard_remove(){

    sudo wg-quick down $vname
    sudo systemctl stop $vname.service
    sudo systemctl disable $vname.service
    sudo rm -rf /etc/systemd/system/$vname.service
    sudo rm -rf /etc/wireguard

}

add_user(){

addrprefix=$(grep Address /etc/wireguard/client.conf | tail -1 | awk -F '[ /]' '{print $3}' | awk -F '.' '{print $1"."$2"."$3}')

if test -z "$addrprefix"
then
        # echo "addrprefix is null"
        echo "addrprefix is $vnetPrefix"
else
      # echo "addrprefix is setup"
        vnetPrefix=$addrprefix
       echo "addrprefix is $vnetPrefix"
fi

    echo -e "\033[37;41m给新用户起个名字，不能和已有用户重复\033[0m"
    read -p "请输入用户名：" newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | tee temprikey | wg pubkey > tempubkey
    ipnum=$(grep Allowed /etc/wireguard/$vname.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = $vnetPrefix.$newnum\/24"'%' $newname.conf



cat >> /etc/wireguard/$vname.conf <<-EOF
[Peer]
PublicKey = $(cat tempubkey)
AllowedIPs = $vnetPrefix.$newnum/32
EOF
    wg set $vname peer $(cat tempubkey) allowed-ips $vnetPrefix.$newnum/32
    echo -e "\033[37;41m添加完成，文件：/etc/wireguard/$newname.conf\033[0m"
    rm -f temprikey tempubkey


    content=$(cat /etc/wireguard/$newname.conf)
    echo "${content}" | qrencode -o - -t UTF8
}

show_qrcode(){
    echo -e "\033[37;41m客户端列表(包括服务端名字,忽略其即可)\033[0m"     
    ls -1 /etc/wireguard/*.conf | tr '\n' '\0' | xargs -0 -n 1 basename -s .conf
    echo -e "\033[37;41m输入要查看的客户端名字\033[0m"
    read -p "请输入客户端名：" nvqname
    content=$(cat /etc/wireguard/$nvqname.conf)
    echo "${content}" | qrencode -o - -t UTF8    
}


#开始菜单
start_menu(){
    clear
    echo -e "\033[43;42m ====================================\033[0m"
    echo -e "\033[43;42m 介绍：wireguard一键脚本              \033[0m"
    echo -e "\033[43;42m 系统：Ubuntu                        \033[0m"
     echo -e "\033[37;41m 网卡名称:  $vname \033[0m"
    echo -e "\033[37;41m 虚拟内网地址:  $vnetPrefix.x/24 \033[0m"
    echo -e "\033[43;42m ====================================\033[0m"
    echo
    echo -e "\033[0;33m 1. 安装wireguard\033[0m"
    echo -e "\033[0;33m 2. 查看客户端二维码\033[0m"
    echo -e "\033[0;31m 3. 删除wireguard\033[0m"
    echo -e "\033[0;33m 4. 增加用户\033[0m"
    echo -e " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    wireguard_install
    ;;
    2)
    show_qrcode
     ;;
    3)
    wireguard_remove
    ;;
    4)
    add_user
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo -e "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
