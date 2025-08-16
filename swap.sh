#!/usr/bin/env bash

Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[34m"

# 检查是否以root权限运行
root_need() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}错误：此脚本必须以root权限运行！${Font}"
        exit 1
    fi
}

# 检查磁盘空间
check_disk_space() {
    local required_size=$1
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_kb=$((required_size * 1024))

    if [[ $available_space -lt $required_kb ]]; then
        echo -e "${Red}错误：磁盘空间不足！需要 ${required_size}MB，可用 $((available_space / 1024))MB${Font}"
        return 1
    fi
    return 0
}

# 检查swap文件是否存在
check_swap_exists() {
    if [[ -f /swapfile ]] && grep -q "/swapfile" /etc/fstab; then
        return 0
    fi
    return 1
}

# 验证用户输入
validate_input() {
    local input=$1
    local min_size=${2:-128}
    local max_size=${3:-32768}

    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${Red}输入错误！请输入一个有效的数字。${Font}"
        return 1
    fi

    if [[ $input -lt $min_size ]]; then
        echo -e "${Red}输入错误！Swap大小不能小于 ${min_size}MB。${Font}"
        return 1
    fi

    if [[ $input -gt $max_size ]]; then
        echo -e "${Red}输入错误！Swap大小不能大于 ${max_size}MB。${Font}"
        return 1
    fi

    return 0
}

# 检测虚拟化环境
check_virtualization() {
    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    case "$virt" in
    kvm)
        echo -e "${Green}您的VPS运行在KVM环境，完全支持Swap操作。${Font}"
        ;;
    openvz)
        echo -e "${Yellow}您的VPS运行在OpenVZ环境，支持Swap操作，但性能可能受限。${Font}"
        ;;
    *)
        echo -e "${Yellow}您的虚拟化环境检测为：${virt}，可能需要自行确认支持情况。${Font}"
        ;;
    esac
}

# 添加Swap
add_swap() {
    echo -e "${Green}请输入需要添加的Swap大小（单位：MB），建议为内存的2倍！${Font}"
    echo -e "${Blue}提示：建议范围 128MB - 32768MB${Font}"
    read -p "请输入Swap大小: " swapsize < /dev/tty

    # 验证用户输入
    if ! validate_input "$swapsize"; then
        return 1
    fi

    # 检查是否已经存在Swap文件
    if check_swap_exists; then
        echo -e "${Red}Swap文件已存在，请先删除现有的Swap文件后再尝试！${Font}"
        return 1
    fi

    # 检查磁盘空间
    if ! check_disk_space "$swapsize"; then
        return 1
    fi

    # 大容量swap确认
    if [[ $swapsize -gt 8192 ]]; then
        echo -e "${Yellow}警告：您要创建的Swap文件较大（${swapsize}MB），确认继续吗？${Font}"
        read -p "输入 'yes' 确认: " confirm < /dev/tty
        if [[ "$confirm" != "yes" ]]; then
            echo -e "${Yellow}操作已取消。${Font}"
            return 0
        fi
    fi

    echo -e "${Green}未发现Swap文件，正在创建Swap文件...${Font}"

    # 优先使用fallocate命令
    if command -v fallocate > /dev/null; then
        echo -e "${Blue}使用fallocate创建Swap文件...${Font}"
        if ! fallocate -l ${swapsize}M /swapfile; then
            echo -e "${Red}fallocate创建失败，尝试使用dd命令...${Font}"
            if ! dd if=/dev/zero of=/swapfile bs=1M count=${swapsize} status=progress; then
                echo -e "${Red}Swap文件创建失败！${Font}"
                rm -f /swapfile
                return 1
            fi
        fi
    else
        echo -e "${Yellow}fallocate命令不可用，正在使用dd命令创建Swap文件...${Font}"
        if ! dd if=/dev/zero of=/swapfile bs=1M count=${swapsize} status=progress; then
            echo -e "${Red}Swap文件创建失败！${Font}"
            rm -f /swapfile
            return 1
        fi
    fi

    # 设置权限和格式化
    if ! chmod 600 /swapfile; then
        echo -e "${Red}设置Swap文件权限失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    if ! mkswap /swapfile; then
        echo -e "${Red}格式化Swap文件失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    if ! swapon /swapfile; then
        echo -e "${Red}启用Swap文件失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    # 添加到fstab
    if ! echo '/swapfile none swap defaults 0 0' >> /etc/fstab; then
        echo -e "${Red}添加到fstab失败！${Font}"
        swapoff /swapfile
        rm -f /swapfile
        return 1
    fi

    echo -e "${Green}Swap创建成功，当前信息如下：${Font}"
    cat /proc/swaps
    cat /proc/meminfo | grep Swap
}

# 删除Swap
del_swap() {
    # 检查是否存在Swap文件
    if ! check_swap_exists; then
        echo -e "${Red}未发现Swap文件，无法删除！${Font}"
        return 1
    fi

    # 显示当前swap信息
    echo -e "${Green}当前Swap信息：${Font}"
    cat /proc/swaps
    echo ""

    # 二次确认
    echo -e "${Yellow}警告：即将删除Swap文件，此操作不可逆！${Font}"
    read -p "输入 'yes' 确认删除: " confirm < /dev/tty
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${Yellow}操作已取消。${Font}"
        return 0
    fi

    echo -e "${Green}正在删除Swap文件...${Font}"

    # 关闭swap
    if ! swapoff /swapfile; then
        echo -e "${Red}关闭Swap失败！${Font}"
        return 1
    fi

    # 从fstab中移除
    if ! sed -i '/swapfile/d' /etc/fstab; then
        echo -e "${Red}从fstab移除条目失败！${Font}"
        return 1
    fi

    # 删除文件
    if ! rm -f /swapfile; then
        echo -e "${Red}删除Swap文件失败！${Font}"
        return 1
    fi

    # 清理缓存
    echo "3" > /proc/sys/vm/drop_caches

    echo -e "${Green}Swap已成功删除！${Font}"
}

# 调整Swap大小
resize_swap() {
    # 检查是否存在Swap文件
    if ! check_swap_exists; then
        echo -e "${Red}未发现Swap文件，无法调整大小，请先创建Swap文件！${Font}"
        return 1
    fi

    echo -e "${Green}检测到已有Swap文件，当前Swap大小如下：${Font}"
    cat /proc/swaps
    echo ""
    echo -e "${Green}请输入新的Swap大小（单位：MB）：${Font}"
    echo -e "${Blue}提示：建议范围 128MB - 32768MB${Font}"
    read -p "请输入新的Swap大小: " newsize < /dev/tty

    # 验证用户输入
    if ! validate_input "$newsize"; then
        return 1
    fi

    # 检查磁盘空间
    if ! check_disk_space "$newsize"; then
        return 1
    fi

    # 大容量swap确认
    if [[ $newsize -gt 8192 ]]; then
        echo -e "${Yellow}警告：您要创建的Swap文件较大（${newsize}MB），确认继续吗？${Font}"
        read -p "输入 'yes' 确认: " confirm < /dev/tty
        if [[ "$confirm" != "yes" ]]; then
            echo -e "${Yellow}操作已取消。${Font}"
            return 0
        fi
    fi

    echo -e "${Green}正在调整Swap大小...${Font}"

    # 关闭当前swap
    if ! swapoff /swapfile; then
        echo -e "${Red}关闭当前Swap失败！${Font}"
        return 1
    fi

    # 删除旧文件
    rm -f /swapfile

    # 使用适当方式重新创建Swap文件
    if command -v fallocate > /dev/null; then
        echo -e "${Blue}使用fallocate创建新的Swap文件...${Font}"
        if ! fallocate -l ${newsize}M /swapfile; then
            echo -e "${Red}fallocate创建失败，尝试使用dd命令...${Font}"
            if ! dd if=/dev/zero of=/swapfile bs=1M count=${newsize} status=progress; then
                echo -e "${Red}Swap文件创建失败！${Font}"
                rm -f /swapfile
                return 1
            fi
        fi
    else
        echo -e "${Yellow}fallocate命令不可用，正在使用dd命令创建Swap文件...${Font}"
        if ! dd if=/dev/zero of=/swapfile bs=1M count=${newsize} status=progress; then
            echo -e "${Red}Swap文件创建失败！${Font}"
            rm -f /swapfile
            return 1
        fi
    fi

    # 设置权限和格式化
    if ! chmod 600 /swapfile; then
        echo -e "${Red}设置Swap文件权限失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    if ! mkswap /swapfile; then
        echo -e "${Red}格式化Swap文件失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    if ! swapon /swapfile; then
        echo -e "${Red}启用Swap文件失败！${Font}"
        rm -f /swapfile
        return 1
    fi

    # 注意：不需要重复添加到fstab，因为条目已经存在
    echo -e "${Green}Swap大小调整成功，当前信息如下：${Font}"
    cat /proc/swaps
    cat /proc/meminfo | grep Swap
}

# 显示当前状态
show_status() {
    echo -e "${Blue}当前系统状态：${Font}"
    if check_swap_exists; then
        echo -e "${Green}✓ Swap文件已存在${Font}"
        cat /proc/swaps
        cat /proc/meminfo | grep Swap
    else
        echo -e "${Yellow}✗ 未发现Swap文件${Font}"
    fi
    echo ""
}

# 开始菜单
main() {
    echo ""
    echo "======================================="
    echo "Linux VPS 一键管理Swap脚本 v2.1"
    echo "======================================="

    # 显示当前状态
    if check_swap_exists; then
        echo "当前状态: Swap文件已存在"
        swapon --show 2>/dev/null || echo "Swap信息获取失败"
    else
        echo "当前状态: 未发现Swap文件"
    fi

    echo ""
    echo "1. 添加Swap"
    echo "2. 删除Swap"
    echo "3. 调整Swap大小"
    echo "4. 查看详细状态"
    echo "0. 退出脚本"
    echo "======================================="

    printf "请输入选择 [0-4]: "
    read num < /dev/tty

    case "$num" in
    1)
        echo ""
        add_swap
        ;;
    2)
        echo ""
        del_swap
        ;;
    3)
        echo ""
        resize_swap
        ;;
    4)
        echo ""
        show_status
        ;;
    0)
        echo "感谢使用，再见！"
        exit 0
        ;;
    *)
        echo "输入错误，请输入 0-4 之间的数字"
        exit 1
        ;;
    esac

    echo ""
    echo "操作完成！如需继续操作，请重新运行脚本。"
}

# 初始化脚本
echo "正在初始化..."
root_need
check_virtualization
echo ""

main
