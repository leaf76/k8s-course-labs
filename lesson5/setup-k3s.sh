#!/usr/bin/env bash
#
# setup-k3s.sh — 一鍵搭建 Multipass + k3s 多節點叢集
#
# 使用方式：
#   chmod +x setup-k3s.sh
#   ./setup-k3s.sh
#
# 前置需求：
#   - 已安裝 Multipass（macOS: brew install multipass / Windows: choco install multipass / Linux: sudo snap install multipass）
#   - 建議至少 8GB RAM 可用（3 台 VM 各 2GB）
#
# 清除叢集：
#   ./setup-k3s.sh cleanup
#

set -euo pipefail

# ---------- 設定 ----------
MASTER_NAME="k3s-master"
WORKER_NAMES=("k3s-worker1" "k3s-worker2")
CPUS=2
MEMORY="2G"
DISK="10G"
KUBECONFIG_PATH="$HOME/.kube/k3s-config"

# ---------- 顏色輸出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- 清除功能 ----------
cleanup() {
    info "開始清除 k3s 叢集..."
    for name in "$MASTER_NAME" "${WORKER_NAMES[@]}"; do
        if multipass info "$name" &>/dev/null; then
            info "刪除 VM: $name"
            multipass delete "$name" --purge
        else
            warn "VM $name 不存在，跳過"
        fi
    done
    if [ -f "$KUBECONFIG_PATH" ]; then
        rm -f "$KUBECONFIG_PATH"
        info "已刪除 kubeconfig: $KUBECONFIG_PATH"
    fi
    info "清除完成！"
    exit 0
}

# 如果傳入 cleanup 參數，執行清除
if [ "${1:-}" = "cleanup" ]; then
    cleanup
fi

# ---------- 檢查 Multipass 是否已安裝 ----------
if ! command -v multipass &>/dev/null; then
    error "找不到 multipass 指令。請先安裝：
  macOS:   brew install multipass
  Windows: choco install multipass
  Linux:   sudo snap install multipass"
fi

info "Multipass 版本: $(multipass version | head -1)"

# ---------- 建立 VM ----------
info "建立 Master VM: $MASTER_NAME"
multipass launch --name "$MASTER_NAME" --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK"

for worker in "${WORKER_NAMES[@]}"; do
    info "建立 Worker VM: $worker"
    multipass launch --name "$worker" --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK"
done

info "所有 VM 建立完成："
multipass list

# ---------- 在 Master 安裝 k3s ----------
info "在 $MASTER_NAME 安裝 k3s..."
multipass exec "$MASTER_NAME" -- bash -c "curl -sfL https://get.k3s.io | sh -"

# 等待 k3s 就緒
info "等待 k3s server 就緒..."
sleep 10
multipass exec "$MASTER_NAME" -- bash -c "sudo kubectl wait --for=condition=Ready node/$MASTER_NAME --timeout=60s" || true

# ---------- 取得 Token 和 Master IP ----------
info "取得 join token 和 Master IP..."
TOKEN=$(multipass exec "$MASTER_NAME" -- sudo cat /var/lib/rancher/k3s/server/node-token)
MASTER_IP=$(multipass info "$MASTER_NAME" | grep IPv4 | awk '{print $2}')

info "Master IP: $MASTER_IP"
info "Token: ${TOKEN:0:20}... (已截斷)"

# ---------- Worker 加入叢集 ----------
for worker in "${WORKER_NAMES[@]}"; do
    info "讓 $worker 加入叢集..."
    multipass exec "$worker" -- bash -c \
        "curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -"
done

# 等待 Worker 就緒
info "等待所有 Worker 加入叢集..."
sleep 15

# ---------- 驗證叢集 ----------
info "驗證叢集狀態："
multipass exec "$MASTER_NAME" -- sudo kubectl get nodes -o wide

# ---------- 複製 kubeconfig 到本機 ----------
info "複製 kubeconfig 到本機..."
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
multipass exec "$MASTER_NAME" -- sudo cat /etc/rancher/k3s/k3s.yaml > "$KUBECONFIG_PATH"

# 替換 127.0.0.1 為 Master 的實際 IP
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS 的 sed 語法不同
    sed -i '' "s/127.0.0.1/$MASTER_IP/g" "$KUBECONFIG_PATH"
else
    sed -i "s/127.0.0.1/$MASTER_IP/g" "$KUBECONFIG_PATH"
fi

chmod 600 "$KUBECONFIG_PATH"

# ---------- 完成 ----------
echo ""
echo "============================================"
info "k3s 多節點叢集搭建完成！"
echo "============================================"
echo ""
echo "使用方式："
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo "  kubectl get nodes"
echo ""
echo "清除叢集："
echo "  ./setup-k3s.sh cleanup"
echo ""
echo "============================================"
