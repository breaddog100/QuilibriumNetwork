#!/bin/bash
# start-cluster.sh

START_CORE_INDEX=1
DATA_WORKER_COUNT=$(nproc)
PARENT_PID=$$

# Get the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Some variables for paths and binaries
QUIL_NODE_PATH="$SCRIPT_DIR/ceremonyclient/node"
QUIL_NODE_CONFIG=$QUIL_NODE_PATH/.config/
NODE_BINARY=node-2.0.5-linux-amd64

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --op)
            OP="$2"
            shift 2
            ;;
        --core-index-start)
            START_CORE_INDEX="$2"
            shift 2
            ;;
        --data-worker-count)
            DATA_WORKER_COUNT="$2"
            shift 2
            ;;
        --node_binary)
            NODE_BINARY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate START_CORE_INDEX
if ! [[ "$START_CORE_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Error: --core-index-start must be a non-negative integer"
    exit 1
fi

# Validate DATA_WORKER_COUNT
if ! [[ "$DATA_WORKER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --data-worker-count must be a positive integer"
    exit 1
fi

# Get the maximum number of CPU cores
MAX_CORES=$(nproc)

# Adjust DATA_WORKER_COUNT if START_CORE_INDEX is 1
if [ "$START_CORE_INDEX" -eq 1 ]; then
    # Adjust MAX_CORES if START_CORE_INDEX is 1
    echo "Adjusting max cores available to $((MAX_CORES - 1)) (from $MAX_CORES) due to starting the master node on core 0"
    MAX_CORES=$((MAX_CORES - 1))
fi

# If DATA_WORKER_COUNT is greater than MAX_CORES, set it to MAX_CORES
if [ "$DATA_WORKER_COUNT" -gt "$MAX_CORES" ]; then
    DATA_WORKER_COUNT=$MAX_CORES
    echo "DATA_WORKER_COUNT adjusted down to maximum: $DATA_WORKER_COUNT"
fi

MASTER_PID=0

start_master() {
    cd $QUIL_NODE_PATH
    ./$NODE_BINARY &
    MASTER_PID=$!
    echo "启动管理节点 $MASTER_PID ..."
}

# Loop through the data worker count and start each core
start_workers() {
    # start the master node
    for ((i=0; i<$DATA_WORKER_COUNT; i++)); do
        echo "总工作进程数量：$DATA_WORKER_COUNT"
        CORE=$((START_CORE_INDEX + i))
        echo "启动核心：$CORE"
        $QUIL_NODE_PATH/$NODE_BINARY --core $CORE --parent-process $PARENT_PID --config "$QUIL_NODE_CONFIG" &
    done
}

if [[ "$OP" == "worker" ]]; then
        start_workers
    elif [[ "$OP" == "master" ]]; then
        echo "正在启动管理节点..."
        sleep 30
        start_master
    else
        echo "无效操作"
fi

is_master_process_running() {
    ps -p $MASTER_PID > /dev/null 2>&1
    return $?
}

while true
do
  # we only care about restarting the master process because the cores should be alive 
  # as long as this file is running (and this will only run on the machine with a start index of 1)
  if [ "$OP" == "master" ] && ! is_master_process_running; then
    echo "管理进程挂了，正在重启..."
    start_master
  fi
  sleep 440
done
