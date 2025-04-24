### 特色
## 1、目标用户动态指定
通过脚本参数TARGET_USER="${1:-$(whoami)}"实现：
无参数时默认使用当前用户（whoami）
支持通过./script.sh custom_user指定任意存在的普通用户
严格禁止使用 root 作为目标用户（新增权限检查）
## 2、路径自动适配
Anaconda 安装路径自动指向目标用户主目录（${HOME}/anaconda3）
systemd 服务中的User/Environment/WorkingDirectory均使用动态变量${TARGET_USER}
## 3、权限模式自动识别
root 执行：创建系统级服务，适配/home/${TARGET_USER}路径
普通用户执行：自动创建用户级服务（存储在~/.config/systemd/user/）
自动处理目录权限（chown -R ${TARGET_USER}:${TARGET_USER}）
## 4、兼容性
支持 Debian/Ubuntu/RedHat 等主流 Linux 发行版
自动检测用户是否存在，缺失时给出清晰提示
同时支持 GPU 环境（目标用户需加入显卡驱动组）
### 使用示例
## 场景 1：当前用户部署（非 root）

# 直接运行（使用当前用户）
./xinference_deploy.sh

# 服务管理（无需sudo）
systemctl --user start xinference.service
## 场景 2：指定目标用户（需 root 权限）

# 以admin用户部署（需提前创建useradd -m admin）
sudo ./xinference_deploy.sh admin

# 系统级服务管理
sudo systemctl status xinference.service
## 场景 3：完全自定义用户（生产环境推荐）
创建专用服务用户：

sudo useradd -m -s /sbin/nologin xinference_user  # 禁止登录的专用用户
sudo ./xinference_deploy.sh xinference_user

关键机制说明
用户级 vs 系统级服务自动切换
脚本根据执行权限自动判断：
root 执行→系统级服务（/etc/systemd/system/）
普通用户执行→用户级服务（~/.config/systemd/user/）
两种模式均支持开机自启动，区别在于是否需要用户登录（系统级无需登录）
环境变量隔离
Anaconda 路径严格绑定目标用户主目录，避免不同用户环境冲突
systemd 服务通过Environment="HOME=/home/${TARGET_USER}"确保正确环境变量
权限最小化
禁止以 root 用户作为目标用户（User=root存在安全风险）
专用服务用户可通过-s /sbin/nologin限制登录权限，提升安全性
## 注意事项
用户创建要求
目标用户必须提前创建（useradd -m ${TARGET_USER}）
推荐使用非登录用户（-s /sbin/nologin）运行服务，降低攻击面
多用户共存
不同用户可独立部署多个 Xinference 实例（通过不同端口区分）
系统级服务需确保端口唯一性（修改--port参数避免冲突）
日志与调试
系统级服务日志：journalctl -u xinference.service -f
用户级服务日志：journalctl --user -u xinference.service -f
可通过ExecStart添加日志输出重定向：

ExecStart=/bin/bash -c "命令 >> /home/${TARGET_USER}/xinference.log 2>&1"


此脚本实现了完全的用户无关性，支持任意普通用户部署，既可以在个人工作站以当前用户运行，也可以在服务器环境通过 root 指定专用服务用户，兼顾灵活性与安全性。
