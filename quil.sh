#!/bin/bash

# 设置版本号
current_version=20241209002

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
	echo "你确定要卸载节点程序吗？这将会删除所有相关的数据。[Y/N]"
	read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            sudo systemctl stop ceremonyclient
			screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
			rm -rf $HOME/ceremonyclient
			echo "卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
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
	node_file=$(last_bin_file "node")
	echo "查询余额："
	"$node_file" -node-info
	cd ~/ceremonyclient/client
	qclient_file=$(last_bin_file "qclient")
	"$qclient_file" --config $CONFIG_PATH token balance --public-rpc

}

# 安装gRPC
function install_grpc(){
	sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
	switch_rpc "0" 
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
		echo "已完成铸造，请使用如下钱包地址到网站查询余额，如果余额为0，说明还未同步到本地。"
		check_balance
	else
		echo "正在铸造，increment：$increment"
	fi
}

# 切换RPC
function switch_rpc(){
	cd $HOME/ceremonyclient/node/.config/ || exit
	# 文件路径
	FILE="config.yml"

	# 判断文件是否存在
	if [ -f "$FILE" ]; then
		if [ "$1" = "1" ]; then
			echo "切换为公共RPC"
			sed -i 's|listenGrpcMultiaddr: "/ip4/127.0.0.1/tcp/8337"|listenGrpcMultiaddr: ""|' config.yml
			sed -i 's|listenRESTMultiaddr: "/ip4/127.0.0.1/tcp/8338"|listenRESTMultiaddr: ""|' config.yml
		elif [ "$1" = "0" ]; then
			echo "切换为自有RPC"
			sed -i 's|listenGrpcMultiaddr: ""|listenGrpcMultiaddr: "/ip4/127.0.0.1/tcp/8337"|' config.yml
			sed -i 's|listenRESTMultiaddr: ""|listenRESTMultiaddr: "/ip4/127.0.0.1/tcp/8338"|' config.yml
			stop_node
			start_node
		else
			echo "切换RPC参数错误"
		fi
	else
		echo "配置文件不存在，请先启动节点，或检查$HOME/ceremonyclient/node/.config/config.yml是否存在"
	fi
	
}

# 代币转账
function coins_transfer(){
	# 转出操作
	read -p "请输入主钱包地址(0x开头):" main_wallet
	echo "开始转移..."
	stop_node
	#switch_rpc "1"
	CONFIG_PATH=$HOME/ceremonyclient/node/.config
	cd $HOME/ceremonyclient/client
	qclient_file=$(last_bin_file "qclient")
	coins_addr=$("$qclient_file" --config $CONFIG_PATH token coins | grep -o '0x[0-9a-fA-F]\+')
	"$qclient_file" token transfer $main_wallet $coins_addr --config $CONFIG_PATH --public-rpc
	echo "转移完成，请到主钱包中运行脚本16进行合并。"
}

# 转账检查
function check_pre_transfer(){
	echo ""
	echo "请先到主钱包机器获取主钱包地址(运行脚本14会看到0x开头的地址)"
	echo -e "${RED}本操作会把本机的代币转到你的主钱包地址中，请务必填写正确的主钱包地址，以防资产损失！${NC}"

	check_balance
	echo "上述查询中：balance和COINS都有值，且均大于0，才能转账，否则还需要等待继续铸造。"
	read -r -p "请确认：[Y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            coins_transfer
            ;;
        *)
            echo "取消操作。"
            ;;
    esac
}

# 代币合并
function coins_merge(){
	# 合并操作
	echo "开始合并..."
	#stop_node
	#switch_rpc "1"
	CONFIG_PATH=$HOME/ceremonyclient/node/.config
	cd $HOME/ceremonyclient/client
	qclient_file=$(last_bin_file "qclient")
	"$qclient_file" --config $CONFIG_PATH token merge all --public-rpc
	echo "完成合并，请到：https://quilibrium.com/bridge 查询。"
}

# 合并检查
function check_pre_merge(){
	echo ""
	echo -e "本操作请在${RED}主钱包机器上${NC}执行。"
	check_balance
	echo "上述查询中：balance和COINS都有值，且均大于0，才能归集，否则还需要等待继续铸造。"
	echo "本操作会把转账机器的代币合并到本机，会用到转账结束后输出的COINS地址。"
	echo "接下来脚本会：1，停止本机节点；2，切换到公共RPC；3，将转移到本机的代币合并到本机主钱包。"
	read -r -p "请确认：[Y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            coins_merge
            ;;
        *)
            echo "取消操作。"
            ;;
    esac
}

# 最新可执行文件
function last_bin_file(){

	case "$1" in
        node)
            # 找到最新节点程序
			cd ~/ceremonyclient/node
			# 定义可执行文件的目录
			DIR="./"  # 当前目录

			# 初始化最新版本变量和版本字符串
			latest_version=""
			latest_file=""

			# 遍历当前目录中的文件
			for file in "${DIR}"node-*-linux-amd64; do
				# 检查文件是否存在
				if [ -f "$file" ]; then
					# 提取版本号
					version=$(echo "$file" | sed -E 's/.*node-([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)-linux-amd64/\1/')
					
					# 如果找到了版本号，则比较版本
					if [[ -n "$version" ]]; then
						# 如果是第一次找到版本，或者找到的版本比当前最新版本更高
						if [ -z "$latest_version" ] || [ "$(printf '%s\n' "$version" "$latest_version" | sort -V | head -n1)" != "$version" ]; then
							latest_version="$version"
							latest_file="$file"
						fi
					fi
				fi
			done
			echo $latest_file
            ;;
        qclient)
            # 找到最新节点程序
			cd ~/ceremonyclient/client
			# 定义可执行文件的目录
			DIR="./"  # 当前目录

			# 初始化最新版本变量和版本字符串
			latest_version=""
			latest_file=""

			# 遍历当前目录中的文件
			for file in "${DIR}"qclient-*-linux-amd64; do
				# 检查文件是否存在
				if [ -f "$file" ]; then
					# 提取版本号
					version=$(echo "$file" | sed -E 's/.*qclient-([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)-linux-amd64/\1/')
					
					# 如果找到了版本号，则比较版本
					if [[ -n "$version" ]]; then
						# 如果是第一次找到版本，或者找到的版本比当前最新版本更高
						if [ -z "$latest_version" ] || [ "$(printf '%s\n' "$version" "$latest_version" | sort -V | head -n1)" != "$version" ]; then
							latest_version="$version"
							latest_file="$file"
						fi
					fi
				fi
			done
			echo $latest_file
            ;;
        *)
            echo "Unknown parameter: $1"
            return 1
            ;;
    esac
}

# 集群
# 生成集群配置文件
function generator_cluster_config() {
    echo "按照提示输入集群基本情况，脚本会生成集群的配置文件，将生成的配置文件上传到管理节点和所有的工作节点中"
    # 输入工作节点数量
    read -p "请输入工作节点数量: " worker_num
	# 初始化端口号
    port_num=40000
	# 初始化工作节点配置项 替换空格的符号
	worker_addrs="  dataWorkerMultiaddrs:\n"

    # 校验worker_num类型是否为整数
    if ! [[ "$worker_num" =~ ^[0-9]+$ ]]; then
        echo "错误: 工作节点数量必须是一个整数."
        return 1  # 返回错误代码
    fi

    # 循环worker_num次，分别输入core_num参数
    for ((i=1; i<=worker_num; i++)); do
        read -p "请输入第 $i 个工作节点的 IP 地址: " worker_ip
		read -p "请输入第 $i 个工作节点的 core_num: " core_num
		
        # 可以在这里添加对core_num的校验
        if ! [[ "$core_num" =~ ^[0-9]+$ ]]; then
            echo "错误: core_num必须是一个整数."
            return 1  # 返回错误代码
        fi

		echo "第 $i 个工作节点 $worker_ip ,核心数: $core_num"

		worker_addrs="$worker_addrs# Node $i - $worker_ip\n"

		for ((j=1; j<=core_num; j++)); do
			# \t 改为2个空格
            worker_addrs="$worker_addrs\t- /ip4/$worker_ip/tcp/$port_num\n"
            port_num=$((port_num+1))

            # 输出 worker_addrs，测试后关闭
            printf "$worker_addrs"

        done
        
    done

	# 将配置项输出到文件
	echo $worker_addrs>~/config_for_cluster.yml
    echo "已经生成集群配置文件：config_for_cluster.yml，并保存在当前目录下"
	echo "请将ceremonyclient/node/.config/config.yml中的dataWorkerMultiaddrs[]替换为config_for_cluster.yml中的内容"
	echo "切记，修改配置文件前先备份！"
}

# 启动worker
function start_worker(){
	echo "启动worker，启动脚本基于官方社区教程中的脚本修改而成"
	# 下载启动脚本并启动
	curl ...
	node_file=$(last_bin_file "node")
	./start_cluster.sh --core-index-start $x --data-worker-count $y --node_binary $node_file
}

# 启动master
function start_master(){
	echo "启动master，启动脚本基于官方社区教程中的脚本修改而成"
	# 下载启动脚本并启动
	curl ...
	node_file=$(last_bin_file "node")
	./start_cluster.sh --core-index-start $x --data-worker-count $y --node_binary $node_file
}

# 启动cluster
function start_cluster(){
	read -r -p "请确定所有的工作节点均已启动：[Y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            start_master
            ;;
        *)
            echo "取消操作。"
            ;;
    esac
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium Network一键部署脚本==================="
		echo "当前版本：$current_version"
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C24G300G;CPU核心越多越好"
		echo "Contabo机器如果无法安装请先运行【修复contabo】"
		echo "感谢以下无私的分享者："
    	echo "yann 协助社区升级1.4.18-p2"
		echo "@defeaty 协助社区解决2.0.4.2国内节点卡块问题"
    	echo "===================桃花潭水深千尺，不及汪伦送我情===================="
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 备份节点 backup_key"
	    echo "3. 查看状态 view_status"
	    echo "4. 查看日志 view_logs"
	    echo "5. 停止节点 stop_node"
	    echo "6. 启动节点 start_node"
	    echo "7. 查询余额 check_balance"
	    echo "8. 更新程序 download_node_and_qclient"
	    echo "9. 限制CPU cpu_limited_rate"
	    echo "10. 安装gRPC install_grpc"
	    echo "11. 修复contabo contabo"
		echo "12. 公共RPC switch_rpc"
		#echo "13. 监控同步状态 qnode_check_for_frames"
		echo "14. 铸造进度 mining_status"
		echo "15. 代币转账(在子钱包运行) check_pre_transfer"
		echo "16. 代币合并(在主钱包运行) check_pre_merge"
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
		12) switch_rpc "1" ;;
		13) qnode_check_for_frames ;;
		14) mining_status ;;
		15) check_pre_transfer ;;
		16) check_pre_merge ;;
		17) generator_cluster_config ;;
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