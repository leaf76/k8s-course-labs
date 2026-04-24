# Lesson 7 Final Practice: Short Link Lab

## Goal

Deploy a ready-made product to Kubernetes without writing application code.

Students will deploy a short link service that can:

1. Open a web UI.
2. Create a short link from a long URL.
3. Redirect `/r/<code>` to the original URL.
4. Keep data after the API Pod is recreated.
5. Keep data after the PostgreSQL Pod is recreated.
6. Show how the same product can be installed with one Helm command.

## Architecture

```text
Browser
  |
  v
Ingress short.local
  |-- /         -> Frontend Deployment -> url-frontend-service
  |-- /api      -> API Deployment      -> url-api-service
  |-- /r/<code> -> API Deployment      -> url-api-service
                                      |
                                      v
                           PostgreSQL StatefulSet
                                      |
                                      v
                                     PVC
```

## Folder Layout

| Path | Purpose |
|---|---|
| `api/` | Express API source code, migration, and Dockerfile |
| `frontend/` | Static frontend source code and Dockerfile |
| `k8s/` | Public-image Kubernetes YAML fallback |
| `k8s-local/` | Local-image YAML for PostgreSQL, API, frontend, and migration Job |
| `helm/url-shortener/` | Helm chart for one-command install and upgrade |
| `scripts/` | Student scripts for build/save/load/check local images |
| `local-smoke-test.sh` | Instructor-only Docker smoke test for local verification |

## Image Strategy

The default class workflow avoids Docker Hub rate limits. The instructor provides a prebuilt image tar from cloud storage, and users import that tar into every k3s node.

```text
cloud download -> k3s ctr images import -> kubectl apply / helm install
```

Important: Docker and k3s do not necessarily use the same image store. Downloading the tar is not enough; k3s runs Pods from the containerd image store inside each Linux node. Import the tar into both the control plane and worker nodes before applying YAML.

Rule of thumb: if a Pod is scheduled to a node, that node must already have the image. With `imagePullPolicy: Never`, k3s will not pull from Docker Hub as a backup.

For the local-image workflow, use the YAML files in `k8s-local/` for every workload that runs an image from the tar:

| YAML | Image behavior |
|---|---|
| `k8s-local/03-postgres.yaml` | Uses `postgres:15` with `imagePullPolicy: Never` |
| `k8s-local/04-migrate-job.yaml` | Uses `busybox:1.36` and `url-shortener-api:lab` with `imagePullPolicy: Never` |
| `k8s-local/05-api.yaml` | Uses `url-shortener-api:lab` with `imagePullPolicy: Never` |
| `k8s-local/06-frontend.yaml` | Uses `url-shortener-frontend:lab` with `imagePullPolicy: Never` |

The image names stay the same as the imported tar. `postgres:15` still means the local `postgres:15` image inside each k3s node's containerd image store. The important difference is `imagePullPolicy: Never`: if the image was not imported to that node, the Pod fails immediately instead of trying Docker Hub.

### Default: instructor-provided image tar

Download `url-shortener-k3s-images.tar` from the instructor's cloud storage link, then verify the checksum:

```bash
sha256sum ~/Downloads/url-shortener-k3s-images.tar
```

Expected SHA256:

```text
bae34023b8fd055f13235ce239976c95d5f97156bde6bd0452c8de7a76f7fc44
```

Import the tar into every k3s node:

```bash
IMAGE_TAR=~/Downloads/url-shortener-k3s-images.tar \
K3S_NODES="user@192.168.56.10 user@192.168.56.11" \
  ./scripts/load-images-to-k3s-ssh.sh
K3S_NODES="user@192.168.56.10 user@192.168.56.11" ./scripts/check-k3s-images-ssh.sh
```

If you place the tar at the default path `./dist/url-shortener-k3s-images.tar`, `IMAGE_TAR` can be omitted:

```bash
K3S_NODES="user@192.168.56.10 user@192.168.56.11" \
  ./scripts/load-images-to-k3s-ssh.sh
```

The tar file contains:

| Image | Used by |
|---|---|
| `url-shortener-api:lab` | API Deployment and migration Job |
| `url-shortener-frontend:lab` | Frontend Deployment |
| `postgres:15` | PostgreSQL StatefulSet |
| `busybox:1.36` | migration Job init container |

Set `K3S_NODES` to the SSH targets for every k3s node. For a Windows + VMware classroom, this usually means the Linux control plane VM and the Linux worker VM. The machine running the script must be able to SSH into each VM, and the SSH user must be able to run `sudo -n k3s ctr images list -q` without an interactive password prompt.

If your SSH command needs extra options, use `SSH_OPTS`:

```bash
SSH_OPTS="-i ~/.ssh/k8s-lab -o StrictHostKeyChecking=accept-new" \
K3S_NODES="user@192.168.56.10 user@192.168.56.11" \
  ./scripts/load-images-to-k3s-ssh.sh
```

For instructor Multipass environments, use the Multipass helper scripts instead:

```bash
./scripts/load-images-to-k3s-multipass.sh
./scripts/check-k3s-images.sh
```

### Optional: rebuild the image tar

Use this path only when the instructor needs to regenerate the tar before class:

```bash
./scripts/build-local-images.sh
docker pull postgres:15
docker pull busybox:1.36
./scripts/save-k3s-images.sh
```

Only building API/frontend is not enough because PostgreSQL and busybox are still runtime images.

### Fallback: public images

The public-image YAML and chart values can still use these tags:

```text
yanchen184/url-shortener-api:v1
yanchen184/url-shortener-frontend:v1
```

Use this only as a fallback. If the whole class pulls public images at the same time, Docker Hub may rate-limit requests and Pods can enter `ImagePullBackOff`.

## Two-Hour Teaching Flow

| Time | Activity | Expected Result |
|---|---|---|
| 0-10 min | Product demo and architecture | Students know what they are deploying |
| 10-25 min | Namespace, Secret, ConfigMap | Runtime boundary and configuration are ready |
| 25-45 min | PostgreSQL StatefulSet + PVC | Database is running and storage is persistent |
| 45-60 min | Migration Job | `short_links` table exists |
| 60-80 min | API Deployment + Service | `/health`, `/ready`, and `/api/links` are reachable |
| 80-95 min | Frontend Deployment + Service | Web UI is running |
| 95-110 min | Ingress + HPA | `short.local` routes traffic and API can autoscale |
| 110-120 min | Validation and Helm wrap-up | Students can explain manual YAML vs Helm |

## Manual Kubernetes Deployment

Run from this directory:

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secret.yaml
kubectl apply -f k8s/02-configmap.yaml
kubectl apply -f k8s-local/03-postgres.yaml
kubectl apply -f k8s-local/04-migrate-job.yaml
kubectl apply -f k8s-local/05-api.yaml
kubectl apply -f k8s-local/06-frontend.yaml
kubectl apply -f k8s/07-hpa.yaml
kubectl apply -f k8s/08-ingress.yaml
```

Check the system:

```bash
kubectl get all -n url-shortener
kubectl get pvc -n url-shortener
kubectl get hpa -n url-shortener
kubectl get ingress -n url-shortener
```

Add local DNS mapping if needed:

```bash
sudo sh -c 'echo "<NODE-IP> short.local" >> /etc/hosts'
```

Validate from the browser:

```text
http://short.local
```

Validate with curl:

```bash
curl -s http://short.local/health
curl -s http://short.local/ready
curl -s -X POST http://short.local/api/links \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://kubernetes.io/","custom_code":"k8stest"}'
curl -I http://short.local/r/k8stest
```

## Failure Validation

Delete the API Pod:

```bash
kubectl delete pod -l app=url-api -n url-shortener
kubectl get pods -n url-shortener -w
```

Expected result: the Deployment creates replacement Pods.

Delete the database Pod:

```bash
kubectl delete pod postgres-0 -n url-shortener
kubectl get pod postgres-0 -n url-shortener -w
```

Expected result: the StatefulSet recreates `postgres-0`, the same PVC is mounted again, and previously created links remain available.

## Helm Install

After users complete the manual flow, show the one-command install:

```bash
helm install url-shortener ./helm/url-shortener \
  -n url-shortener \
  --create-namespace \
  -f ./helm/url-shortener/values-local.yaml
```

Upgrade with values:

```bash
helm upgrade url-shortener ./helm/url-shortener \
  -n url-shortener \
  --set replicaCount.api=3 \
  --set hpa.maxReplicas=10 \
  --set ingress.host=short.demo.local \
  --set resources.api.requests.cpu=150m
```

Rollback:

```bash
helm rollback url-shortener 1 -n url-shortener
```

## Values Students Can Tune

| Value | Meaning |
|---|---|
| `image.registry` | Empty for local images, public registry namespace for remote images |
| `image.tag` | Product version to deploy |
| `replicaCount.api` | API Pod count before HPA changes it |
| `replicaCount.frontend` | Frontend Pod count |
| `resources.api.requests.cpu` | API CPU request, also the HPA baseline |
| `resources.api.limits.memory` | API memory ceiling |
| `hpa.enabled` | Enable or disable autoscaling |
| `hpa.minReplicas` / `hpa.maxReplicas` | Autoscaling lower and upper bounds |
| `ingress.host` | Public hostname |
| `postgres.storageSize` | PostgreSQL PVC size |
| `secret.postgresPassword` | Lab database password placeholder |

## Cleanup

```bash
kubectl delete namespace url-shortener
```

## Instructor Local Smoke Test

If the Kubernetes cluster is unavailable, instructors can still verify the app locally with Docker:

```bash
./local-smoke-test.sh
```

The script starts PostgreSQL, runs the migration, starts the API and frontend, adds a local nginx gateway to mimic Ingress, validates health/readiness/create/list/redirect behavior, recreates the API container, checks data still exists, and then removes all test containers and the test network.
