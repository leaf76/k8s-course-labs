# 第四堂：K8s 全貌 + Pod + Deployment 入門

## 事前準備

```bash
# 確認 minikube 在跑
minikube status
kubectl get nodes
```

## Lab 清單

| Lab | 檔案 | 對應影片 | 學什麼 |
|:---:|------|:-------:|--------|
| 1 | `pod.yaml` | 4-10 | 第一個 Pod：部署 nginx，完整 CRUD |
| 2 | `pod-broken.yaml` | 4-13 | 排錯：image 拼錯 → ImagePullBackOff |
| 3 | `pod-crash.yaml` | 4-13 | 排錯：CrashLoopBackOff 退避策略 |
| 4 | `pod-sidecar.yaml` | 4-16 | Sidecar：nginx + busybox 共享 Volume |
| 5 | `pod-httpd.yaml` | 4-10 | 自由練習：換 httpd image |
| 6 | `pod-mysql-broken.yaml` / `pod-mysql.yaml` | 4-22 | 環境變數：MySQL 沒設密碼會 crash |
| 7 | `deployment.yaml` | 4-24 | Deployment 初體驗：刪 Pod 自動補回來 |

---

## Lab 1：第一個 Pod

```bash
kubectl apply -f pod.yaml
kubectl get pods
kubectl get pods -o wide
kubectl describe pod my-nginx          # 重點看 Events

kubectl logs my-nginx

kubectl exec -it my-nginx -- /bin/sh
# nginx 沒有預裝 curl，兩種驗證方式：
# 方式 A：直接看檔案
cat /usr/share/nginx/html/index.html
# 方式 B：裝 curl 再連
apt-get update && apt-get install -y curl
curl localhost
exit

# port-forward 在瀏覽器看頁面
kubectl port-forward pod/my-nginx 8080:80
# 開瀏覽器 → http://localhost:8080
# Ctrl+C 停止

# 清理
kubectl delete pod my-nginx
```

## Lab 2：排錯 — ImagePullBackOff

```bash
kubectl apply -f pod-broken.yaml
kubectl get pods                       # 看到 ErrImagePull 或 ImagePullBackOff
kubectl get pods --watch               # 觀察狀態變化（Ctrl+C 停止）
kubectl describe pod broken-pod        # 拉到最下面看 Events → 找到錯誤原因

# 修正：把 pod-broken.yaml 裡的 image 從 ngin 改成 nginx:1.27
kubectl delete pod broken-pod
kubectl apply -f pod-broken.yaml
kubectl get pods                       # 應該變成 Running

# 清理
kubectl delete pod broken-pod
```

## Lab 3：排錯 — CrashLoopBackOff

```bash
kubectl apply -f pod-crash.yaml
kubectl get pods --watch               # 觀察重啟間隔：10s → 20s → 40s → ...
# Ctrl+C 停止觀察
kubectl describe pod crash-pod         # 看 Events 裡的 Back-off restarting
kubectl logs crash-pod                 # 看到 "hello"（容器有跑起來，但馬上 exit 1）

# 清理
kubectl delete pod crash-pod
```

## Lab 4：Sidecar 多容器 Pod

```bash
kubectl apply -f pod-sidecar.yaml
kubectl get pods                       # 看 READY 欄位：2/2

# 製造流量（nginx 沒有 curl，先裝）
kubectl exec -it sidecar-pod -c nginx -- /bin/sh
apt-get update && apt-get install -y curl
curl localhost
curl localhost
curl localhost
exit

# 從 Sidecar 看日誌
kubectl logs sidecar-pod -c log-reader # 看到三次 access log
kubectl logs sidecar-pod -c nginx      # 對比 nginx 的 stdout（沒東西，因為被 Volume 覆蓋了）

# 清理
kubectl delete pod sidecar-pod
```

> **技術細節**：nginx 官方 Image 預設把 access.log symlink 到 /dev/stdout。
> 掛載 emptyDir 到 /var/log/nginx 後 symlink 被覆蓋，nginx 改寫真正的檔案。
> 所以 `kubectl logs -c nginx` 看不到 access log，但 log-reader 透過共享 Volume 讀得到。

## Lab 5：自由練習 — httpd

```bash
kubectl apply -f pod-httpd.yaml
kubectl get pods

# httpd 也沒有預裝 curl，用 cat 驗證
kubectl exec -it my-httpd -- /bin/sh
cat /usr/local/apache2/htdocs/index.html   # 看到 "It works!"
exit

# 或用 port-forward
kubectl port-forward pod/my-httpd 8080:80
# 瀏覽器 → http://localhost:8080

# 清理
kubectl delete pod my-httpd
```

## Lab 6：環境變數 — MySQL Pod

```bash
# Step 1：先故意做錯（不設密碼）
kubectl apply -f pod-mysql-broken.yaml
kubectl get pods --watch               # 看到 CrashLoopBackOff
# Ctrl+C
kubectl logs mysql-pod                 # 看到 "database is uninitialized and password option is not specified"
kubectl delete pod mysql-pod

# Step 2：用正確的版本（有設密碼）
kubectl apply -f pod-mysql.yaml
kubectl get pods                       # 等到 Running（MySQL image 比較大，要等一下）

# Step 3：進去操作 MySQL
kubectl exec -it mysql-pod -- mysql -u root -pmy-secret
# 注意：-p 和密碼之間沒有空格！

# 在 MySQL 裡面：
CREATE DATABASE testdb;
SHOW DATABASES;                        # 看到 testdb
USE testdb;
CREATE TABLE users (id INT, name VARCHAR(50));
INSERT INTO users VALUES (1, 'Alice');
SELECT * FROM users;                   # 看到 Alice
exit

# 清理
kubectl delete pod mysql-pod
```

> **思考**：密碼 `my-secret` 直接寫在 YAML 裡面，git commit 就全世界看到了。
> 第六堂會學 Secret 來解決這個問題。

## Lab 7：Deployment 初體驗

```bash
# Step 1：先感受一下 Pod 的脆弱
kubectl apply -f pod.yaml
kubectl get pods                       # my-nginx Running
kubectl delete pod my-nginx
kubectl get pods                       # 空了！沒人幫你補

# Step 2：改用 Deployment
kubectl apply -f deployment.yaml
kubectl get deploy                     # 看到 my-nginx，READY 3/3
kubectl get pods                       # 看到 3 個 Pod
kubectl get rs                         # 看到 ReplicaSet（三層關係）

# Step 3：手動刪一個 Pod，看它自動補回來
kubectl delete pod <複製其中一個 Pod 的名字>
kubectl get pods                       # 馬上又變回 3 個！

# Step 4：scale 擴縮容
kubectl scale deployment my-nginx --replicas=5
kubectl get pods                       # 5 個
kubectl scale deployment my-nginx --replicas=2
kubectl get pods                       # 多的被砍掉，剩 2 個

# 清理
kubectl delete deployment my-nginx
```

> **對比**：
> - `kubectl delete pod` → Pod 消失了，沒人補
> - Deployment 裡的 Pod 被刪 → 自動補回來
> - 這就是「一個人做事」vs「一個團隊做事」的差別

---

## 學完驗證清單

- [ ] `kubectl get nodes` 看到 Ready
- [ ] 能獨立寫 Pod YAML 部署 nginx
- [ ] `port-forward` 後瀏覽器看到 nginx 頁面
- [ ] 看到 `ImagePullBackOff` 能用 `describe` 找到原因
- [ ] 看到 `CrashLoopBackOff` 知道是容器啟動後 crash
- [ ] Sidecar Pod 的 `READY` 顯示 `2/2`，會用 `-c` 指定容器
- [ ] MySQL Pod 會用 `env` 設定環境變數
- [ ] 知道 `kubectl logs` 看 crash 原因
- [ ] Deployment 建 3 個 Pod，刪一個會自動補回來
- [ ] 會用 `kubectl scale` 調整副本數

## 反思問題（下堂課會回答）

> 你的 nginx Deployment 跑了 3 個 Pod。其他人的 Pod 怎麼連到你的 nginx？
> 直接用 Pod IP 嗎？但 Pod IP 會變啊...
>
> **問題：怎麼讓其他 Pod 用一個穩定的地址連到你的 nginx，不管 Pod 怎麼重建、IP 怎麼變？**
