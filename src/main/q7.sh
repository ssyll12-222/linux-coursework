#!/bin/bash
# Q7：读取 input/remote.env，生成 ssh_config，用 SSH 和 SCP 获取远程数据。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

source "$input/remote.env"

config=$output/ssh_config
cat > "$config" <<EOF
Host aim-sentry
    HostName $HOST
    Port $PORT
    User $REMOTE_USER
    IdentityFile "$KEY_PATH"
    IdentitiesOnly yes
    UserKnownHostsFile "$KNOWN_HOSTS"
    StrictHostKeyChecking yes
EOF
chmod 600 "$config"

ssh -F "$config" -o BatchMode=yes -o ConnectTimeout=5 aim-sentry whoami > "$output/remote-user.txt"

mkdir -p "$output/received"
scp -F "$config" -o BatchMode=yes "aim-sentry:$REMOTE_LOG" "$output/received/errors.log"
