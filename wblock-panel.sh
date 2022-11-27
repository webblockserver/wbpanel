#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "Error:  This script must be run by the root user!\n" && exit 1

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
    LOGE "system version not detected, please rerun the script or contact us!\n" && exit 1
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
        LOGE "Please use CentOS 7 or later!\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        LOGE "Please use Ubuntu 16 or later!\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        LOGE "Please use Debian 8 or later!\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [default $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Do you want to restart the panel?(restarting the panel will also restart xray)" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press Enter to return to the main menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/webblockserver/wbpanel/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "This function will force the latest version to be reinstalled (the data will not be lost). Do you want to continue?" "n"
    if [[ $? != 0 ]]; then
        LOGE "canceled"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/webblockserver/wbpanel/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "Update is complete, panel has been automatically restarted"
        exit 0
    fi
}

uninstall() {
    confirm "Are you sure you want to uninstall the panel?(xray will also be uninstalled)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop wblock-panel
    systemctl disable wblock-panel
    rm /etc/systemd/system/wblock-panel.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /etc/wblock/
    rm -rf /usr/local/wblock/

    echo ""
    echo -e "uninstalled successfully, if you want to delete this script, exit the script and run ${green}rm -f /usr/bin/wblock${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config_user() {
    read -p "Enter new username: " config_account
    read -p "Enter new password: " config_password
    /usr/local/wblock/wblock setting -username ${config_account} -password ${config_password}
    echo -e "Restart panel."
    confirm_restart
}

reset_config() {
    confirm "Are you sure you want to reset all panel settings?(account data will not be lost, username and password will not change)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/wblock/wblock setting -reset
    echo -e "All panel settings have been reset to defaults, now please restart the panel and access the panel using the default ${green}1234${plain} port"
    confirm_restart
}

check_config() {
    info=$(/usr/local/wblock/wblock setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error, please check logs."
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "Enter the port number[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "canceled"
        before_show_menu
    else
        /usr/local/wblock/wblock setting -port ${port}
        echo -e "Now restart the panel and access the panel using the newly set port ${green}${port}${plain}"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "Panel is running, no need to start again, if you need to restart, please select Restart"
    else
        systemctl start wblock-panel
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "wblock started successfully"
        else
            LOGE "The panel failed to start, possibly because the startup time exceeded two seconds, please check the log information later"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "panel is stopped, no need to stop again"
    else
        systemctl stop wblock-panel
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "wblock and xray stopped successfully"
        else
            LOGE "Panel stop failed, probably because the stop time exceeded two seconds, please check the log information later"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart wblock-panel
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "wblock and xray reboot successful"
    else
        LOGE "Panel restart failed, may be because the boot time is more than two seconds, please check the log information later"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status wblock-panel -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable wblock-panel
    if [[ $? == 0 ]]; then
        LOGI "wblock set boot successfully"
    else
        LOGE "wblock set boot failed"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable wblock-panel
    if [[ $? == 0 ]]; then
        LOGI "wblock auto-start, canceled successfully"
    else
        LOGE "wblock cancel boot auto-start, failed"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u wblock-panel.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    # temporary work around for installing bbr
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/wblock -N --no-check-certificate https://github.com/webblockserver/wbpanel/raw/main/wblock-panel.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Download script failed, please check whether the machine can connect to Github"
        before_show_menu
    else
        chmod +x /usr/bin/wblock
        LOGI "Upgrade script was successful, please rerun the script" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/wblock-panel.service ]]; then
        return 2
    fi
    temp=$(systemctl status wblock-panel | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled wblock-panel)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "The panel is already installed, please do not install it again"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Please install the panel first"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "  panel status: ${green}Running${plain}"
        show_enable_status
        ;;
    1)
        echo -e "  panel status: ${yellow}not running${plain}"
        show_enable_status
        ;;
    2)
        echo -e "  panel status: ${red}not installed${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "  auto-start:   ${green}Enabled${plain}"
    else
        echo -e "  auto-start:   ${red}disabled${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "  xray status:  ${green}Running${plain}"
    else
        echo -e "  xray status:  ${red}not running${plain}"
    fi
}

ssl_cert_issue() {
    echo -E ""
    LOGD "******Instructions for use******"
    LOGI "This script will use the Acme script to apply for a certificate, and you need to ensure that:"
    LOGI "1. Know the registered email address of Cloudflare"
    LOGI "2. Know Cloudflare Global API Key"
    LOGI "3. The domain name has been resolved to the current server through Cloudflare"
    LOGI "4. The default installation path of this script certificate application is /root/cert directory"
    confirm "I have confirmed the above[y/n]" "y"
    if [ $? -eq 0 ]; then
        cd ~
        LOGI "Install Acme Script"
        curl https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            LOGE "failed to install acme script"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "Please set domain name"
        read -p "Input your domain here: " CF_Domain
        LOGD "Your domain name is set to: ${CF_Domain}"
        LOGD "Please set API key"
        read -p "Input your key here: " CF_GlobalKey
        LOGD "Your API key is: ${CF_GlobalKey}"
        LOGD "Please set registered email"
        read -p "Input your email here: " CF_AccountEmail
        LOGD "Your registered email address is: ${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "Failed to change default CA to Lets'Encrypt, script exited."
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "Certificate signing failed, script exited"
            exit 1
        else
            LOGI "Certificate issued successfully, installation..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "Certificate installation failed, script exited"
            exit 1
        else
            LOGI "Certificate installed successfully, turn on automatic updates..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Automatic update settings failed, script exited"
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "The certificate is installed and automatic updates are turned on, the details are below"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

show_usage() {
    echo "  wbPanel management script usage: "
    echo "  ------------------------------------------"
    echo "  wblock             - Show admin menu (more features)"
    echo "  wblock start       - Launches wbPanel"
    echo "  wblock stop        - Stop wbPanel"
    echo "  wblock restart     - Restart wbPanel"
    echo "  wblock status      - View wbPanel status"
    echo "  wblock enable      - Set wbPanel to start automatically"
    echo "  wblock disable     - Cancels wbPanel auto-start"
    echo "  wblock log         - View wbPanel logs"
    echo "  wblock update      - Update wbPanel"
    echo "  wblock install     - Installs wbPanel"
    echo "  wblock uninstall   - Uninstalls wbPanel"
    echo "  ------------------------------------------"
    echo ""
}

show_menu() {
    echo -e "
  ${yellow}wbPanel management script${plain}

  ${green}0.${plain}  exit script
  ——————————————
  ${green}1.${plain}  Install wbPanel
  ${green}2.${plain}  Update wbPanel
  ${green}3.${plain}  Uninstall wbPanel
  ——————————————
  ${green}4.${plain}  Change username & password
  ${green}5.${plain}  Reset panel settings
  ${green}6.${plain}  Set up panel ports
  ${green}7.${plain}  View current panel settings
  ——————————————
  ${green}8.${plain}  Start wbPanel
  ${green}9.${plain}  Stop wbPanel
  ${green}10.${plain} Restart wbPanel
  ${green}11.${plain} View wbPanel status
  ${green}12.${plain} View wbPanel logs
  ——————————————
  ${green}13.${plain} Set the wbPanel to start automatically
  ${green}14.${plain} Cancel wbPanel auto-start
  ——————————————
  ${green}15.${plain} One-click bbr installation (latest kernel)
  ${green}16.${plain} One-click SSL certificate application (acme application)
 "
    show_status
    echo && read -p "Please enter the option [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && config_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && show_log
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        install_bbr
        ;;
    16)
        ssl_cert_issue
        ;;
    *)
        LOGE "Please enter the correct number [0-16]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
