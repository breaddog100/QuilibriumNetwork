#!/bin/bash

# 定义日志文件的位置
LOGFILE="/var/log/my_program.log"

# 获取当前时间
NOW=$(date '+%F %T')

# 检查程序是否正在运行
#process=$(ps -ef | grep '/tmp/go-build' | grep -v grep)
process=$(screen -ls | grep 'quil')

# 如果进程不存在，则重启程序
if [ -z "$process" ]; then
    echo "${NOW} - 程序未运行，正在尝试重启..." | tee -a "$LOGFILE"

    # 环境设定
    source /root/.gvm/scripts/gvm
    gvm use go1.4
    export GOROOT_BOOTSTRAP=$GOROOT
    gvm use go1.17.13
    export GOROOT_BOOTSTRAP=$GOROOT
    gvm use go1.20.2

    # 进入程序目录
    cd /root/ceremonyclient/node

    # 启动程序
    screen -dmS quil bash -c './poor_mans_cd.sh'

    # 记录重启操作
    if [ $? -eq 0 ]; then
        echo "${NOW} - 程序重启成功。" | tee -a "$LOGFILE"
    else
        echo "${NOW} - 程序重启失败！" | tee -a "$LOGFILE"
    fi
else
    # 程序正在运行，记录状态
    echo "${NOW} - 程序正在运行。" | tee -a "$LOGFILE"
fi