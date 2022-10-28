#!/bin/sh
#--------------------------------
#系统加固，系统初始化脚本
#作者：袁凯 20221020
#qq: 837978792
#---------------------------------
#要添加的用户
users='devops ausa'
pass='01wjMHuwvSz3ujT2'
sshd_config='/etc/ssh/sshd_config'
#要安装的基础软件工具
softwares='sudo net-tools wget lsof lrzsz zip gzip unzip telnet ntpdate curl nc'

echo "================"
echo "当前用户: $USER"

if [ `id -u $USER` -ne 0 ]; then
  echo "Current User is not root,Pls run this script with root!"
  exit 1
fi

#基本软件安装
soft-install() {
  echo "- Install software"
  yum install -y $softwares 
}

#创建普通用户
create-users() {
  for u in $users
  do 
    [ -z "$(grep $u /etc/passwd)" ] && useradd -m -p $pass -G wheel -s /bin/bash $u
    if [ "$u" == "devops" ];then
       [ -z "$(egrep -v '^#' /etc/sudoers | grep $u)" ] && \
       echo "$u  ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
    fi
    mkdir /data/${u} -p
    [ -d /data/${u} ] && chown -R $u:$u /data/${u}
  done
}

#ssh加固
sshsafe() {
  sed -i '/^#LogLevel/s/#//' $sshd_config           #设置LogLevel为INFO级别，记录登录和注销
  sed -i 's/\(.*\)ClientAliveInterval \(.*\)/ClientAliveInterval 600 /' $sshd_config #ssh空闲退出时间
  sed -i -e '/^#ClientAliveCountMax/s/#//;/ClientAliveCountMax/s/3/2/' $sshd_config 
  sed -i -e '/^#MaxAuthTries/s/#//;/MaxAuthTries/s/6/4/' $sshd_config    #最大尝试次数
  sed -i -e '/^#PermitEmptyPasswords/s/#//;/PermitEmptyPasswords/s/yes/no/' $sshd_config    #不允许空密码登录
  [ -z "`egrep ^Protocol $sshd_config`" ] && sed -i '/^#Port/a Protocol 2' $sshd_config     #强制ssh使用V2安全协议
  echo "SSH连接加固："
  echo ------------------------
  egrep 'LogLevel|ClientAliveInterval|ClientAliveCountMax|MaxAuthTries|PermitEmptyPasswords|Protocol' $sshd_config | grep -v '^#'
  echo ------------------------
}

#密码加固
passafe() {
  #echo -e "difok = 3\nminlen = 8\ndcredit = -1\nucredit = -1\nlcredit = -1\nretry = 3" >> /etc/security/pwquality.conf
  sed -i -e '/difok/s/\(.*\)/difok = 3/;/minlen/s/\(.*\)/minlen = 8/;/dcredit/s/\(.*\)/dcredit = -1/;/ucredit/s/\(.*\)/ucredit = -1/;/lcredit/s/\(.*\)/lcredit = -1/;/minclass/s/\(.*\)/minclass = 3/;/retry/s/\(.*\)/retry = 3/' /etc/security/pwquality.conf
  sed -i -e '/^PASS_MIN_DAYS/s/\(.*\)/PASS_MIN_DAYS 7/;/^PASS_MAX_DAYS/s/\(.*\)/PASS_MAX_DAYS 90/;/^PASS_MIN_LEN/s/\(.*\)/PASS_MIN_LEN 8/;/^PASS_WARN_AGE/s/\(.*\)/PASS_WARN_AGE 7/' /etc/login.defs
  chage --mindays 7 root
  chage --maxdays 90 root
  chage --warndays 7 root
  echo "密码策略加固"
  echo ------------------------
  egrep 'PASS_MIN_DAYS|PASS_MAX_DAYS|PASS_MIN_LEN|PASS_WARN_AGE' /etc/login.defs | grep -v '^#'
  egrep 'difok|minlen|dcredit|ucredit|lcredit|retry|minclass' /etc/security/pwquality.conf | grep -v '^#'
  echo ------------------------
}

#清理多余用户
usersafe() {
  echo "非法超级账户："
  echo -----------------------
  cat /etc/passwd | awk -F: '($3 == 0) { print $1 }'|grep -v '^root$'
  echo -----------------------
  echo "空口令账户:"
  echo -----------------------
  awk -F: 'length($2)==0 {print $1}' /etc/shadow
  echo -----------------------
}

#内核加固
kernelsafe() {
  #限制核心转储
  [ -z "$(egrep '^*  hard  core   0' /etc/security/limits.conf)" ] && echo "*  hard  core   0" >> /etc/security/limits.conf
  [ -z "$(grep fs.suid_dumpable=0 /etc/sysctl.conf)" ] && echo "fs.suid_dumpable=0" >> /etc/sysctl.conf
  #空间布局随机化
  [ -z "$(grep randomize_va_space=2 /etc/sysctl.conf)" ] && echo "kernel.randomize_va_space=2" >> /etc/sysctl.conf
  echo "内核安全加固"
  echo -----------------------
  sysctl -w fs.suid_dumpable=0
  sysctl -w kernel.randomize_va_space=2
  echo -----------------------
}

#配置文件权限
configfilesafe() {
  [ -f /etc/hosts.allow -a -f /etc/hosts.deny ] || exit 1 
  chown root:root /etc/hosts.allow /etc/hosts.deny
  chmod 644 /etc/hosts.deny
  chmod 644 /etc/hosts.allow
  chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
  chmod 0644 /etc/group
  chmod 0644 /etc/passwd
  chmod 0400 /etc/shadow
  chmod 0400 /etc/gshadow
  #umask 027
  [ -z "$(grep 'umask 027' /etc/profile)" ] && echo "umask 027" >> /etc/profile
  echo "文件权限加固"
  echo -----------------------
  ls -l /etc/{hosts.deny,hosts.allow,passwd,group,shadow,gshadow}
  echo -----------------------
}

#服务最小启动
servicesafe() {
  echo "服务开启状态"
  echo -----------------------
  declare -A srv_info
  for s in rsyslog auditd
  do
    systemctl enable $s
    systemctl start $s
    s_status=`systemctl status $s | sed  -n /^\ \ \ Active/p | awk '{print $2" "$3}'`
    echo -e "${s}: \033[32m ${s_status} \033[0m"
  done
}


main() {
 soft-install 
 create-users
 sshsafe
 passafe
 usersafe
 kernelsafe
 configfilesafe
 servicesafe
}

main '$*'
