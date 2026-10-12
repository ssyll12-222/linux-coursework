#!/bin/bash
# Q8：repair 时识别并停止采集器、修复 HTTP 服务；cleanup 时停止修复后的服务。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-repair}

source "$input/process.env"

wait_gone() {
    # 等待进程退出；僵死进程（未被父进程回收）也视为已结束。
    local target=$1
    local i
    for i in $(seq 1 100); do
        kill -0 "$target" 2>/dev/null || return 0
        ps -o stat= -p "$target" 2>/dev/null | grep -q Z && return 0
        sleep 0.05
    done
}

if [ "$action" = "repair" ]; then
    # 识别采集器进程
    user=$(ps -o user= -p "$TARGET_PID" | tr -d ' ')
    state=$(ps -o state= -p "$TARGET_PID" | tr -d ' ')
    cmdline=$(ps -o args= -p "$TARGET_PID")
    printf 'pid=%s\nuser=%s\nstate=%s\ncommand=%s\n' \
        "$TARGET_PID" "$user" "$state" "$cmdline" > "$output/process.txt"

    # 优雅停止采集器（worker 收到 SIGTERM 会写入 STOP 记录后退出）
    kill "$TARGET_PID"
    wait_gone "$TARGET_PID"

    # 保存目标采集器的日志样本
    grep -F "TICK $TARGET_TOKEN " "$WORKER_LOG" > "$output/collector-sample.log"

    # 停止旧服务
    kill "$SERVICE_PID" 2>/dev/null || true
    wait_gone "$SERVICE_PID"

    # 写出修复后的配置
    printf 'bind=127.0.0.1\nport=%s\nroute=/status\n' "$TARGET_PORT" > "$output/server.conf"

    # 启动修复后的服务，等待它就绪并完成一次真实请求
    bash "$START_TOOL" "$output/server.conf" "$output/service-state"
    code=000
    for i in $(seq 1 50); do
        if code=$(curl -s -o "$output/http-body.txt" -w '%{http_code}' \
                "http://127.0.0.1:$TARGET_PORT/status" 2>/dev/null) && [ "$code" = 200 ]; then
            break
        fi
        sleep 0.1
    done
    printf '%s\n' "$code" > "$output/http-status.txt"
else
    # cleanup：停止 repair 阶段启动的服务
    pidfile=$output/service-state/pid
    if [ -f "$pidfile" ]; then
        spid=$(cat "$pidfile")
        kill "$spid" 2>/dev/null || true
        wait_gone "$spid"
    fi
fi
