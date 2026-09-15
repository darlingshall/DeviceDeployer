import os
import sys
import json
import paramiko


def get_base_dir():
    """获取程序所在目录（兼容 PyInstaller 打包后的路径）"""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def load_config():
    """加载同目录下的 config.json"""
    base_dir = get_base_dir()
    config_path = os.path.join(base_dir, "config.json")

    if not os.path.exists(config_path):
        print(f"[错误] 找不到配置文件: {config_path}")
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def apply_paramiko_patch():
    """=== 核心兼容处理：适配旧版 ssh-rsa 签名与免密登录设备 ==="""
    try:
        if 'ssh-rsa' not in paramiko.transport.Transport._key_info:
            paramiko.transport.Transport._key_info['ssh-rsa'] = paramiko.RSAKey

        if "ssh-rsa" not in paramiko.transport.Transport._preferred_keys:
            paramiko.transport.Transport._preferred_keys = (
                    paramiko.transport.Transport._preferred_keys + ("ssh-rsa",)
            )
        if "ssh-rsa" not in paramiko.transport.Transport._preferred_pubkeys:
            paramiko.transport.Transport._preferred_pubkeys = (
                    paramiko.transport.Transport._preferred_pubkeys + ("ssh-rsa",)
            )

        paramiko.RSAKey.verify_ssh_sig = lambda self, data, msg: True
    except Exception as patch_err:
        print(f"[警告] 安全策略兼容补丁加载异常: {patch_err}")


def deploy():
    base_dir = get_base_dir()
    config = load_config()

    scripts = config.get("scripts", [])
    if not scripts:
        print("[提示] config.json 中未配置任何待上传的 scripts 脚本，退出部署。")
        return

    # 加载 SSH 兼容补丁
    apply_paramiko_patch()

    # SSH 连接配置
    ssh_conf = config["ssh"]
    host = ssh_conf["host"]
    # 这里为了不暴露ssh的账号和端口号，不使用配置文件里的内容,这样配置文件里可以随便改。
    # port = ssh_conf["port"]
    # username = ssh_conf["username"]
    port = 9527
    username = "Demo"
    password = ssh_conf.get("password", "")

    # 指定 /opt 下的新建子目录路径
    REMOTE_DIR = "/opt/watchdog_scripts"

    print(f"正在连接设备 {host}:{port} ...")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        transport = paramiko.Transport((host, port))
        transport.connect(username=username)
        try:
            # 优先尝试免密 none 认证
            transport.auth_none(username)
        except Exception:
            # 如果 none 认证失败，回退到密码认证
            transport.auth_password(username, password)

        client._transport = transport
        print(f"[OK] 成功连接设备 {host}\n")

        # 1. 确保远程 /opt/watchdog_scripts 目录存在
        print(f"创建远程目录: {REMOTE_DIR} ...", end=" ")
        client.exec_command(f"mkdir -p {REMOTE_DIR}")
        print("OK\n")

        sftp = client.open_sftp()

        # 逐个处理配置文件里的脚本
        for item in scripts:
            script_name = item["name"]
            cron_schedule = item.get("cron", "*/5 * * * *")

            local_path = os.path.join(base_dir, script_name)
            remote_path = f"{REMOTE_DIR}/{script_name}"

            print(f"--> 开始部署脚本: {script_name}")

            # 校验本地文件是否存在
            if not os.path.exists(local_path):
                print(f"    [跳过] 本地未找到文件 {local_path}")
                print()
                continue

            # 1. 上传文件
            print(f"    [1/3] 上传: {script_name} -> {remote_path} ...", end=" ")
            sftp.put(local_path, remote_path)
            print("OK")

            # 2. 设置可执行权限
            print(f"    [2/3] 赋权 (chmod +x) ...", end=" ")
            client.exec_command(f"chmod +x {remote_path}")
            print("OK")

            # 3. 写入 Crontab (自动去重)
            print(f"    [3/3] 配置 Crontab ({cron_schedule}) ...", end=" ")
            cron_job = f"{cron_schedule} {remote_path} >/dev/null 2>&1"
            cron_cmd = f'(crontab -l 2>/dev/null | grep -v "{remote_path}"; echo "{cron_job}") | crontab -'
            client.exec_command(cron_cmd)
            print("OK\n")

        sftp.close()
        print("=" * 50)
        print("[完成] 所有配置的脚本部署完毕！")

    except Exception as e:
        print(f"\n[失败] 部署过程出现错误: {e}")
    finally:
        client.close()


if __name__ == "__main__":
    print("=" * 50)
    print("  DeviceDeployer - 远程脚本部署工具")
    print("=" * 50)
    print()

    deploy()

    print()
    input("按回车键退出...")