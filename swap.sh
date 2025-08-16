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

# 显示 swappiness 设置
show_swappiness() {
    local current_swappiness=$(cat /proc/sys/vm/swappiness)
    echo "======================================="
    echo "Swappiness 参数管理"
    echo "======================================="
    echo "当前 swappiness 值: $current_swappiness"
    echo ""
    echo "Swappiness 值说明："
    echo "  0   - 仅在物理内存完全耗尽时才使用 Swap"
    echo "  1-10 - 非常保守，尽可能避免使用 Swap"
    echo "  60  - 默认值，均衡的选择"
    echo "  100 - 非常激进，倾向于把数据移到 Swap"
    echo ""

    if [[ $current_swappiness -eq 60 ]]; then
        echo "✓ 当前设置为推荐的默认值"
    elif [[ $current_swappiness -lt 10 ]]; then
        echo "⚠ 当前设置较为保守，可能不会充分利用 Swap"
    elif [[ $current_swappiness -gt 80 ]]; then
        echo "⚠ 当前设置较为激进，可能影响系统性能"
    else
        echo "ℹ 当前设置在合理范围内"
    fi
}

# 设置 swappiness
set_swappiness() {
    show_swappiness
    echo ""
    echo "请选择设置方式："
    echo "1. 临时设置 (重启后失效)"
    echo "2. 永久设置 (写入配置文件)"
    echo "0. 返回"
    echo ""

    printf "请输入选择 [0-2]: "
    read choice < /dev/tty

    case "$choice" in
    1|2)
        echo ""
        echo "推荐值："
        echo "  10 - 保守 (服务器推荐)"
        echo "  60 - 默认 (桌面系统推荐)"
        echo "  80 - 激进 (大内存系统)"
        echo ""
        printf "请输入新的 swappiness 值 [0-100]: "
        read new_value < /dev/tty

        if ! [[ "$new_value" =~ ^[0-9]+$ ]] || [[ $new_value -lt 0 ]] || [[ $new_value -gt 100 ]]; then
            echo "错误：请输入 0-100 之间的数字"
            return 1
        fi

        # 临时设置
        if sysctl vm.swappiness=$new_value; then
            echo "✓ 临时设置成功，当前 swappiness = $new_value"

            # 永久设置
            if [[ "$choice" == "2" ]]; then
                # 检查是否已存在配置
                if grep -q "^vm.swappiness" /etc/sysctl.conf; then
                    # 更新现有配置
                    sed -i "s/^vm.swappiness=.*/vm.swappiness=$new_value/" /etc/sysctl.conf
                else
                    # 添加新配置
                    echo "vm.swappiness=$new_value" >> /etc/sysctl.conf
                fi

                if sysctl -p > /dev/null 2>&1; then
                    echo "✓ 永久设置成功，重启后仍然有效"
                else
                    echo "⚠ 永久设置可能失败，请检查 /etc/sysctl.conf"
                fi
            fi
        else
            echo "✗ 设置失败"
            return 1
        fi
        ;;
    0)
        return 0
        ;;
    *)
        echo "输入错误"
        return 1
        ;;
    esac
}

# 系统分析工具
system_analysis() {
    echo "======================================="
    echo "系统内存和 Swap 分析"
    echo "======================================="

    # 获取内存信息
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local used_mem=$((total_mem - available_mem))
    local mem_usage_percent=$((used_mem * 100 / total_mem))

    echo "内存使用情况："
    echo "  总内存: $((total_mem / 1024)) MB"
    echo "  已用内存: $((used_mem / 1024)) MB ($mem_usage_percent%)"
    echo "  可用内存: $((available_mem / 1024)) MB"
    echo ""

    # Swap 信息
    if check_swap_exists; then
        local swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
        local swap_used=$(grep SwapUsed /proc/meminfo | awk '{print $2}')
        local swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')

        if [[ $swap_total -gt 0 ]]; then
            local swap_usage_percent=$((swap_used * 100 / swap_total))
            echo "Swap 使用情况："
            echo "  总 Swap: $((swap_total / 1024)) MB"
            echo "  已用 Swap: $((swap_used / 1024)) MB ($swap_usage_percent%)"
            echo "  可用 Swap: $((swap_free / 1024)) MB"
        else
            echo "Swap 状态: 已配置但未使用"
        fi
    else
        echo "Swap 状态: 未配置"
    fi
    echo ""

    # Swappiness 信息
    local swappiness=$(cat /proc/sys/vm/swappiness)
    echo "Swappiness 设置: $swappiness"
    echo ""

    # 性能建议
    echo "性能建议："

    # 内存使用建议
    if [[ $mem_usage_percent -gt 80 ]]; then
        echo "⚠ 内存使用率较高 ($mem_usage_percent%)，建议："
        echo "  - 考虑增加 Swap 空间"
        echo "  - 关闭不必要的服务"
        if [[ $swappiness -lt 10 ]]; then
            echo "  - 适当提高 swappiness 值 (当前: $swappiness)"
        fi
    elif [[ $mem_usage_percent -lt 30 ]]; then
        echo "✓ 内存使用率较低 ($mem_usage_percent%)，系统运行良好"
        if [[ $swappiness -gt 60 ]]; then
            echo "  - 可以降低 swappiness 值以提高性能"
        fi
    else
        echo "✓ 内存使用率正常 ($mem_usage_percent%)"
    fi

    # Swap 建议
    if check_swap_exists && [[ $swap_total -gt 0 ]]; then
        local recommended_swap=$((total_mem / 1024))
        local current_swap=$((swap_total / 1024))

        if [[ $current_swap -lt $((recommended_swap / 2)) ]]; then
            echo "⚠ Swap 空间可能不足，建议增加到 ${recommended_swap}MB"
        elif [[ $current_swap -gt $((recommended_swap * 3)) ]]; then
            echo "ℹ Swap 空间较大，如果不常用可以考虑减少"
        else
            echo "✓ Swap 空间配置合理"
        fi

        if [[ $swap_usage_percent -gt 50 ]]; then
            echo "⚠ Swap 使用率较高 ($swap_usage_percent%)，可能影响性能"
        fi
    else
        local recommended_swap=$((total_mem / 1024))
        echo "ℹ 建议配置 Swap 空间: ${recommended_swap}MB (与内存大小相等)"
    fi
}

# 一键优化设置
auto_optimize() {
    echo "======================================="
    echo "一键优化 Swap 设置"
    echo "======================================="

    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem / 1024))
    local current_swappiness=$(cat /proc/sys/vm/swappiness)

    echo "系统分析："
    echo "  内存大小: ${total_mem_mb} MB"
    echo "  当前 swappiness: $current_swappiness"
    echo ""

    # 根据内存大小推荐设置
    local recommended_swappiness
    local recommended_swap

    if [[ $total_mem_mb -lt 1024 ]]; then
        # 小于 1GB 内存
        recommended_swappiness=60
        recommended_swap=$((total_mem_mb * 2))
        echo "检测到小内存系统 (<1GB)，推荐配置："
    elif [[ $total_mem_mb -lt 4096 ]]; then
        # 1-4GB 内存
        recommended_swappiness=30
        recommended_swap=$total_mem_mb
        echo "检测到中等内存系统 (1-4GB)，推荐配置："
    else
        # 大于 4GB 内存
        recommended_swappiness=10
        recommended_swap=$((total_mem_mb / 2))
        echo "检测到大内存系统 (>4GB)，推荐配置："
    fi

    echo "  推荐 Swap 大小: ${recommended_swap} MB"
    echo "  推荐 swappiness: $recommended_swappiness"
    echo ""

    printf "是否应用推荐设置？(y/N): "
    read confirm < /dev/tty

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo ""
        echo "正在应用优化设置..."

        # 设置 swappiness
        if sysctl vm.swappiness=$recommended_swappiness; then
            echo "✓ 已设置 swappiness = $recommended_swappiness"

            # 永久保存
            if grep -q "^vm.swappiness" /etc/sysctl.conf; then
                sed -i "s/^vm.swappiness=.*/vm.swappiness=$recommended_swappiness/" /etc/sysctl.conf
            else
                echo "vm.swappiness=$recommended_swappiness" >> /etc/sysctl.conf
            fi
            echo "✓ 已永久保存 swappiness 设置"
        fi

        # Swap 大小建议
        if check_swap_exists; then
            local current_swap=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
            local current_swap_mb=$((current_swap / 1024))

            if [[ $current_swap_mb -ne $recommended_swap ]]; then
                echo ""
                echo "当前 Swap: ${current_swap_mb} MB"
                echo "建议 Swap: ${recommended_swap} MB"
                echo "如需调整 Swap 大小，请使用菜单选项 3"
            else
                echo "✓ Swap 大小已经是推荐值"
            fi
        else
            echo ""
            echo "建议创建 ${recommended_swap} MB 的 Swap 文件"
            echo "请使用菜单选项 1 创建 Swap"
        fi

        echo ""
        echo "✓ 优化完成！"
    else
        echo "优化已取消"
    fi
}

# 开始菜单
main() {
    echo ""
    echo "======================================="
    echo "Linux VPS 一键管理Swap脚本 v3.0"
    echo "======================================="

    # 显示当前状态
    if check_swap_exists; then
        echo "当前状态: Swap文件已存在"
        swapon --show 2>/dev/null || echo "Swap信息获取失败"
    else
        echo "当前状态: 未发现Swap文件"
    fi

    local swappiness=$(cat /proc/sys/vm/swappiness)
    echo "Swappiness: $swappiness"

    echo ""
    echo "=== Swap 管理 ==="
    echo "1. 添加Swap"
    echo "2. 删除Swap"
    echo "3. 调整Swap大小"
    echo "4. 查看详细状态"
    echo ""
    echo "=== 性能优化 ==="
    echo "5. Swappiness 设置"
    echo "6. 系统分析"
    echo "7. 一键优化"
    echo ""
    echo "0. 退出脚本"
    echo "======================================="

    printf "请输入选择 [0-7]: "
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
    5)
        echo ""
        set_swappiness
        ;;
    6)
        echo ""
        system_analysis
        ;;
    7)
        echo ""
        auto_optimize
        ;;
    0)
        echo "感谢使用，再见！"
        exit 0
        ;;
    *)
        echo "输入错误，请输入 0-7 之间的数字"
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
