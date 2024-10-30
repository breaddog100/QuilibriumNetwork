#!/bin/bash

# 设置版本号
current_version=20241030002

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/QuilibriumNetwork/main/quil.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

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
    sudo apt install -y git ufw bison screen binutils gcc make bsdmainutils jq coreutils unzip zip

	# 设置缓存
	echo -e "\n\n# set for Quil" | sudo tee -a /etc/sysctl.conf
	echo "net.core.rmem_max=600000000" | sudo tee -a /etc/sysctl.conf
	echo "net.core.wmem_max=600000000" | sudo tee -a /etc/sysctl.conf
	sudo sysctl -p

	# 安装 go
	wget https://go.dev/dl/go1.22.4.linux-amd64.tar.gz
	sudo tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
	export PATH=$PATH:/usr/local/go/bin
	echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
	source ~/.bashrc
	go version
	
	# github仓库
	git clone https://github.com/QuilibriumNetwork/ceremonyclient.git
	cd $HOME/ceremonyclient/
	git pull
	git checkout release
	
    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/release_autorun.sh
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

# 备份节点
function backup_key(){
    # 文件路径
    sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
    cd $HOME/ceremonyclient/node/
    # 检查是否安装了zip
	if ! command -v zip &> /dev/null; then
	    echo "zip is not installed. Installing now..."
	    sudo apt-get update
	    sudo apt-get install zip -y
	fi
	
	# 创建压缩文件
	zip -r ~/quil_bak_$(hostname)_$(date +%Y%m%d%H%M%S).zip .config
	echo "已将 .config目录压缩并保存到$HOME下"

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
	if systemctl list-unit-files | grep -q 'ceremonyclient14211\.service'; then
		sudo systemctl stop ceremonyclient14211
	fi
	echo "quil 节点已停止"
}

# 启动节点
function start_node(){
	sudo systemctl start ceremonyclient
	echo "quil 节点已启动"
}

# 卸载节点
function uninstall_node(){
    sudo systemctl stop ceremonyclient
    screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
	rm -rf $HOME/ceremonyclient
	rm -rf $HOME/check_and_restart.sh
	echo "卸载完成。"
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

# 节点信息
function node_info(){
	sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
	check_grpc
	cd ~/ceremonyclient/node
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
	output=$(./node-2.0.0.7-linux-amd64 -node-info)
	peerid=$(echo "$output" | awk '/Peer ID:/ {print $3}')
	balance=$(echo "$output" | awk '/Owned balance:/ {print $3, $4}')
	cpu_usage=$(top -bn 1 | grep "%Cpu(s)" | awk '{print $2}')
	./node-2.0.0.7-linux-amd64 -node-info
	echo "查询时间:$current_time,PeerID:$peerid,CPU使用率:$cpu_usage%,当前余额:$balance"
}

# 查询余额
function check_balance(){
	sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
	cd ~/ceremonyclient/node
	./../client/qclient-2.0.2.3-linux-amd64 token balance
}

# 安装gRPC
function install_grpc(){
	sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
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

# 检查grpc
check_grpc() {
	cpu_usage=$(top -bn 1 | grep "%Cpu(s)" | awk '{print $2}')
	if (( $(echo "$cpu_usage > 80" | bc -l) )); then
		echo "quil已启动"
		if ! sudo lsof -i :8337 > /dev/null; then
			echo "grpc未启用，正在安装"
			install_grpc
		fi
	else
		echo "quil未启动"
		start_node
	fi
    
}

# 健康状态
function check_heal(){
	sudo journalctl -u ceremonyclient.service --no-hostname --since "today" | awk '/"current_frame"/ {print $1, $2, $3, $7}'
	echo "提取了当天的日志，如果current_frame一直在增加，说明程序运行正常"
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
ExecStart=$HOME/ceremonyclient/node/release_autorun.sh
CPUQuota=$limit_rate%
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient
    sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
    echo "quil 节点已启动"
}

# contabo
function contabo(){
	echo "DNS=8.8.8.8 8.8.4.4" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
	sudo systemctl restart systemd-resolved
	echo "已修复contabo网络"
}

function download_node_and_qclient(){
	
	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    release_os="linux"
    if [[ $(uname -m) == "aarch64"* ]]; then
        release_arch="arm64"
    else
        release_arch="amd64"
    fi
	else
		release_os="darwin"
		release_arch="arm64"
	fi

	is_update=0

	cd $HOME/ceremonyclient/client/
	for files in $(curl -s https://releases.quilibrium.com/qclient-release | grep $release_os-$release_arch); do
		echo "检查文件: $files"
		
		if [ -f "$files" ]; then
			echo "文件: $files 已存在"
		else
			echo "下载文件: $files"
			curl -s -O "https://releases.quilibrium.com/$files"

			version=$(echo "$files" | cut -d '-' -f 2)
			if [ "$files" == "qclient-$version-$release_os-$release_arch" ]; then
				chmod +x "$files"
			fi
		fi

	done

	cd $HOME/ceremonyclient/node/
	for files in $(curl -s https://releases.quilibrium.com/release | grep $release_os-$release_arch); do
		echo "检查文件: $files"
		
		if [ -f "$files" ]; then
			echo "文件: $files 已存在"
		else
			is_update=1
			echo "下载文件: $files"
			curl -s -O "https://releases.quilibrium.com/$files"

			version=$(echo "$files" | cut -d '-' -f 2)
			if [ "$files" == "node-$version-$release_os-$release_arch" ]; then
				chmod +x "$files"
			fi
		fi

	done

	if [ "$is_update" -eq 1 ]; then
		echo "更新完成，正在重启..."
		stop_node
		start_node
	else
		echo "当前程序已经是最新，无需更新..."
	fi
	
}

function start_node_14211(){
	echo "此功能会先停止当前运行的quil，然后启动1.4.21.1程序。"
	echo "期间请留意2.0是否能运行，如果能运行则请运行脚本5停止节点，然后脚本6启动脚本即可。"
	stop_node
	cd $HOME/ceremonyclient/node/
	files=(
	"node-1.4.21.1-linux-amd64"
	"node-1.4.21.1-linux-amd64.dgst.sig.13"
	"node-1.4.21.1-linux-amd64.dgst.sig.17"
	"node-1.4.21.1-linux-amd64.dgst.sig.8"
	"node-1.4.21.1-linux-amd64.dgst"
	"node-1.4.21.1-linux-amd64.dgst.sig.15"
	"node-1.4.21.1-linux-amd64.dgst.sig.2"
	"node-1.4.21.1-linux-amd64.dgst.sig.9"
	"node-1.4.21.1-linux-amd64.dgst.sig.1"
	"node-1.4.21.1-linux-amd64.dgst.sig.16"
	"node-1.4.21.1-linux-amd64.dgst.sig.3"
	)

	for file in "${files[@]}"; do
	if [ -e "$file" ]; then
		echo "文件 $file 已存在，跳过"
	else
		echo "正在下载文件：$file"
		curl -s -O "https://releases.quilibrium.com/$file"
	fi
	done

	sudo chmod +x node-1.4.21.1-linux-amd64

	if systemctl list-unit-files | grep -q 'ceremonyclient14211\.service'; then
		sudo systemctl start ceremonyclient14211
	else
		sudo tee /lib/systemd/system/ceremonyclient14211.service > /dev/null <<EOF
[Unit]
Description=Ceremony14211 Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.21.1-linux-amd64
[Install]
WantedBy=multi-user.target
EOF
		sudo systemctl daemon-reload
		sudo systemctl start ceremonyclient14211
	fi

	echo "Quil 1.4.21.1 已启动"
	echo "查看日志：sudo journalctl -u ceremonyclient14211.service -f --no-hostname -o cat"
	echo "查看余额：cd $HOME/ceremonyclient/node && ./node-1.4.21.1-linux-amd64 -node-info"

}

# 检查frames同步状态

install_dependencies() {
	local pkg_name
	echo -e "${YELLOW}安装依赖包：${NC}"
	sudo apt update -qq
	
	for pkg_name in "jq" "bc" "cron"; do
		if ! sudo apt install -y "$pkg_name"; then
			echo -e "${RED}安装失败 $pkg_name${NC}"
			return 1
		fi
		echo -e "${GREEN}$pkg_name 安装成功${NC}"
	done
	
	echo
	sleep 1
	return 0
}

function qnode_check_for_frames(){

	echo -e "${GREEN}此功能会监控同步状态，如果超过60分钟没有同步则会重启节点${NC}"
	sleep 5

	FILE="${HOME}/scripts/qnode_check_for_frames.sh"

	if [ -f "$FILE" ]; then
		CRON_JOB="*/60 * * * * sudo ${HOME}/scripts/qnode_check_for_frames.sh"

		if crontab -l | grep -qF "$CRON_JOB"; then
			:
		else
			(crontab -l 2>/dev/null; echo "*/60 * * * * sudo ${HOME}/scripts/qnode_check_for_frames.sh") | crontab -
		fi
		echo "已设置每隔60分钟检查一次同步状态"
		
	else
		echo "正在停止节点..."
		stop_node
		download_node_and_qclient
		mkdir -p ~/scripts

		# Install dependencies
		if ! install_dependencies; then
			exit 1
		fi
		if ! curl -sSL "https://raw.githubusercontent.com/lamat1111/QuilibriumScripts/main/test/qnode_check_for_frames.sh" -o ~/scripts/qnode_check_for_frames.sh; then
			echo -e "${RED}脚本下载失败${NC}"
			exit 1
		fi
		echo -e "${GREEN}脚本下载成功${NC}"
		echo
		sleep 1
		if ! chmod +x ~/scripts/qnode_check_for_frames.sh; then
			echo -e "${RED}Failed to make script executable${NC}"
			exit 1
		fi
		(crontab -l 2>/dev/null; echo "*/60 * * * * sudo ${HOME}/scripts/qnode_check_for_frames.sh") | crontab -
		start_node

		echo -e "${GREEN}已设置为每隔60分钟检查一次同步状态，如果未同步则会重启节点，运行情况请查看日志文件：${HOME}/scripts/logs/qnode_check_for_frames.log${NC}"
		
	fi
}

# 铸造进度
function mining_status(){
	# 获取最后一条日志记录中包含 "increment" 的行
	last_log=$(journalctl -u ceremonyclient.service --no-hostname -g "increment" -r -n 1)

	# 提取 increment 的值
	increment=$(echo "$last_log" | grep -o '"increment":[0-9]*' | awk -F: '{print $2}')

	# 判断 increment 的值并输出相应的信息
	if [ "$increment" -eq 0 ]; then
		echo "已完成铸造，请使用如下钱包地址到网站查询余额，虽然余额显示0，但仍然是完成了铸造。"
		check_balance
	else
		echo "正在铸造，仍需努力，increment：$increment"
	fi
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium Network一键部署脚本==================="
		echo "当前版本：$current_version"
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C24G300G;CPU核心越多越好"
		echo "查询余额请先运行【安装gRPC】只需运行一次，安装后等待30分钟再查询"
		echo "Contabo机器如果无法安装请先运行【修复contabo】"
		echo "感谢以下无私的分享者："
    	echo "yann 协助社区升级1.4.18-p2"
    	echo "===================桃花潭水深千尺，不及汪伦送我情===================="
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 备份节点 backup_key"
	    echo "3. 查看状态 view_status"
	    echo "4. 查看日志 view_logs"
	    echo "5. 停止节点 stop_node"
	    echo "6. 启动节点 start_node"
	    echo "7. 查询余额 check_balance"
	    echo "8. 升级2.0 download_node_and_qclient"
	    echo "9. 限制CPU cpu_limited_rate"
	    echo "10. 安装gRPC install_grpc"
	    echo "11. 修复contabo contabo"
		echo "12. 运行1.4.21.1程序 start_node_14211"
		echo "13. 监控同步状态 qnode_check_for_frames"
		echo "14. 铸造进度 mining_status"
	    echo "1618. 卸载节点 uninstall_node"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) backup_key ;;
	    3) view_status ;;
	    4) view_logs ;;
	    5) stop_node ;;
	    6) start_node ;;
	    7) check_balance ;;
	    8) download_node_and_qclient ;;
	    9) cpu_limited_rate ;;
	    10) install_grpc ;;
	    11) contabo ;;
		12) start_node_14211 ;;
		13) qnode_check_for_frames ;;
		14) mining_status ;;
	    1618) uninstall_node ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 检查更新
update_script

case "$1" in
    balance)
        check_balance
        ;;
    backup)
        backup_key
        ;;
    help)
        echo "用法: $0 {balance|backup}"
        exit 1
        ;;
    *)
        main_menu
        ;;
esac