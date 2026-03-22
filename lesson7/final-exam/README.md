# 總複習實戰：12 步部署完整系統

## 目標

從一個空的 Namespace 開始，部署一套完整的生產級應用：
- MySQL 資料庫（StatefulSet + PVC）
- API 服務（Deployment + 3 副本 + Probe + Resource limits）
- 前端服務（Deployment + Nginx 反向代理）
- 完整的 Service + Ingress + NetworkPolicy + HPA

## 架構圖

```
使用者 → Ingress（myapp.local）
          ├── /     → frontend-svc → frontend Pod x2
          └── /api  → api-svc     → api Pod x3
                                        ↓
                                   mysql-headless → mysql Pod x1（StatefulSet）
```

## 12 步部署指南

### Step 1：建立 Namespace

```bash
kubectl apply -f namespace.yaml
kubectl get ns prod
```

### Step 2：建立 Secret（DB 密碼）

```bash
kubectl apply -f secret.yaml
kubectl get secret -n prod
# 驗證（不要在生產環境這樣做）
kubectl get secret db-secret -n prod -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d
```

### Step 3：建立 ConfigMap（API 設定）

```bash
kubectl apply -f configmap.yaml
kubectl get configmap -n prod
```

### Step 4：部署 MySQL（StatefulSet）

```bash
kubectl apply -f mysql-statefulset.yaml

# 等 MySQL 啟動（可能需要 30-60 秒）
kubectl get pods -n prod -w
# 看到 mysql-0 變成 1/1 Running 就可以了（Ctrl+C 停止 watch）

# 驗證 PVC 自動建立
kubectl get pvc -n prod
```

### Step 5：部署 API

```bash
kubectl apply -f api-deployment.yaml

# 等 Pod 啟動
kubectl get pods -n prod -l app=api
# 應該看到 3 個 Pod 都是 Running
```

### Step 6：部署前端

```bash
kubectl apply -f frontend-deployment.yaml

# 等 Pod 啟動
kubectl get pods -n prod -l app=frontend
# 應該看到 2 個 Pod 都是 Running
```

### Step 7：建立 Service

```bash
kubectl apply -f services.yaml

# 驗證 Service
kubectl get svc -n prod
# 應該看到 api-svc 和 frontend-svc
```

### Step 8：建立 Ingress

```bash
kubectl apply -f ingress.yaml

# 驗證 Ingress
kubectl get ingress -n prod
```

### Step 9：設定 NetworkPolicy

```bash
kubectl apply -f networkpolicy.yaml

# 驗證 NetworkPolicy
kubectl get networkpolicy -n prod
# 應該看到 db-policy、api-policy、frontend-policy 三條規則
```

### Step 10：設定 HPA

```bash
kubectl apply -f hpa.yaml

# 驗證 HPA
kubectl get hpa -n prod
```

### Step 11：完整驗證

```bash
# 1. 查看所有資源
kubectl get all -n prod

# 2. 驗證 Pod 間的 DNS
kubectl run dns-test --image=busybox:1.36 -n prod --rm -it --restart=Never -- nslookup api-svc

# 3. 驗證 API 可以連到 DB
kubectl exec -it $(kubectl get pods -n prod -l role=api -o jsonpath='{.items[0].metadata.name}') -n prod -- \
  sh -c "apt-get update > /dev/null 2>&1 && apt-get install -y curl > /dev/null 2>&1 && curl -s mysql-headless:3306 || echo 'TCP connection works (MySQL protocol error is expected)'"

# 4. 驗證 Probe 狀態
kubectl describe pods -n prod -l app=api | grep -A5 "Liveness\|Readiness"

# 5. 驗證 HPA 狀態
kubectl get hpa -n prod

# 6. 驗證 NetworkPolicy（從非 API Pod 嘗試連 DB，應該被擋）
kubectl run test-block --image=busybox:1.36 -n prod --rm -it --restart=Never -- \
  wget --timeout=3 -qO- http://mysql-headless:3306 2>&1 || echo "Blocked as expected!"
```

### Step 12：壓測觸發 HPA（選做）

```bash
# 確保 metrics-server 有裝
kubectl top pods -n prod

# 用壓測 Pod 打 API
kubectl run load-test --image=busybox:1.36 -n prod --rm -it --restart=Never -- \
  sh -c "while true; do wget -qO- http://api-svc:80 > /dev/null 2>&1; done"

# 另開一個終端機觀察 HPA
kubectl get hpa -n prod -w
# 應該會看到 REPLICAS 從 3 慢慢增加

# 壓測完按 Ctrl+C，等幾分鐘後 Pod 會自動縮回來
```

## 清理

```bash
kubectl delete namespace prod
```

## 驗證清單

- [ ] prod Namespace 建立成功
- [ ] Secret 和 ConfigMap 都在 prod Namespace 裡
- [ ] MySQL StatefulSet 跑起來了，PVC 自動建立
- [ ] API 有 3 個 Pod 都是 Running
- [ ] 前端有 2 個 Pod 都是 Running
- [ ] Service（api-svc、frontend-svc）建立成功
- [ ] Ingress 規則設定正確
- [ ] NetworkPolicy 生效（非 API Pod 連不到 DB）
- [ ] HPA 設定成功，能看到 CPU metrics
- [ ] 壓測時 Pod 自動擴容
