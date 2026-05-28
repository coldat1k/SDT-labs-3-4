if [ "$EUID" -ne 0 ]; then
  echo "Будь ласка, запустіть скрипт з правами root (sudo ./setup.sh)"
  exit 1
fi

echo "1. Встановлення пакетів (Nginx та Docker)..."
apt-get update
apt-get install -y nginx docker.io curl

echo "2. Створення користувачів та налаштування безпеки..."
useradd -m -s /bin/bash -G sudo student
echo "student:12345678" | chpasswd
chage -d 0 student

useradd -m -s /bin/bash -G sudo teacher
echo "teacher:12345678" | chpasswd
chage -d 0 teacher

useradd -m -s /bin/bash operator
echo "operator:12345678" | chpasswd
chage -d 0 operator

usermod -aG docker operator

cat <<EOF > /etc/sudoers.d/operator
operator ALL=(ALL) NOPASSWD: /bin/systemctl start mywebapp, /bin/systemctl stop mywebapp, /bin/systemctl restart mywebapp, /bin/systemctl status mywebapp, /bin/systemctl reload nginx
EOF
chmod 0440 /etc/sudoers.d/operator

echo "3. Налаштування Docker-мережі та директорій конфігурації..."
docker network create backend-net || true
mkdir -p /etc/mywebapp

cat <<EOF > /etc/mywebapp/config.json
{
  "port": 8000,
  "db": {
    "user": "inventory_user",
    "host": "db",
    "database": "inventory_db",
    "password": "inventory_password",
    "port": 5432
  }
}
EOF
chmod 600 /etc/mywebapp/config.json

echo "4. Налаштування та запуск контейнера БД (PostgreSQL)..."
docker run -d \
  --name db \
  --network backend-net \
  --restart always \
  -e POSTGRES_DB=inventory_db \
  -e POSTGRES_USER=inventory_user \
  -e POSTGRES_PASSWORD=inventory_password \
  -v pgdata:/var/lib/postgresql/data \
  postgres:15-alpine || docker start db

echo "5. Налаштування systemd-unit для керування Docker-контейнером застосунку..."
cat <<EOF > /etc/systemd/system/mywebapp.service
[Unit]
Description=Simple Inventory Web App (Docker Container)
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop mywebapp
ExecStartPre=-/usr/bin/docker rm mywebapp
# Перед стартом підтягуємо свіжий образ, який зварив наш CI конвеєр
ExecStartPre=/usr/bin/docker pull ghcr.io/coldat1k/sdt-labs-3-4:stable
ExecStart=/usr/bin/docker run --name mywebapp \
  --network backend-net \
  -v /etc/mywebapp/config.json:/etc/mywebapp/config.json:ro \
  -p 127.0.0.1:8000:8000 \
  ghcr.io/coldat1k/sdt-labs-3-4:stable

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "6. Налаштування Nginx (як у ЛР1, з блокуванням)..."
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Перенаправляємо запити на локальний порт контейнера
    location = / {
        proxy_pass http://127.0.0.1:8000;
    }

    location /items {
        proxy_pass http://127.0.0.1:8000;
    }

    # Блокуємо ззовні доступ до /health/alive та /health/ready, як і в першій лабі
    location / {
        return 403;
    }
}
EOF

systemctl restart nginx

echo "7. Створення файлу gradebook..."
echo "23" > /home/student/gradebook
chown student:student /home/student/gradebook

echo "8. Блокування дефолтного користувача..."
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -L "$SUDO_USER"
    echo "Користувача $SUDO_USER заблоковано."
fi

echo "Первинне розгортання та налаштування середовища завершено!"