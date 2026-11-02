#!/bin/bash
# corre como root en el primer arranque, log en /var/log/user-data.log
# releases/<ver>: codigo por version, current: enlace a la activa
# /etc/to-do-list.env: DATABASE_URL y APP_VERSION
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

dnf install -y git python3 python3-pip unzip

BASE=/opt/to-do-list
git clone --branch "${repo_branch}" "${repo_url}" "$BASE/releases/initial"
VERSION=$(git -C "$BASE/releases/initial" describe --tags --always)
ln -sfn "$BASE/releases/initial" "$BASE/current"

python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install --upgrade pip
"$BASE/venv/bin/pip" install -r "$BASE/current/app/requirements.txt"
chown -R ec2-user:ec2-user "$BASE"

cat > /etc/to-do-list.env <<EOF
DATABASE_URL=${database_url}
APP_VERSION=$VERSION
EOF
chmod 600 /etc/to-do-list.env

cat > /etc/systemd/system/to-do-list.service <<'EOF'
[Unit]
Description=To-do list API
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/to-do-list/current/app
EnvironmentFile=/etc/to-do-list.env
ExecStart=/opt/to-do-list/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:${app_port} app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now to-do-list.service
