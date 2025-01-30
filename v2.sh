#!/bin/bash
clear

# 配置文件
LOG_FILE="user_operations.log"
USER_FILE="template_user.yml"
NGINX_FILE="template_nginx.conf"

# 颜色定义
GREEN='\e[1;32m'  # 绿色
RED='\e[1;31m'    # 红色
YELLOW='\e[1;33m' # 黄色
WHITE='\e[1;37m'  # 白色
NC='\e[0m'        # 无颜色

# 检查输入参数数量
if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# 日志记录函数
function log_operation {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 检查文件是否存在
function check_file_exists {
    if [[ -f "$1" ]]; then
        return 0
    else
        echo -e "${RED}文件 $1 不存在!${NC}"
        return 1
    fi
}

# 生成随机密码
function generate_password {
    local length=12
    local characters="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    cat /dev/urandom | tr -dc "$characters" | head -c "$length"
}

# 新增用户
function add_user {
    read -p "请输入用户名: " USERNAME

    if find ./conf_yml/ -name "${USERNAME}_*.yml" | grep -q .; then
       echo -e "${RED}错误!已存在相同用户名!${NC}"
       return
    fi

    read -p "请输入患者姓名: " CNNAME
    read -p "请输入端口号: " PORT

    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}错误！端口号必须在1-65535之间！${NC}"
        return
    fi

    if find ./conf_yml/ -name "*_${PORT}.yml" | grep -q .; then
       echo -e "${RED}错误！端口${PORT}已被使用！${NC}"
       return
    fi

    OUTPUT_FILE="${USERNAME}_${PORT}"
    echo "输入的用户名和端口号为：${CNNAME}:${USERNAME}_${PORT}"
    read -p "确认新增用户配置? (y/n): " CONFIRM

    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "操作取消！"
        return
    fi

    {
        echo "生成新用户配置文件: $OUTPUT_FILE"
        password=$(generate_password)
        
        # 替换内容并输出到新文件
        sed "s/template_user/$USERNAME/g; s/template_port/$PORT/g; s/template_password/$password/g; s/template_title/${CNNAME}/g" "$USER_FILE" > "conf_yml/$OUTPUT_FILE.yml"
        sed "s/template_user/$USERNAME/g; s/template_port/$PORT/g" "$NGINX_FILE" > "conf_nginx/$OUTPUT_FILE.conf"
    }
    
    log_operation "新增患者: ${CNNAME}   用户名: $USERNAME 端口: $PORT 密码: $password"
    
    if ! docker-compose -f "conf_yml/$OUTPUT_FILE.yml" -p "$USERNAME" up -d; then   
         rm -f "conf_yml/$OUTPUT_FILE.yml" "conf_nginx/$OUTPUT_FILE.conf"
        echo -e "${RED}容器启动失败，请检查${NC}"
    else
        cp conf_nginx/$OUTPUT_FILE.conf /etc/nginx/conf/conf.d/
        /etc/nginx/sbin/nginx -s reload
        echo -e "${GREEN}docker-compose项目运行状态:${NC}"
        docker-compose -f "conf_yml/$OUTPUT_FILE.yml" -p "$USERNAME" ps
        echo -e "${GREEN}docker容器运行状态:${NC}"
        docker ps | grep -E "${USERNAME}|STATUS"
        echo -n -e "${GREEN}按回车键继续.....${NC}";read
    fi   
}

# 检查用户
function check_user {
    read -p "请输入用户名: " USERNAME
    read -p "请输入端口号: " PORT

    OUTPUT_FILE="${USERNAME}_${PORT}"

    if check_file_exists "conf_yml/$OUTPUT_FILE.yml" && check_file_exists "conf_nginx/$OUTPUT_FILE.conf"; then
        echo "用户配置文件 '${OUTPUT_FILE}.yml' 存在."
        echo -e "${GREEN}docker-compose项目运行状态:${NC}"
        docker-compose -f "conf_yml/$OUTPUT_FILE.yml" -p "$USERNAME" ps
        echo -e "${GREEN}容器运行状态如下：${NC}"
        docker ps | grep -E "${USERNAME}|STATUS"
        echo -n -e "${GREEN}按回车键继续.....${NC}";read
    else
        echo -e "${RED}用户配置文件conf_yml/$OUTPUT_FILE.yml不存在!${NC}"
        docker stats --no-stream|grep -E "cgm|NAME"|more
        echo -n -e "${GREEN}按回车键继续.....${NC}";read
    fi
}

# 查找用户
function search_user {
    read -p "请输入要查找的用户名或患者姓名:" USERNAME
    
    echo "----------------------------------------记录查找结果----------------------------"
    grep "$USERNAME" "$LOG_FILE" | more
    echo "---------------------------------------------------------------------------------"
    read -p "请按回车键继续..."
}

# 删除用户
function delete_user {
    read -p "请输入用户名: " USERNAME
    read -p "请输入端口号: " PORT

    OUTPUT_FILE="${USERNAME}_${PORT}"

    if check_file_exists "conf_yml/$OUTPUT_FILE.yml" || check_file_exists "conf_nginx/$OUTPUT_FILE.conf"; then
        docker-compose -f "conf_yml/$OUTPUT_FILE.yml" -p "$USERNAME" down
        rm -f "conf_yml/$OUTPUT_FILE.yml" "conf_nginx/$OUTPUT_FILE.conf"
        echo "删除docker-compose配置文件：$USERNAME_$PORT.yml"
        log_operation "删除用户配置: $USERNAME 端口: $PORT"
        echo "删除nginx配置文件:/etc/nginx/conf/conf.d/$OUTPUT_FILE.conf" 
        rm -f  /etc/nginx/conf/conf.d/$OUTPUT_FILE.conf
        /etc/nginx/sbin/nginx -s reload

        echo -n -e "${GREEN}按回车键继续.....${NC}";read
    else
        echo -e "${RED}用户配置文件不存在 '$USERNAME' on port '$PORT' does not exist.${NC}"
        echo -n -e "${GREEN}按回车键继续.....${NC}";read
    fi
}

# 列出用户
function list_users {
    echo -e "${GREEN}----------当前已有用户配置文件$(ls conf_yml/*_*.yml | wc -l)个:----------${NC}"
    ls conf_yml/*_*.yml -t | sed 's/\.yml$//' | more
    echo -e "${GREEN}-----------------------------------------------${NC}"
    echo -n -e "${GREEN}按回车键继续.....${NC}";read
}

# 列出日志
function list_logs {
    echo "--------------------------最近20条用户日志:------------------------------"
    tail -n 20 "$LOG_FILE" | more
    echo "-------------------------------------------------------------------------"
    echo -n -e "${GREEN}按回车键继续.....${NC}";read
}

# 显示菜单
function show_menu {
    echo -e "${GREEN}MENU:${NC}"
    echo -e "${GREEN}1. 增加用户配置${NC}"
    echo -e "${GREEN}2. 检查用户配置${NC}"
    echo -e "${GREEN}3. 删除用户配置${NC}"
    echo -e "${GREEN}4. 显示配置列表${NC}"
    echo -e "${GREEN}5. 查找用户记录${NC}"
    echo -e "${GREEN}6. 最近操作日志${NC}"
    echo -e "${GREEN}7. 退出${NC}"
}

# 主循环
while true; do
    show_menu

    read -p "请选择一个选项 [1-7]: " OPTION

    case $OPTION in
        1) add_user ;;
        2) check_user ;;
        3) delete_user ;;
        4) list_users ;;
        5) search_user ;;
        6) list_logs ;;
        7) exit 0 ;;
        *) echo -e "${RED}无效选项，请重试。${NC}" ;;
    esac
done
