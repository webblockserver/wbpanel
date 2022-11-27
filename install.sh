#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error：${plain} This script must be run by the root user!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}system version not detected, please rerun the script or contact us！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
else
    arch="amd64"
    echo -e "${red}failed to detect schema, using default schema: ${arch}${plain}"
fi

echo "schema: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "This software does not support 32-bit systems (x86), please use a 64-bit system (x86_64), if the detection is incorrect, please rerun the script or contact us."
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or later!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or later!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or later!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed wblock out of sercurity
config_after_install() {
    echo -e "${yellow}For security reasons, it is necessary to forcibly modify the port and account password after the installation/update is completed${plain}"
    read -p "Do you want to continue?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Please set your account name:" config_account
        echo -e "${yellow}Your account name will be set to:${config_account}${plain}"
        read -p "Please set your account password:" config_password
        echo -e "${yellow}Your account password will be set to:${config_password}${plain}"
        read -p "Please set panel access port:" config_port
        echo -e "${yellow}Your panel access port will be set to:${config_port}${plain}"
        echo -e "${yellow}confirms setting...${plain}"
        /usr/local/wblock/wblock setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}account password setting${plain}"
        /usr/local/wblock/wblock setting -port ${config_port}
        echo -e "${yellow}panel port setting${plain}"
    else
        echo -e "${red}has been canceled, all setting items are default settings, please modify in time${plain}"
    fi
}

install_wblock() {
    systemctl stop wblock-panel
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/webblockserver/wbpanel/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}failed to detect wblock version, possibly exceeding Github API limits, please try again later, or manually specify wblock version to install${plain}"
            exit 1
        fi
        echo -e "Detected latest version of wblock：${last_version}， start installation"
        wget -N --no-check-certificate -O /usr/local/wbpanel-linux-${arch}.tar.gz https://github.com/webblockserver/wbpanel/releases/download/${last_version}/wbpanel-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}failed to download wblock, make sure your server can download the Github file${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/webblockserver/wbpanel/releases/download/${last_version}/wbpanel-linux-${arch}.tar.gz"
        echo -e "Start installing wblock v$1"
        wget -N --no-check-certificate -O /usr/local/wbpanel-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}failed to download wblock v$1, make sure exists for this version${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/wblock/ ]]; then
        rm -rf /usr/local/wblock/
    fi

    tar -xvf wbpanel-linux-${arch}.tar.gz
    rm -f wbpanel-linux-${arch}.tar.gz
    cd wblock
    chmod +x wblock bin/xray-linux-${arch}
    cp -f wblock-panel.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/wblock https://raw.githubusercontent.com/webblockserver/wbpanel/main/wblock-panel.sh
    chmod +x /usr/local/wblock/wblock-panel.sh
    chmod +x /usr/bin/wblock
    config_after_install

    systemctl daemon-reload
    systemctl enable wblock-panel
    systemctl start wblock-panel
    echo -e "${green}wblock v${last_version}${plain} installation complete, panel started，"
    echo -e ""
    echo -e "wbPanel manual: "
    echo -e "----------------------------------------------"
    echo -e "wblock              - Show admin menu (more features)"
    echo -e "wblock start        - Launches wbPanel"
    echo -e "wblock stop         - Stop wbPanel"
    echo -e "wblock restart      - Restart wbPanel"
    echo -e "wblock status       - View wbPanel status"
    echo -e "wblock enable       - Set wbPanel to start automatically"
    echo -e "wblock disable      - Cancels wbPanel auto-start"
    echo -e "wblock log          - View wbPanel logs"
    echo -e "wblock update       - Update wbPanel"
    echo -e "wblock install      - Installs wbPanel"
    echo -e "wblock uninstall    - Uninstall wbPanel"
    echo -e "----------------------------------------------"
}

echo -e "${green}start installation...${plain}"
install_base
install_wblock $1
