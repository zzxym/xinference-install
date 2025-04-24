#!/bin/bash
set -euo pipefail
trap 'echo "部署失败: $?"; exit 1' ERR

# ----------------------
# 配置参数（动态用户适配）
# ----------------------
TARGET_USER="${1:-$(whoami)}"  # 默认使用当前用户，可通过第一个参数指定
ANACONDA_INSTALLER="Anaconda3-2024.10-1-Linux-x86_64.sh"
ANACONDA_DIR="${HOME}/anaconda3"  # 目标用户主目录下的Anaconda路径
SCRIPT_DIR=$(dirname $(realpath "$0"))
INSTALLER_PATH="${SCRIPT_DIR}/${ANACONDA_INSTALLER}"
SERVICE_FILE_PATH="/etc/systemd/system/xinference.service"

# ----------------------
# 权限与用户检查
# ----------------------
if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" = "root" ]; then
    echo "错误：禁止以root用户作为目标用户，请指定普通用户"
    exit 1
fi

if ! getent passwd ${TARGET_USER} >/dev/null; then
    echo "错误：目标用户 ${TARGET_USER} 不存在，请先创建（useradd -m ${TARGET_USER}）"
    exit 1
fi

# ----------------------
# Anaconda安装（目标用户目录）
# ----------------------
echo "开始为用户 ${TARGET_USER} 安装Anaconda3..."
if [ "$(id -u)" -eq 0 ]; then
    # root用户执行时切换到目标用户安装
    su - ${TARGET_USER} -c "
        bash ${INSTALLER_PATH} -b -p ${ANACONDA_DIR}
        echo 'export PATH=${ANACONDA_DIR}/bin:\$PATH' >> ~/.bashrc
        source ~/.bashrc
    "
else
    # 普通用户直接安装（非root场景）
    bash ${INSTALLER_PATH} -b -p ${ANACONDA_DIR}
    echo 'export PATH=${ANACONDA_DIR}/bin:\$PATH' >> ~/.bashrc
    source ~/.bashrc
fi

# ----------------------
# Xinference环境配置
# ----------------------
echo "为用户 ${TARGET_USER} 配置Xinference运行环境..."
if [ "$(id -u)" -eq 0 ]; then
    su - ${TARGET_USER} -c "
        ${ANACONDA_DIR}/bin/conda init bash
        source ${ANACONDA_DIR}/etc/profile.d/conda.sh
        conda create -n Xinference --yes
        conda activate Xinference
        pip install \"xinference[all]\"
    "
else
    ${ANACONDA_DIR}/bin/conda init bash
    source ${ANACONDA_DIR}/etc/profile.d/conda.sh
    conda create -n Xinference --yes
    conda activate Xinference
    pip install "xinference[all]"
fi

# ----------------------
# 生成动态用户systemd服务
# ----------------------
cat > "${SERVICE_FILE_PATH}" <<EOF
[Unit]
Description=Xinference Service for User ${TARGET_USER}
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=simple
User=${TARGET_USER}          # 动态用户配置
Environment="HOME=/home/${TARGET_USER}"
WorkingDirectory=/home/${TARGET_USER}
ExecStartPre=/bin/bash -c "
    . ${ANACONDA_DIR}/etc/profile.d/conda.sh
    conda activate Xinference >/dev/null 2>&1
"
ExecStart=/bin/bash -c "
    ANACONDA_DIR=${ANACONDA_DIR}
    xinference-local --host 0.0.0.0 --port 9997 &
    LLM_PID=\$!
    xinference launch --model-name qwen2.5-instruct --model-type LLM --model-engine vLLM --model-format awq --size-in-billions 32 --quantization Int4 --n-gpu auto --replica 1 --n-worker 1 &
    EMBEDDING_PID=\$!
    xinference launch --model-name bge-large-zh-v1.5 --model-type embedding --replica 1 --n-gpu auto --download-hub modelscope &
    RERANK_PID=\$!
    wait \$LLM_PID \$EMBEDDING_PID \$RERANK_PID
"
ExecStop=/bin/bash -c "
    kill -9 \$(pgrep -u ${TARGET_USER} -f 'xinference-local --host 0.0.0.0 --port 9997')
    kill -9 \$(pgrep -u ${TARGET_USER} -f 'qwen2.5-instruct')
    kill -9 \$(pgrep -u ${TARGET_USER} -f 'bge-large-zh-v1.5')
    kill -9 \$(pgrep -u ${TARGET_USER} -f 'jina-reranker-v2')
"
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ----------------------
# 系统服务配置
# ----------------------
if [ "$(id -u)" -eq 0 ]; then
    chmod 644 "${SERVICE_FILE_PATH}"
    systemctl daemon-reload
    systemctl enable --now xinference.service
    chown -R ${TARGET_USER}:${TARGET_USER} /home/${TARGET_USER}/anaconda3
else
    # 普通用户安装用户级服务（需systemd user instance支持）
    mkdir -p ~/.config/systemd/user/
    mv "${SERVICE_FILE_PATH}" ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now xinference.service
fi

echo "
====================================================================
Xinference已为用户 ${TARGET_USER} 完成部署！

使用方式：
1. 目标用户：${TARGET_USER}
2. Anaconda路径：${ANACONDA_DIR}
3. 服务类型：$(if [ "$(id -u)" -eq 0 ]; then echo "系统级服务"; else echo "用户级服务"; fi)

启动验证：
systemctl $(if [ "$(id -u)" -eq 0 ]; then echo ""; else echo "--user "; fi)status xinference.service

高级用法：
指定目标用户：sudo ./xinference_deploy.sh custom_user
当前用户部署：./xinference_deploy.sh（非root用户自动创建用户级服务）
====================================================================
"
