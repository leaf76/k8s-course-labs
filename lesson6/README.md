# 第六堂：Ingress + 配置管理 + 資料持久化

## 事前準備

```bash
# 確認 k3s 叢集在跑
kubectl get nodes

# 確認上堂課的資源已清理
kubectl get all
```

## Lab 清單

| Lab | 檔案 | 學什麼 |
|:---:|------|--------|
| 1 | `ingress-basic.yaml` | Ingress path-based routing：根據 URL 路徑導流量 |
| 2 | `ingress-host.yaml` | Ingress host-based routing：根據域名導流量 |
| 3 | `configmap-literal.yaml` | ConfigMap：用環境變數注入設定 |
| 4 | `configmap-nginx.yaml` | ConfigMap 掛載為檔案：管理 Nginx 設定檔 + 熱更新 |
| 5 | `secret-db.yaml` | Secret：管理 MySQL 密碼（Base64 不是加密！） |
| 6 | `pv-pvc.yaml` | PV + PVC 靜態佈建：資料持久化，刪 Pod 資料還在 |
| 7 | `statefulset-mysql.yaml` | StatefulSet：有狀態應用部署（MySQL 主從） |
| 8 | （指令操作） | Helm 入門：helm install / upgrade / rollback |

---

## Lab 1：Ingress Path-based Routing

### 前置：啟用 Ingress Controller

```bash
# k3s 內建 Traefik，預設已啟用，確認一下：
kubectl get pods -n kube-system | grep traefik

# 如果用 minikube：
minikube addons enable ingress
kubectl get pods -n ingress-nginx    # 等到 Running
```

### 部署與驗證

```bash
# 部署 Deployment + Service + Ingress
kubectl apply -f ingress-basic.yaml

# 查看 Ingress
kubectl get ingress
kubectl describe ingress app-ingress

# 取得 Ingress 的存取 IP
# k3s：用任一 Node 的 IP
kubectl get nodes -o wide

# minikube：
minikube ip

# 測試 path routing
curl http://<NODE-IP>/              # 應該看到 Nginx 歡迎頁
curl http://<NODE-IP>/api           # 應該看到 "Hello from API"
```

## Lab 2：Ingress Host-based Routing

```bash
# 先修改 /etc/hosts（模擬 DNS）
# 把 <NODE-IP> 替換成你的 Node IP
sudo sh -c 'echo "<NODE-IP> app.example.com api.example.com" >> /etc/hosts'

# 部署 host-based Ingress
kubectl apply -f ingress-host.yaml

# 查看
kubectl get ingress

# 測試 host routing
curl http://app.example.com         # Nginx 歡迎頁
curl http://api.example.com         # "Hello from API"

# 清理 /etc/hosts（記得刪掉剛才加的那行）
```

## Lab 3：ConfigMap（環境變數注入）

```bash
# 部署 ConfigMap + Deployment
kubectl apply -f configmap-literal.yaml

# 查看 ConfigMap
kubectl get configmap
kubectl describe configmap app-config

# 驗證環境變數有注入
kubectl logs deployment/app-with-config | head -20
# 應該看到 APP_ENV=production、LOG_LEVEL=info 等

# 也可以進 Pod 裡確認
kubectl exec deployment/app-with-config -- env | grep APP_ENV

# --- 修改 ConfigMap ---
kubectl edit configmap app-config
# 把 LOG_LEVEL 改成 debug，存檔離開

# ⚠️ 環境變數不會自動更新！要重啟 Pod 才會生效
kubectl rollout restart deployment/app-with-config
kubectl logs deployment/app-with-config | grep LOG_LEVEL
```

### 用指令建立 ConfigMap（不寫 YAML）

```bash
# 從 literal 建立
kubectl create configmap my-config --from-literal=KEY1=value1 --from-literal=KEY2=value2

# 從檔案建立
echo "server { listen 80; }" > /tmp/nginx.conf
kubectl create configmap nginx-conf --from-file=/tmp/nginx.conf

# 查看
kubectl get configmap my-config -o yaml
```

## Lab 4：ConfigMap 掛載為檔案 + 熱更新

```bash
# 部署
kubectl apply -f configmap-nginx.yaml

# 驗證設定檔有掛載進去
kubectl exec deployment/nginx-custom -- cat /etc/nginx/conf.d/default.conf

# 測試 /healthz 端點
kubectl port-forward svc/nginx-custom-svc 8080:80 &
curl http://localhost:8080/healthz    # 應該回 OK

# --- 熱更新測試 ---
# 修改 ConfigMap
kubectl edit configmap nginx-config
# 把 /healthz 的回應從 'OK' 改成 'HEALTHY'，存檔

# 等 30-60 秒，確認檔案自動更新了
kubectl exec deployment/nginx-custom -- cat /etc/nginx/conf.d/default.conf
# 應該看到新的內容

# ⚠️ 但 Nginx 不會自動 reload！要手動：
kubectl exec deployment/nginx-custom -- nginx -s reload
curl http://localhost:8080/healthz    # 應該回 HEALTHY

# 清理 port-forward
kill %1
```

## Lab 5：Secret（MySQL 密碼）

```bash
# 部署 Secret + MySQL
kubectl apply -f secret-db.yaml

# 查看 Secret（注意值是被隱藏的）
kubectl get secret mysql-secret
kubectl describe secret mysql-secret    # 只顯示大小，不顯示值

# 要看實際值（Base64 編碼）：
kubectl get secret mysql-secret -o yaml
# 再手動解碼：
echo "cm9vdHBhc3N3b3JkMTIz" | base64 -d    # rootpassword123

# 等 MySQL 啟動（約 30 秒）
kubectl get pods -l app=mysql -w         # 等到 Running，Ctrl+C

# 驗證：用密碼連進 MySQL
kubectl exec -it deployment/mysql-deploy -- mysql -u root -prootpassword123 -e "SHOW DATABASES;"
# 應該看到 myappdb

# --- 用指令建立 Secret（推薦，不用手動 Base64）---
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=supersecret123

kubectl get secret my-secret -o yaml
```

## Lab 6：PV + PVC（資料持久化）

```bash
# 部署 PV + PVC + Deployment
kubectl apply -f pv-pvc.yaml

# 查看 PV 和 PVC 的狀態
kubectl get pv                  # STATUS 應該是 Bound
kubectl get pvc                 # STATUS 應該是 Bound

# 查看 Pod 寫入的資料
kubectl logs deployment/app-with-storage

# --- 重點實驗：刪掉 Pod，資料還在嗎？---
kubectl delete pod -l app=app-with-storage

# 等新 Pod 跑起來
kubectl get pods -l app=app-with-storage -w    # Ctrl+C

# 再看日誌 — 應該看到之前寫入的資料還在，加上新的一行！
kubectl logs deployment/app-with-storage

# --- 對照：沒有 PVC 的話 ---
# 不掛 PVC 的 Pod，刪掉後資料就消失了
# 這跟 Docker 不掛 Volume 是一樣的道理
```

## Lab 7：StatefulSet（MySQL）

```bash
# 部署 Headless Service + Secret + StatefulSet
kubectl apply -f statefulset-mysql.yaml

# 觀察有序啟動（mysql-0 先起來，再起 mysql-1）
kubectl get pods -w             # 等兩個都 Running，Ctrl+C

# 注意 Pod 名稱是固定的，不是 random
kubectl get pods -l app=mysql-sts
# mysql-0
# mysql-1

# 查看每個 Pod 有自己的 PVC
kubectl get pvc
# mysql-data-mysql-0
# mysql-data-mysql-1

# 用 DNS 名稱存取個別 Pod
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup mysql-0.mysql-headless
# 應該解析到 mysql-0 的 Pod IP

# 連進 mysql-0
kubectl exec -it mysql-0 -- mysql -u root -prootpass123 -e "CREATE DATABASE testdb;"

# 刪掉 mysql-0，等它重建
kubectl delete pod mysql-0
kubectl get pods -w             # mysql-0 會重新建立（同一個名字！）

# 確認資料還在
kubectl exec -it mysql-0 -- mysql -u root -prootpass123 -e "SHOW DATABASES;"
# 應該還看得到 testdb

# --- 有序刪除：縮容時從最大編號開始刪 ---
kubectl scale statefulset mysql --replicas=1
kubectl get pods -w             # mysql-1 先被刪除，mysql-0 留著
kubectl scale statefulset mysql --replicas=2
kubectl get pods -w             # mysql-1 重新建立
```

## Lab 8：Helm 入門

```bash
# --- 安裝 Helm ---
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# --- 基本操作 ---

# 加入官方 Chart 倉庫
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 搜尋可用的 Chart
helm search repo redis

# 安裝 Redis（一行搞定，不用自己寫 YAML）
helm install my-redis bitnami/redis --set auth.password=myredis123

# 查看安裝了什麼
kubectl get all -l app.kubernetes.io/instance=my-redis
helm list

# 查看 Release 的詳細資訊
helm status my-redis

# --- values.yaml 客製化 ---

# 查看有哪些可以設定的參數
helm show values bitnami/redis | head -50

# 用 --set 覆蓋參數
helm upgrade my-redis bitnami/redis \
  --set auth.password=myredis123 \
  --set replica.replicaCount=2

# 查看升級歷史
helm history my-redis

# 回滾到上一版
helm rollback my-redis 1

# --- 清理 ---
helm uninstall my-redis
```

---

## 最終清理

```bash
# 刪除所有本堂課建立的資源
kubectl delete -f ingress-basic.yaml 2>/dev/null
kubectl delete -f ingress-host.yaml 2>/dev/null
kubectl delete -f configmap-literal.yaml 2>/dev/null
kubectl delete -f configmap-nginx.yaml 2>/dev/null
kubectl delete -f secret-db.yaml 2>/dev/null
kubectl delete -f pv-pvc.yaml 2>/dev/null
kubectl delete -f statefulset-mysql.yaml 2>/dev/null

# 刪除手動建立的資源
kubectl delete configmap my-config nginx-conf 2>/dev/null
kubectl delete secret my-secret 2>/dev/null

# 確認清理乾淨
kubectl get all
kubectl get pv,pvc
kubectl get configmap
kubectl get secret
kubectl get ingress
```

---

## 學完驗證清單

- [ ] 能安裝 Ingress Controller，建立 path-based 和 host-based routing
- [ ] 能用 ConfigMap 管理設定，注入為環境變數或掛載為檔案
- [ ] 知道 ConfigMap Volume 掛載支援熱更新，但 subPath 不會更新
- [ ] 能用 Secret 管理敏感資訊，知道 Base64 不是加密
- [ ] 能用 `kubectl create secret` 指令建立 Secret（不用手動 Base64）
- [ ] 能建立 PV + PVC，驗證刪 Pod 後資料還在
- [ ] 知道 PV 的 AccessMode（RWO/ROX/RWX）和 ReclaimPolicy（Retain/Delete）
- [ ] 能用 StatefulSet 部署 MySQL，理解固定名稱 + 有序啟動 + 獨立 PVC
- [ ] 知道 Headless Service 的作用（每個 Pod 有自己的 DNS）
- [ ] 能用 Helm 安裝、升級、回滾一個 Chart

---

## 反思問題（下堂課會回答）

> 你的系統全部跑起來了：Ingress 設好了、ConfigMap 分離了、Secret 管密碼了、PVC 資料也不會丟了。
> 看起來很完美，但有一個隱藏的炸彈：
>
> **你的 API Pod 裡的程式死鎖了（deadlock），不再處理任何請求。**
> 但從 K8s 的角度看，Pod 的 STATUS 還是 `Running`（因為 process 沒有退出）。
> Service 照樣把流量送過去，使用者看到的是 502 Bad Gateway。
>
> **問題：K8s 怎麼知道一個 Pod「活著但不健康」？你要怎麼告訴 K8s「這個 Pod 雖然 Running，但別再送流量給它了」？**
>
> 提示：想想 Docker 的 `HEALTHCHECK` 指令...
>
> -- 下堂課我們來教 Probe（健康檢查）。
