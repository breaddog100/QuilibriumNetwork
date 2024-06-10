#!/bin/bash

# 节点安装功能
function install_node() {
	
	# 获取内存大小（单位：GB）
	mem_size=$(free -g | grep "Mem:" | awk '{print $2}')
	
	# 获取当前swap大小（单位：GB）
	swap_size=$(free -g | grep "Swap:" | awk '{print $2}')
	
	# 计算期望的swap大小（内存的两倍或者24GB中的较小者）
	desired_swap_size=$((mem_size * 2))
	if ((desired_swap_size >= 32)); then
	    desired_swap_size=32
	fi
	
	# 检查当前swap大小是否满足要求
	if ((swap_size < desired_swap_size)) && ((swap_size < 32)); then
	    echo "当前swap大小不足。正在将swap大小设置为 $desired_swap_size GB..."
	
	    # 关闭所有swap分区
	    sudo swapoff -a
	
	    # 分配新的swap文件
	    sudo fallocate -l ${desired_swap_size}G /swapfile
	
	    # 设置正确的文件权限
	    sudo chmod 600 /swapfile
	
	    # 设置swap分区
	    sudo mkswap /swapfile
	
	    # 启用swap分区
	    sudo swapon /swapfile
	
	    # 添加swap分区至fstab，确保开机时自动挂载
	    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
	
	    echo "Swap大小已设置为 $desired_swap_size GB。"
	else
	    echo "当前swap大小已经满足要求或大于等于32GB，无需改动。"
	fi
	
    sudo apt update
    sudo apt install -y git ufw bison screen binutils gcc make bsdmainutils jq coreutils

	# 设置缓存
	echo -e "\n\n# set for Quil" | sudo tee -a /etc/sysctl.conf
	echo "net.core.rmem_max=600000000" | sudo tee -a /etc/sysctl.conf
	echo "net.core.wmem_max=600000000" | sudo tee -a /etc/sysctl.conf
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
	export GOROOT_BOOTSTRAP=$GOROOT
	gvm install go1.22.4
	gvm use go1.22.4
	
	# 克隆仓库
	git clone https://source.quilibrium.com/quilibrium/ceremonyclient.git
	cd $HOME/ceremonyclient/
	git switch release

    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.19-linux-amd64
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient

	rm $HOME/go/bin/qclient
	cd $HOME/ceremonyclient/client
	GOEXPERIMENT=arenas go build -o $HOME/go/bin/qclient main.go
	# building grpcurl
	cd ~
	go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

	echo "部署完成"
}

# 提取秘钥
function backup_key(){
    # 文件路径
    sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
    cd $HOME/ceremonyclient/node/.config/
    # 检查是否安装了zip
	if ! command -v zip &> /dev/null; then
	    echo "zip is not installed. Installing now..."
	    sudo apt-get update
	    sudo apt-get install zip -y
	fi
	
	# 创建压缩文件
	zip -r ~/quil_bak_$(date +%Y%m%d).zip config.yml keys.yml store
	echo "已将config.yml、keys.yml和目录store压缩并保存到$HOME下"

}

# 查看日志
function view_logs(){
	sudo journalctl -u ceremonyclient.service -f --no-hostname -o cat
}

# 查看节点状态
function view_status(){
	sudo systemctl status ceremonyclient
}

# 停止节点
function stop_node(){
	sudo systemctl stop ceremonyclient
	ps aux | grep 'node-' | grep -v grep | awk '{print $2}' | sudo xargs kill -9
	echo "quil 节点已停止"
}

# 启动节点
function start_node(){
	sudo systemctl start ceremonyclient
	echo "quil 节点已启动"
}

# 卸载节点
function uninstall_node(){
    #screen -S quil -X quit
    sudo systemctl stop ceremonyclient
    screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
	rm -rf $HOME/ceremonyclient
	rm -rf $HOME/check_and_restart.sh
	echo "卸载完成。"
}

# 查询节点信息
function check_node_info(){
	cd ~/ceremonyclient/node && ./node-1.4.19-linux-amd64 -node-info
	#echo "该命令目前官方提示在1.4.18无法执行，需要等待"
	echo "当前版本："
	cat ~/ceremonyclient/node/config/version.go | grep -A 1 'func GetVersion() \[\]byte {' | grep -Eo '0x[0-9a-fA-F]+' | xargs printf '%d.%d.%d'
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
        sudo unzip store.zip -d $HOME/ceremonyclient/node/.config/
    	start_node
    	#echo "快照已更新，超过30分钟高度没有增加请运行【10.更新REPAIR】文件"
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

# 查询余额
function check_balance(){
	cd ~/ceremonyclient/node && ./node-1.4.19-linux-amd64 -node-info
	
}

# 安装gRPC
function install_grpc(){
	# 检查当前 Go 版本
	current_go_version=$(go version | awk '{print $3}')
	
	# 解析版本号并比较
	if [[ "$current_go_version" < "go1.22.4" ]]; then
	  # 如果当前版本低于1.22.4，则使用 GVM 安装1.22.4
	  echo "当前 Go 版本为 $current_go_version，低于1.22.4，开始安装1.22.4版本..."
	  source $HOME/.gvm/scripts/gvm
	  gvm install go1.22.4
	  gvm use go1.22.4 --default
	else
	  echo "当前 Go 版本为 $current_go_version，不需要更新。"
	fi

	go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
	wget --no-cache -O - https://raw.githubusercontent.com/lamat1111/quilibriumscripts/master/tools/qnode_gRPC_calls_setup.sh | bash
	stop_node
	start_node
}

# 健康状态
function check_heal(){
	sudo journalctl -u ceremonyclient.service --no-hostname --since "today" | awk '/"current_frame"/ {print $1, $2, $3, $7}'
	echo "提取了当天的日志，如果current_frame一直在增加，说明程序运行正常"
}

# 升级程序
function update_quil(){
	stop_node
	# switch to Gitlab repo of Cassie
	cd ~/ceremonyclient
	git remote set-url origin https://source.quilibrium.com/quilibrium/ceremonyclient.git
	git pull
	# end of switch code block
	cd ~/ceremonyclient 
	git reset --hard origin/release-cdn
	git fetch --all
	git clean -df
	git merge origin/release-cdn
	cd ~/ceremonyclient/node
	sudo rm -f /lib/systemd/system/ceremonyclient.service
    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.19-linux-amd64
[Install]
WantedBy=multi-user.target
EOF
	sudo systemctl daemon-reload
	start_node
}

# 限制CPU使用率
function cpu_limited_rate(){
    read -p "输入每个CPU允许quil使用占比(如60%输入0.6，最大1):" cpu_rate
    comparison=$(echo "$cpu_rate >= 1" | bc)
    if [ "$comparison" -eq 1 ]; then
        cpu_rate=1
    fi
    
    cpu_core=$(lscpu | grep '^CPU(s):' | awk '{print $2}')
    limit_rate=$(echo "scale=2; $cpu_rate * $cpu_core * 100" | bc)
    echo "最终限制的CPU使用率为：$limit_rate%"
    echo "正在重启，请稍等..."
    
    stop_node
    sudo rm -f /lib/systemd/system/ceremonyclient.service
    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.19-linux-amd64
CPUQuota=$limit_rate%
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient
    echo "quil 节点已启动"
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium Network一键部署脚本==================="
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C24G300G"
		echo "查询余额请先运行【14.安装gRPC】只需运行一次，安装后等待30分钟再查询"
		echo "感谢以下无私的分享者："
    	echo "yann 协助社区升级1.4.18-p2"
    	echo "===================桃花潭水深千尺，不及汪伦送我情====================="
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 备份秘钥 backup_key"
	    echo "3. 查看状态 view_status"
	    echo "4. 查看日志 view_logs"
	    echo "5. 停止节点 stop_node"
	    echo "6. 启动节点 start_node"
	    echo "7. 节点信息 check_node_info"
	    echo "8. 卸载节点 uninstall_node"
	    echo "9. 查询余额 check_balance"
	    echo "10. 下载快照 download_snap"
	    echo "11. 运行状态 check_heal"
	    echo "12. 升级程序 update_quil"
	    echo "13. 限制CPU cpu_limited_rate"
	    echo "14. 安装gRPC install_grpc"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) backup_key ;;
	    3) view_status ;;
	    4) view_logs ;;
	    5) stop_node ;;
	    6) start_node ;;
	    7) check_node_info ;;
	    8) uninstall_node ;;
	    9) check_balance ;;
	    10) download_snap ;;
	    11) check_heal ;;
	    12) update_quil ;;
	    13) cpu_limited_rate ;;
	    14) install_grpc ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu