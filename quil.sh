#!/bin/bash

# 节点安装功能
function install_node() {
	
	# 获取内存大小（单位：GB）
	mem_size=$(free -g | grep "Mem:" | awk '{print $2}')
	
	# 获取当前swap大小（单位：GB）
	swap_size=$(free -g | grep "Swap:" | awk '{print $2}')
	
	# 计算期望的swap大小（内存的两倍）
	desired_swap_size=$((mem_size * 2))
	
	# 检查当前swap大小是否为内存的两倍
	if [[ $swap_size -ne $desired_swap_size ]]; then
	    echo "当前swap小。正在将swap大小设置为 $desired_swap_size GB..."
	
	    # 如果当前没有swap，创建一个新的swap文件
	    if [[ $swap_size -eq 0 ]]; then
	        sudo fallocate -l ${desired_swap_size}G /swapfile
	        sudo chmod 600 /swapfile
	        sudo mkswap /swapfile
	        sudo swapon /swapfile
	        echo '/swapfile none swap sw 0 0' >> /etc/fstab
	    else
	        # 如果swap已存在，先关闭再重新设置大小
	        sudo swapoff -a
	        sudo fallocate -l ${desired_swap_size}G /swapfile
	        sudo chmod 600 /swapfile
	        sudo mkswap /swapfile
	        sudo swapon -a
	        echo '/swapfile none swap sw 0 0' >> /etc/fstab
	    fi
	
	    echo "Swap大小已设置为 $desired_swap_size GB。"
	else
	    echo "Swap已经设置为内存的两倍。"
	fi
	
    sudo apt update
    sudo apt install -y git ufw bison screen binutils gcc make bsdmainutils

	# 设置缓存
	sudo echo -e "\n\n# set for Quil " >> /etc/sysctl.conf
	sudo echo "net.core.rmem_max=600000000" >> /etc/sysctl.conf
	sudo echo "net.core.wmem_max=600000000" >> /etc/sysctl.conf
	sudo sysctl -p

	# 安装GVM
	bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
	source $HOME/.gvm/scripts/gvm
	
	gvm install go1.4 -B
	gvm use go1.4
	export GOROOT_BOOTSTRAP=$GOROOT
	gvm install go1.17.13
	gvm use go1.17.13
	export GOROOT_BOOTSTRAP=$GOROOT
	gvm install go1.20.2
	gvm use go1.20.2
	
	# 克隆仓库
	git clone https://github.com/quilibriumnetwork/ceremonyclient
	cd ceremonyclient/node 
	chmod +x poor_mans_cd.sh
	
	# 运行
	screen -dmS quil bash -c './poor_mans_cd.sh'

	# 设置守护
	script_path="$HOME/check_and_restart.sh"
	wget -O $script_path https://raw.githubusercontent.com/breaddog100/QuilibriumNetwork/main/check_and_restart.sh && chmod +x $script_path
	(crontab -l 2>/dev/null; echo "*/30 * * * * $script_path") | crontab -

	echo "部署完成，然后开始挖矿"
}

# 提取秘钥
function backup_key(){

    # 文件路径
	file_path_keys="$HOME/ceremonyclient/node/.config/keys.yml"
	file_path_config="$HOME/ceremonyclient/node/.config/config.yml"
	
	# 检查文件是否存在
	if [ -f "$file_path_keys" ]; then
	    echo "keys文件已生成，路径为: $file_path_keys，请尽快备份"
	else
	    echo "keys文件未生成，请等待..."
	fi
	# 检查文件是否存在
	if [ -f "$file_path_config" ]; then
	    echo "config文件已生成，路径为: $file_path_config，请尽快备份"
	else
	    echo "config文件未生成，请等待..."
	fi

}

# 查看日志
function view_logs(){
	clear
	echo "3秒后进入screen，查看完请ctrl + a + d 退出"
	sleep 3
	screen -r quil
}

# 查看节点状态
function view_status(){
	
	quil_log="/var/log/my_program.log"
	if [ -f "$quil_log" ]; then
	tail -96 $quil_log
	else
		echo "日志文件需要30分钟后生成请等待..."
	fi
}

# 停止节点
function stop_node(){
	screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
	echo "quil 节点已停止"
}

# 启动节点
function start_node(){
	$HOME/check_and_restart.sh
	echo "quil 节点已启动"
}

# 卸载节点
function uninstall_node(){

    #screen -S quil -X quit
    screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
	rm -rf $HOME/ceremonyclient
	rm -rf $HOME/check_and_restart.sh
	echo "卸载完成。"

}

# 查询Peer ID
function check_peer_id(){
	source /root/.gvm/scripts/gvm
	gvm use go1.20.2
	cd $HOME/ceremonyclient/node/ && GOEXPERIMENT=arenas go run ./... -peer-id
	echo "浏览器打开：https://quilibrium.com/rewards/ ，在左侧输入Peer ID查询"
}

# 下载快照
function download_snap(){
	echo "快照文件较大，下载需要较长时间，请保持电脑屏幕不要熄灭"
    # 下载快照
    if wget -P $HOME/ https://snapshots.cherryservers.com/quilibrium/store.zip ;
    then
    	# 检查unzip是否已安装
		if ! command -v unzip &> /dev/null
		then
		    # 安装unzip
		    sudo apt-get update && sudo apt-get install -y unzip
		    if [ $? -eq 0 ]; then
		        echo "unzip has been successfully installed."
		    else
		        echo "Failed to install unzip. Please check your package manager settings."
		        exit 1
		    fi
		else
		    echo "unzip is already installed."
		fi
        stop_node
        unzip store.zip -d $HOME/ceremonyclient/node/.config/
    	start_node
    	echo "快照已更新，超过30分钟高度没有增加请运行10.更新REPAIR文件"
    else
        echo "下载失败。"
        exit 1
    fi
}

# 更新REPAIR
function update_repair(){
	echo "快照文件较大，下载需要较长时间，请保持电脑屏幕不要熄灭"
    # 备份REPAIR
    stop_node
    cp $HOME/ceremonyclient/node/.config/REPAIR $HOME/REPAIR.bak
    # 下载REPAIR
    if wget -O $HOME/ceremonyclient/node/.config/REPAIR 'https://2040319038-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FwYHoFaVat0JopE1zxmDI%2Fuploads%2FJL4Ytu5OIWHbisIbZs8v%2FREPAIR?alt=media&token=d080b681-ee26-470c-baae-4723bcf018a3' ;
    then
    	start_node
    	echo "REPAIR已更新..."
    else
        echo "下载失败。"
        exit 1
    fi
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium Network一键部署脚本==================="
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C16G250G"
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 提取秘钥 backup_key"
	    echo "3. 查看状态 view_status"
	    echo "4. 查看日志 view_logs"
	    echo "5. 停止节点 stop_node"
	    echo "6. 启动节点 start_node"
	    echo "7. 查询PeerID check_peer_id"
	    echo "8. 卸载节点 uninstall_node"
	    echo "9. 下载快照 download_snap"
	    echo "10. 更新REPAIR update_repair"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) backup_key ;;
	    3) view_status ;;
	    4) view_logs ;;
	    5) stop_node ;;
	    6) start_node ;;
	    7) check_peer_id ;;
	    8) uninstall_node ;;
	    9) download_snap ;;
	    10) update_repair ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu