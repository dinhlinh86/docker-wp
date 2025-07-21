#!/bin/bash

# =================================================================
# Script tự động triển khai WordPress với Docker và Cloudflare Tunnel
# Tác giả: Script hỗ trợ triển khai cho vuamatdung.com
# =================================================================

set -e  # Dừng script nếu có lỗi

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function để in log có màu
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Script này không nên chạy với quyền root!"
        print_status "Hãy chạy: sudo usermod -aG docker \$USER && su - \$USER"
        exit 1
    fi
}

# Kiểm tra Docker
check_docker() {
    print_status "Kiểm tra Docker..."
    if ! command -v docker &> /dev/null; then
        print_warning "Docker chưa được cài đặt. Đang cài đặt..."
        sudo apt update
        sudo apt install -y docker.io docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        print_warning "Vui lòng logout và login lại để áp dụng quyền Docker group"
        print_warning "Sau đó chạy lại script này"
        exit 0
    fi
    
    # Kiểm tra quyền docker
    if ! docker ps &> /dev/null; then
        print_error "Không có quyền truy cập Docker. Chạy: sudo usermod -aG docker \$USER && su - \$USER"
        exit 1
    fi
    
    print_success "Docker đã sẵn sàng"
}

# Tạo thư mục project
create_project_dir() {
    print_status "Tạo thư mục project..."
    
    if [[ -d "vuamatdung" ]]; then
        read -p "Thư mục vuamatdung đã tồn tại. Bạn có muốn xóa và tạo mới? (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            rm -rf vuamatdung
            print_warning "Đã xóa thư mục cũ"
        else
            print_error "Hủy bỏ triển khai"
            exit 0
        fi
    fi
    
    mkdir -p vuamatdung
    cd vuamatdung
    print_success "Đã tạo thư mục vuamatdung"
}

# Tạo file .env
create_env_file() {
    print_status "Tạo file .env..."
    
    cat > .env << 'EOF'
# Traefik Variables
TRAEFIK_IMAGE_TAG=traefik:2.9
TRAEFIK_LOG_LEVEL=WARN
TRAEFIK_ACME_EMAIL=dinhlinh.arch@gmail.com
TRAEFIK_HOSTNAME=traefik.vuamatdung.com
# Basic Authentication for Traefik Dashboard
# Username: dinhlinh
# Passwords must be encoded using BCrypt https://hostingcanada.org/htpasswd-generator/
TRAEFIK_BASIC_AUTH=dinhlinh:$2y$10$Q2yr2pCiamRpl/iwVFxd3eKSeBUV3Cd0YTCXYyRUE4Ry9t5EiVT4i

# WordPress Variables 
WORDPRESS_MARIADB_IMAGE_TAG=mariadb:11.4
WORDPRESS_IMAGE_TAG=bitnami/wordpress:6.6.2
WORDPRESS_DB_NAME=Vuamatdung
WORDPRESS_DB_USER=dinhlinh
WORDPRESS_DB_PASSWORD=banhbeoNha@123
WORDPRESS_DB_ADMIN_PASSWORD=banhbeoNha@123
WORDPRESS_TABLE_PREFIX=wpapp_
WORDPRESS_BLOG_NAME=Vuamatdung
WORDPRESS_ADMIN_NAME=Linh
WORDPRESS_ADMIN_LASTNAME=Dinh
WORDPRESS_ADMIN_USERNAME=admin
WORDPRESS_ADMIN_PASSWORD=banhbeoNha@123
WORDPRESS_ADMIN_EMAIL=dinhlinh.arch@gmail.com
WORDPRESS_HOSTNAME=vuamatdung.com
WORDPRESS_SMTP_ADDRESS=smtp.larksuite.com
WORDPRESS_SMTP_PORT=587
WORDPRESS_SMTP_USER_NAME=noreply@vuamatdung.com
WORDPRESS_SMTP_PASSWORD=1OoDadmqW9F728wK
EOF

    # Set quyền bảo mật cho file .env
    chmod 600 .env
    print_success "Đã tạo file .env với quyền bảo mật"
}

# Tạo file docker-compose.yml
create_docker_compose() {
    print_status "Tạo file docker-compose.yml..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

networks:
  wordpress-network:
    external: true
  traefik-network:
    external: true

volumes:
  mariadb-data:
  wordpress-data:
  traefik-certificates:

services:
  mariadb:
    image: ${WORDPRESS_MARIADB_IMAGE_TAG}
    volumes:
      - mariadb-data:/var/lib/mysql
    environment:
      MARIADB_DATABASE: ${WORDPRESS_DB_NAME}
      MARIADB_USER: ${WORDPRESS_DB_USER}
      MARIADB_PASSWORD: ${WORDPRESS_DB_PASSWORD}
      MARIADB_ROOT_PASSWORD: ${WORDPRESS_DB_ADMIN_PASSWORD}
    networks:
      - wordpress-network
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 60s
    restart: unless-stopped

  wordpress:
    image: ${WORDPRESS_IMAGE_TAG}
    volumes:
      - wordpress-data:/bitnami/wordpress
    environment:
      WORDPRESS_DATABASE_HOST: mariadb
      WORDPRESS_DATABASE_PORT_NUMBER: 3306
      WORDPRESS_DATABASE_NAME: ${WORDPRESS_DB_NAME}
      WORDPRESS_DATABASE_USER: ${WORDPRESS_DB_USER}
      WORDPRESS_DATABASE_PASSWORD: ${WORDPRESS_DB_PASSWORD}
      WORDPRESS_TABLE_PREFIX: ${WORDPRESS_TABLE_PREFIX}
      WORDPRESS_BLOG_NAME: ${WORDPRESS_BLOG_NAME}
      WORDPRESS_FIRST_NAME: ${WORDPRESS_ADMIN_NAME}
      WORDPRESS_LAST_NAME: ${WORDPRESS_ADMIN_LASTNAME}
      WORDPRESS_USERNAME: ${WORDPRESS_ADMIN_USERNAME}
      WORDPRESS_PASSWORD: ${WORDPRESS_ADMIN_PASSWORD}
      WORDPRESS_EMAIL: ${WORDPRESS_ADMIN_EMAIL}
      WORDPRESS_SMTP_HOST: ${WORDPRESS_SMTP_ADDRESS}
      WORDPRESS_SMTP_PORT: ${WORDPRESS_SMTP_PORT}
      WORDPRESS_SMTP_USER: ${WORDPRESS_SMTP_USER_NAME}
      WORDPRESS_SMTP_PASSWORD: ${WORDPRESS_SMTP_PASSWORD}
    networks:
      - wordpress-network
      - traefik-network
    healthcheck:
      test: timeout 10s bash -c ':> /dev/tcp/127.0.0.1/8080' || exit 1
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 90s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.wordpress.rule=Host(`${WORDPRESS_HOSTNAME}`)"
      - "traefik.http.routers.wordpress.service=wordpress"
      - "traefik.http.routers.wordpress.entrypoints=websecure"
      - "traefik.http.services.wordpress.loadbalancer.server.port=8080"
      - "traefik.http.routers.wordpress.tls=true"
      - "traefik.http.routers.wordpress.tls.certresolver=letsencrypt"
      - "traefik.http.services.wordpress.loadbalancer.passhostheader=true"
      - "traefik.http.routers.wordpress.middlewares=compresstraefik"
      - "traefik.http.middlewares.compresstraefik.compress=true"
      - "traefik.docker.network=traefik-network"
    restart: unless-stopped
    depends_on:
      mariadb:
        condition: service_healthy
      traefik:
        condition: service_healthy

  traefik:
    image: ${TRAEFIK_IMAGE_TAG}
    command:
      - "--log.level=${TRAEFIK_LOG_LEVEL}"
      - "--accesslog=true"
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--ping=true"
      - "--ping.entrypoint=ping"
      - "--entryPoints.ping.address=:8082"
      - "--entryPoints.web.address=:80"
      - "--entryPoints.websecure.address=:443"
      - "--providers.docker=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedByDefault=false"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=${TRAEFIK_ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/etc/traefik/acme/acme.json"
      - "--metrics.prometheus=true"
      - "--metrics.prometheus.buckets=0.1,0.3,1.2,5.0"
      - "--global.checkNewVersion=true"
      - "--global.sendAnonymousUsage=false"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - traefik-certificates:/etc/traefik/acme
    networks:
      - traefik-network
    ports:
      - "80:80"
      - "443:443"
    healthcheck:
      test: ["CMD", "wget", "http://localhost:8082/ping", "--spider"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`${TRAEFIK_HOSTNAME}`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.services.dashboard.loadbalancer.server.port=8080"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.services.dashboard.loadbalancer.passhostheader=true"
      - "traefik.http.routers.dashboard.middlewares=authtraefik"
      - "traefik.http.middlewares.authtraefik.basicauth.users=${TRAEFIK_BASIC_AUTH}"
      - "traefik.http.routers.http-catchall.rule=HostRegexp(`{host:.+}`)"
      - "traefik.http.routers.http-catchall.entrypoints=web"
      - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
    restart: unless-stopped
EOF

    print_success "Đã tạo file docker-compose.yml"
}

# Tạo Docker networks
create_networks() {
    print_status "Tạo Docker networks..."
    
    # Kiểm tra và tạo networks nếu chưa tồn tại
    if ! docker network ls | grep -q "traefik-network"; then
        docker network create traefik-network
        print_success "Đã tạo traefik-network"
    else
        print_warning "traefik-network đã tồn tại"
    fi
    
    if ! docker network ls | grep -q "wordpress-network"; then
        docker network create wordpress-network
        print_success "Đã tạo wordpress-network"
    else
        print_warning "wordpress-network đã tồn tại"
    fi
}

# Kiểm tra cấu hình
validate_config() {
    print_status "Kiểm tra cấu hình Docker Compose..."
    
    if docker-compose config > /dev/null 2>&1; then
        print_success "Cấu hình Docker Compose hợp lệ"
    else
        print_error "Cấu hình Docker Compose có lỗi:"
        docker-compose config
        exit 1
    fi
}

# Pull Docker images
pull_images() {
    print_status "Tải các Docker images..."
    docker-compose pull
    print_success "Đã tải xong các images"
}

# Deploy services
deploy_services() {
    print_status "Triển khai các services..."
    
    # Deploy với verbose output
    docker-compose -p vuamatdung up -d
    
    # Chờ một chút để services khởi động
    sleep 10
    
    print_success "Đã triển khai các services"
}

# Kiểm tra trạng thái services
check_services() {
    print_status "Kiểm tra trạng thái các services..."
    
    echo ""
    echo "=== TRẠNG THÁI CONTAINERS ==="
    docker-compose -p vuamatdung ps
    
    echo ""
    echo "=== KIỂM TRA HEALTH CHECKS ==="
    
    # Chờ health checks
    print_status "Đang chờ MariaDB khởi động..."
    for i in {1..30}; do
        if docker-compose -p vuamatdung ps mariadb | grep -q "healthy"; then
            print_success "MariaDB đã sẵn sàng"
            break
        fi
        sleep 2
        echo -n "."
    done
    
    print_status "Đang chờ Traefik khởi động..."
    for i in {1..15}; do
        if docker-compose -p vuamatdung ps traefik | grep -q "healthy"; then
            print_success "Traefik đã sẵn sàng"
            break
        fi
        sleep 2
        echo -n "."
    done
    
    print_status "Đang chờ WordPress khởi động..."
    for i in {1..45}; do
        if docker-compose -p vuamatdung ps wordpress | grep -q "healthy"; then
            print_success "WordPress đã sẵn sàng"
            break
        fi
        sleep 2
        echo -n "."
    done
}

# Tạo script quản lý
create_management_scripts() {
    print_status "Tạo scripts quản lý..."
    
    # Script khởi động
    cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose -p vuamatdung up -d
echo "WordPress đã được khởi động"
EOF
    chmod +x start.sh
    
    # Script dừng
    cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker-compose -p vuamatdung down
echo "WordPress đã được dừng"
EOF
    chmod +x stop.sh
    
    # Script xem logs
    cat > logs.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Chọn service để xem logs:"
echo "1) Tất cả"
echo "2) WordPress"
echo "3) MariaDB"
echo "4) Traefik"
read -p "Nhập lựa chọn (1-4): " choice

case $choice in
    1) docker-compose -p vuamatdung logs -f ;;
    2) docker-compose -p vuamatdung logs -f wordpress ;;
    3) docker-compose -p vuamatdung logs -f mariadb ;;
    4) docker-compose -p vuamatdung logs -f traefik ;;
    *) echo "Lựa chọn không hợp lệ" ;;
esac
EOF
    chmod +x logs.sh
    
    # Script backup
    cat > backup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Đang backup database..."
docker exec vuamatdung_mariadb_1 mysqldump -u root -pbanhbeoNha@123 Vuamatdung > "$BACKUP_DIR/database.sql"

echo "Đang backup WordPress files..."
docker run --rm -v vuamatdung_wordpress-data:/data -v $(pwd)/$BACKUP_DIR:/backup alpine tar czf /backup/wordpress-files.tar.gz -C /data .

echo "Backup hoàn tất tại: $BACKUP_DIR"
EOF
    chmod +x backup.sh
    
    print_success "Đã tạo scripts quản lý: start.sh, stop.sh, logs.sh, backup.sh"
}

# Hiển thị thông tin kết thúc
show_completion_info() {
    echo ""
    echo "================================================================"
    print_success "TRIỂN KHAI HOÀN TẤT!"
    echo "================================================================"
    echo ""
    echo "🌐 Trang web: https://vuamatdung.com"
    echo "⚙️  Traefik Dashboard: https://traefik.vuamatdung.com"
    echo "   Username: dinhlinh"
    echo "   Password: [như đã cấu hình]"
    echo ""
    echo "🔧 WordPress Admin:"
    echo "   URL: https://vuamatdung.com/wp-admin"
    echo "   Username: admin"
    echo "   Password: banhbeoNha@123"
    echo ""
    echo "📁 Thư mục project: $(pwd)"
    echo ""
    echo "🛠️  Các lệnh quản lý:"
    echo "   ./start.sh     - Khởi động services"
    echo "   ./stop.sh      - Dừng services"
    echo "   ./logs.sh      - Xem logs"
    echo "   ./backup.sh    - Backup dữ liệu"
    echo ""
    echo "📊 Kiểm tra trạng thái:"
    echo "   docker-compose -p vuamatdung ps"
    echo "   docker-compose -p vuamatdung logs -f"
    echo ""
    print_warning "LƯU Ý: Đảm bảo Cloudflare Tunnel đã được cấu hình đúng và trỏ về localhost:80 và localhost:443"
    echo "================================================================"
}

# Hàm main
main() {
    echo ""
    echo "================================================================"
    echo "🚀 SCRIPT TỰ ĐỘNG TRIỂN KHAI WORDPRESS VỚI DOCKER"
    echo "================================================================"
    echo ""
    
    # Thực hiện các bước
    check_root
    check_docker
    create_project_dir
    create_env_file
    create_docker_compose
    create_networks
    validate_config
    pull_images
    deploy_services
    check_services
    create_management_scripts
    show_completion_info
    
    # Hỏi có muốn xem logs không
    echo ""
    read -p "Bạn có muốn xem logs để kiểm tra? (y/N): " view_logs
    if [[ $view_logs =~ ^[Yy]$ ]]; then
        echo ""
        print_status "Hiển thị logs (Ctrl+C để thoát):"
        docker-compose -p vuamatdung logs -f
    fi
}

# Chạy script
main "$@"
