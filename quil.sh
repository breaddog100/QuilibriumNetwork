#!/bin/bash

# 节点安装功能
function install_node() {
	
	# 获取内存大小（单位：GB）
	mem_size=$(free -g | grep "Mem:" | awk '{print $2}')
	
	# 获取当前swap大小（单位：GB）
	swap_size=$(free -g | grep "Swap:" | awk '{print $2}')
	
	# 计算期望的swap大小（内存的两倍或者24GB中的较小者）
	desired_swap_size=$((mem_size * 2))
	if ((desired_swap_size >= 24)); then
	    desired_swap_size=24
	fi
	
	# 检查当前swap大小是否满足要求
	if ((swap_size < desired_swap_size)) && ((swap_size < 24)); then
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
	    echo "当前swap大小已经满足要求或大于等于24GB，无需改动。"
	fi
	
    sudo apt update
    sudo apt install -y git ufw bison screen binutils gcc make bsdmainutils jq

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
	
	# 克隆仓库
	git clone https://github.com/QuilibriumNetwork/ceremonyclient.git
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
ExecStart=$HOME/ceremonyclient/node/node-1.4.18-linux-amd64
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient

	rm $HOME/go/bin/qclient
	cd $HOME/ceremonyclient/client
	GOEXPERIMENT=arenas go build -o $HOME/go/bin/qclient main.go

	echo "部署完成"
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
	sudo journalctl -u ceremonyclient.service -f --no-hostname -o cat
}

# 查看节点状态
function view_status(){
	sudo systemctl status ceremonyclient
}

# 停止节点
function stop_node(){
	sudo systemctl stop ceremonyclient
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
	#source $HOME/.gvm/scripts/gvm
	#gvm use go1.20.2
	#cd $HOME/ceremonyclient/node/ && GOEXPERIMENT=arenas go run ./... -node-info
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
	source $HOME/.gvm/scripts/gvm
	gvm use go1.20.2
	cd "$HOME/ceremonyclient/client"
	# 设置文件路径
	FILE="$HOME/ceremonyclient/client/qclient"
	
	# 检查文件是否存在
	if [ ! -f "$FILE" ]; then
	    echo "文件不存在，正在尝试构建..."
	    # 运行go build命令来构建程序
	    GOEXPERIMENT=arenas go build -o qclient main.go
	    # 检查go build命令是否成功执行
	    if [ $? -eq 0 ]; then
	        echo "余额："
	        ./qclient token balance
	    else
	        echo "构建失败。"
	        exit 1
	    fi
	else
		echo "余额："
	    ./qclient token balance
	fi
}

function install_grpc(){
	# grpc
	go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
}

# 健康状态
function check_heal(){
	sudo journalctl -u ceremonyclient.service --no-hostname --since "today" | awk '/"current_frame"/ {print $1, $2, $3, $7}'
	echo "提取了当天的日志，如果current_frame一直在增加，说明程序运行正常"
}

# 升级程序
function update_quil(){
	stop_node
	cd ceremonyclient
	git remote remove origin
	git remote add origin https://source.quilibrium.com/quilibrium/ceremonyclient.git
	git pull origin main 
	#git reset --hard v1.4.18-p2
	start_node
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium Network一键部署脚本==================="
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C16G250G"
		echo "如果是老节点升级，请依次运行2备份秘钥，8卸载节点，1部署节点，然后再恢复秘钥"
		echo "感谢以下无私的分享者："
    	echo "yann 协助大家升级1.4.18-p2"
    	echo "===================桃花潭水深千尺，不及汪伦送我情====================="
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 提取秘钥 backup_key"
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
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu