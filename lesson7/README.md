# 第七堂：生產就緒 — 安全、監控與總複習

## 事前準備

```bash
# 確認 k3s 叢集在跑
kubectl get nodes
# 應該看到 master + worker 節點都是 Ready

# 確認 metrics-server 有裝（HPA 需要）
kubectl top nodes
# 如果沒裝，執行：
# kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Lab 清單

| Lab | 檔案 | 學什麼 |
|:---:|------|--------|
| 1 | `deployment-probe.yaml` | Health Check：livenessProbe + readinessProbe |
| 2 | `deployment-resources.yaml` | Resource 管理：requests/limits + OOMKilled |
| 3 | `hpa.yaml` | HPA 自動擴縮：CPU 超標自動加 Pod |
| 4 | `rbac-viewer.yaml` | RBAC：只讀使用者 Role + RoleBinding |
| 5 | `networkpolicy-db.yaml` | NetworkPolicy：DB 只允許 API 連 |
| 6 | `daemonset.yaml` | DaemonSet：每個 Node 跑一個 Pod |
| 7 | `cronjob.yaml` | Job + CronJob：一次性任務 + 排程任務 |
| 8 | `final-exam/` | 總複習：12 步部署完整系統 |

---

## Lab 1：Health Check — Probe

```bash
# 部署帶 Probe 的 Deployment
kubectl apply -f deployment-probe.yaml

# 查看 Pod 狀態
kubectl get pods -l app=api-probe-demo

# 查看 Probe 設定和狀態
kubectl describe pods -l app=api-probe-demo | grep -A10 "Liveness\|Readiness"

# --- 故意搞壞：讓 livenessProbe 失敗 ---
# 進入 Pod，刪掉 nginx 的預設頁面（讓 HTTP GET / 回傳 404）
POD_NAME=$(kubectl get pods -l app=api-probe-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- rm /usr/share/nginx/html/index.html

# 觀察 Pod 的 RESTARTS 數字會開始增加
kubectl get pods -l app=api-probe-demo -w
# 大約 30 秒後（initialDelay + period x failureThreshold），Pod 會被重啟
# 重啟後 nginx 重新載入預設頁面，Probe 就又通過了

# --- 驗證 readinessProbe ---
# readinessProbe 失敗時，Pod 不會被重啟，但會從 Service 的 Endpoints 移除
# 建一個 Service 來觀察
kubectl expose deployment api-probe-demo --port=80 --type=ClusterIP --name=probe-svc
kubectl get endpoints probe-svc
# 正常情況下，Endpoints 會列出所有 Pod 的 IP

# 再次刪掉 index.html
kubectl exec $POD_NAME -- rm /usr/share/nginx/html/index.html

# 觀察 Endpoints（Pod 的 IP 會暫時消失）
kubectl get endpoints probe-svc -w

# 清理
kubectl delete deployment api-probe-demo
kubectl delete svc probe-svc
```

## Lab 2：Resource 管理 — requests / limits

```bash
# 部署帶資源限制的 Deployment
kubectl apply -f deployment-resources.yaml

# 查看資源設定
kubectl describe pods -l app=api-resources-demo | grep -A6 "Limits\|Requests"

# 查看 QoS 等級
kubectl get pods -l app=api-resources-demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.qosClass}{"\n"}{end}'
# 應該是 Burstable（因為 requests != limits）

# --- 觀察 OOMKilled ---
# oom-demo 這個 Pod 會嘗試用 256Mi 記憶體，但限制只有 128Mi
kubectl get pods -l app=oom-demo -w
# 你會看到它不斷重啟，Status 顯示 OOMKilled 或 CrashLoopBackOff

# 查看 OOMKilled 原因
kubectl describe pod -l app=oom-demo | grep -A5 "Last State"

# 查看資源使用量（需要 metrics-server）
kubectl top pods

# 清理
kubectl delete deployment api-resources-demo oom-demo
```

## Lab 3：HPA 自動擴縮

```bash
# 先部署有 resource limits 的 Deployment（HPA 需要）
kubectl apply -f deployment-resources.yaml
# 只用 api-resources-demo，不要 oom-demo
kubectl delete deployment oom-demo 2>/dev/null

# 建立 Service（壓測需要透過 Service 存取）
kubectl expose deployment api-resources-demo --port=80 --target-port=80 --name=api-resources-demo

# 部署 HPA
kubectl apply -f hpa.yaml

# 查看 HPA 狀態
kubectl get hpa

# 壓測觸發擴容（開另一個終端機）
kubectl run load-test --image=busybox:1.36 --rm -it --restart=Never -- \
  sh -c "while true; do wget -qO- http://api-resources-demo > /dev/null 2>&1; done"

# 在原本的終端機觀察 HPA
kubectl get hpa -w
# TARGETS 欄位會從 <unknown> 變成實際的 CPU 百分比
# 超過 50% 後，REPLICAS 會開始增加

# 壓測完（Ctrl+C），等 5 分鐘左右，Pod 會自動縮回來

# 清理
kubectl delete hpa api-hpa
kubectl delete svc api-resources-demo
kubectl delete deployment api-resources-demo
```

## Lab 4：RBAC — 只讀使用者

```bash
# 建立 ServiceAccount + Role + RoleBinding
kubectl apply -f rbac-viewer.yaml

# 驗證：用 viewer-sa 的身份查看 Pod（應該成功）
kubectl get pods --as=system:serviceaccount:default:viewer-sa
# 應該會列出 Pod

# 驗證：用 viewer-sa 的身份嘗試建立 Pod（應該被拒絕）
kubectl run test-forbidden --image=nginx --as=system:serviceaccount:default:viewer-sa
# 應該看到 Error: pods is forbidden

# 驗證：用 viewer-sa 的身份嘗試刪除 Pod（應該被拒絕）
kubectl delete pod <任意 pod> --as=system:serviceaccount:default:viewer-sa
# 應該看到 Error: pods "xxx" is forbidden

# 查看 Role 的權限
kubectl describe role pod-viewer

# 查看 RoleBinding
kubectl describe rolebinding viewer-binding

# 清理
kubectl delete -f rbac-viewer.yaml
```

## Lab 5：NetworkPolicy — DB 只允許 API 連

```bash
# 部署 DB + API + NetworkPolicy
kubectl apply -f networkpolicy-db.yaml

# 等 Pod 都跑起來
kubectl get pods -l "role in (database,api)"

# 驗證：從 API Pod 連 DB（應該成功）
API_POD=$(kubectl get pods -l role=api -o jsonpath='{.items[0].metadata.name}')
kubectl exec $API_POD -- curl -s --max-time 3 http://fake-db-svc:3306
# 會看到回應（可能是亂碼，因為 MySQL port 不是 HTTP，但重點是有回應 = 連線成功）

# 驗證：從其他 Pod 連 DB（應該被擋）
kubectl run test-block --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s --max-time 3 http://fake-db-svc:3306
# 應該 timeout（被 NetworkPolicy 擋掉了）

# 注意：NetworkPolicy 需要 CNI 支援（Calico、Cilium）
# k3s 預設用 Flannel，不支援 NetworkPolicy
# 如果上面的測試沒被擋，需要安裝 Calico：
# kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 清理
kubectl delete -f networkpolicy-db.yaml
```

## Lab 6：DaemonSet — 每個 Node 跑一份

```bash
# 部署 DaemonSet
kubectl apply -f daemonset.yaml

# 查看 DaemonSet
kubectl get daemonset
# DESIRED 和 CURRENT 應該等於你的 Node 數量

# 查看 Pod 分佈在哪些 Node
kubectl get pods -l app=log-collector -o wide
# 每個 Node 都會有一個 Pod

# 看日誌
kubectl logs -l app=log-collector --tail=5

# 如果你加一個新 Node 進叢集，DaemonSet 會自動在新 Node 上建 Pod
# 如果你移除一個 Node，對應的 Pod 也會自動消失

# 清理
kubectl delete daemonset log-collector
```

## Lab 7：Job + CronJob — 一次性任務 + 排程任務

```bash
# 部署 Job 和 CronJob
kubectl apply -f cronjob.yaml

# --- 一次性 Job ---
# 查看 Job 狀態
kubectl get jobs
# 等一下會看到 COMPLETIONS 變成 1/1

# 看 Job 的日誌
kubectl logs job/one-time-job

# --- CronJob ---
# 查看 CronJob
kubectl get cronjobs
# SCHEDULE 欄位顯示 */1 * * * *

# 等一兩分鐘，查看 CronJob 產生的 Job
kubectl get jobs
# 每分鐘會多一個 timestamp-printer-xxxxxx 的 Job

# 看最近一次的日誌（用 --sort-by 找最新的 Pod）
kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# 清理
kubectl delete job one-time-job
kubectl delete cronjob timestamp-printer
```

## Lab 8：總複習 — 從零部署完整系統

詳見 [final-exam/README.md](final-exam/README.md) 的 12 步部署指南。

---

## 最終清理

```bash
# 清理所有 Lab 資源
kubectl delete namespace prod 2>/dev/null
kubectl delete deployment api-probe-demo api-resources-demo oom-demo fake-db fake-api 2>/dev/null
kubectl delete svc probe-svc fake-db-svc 2>/dev/null
kubectl delete daemonset log-collector 2>/dev/null
kubectl delete job one-time-job 2>/dev/null
kubectl delete cronjob timestamp-printer 2>/dev/null
kubectl delete hpa api-hpa 2>/dev/null
kubectl delete -f rbac-viewer.yaml 2>/dev/null
kubectl delete -f networkpolicy-db.yaml 2>/dev/null

# 確認清理乾淨
kubectl get all
```

---

## 學完驗證清單

### Health Check
- [ ] 能寫出 livenessProbe 和 readinessProbe 的 YAML
- [ ] 知道 liveness 失敗 → 重啟，readiness 失敗 → 從 Service 移除
- [ ] 故意讓 Probe 失敗，觀察到 Pod 重啟

### Resource 管理
- [ ] 能設定 requests 和 limits
- [ ] 知道 requests、limits 的差異
- [ ] 觀察到 OOMKilled
- [ ] HPA 在壓測時自動擴容

### RBAC
- [ ] 能建立 Role + RoleBinding + ServiceAccount
- [ ] 用只讀帳號查看成功、建立失敗

### NetworkPolicy
- [ ] 能寫出限制流量的 NetworkPolicy
- [ ] API 可以連 DB，其他 Pod 被擋

### DaemonSet + Job/CronJob
- [ ] DaemonSet 在每個 Node 都有一個 Pod
- [ ] Job 跑完就結束
- [ ] CronJob 每分鐘自動跑一次

### 總複習
- [ ] 從空 Namespace 完成 12 步部署
- [ ] 所有元件跑起來並通過驗證
