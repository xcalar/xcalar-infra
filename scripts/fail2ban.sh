systemctl enable --now firewalld
firewall-cmd --zone=public --change-interface=eth0 --permanent
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --reload

yum install -y fail2ban
cd /etc/fail2ban/
cat > jail.local <<EOF
[DEFAULT]

bantime = 3600
ignoreip = 76.103.53.99/32 207.135.66.186/32
findtime  = 3600
maxretry = 3
banaction = firewallcmd-ipset

[sshd]
enabled = true
EOF

systemctl enable --now fail2ban

touch /etc/krb5.keytab
mkdir -p /etc/opt/omi/creds/
touch /etc/opt/omi/creds/omi.keytab
yum install ntpd
systemctl enable --now ntpd
