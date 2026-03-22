# 第五堂：Deployment + Service + DNS + Namespace

## 事前準備

```bash
# 確認 minikube 在跑
minikube status
kubectl get nodes
```

## Lab 清單

| Lab | 檔案 | 學什麼 |
|:---:|------|--------|
| 1 | `deployment.yaml` | Deployment 基本操作：建立、查看、刪 Pod 看自動重建 |
| 2 | （指令操作） | 滾動更新與回滾：set image、rollout undo |
| 3 | `service-clusterip.yaml` | ClusterIP Service：叢集內部存取 + 負載均衡驗證 |
| 4 | `service-nodeport.yaml` | NodePort Service：從外部瀏覽器存取 |
| 5 | （指令操作） | DNS 與服務發現：用服務名稱連線 |
| 6 | `namespace-practice.yaml` | Namespace 隔離：在不同 Namespace 部署相同應用 |
| 7 | `full-stack.yaml` | 完整練習：API + 前端 + Service + Namespace |

---

## Lab 1：第一個 Deployment

```bash
# 部署 3 副本的 nginx
kubectl apply -f deployment.yaml

# 查看 Deployment
kubectl get deployments
kubectl get deploy                    # 縮寫

# 查看 ReplicaSet（Deployment 自動建立的）
kubectl get replicasets
kubectl get rs                        # 縮寫

# 查看 Pod（注意名字的格式：deployment-replicaset-random）
kubectl get pods
kubectl get pods -o wide              # 看 Pod 分散到哪些 Node

# 看三層關係
kubectl describe deployment nginx-deploy

# 重點實驗：刪掉一個 Pod，看自動重建
kubectl delete pod <任意一個 pod 名字>
kubectl get pods                      # 馬上會看到新的 Pod 出現！

# 擴容到 5 個
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods                      # 應該看到 5 個

# 縮容回 3 個
kubectl scale deployment nginx-deploy --replicas=3
kubectl get pods                      # 多的 Pod 會被刪掉
```

## Lab 2：滾動更新與回滾

```bash
# 看目前的 image 版本
kubectl describe deployment nginx-deploy | grep Image

# 更新到 nginx:1.28（滾動更新）
kubectl set image deployment/nginx-deploy nginx=nginx:1.28

# 即時觀察更新過程
kubectl rollout status deployment/nginx-deploy

# 查看更新歷史
kubectl rollout history deployment/nginx-deploy

# 確認新版本
kubectl describe deployment nginx-deploy | grep Image

# --- 故意搞壞：更新到不存在的 image ---
kubectl set image deployment/nginx-deploy nginx=nginx:9.9.9

# 觀察（會看到新 Pod 一直 ImagePullBackOff）
kubectl get pods
kubectl rollout status deployment/nginx-deploy
# 按 Ctrl+C 停止

# 回滾到上一個版本
kubectl rollout undo deployment/nginx-deploy

# 確認回滾成功
kubectl rollout status deployment/nginx-deploy
kubectl describe deployment nginx-deploy | grep Image
kubectl get pods                      # 全部 Running
```

## Lab 3：ClusterIP Service

```bash
# 確認 Deployment 還在跑
kubectl get pods -l app=nginx

# 建立 ClusterIP Service
kubectl apply -f service-clusterip.yaml

# 查看 Service
kubectl get services
kubectl get svc                       # 縮寫

# 查看 Service 細節（注意 Endpoints 列出了 Pod 的 IP）
kubectl describe service nginx-svc

# 驗證負載均衡：從臨時 Pod 去 curl Service
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- sh

# 進到 test-curl 後，連續 curl 幾次：
curl http://nginx-svc
curl http://nginx-svc
curl http://nginx-svc
# 觀察回應的 Server header 或 Pod hostname
# 輸入 exit 離開（Pod 會自動刪除）
```

## Lab 4：NodePort Service

```bash
# 建立 NodePort Service
kubectl apply -f service-nodeport.yaml

# 查看 Service（注意 PORT(S) 欄位顯示 80:30080）
kubectl get svc

# 取得 minikube 的 IP
minikube ip

# 用 curl 從外部存取（替換成你的 minikube IP）
curl http://<minikube-ip>:30080

# 或者用 minikube 內建指令直接開瀏覽器
minikube service nginx-nodeport

# 清理（留著 ClusterIP 給下一個 Lab 用）
kubectl delete svc nginx-nodeport
```

## Lab 5：DNS 與服務發現

```bash
# 確認 ClusterIP Service 還在
kubectl get svc nginx-svc

# 從臨時 Pod 測試 DNS
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- sh

# 進到 dns-test 後：
# 用服務名稱連線（最簡短寫法）
wget -qO- http://nginx-svc

# 完整 DNS 名稱（FQDN）
wget -qO- http://nginx-svc.default.svc.cluster.local

# 查看 DNS 解析
nslookup nginx-svc

# 輸入 exit 離開
```

## Lab 6：Namespace 隔離

```bash
# 建立 dev 和 staging 兩個 Namespace
kubectl apply -f namespace-practice.yaml

# 查看所有 Namespace
kubectl get namespaces
kubectl get ns                        # 縮寫

# 在 dev namespace 部署 nginx
kubectl create deployment nginx-dev --image=nginx:1.27 -n dev
kubectl get pods -n dev

# 在 staging namespace 也部署 nginx（名字可以一樣！）
kubectl create deployment nginx-dev --image=nginx:1.27 -n staging
kubectl get pods -n staging

# 兩個 Namespace 各自獨立，互不干擾
kubectl get deployments --all-namespaces

# 在 dev 建立 Service
kubectl expose deployment nginx-dev --port=80 --type=ClusterIP -n dev

# 跨 Namespace 存取（從 default 存取 dev 的 Service）
kubectl run cross-ns-test --image=busybox:1.36 --rm -it --restart=Never -- sh
# 進去後：
wget -qO- http://nginx-dev.dev.svc.cluster.local
# 注意：跨 Namespace 要用完整 FQDN
exit

# 清理
kubectl delete namespace dev staging
```

## Lab 7：完整練習

```bash
# 一次部署所有資源（Namespace + Deployment + Service）
kubectl apply -f full-stack.yaml

# 查看 fullstack-demo namespace 的所有資源
kubectl get all -n fullstack-demo

# 應該看到：
# - 2 個 Deployment（api-deploy、frontend-deploy）
# - 2 個 ReplicaSet
# - 4 個 Pod（api 2 個 + frontend 2 個）
# - 2 個 Service（api-svc、frontend-svc）

# 驗證前端可以從外部存取
minikube service frontend-svc -n fullstack-demo

# 驗證 API 可以從前端 Pod 存取（叢集內部）
kubectl exec -it <frontend-pod-name> -n fullstack-demo -- curl http://api-svc

# 驗證 DNS 解析
kubectl run dns-final --image=busybox:1.36 -n fullstack-demo --rm -it --restart=Never -- nslookup api-svc

# 清理
kubectl delete namespace fullstack-demo
```

## 最終清理

```bash
# 刪除 default namespace 的資源
kubectl delete deployment nginx-deploy
kubectl delete svc nginx-svc
kubectl delete svc nginx-nodeport 2>/dev/null

# 確認清理乾淨
kubectl get all
```

---

## 學完驗證清單

- [ ] 能寫出 Deployment YAML，指定副本數
- [ ] 刪掉 Pod 後看到 K8s 自動重建
- [ ] `kubectl scale` 可以擴容和縮容
- [ ] `kubectl set image` + `kubectl rollout undo` 完成更新和回滾
- [ ] 能建立 ClusterIP Service，從另一個 Pod 用 curl 連到
- [ ] 能建立 NodePort Service，從瀏覽器存取
- [ ] 在 Pod 裡用服務名稱（不用 IP）連到 Service
- [ ] 知道 `<service>.<namespace>.svc.cluster.local` 的 DNS 格式
- [ ] 能建立 Namespace，在不同 Namespace 部署同名應用
- [ ] 跨 Namespace 存取需要用完整 FQDN

---

## 反思問題（下堂課會回答）

> 你的 API 在跑了、NodePort 也建好了，使用者可以用 `http://<node-ip>:30080` 存取。
> 但是在生產環境，你不可能叫使用者輸入 IP 和 Port。
>
> **問題 1：怎麼讓使用者用 `https://myapp.com` 就能連到你的服務？**
>
> **問題 2：你的資料庫密碼現在寫死在 Deployment YAML 裡，推到 Git 就全世界都看到了。怎麼安全地管理這些敏感資訊？**
