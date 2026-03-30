#!/usr/bin/env julia
# scripts/k8s_deployment.jl — Kubernetes deployment manifest generator
# Chapter 47 — Open-Source Healthcare GIS Textbook in Julia
#
# Generates production-grade Kubernetes manifests for the Healthcare GIS API:
#   - Deployment (rolling update, health checks, resource limits)
#   - Service (ClusterIP + optional LoadBalancer)
#   - HorizontalPodAutoscaler (CPU + memory-based)
#   - ConfigMap (application configuration)
#   - PodDisruptionBudget (HA guarantee)
#   - Ingress (NGINX, TLS)

# ── Configuration ─────────────────────────────────────────────────────────────

struct K8sConfig
    namespace          :: String
    app_name           :: String
    image              :: String
    image_tag          :: String
    replicas           :: Int
    cpu_request        :: String
    cpu_limit          :: String
    memory_request     :: String
    memory_limit       :: String
    port               :: Int
    health_path        :: String
    min_replicas       :: Int
    max_replicas       :: Int
    target_cpu_pct     :: Int
    postgres_host      :: String
    julia_threads      :: Int
    tls_secret         :: String
    ingress_host       :: String
end

function K8sConfig(;
    namespace      = "healthcare-gis",
    app_name       = "healthcare-gis-api",
    image          = "ghcr.io/timothyhartzog/geo-julia",
    image_tag      = "v0.7.0",
    replicas       = 3,
    cpu_request    = "500m",
    cpu_limit      = "2000m",
    memory_request = "512Mi",
    memory_limit   = "2Gi",
    port           = 8080,
    health_path    = "/api/v2/health",
    min_replicas   = 2,
    max_replicas   = 10,
    target_cpu_pct = 70,
    postgres_host  = "postgres-service",
    julia_threads  = 4,
    tls_secret     = "healthcare-gis-tls",
    ingress_host   = "api.healthcaregis.example.com",
)
    K8sConfig(namespace, app_name, image, image_tag, replicas,
              cpu_request, cpu_limit, memory_request, memory_limit,
              port, health_path, min_replicas, max_replicas, target_cpu_pct,
              postgres_host, julia_threads, tls_secret, ingress_host)
end

# ── YAML generation helpers ───────────────────────────────────────────────────

function indent(s::String, n::Int)
    pad = " " ^ n
    join(pad .* split(s, "\n"), "\n")
end

function k8s_labels(cfg::K8sConfig)
    """
      app: $(cfg.app_name)
      version: "$(cfg.image_tag)"
      managed-by: geo-julia"""
end

# ── Namespace manifest ────────────────────────────────────────────────────────

function gen_namespace(cfg::K8sConfig)
    """
apiVersion: v1
kind: Namespace
metadata:
  name: $(cfg.namespace)
  labels:
    name: $(cfg.namespace)
"""
end

# ── ConfigMap ────────────────────────────────────────────────────────────────

function gen_configmap(cfg::K8sConfig)
    """
apiVersion: v1
kind: ConfigMap
metadata:
  name: $(cfg.app_name)-config
  namespace: $(cfg.namespace)
data:
  JULIA_NUM_THREADS: "$(cfg.julia_threads)"
  JULIA_DEPOT_PATH: "/opt/julia/depot"
  APP_PORT: "$(cfg.port)"
  POSTGRES_HOST: "$(cfg.postgres_host)"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "healthcare_gis"
  ENABLE_REALTIME_SSE: "true"
  DRIFT_CHECK_INTERVAL_MINS: "30"
  MODEL_REGISTRY_PATH: "/data/model_registry"
  LOG_LEVEL: "info"
"""
end

# ── Deployment ────────────────────────────────────────────────────────────────

function gen_deployment(cfg::K8sConfig)
    """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $(cfg.app_name)
  namespace: $(cfg.namespace)
  labels:
$(k8s_labels(cfg))
  annotations:
    deployment.kubernetes.io/revision: "1"
spec:
  replicas: $(cfg.replicas)
  selector:
    matchLabels:
      app: $(cfg.app_name)
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
$(k8s_labels(cfg))
    spec:
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: $(cfg.app_name)
          image: $(cfg.image):$(cfg.image_tag)
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: $(cfg.port)
              protocol: TCP
          envFrom:
            - configMapRef:
                name: $(cfg.app_name)-config
            - secretRef:
                name: $(cfg.app_name)-secrets
          resources:
            requests:
              cpu: "$(cfg.cpu_request)"
              memory: "$(cfg.memory_request)"
            limits:
              cpu: "$(cfg.cpu_limit)"
              memory: "$(cfg.memory_limit)"
          livenessProbe:
            httpGet:
              path: $(cfg.health_path)
              port: $(cfg.port)
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: $(cfg.health_path)
              port: $(cfg.port)
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 3
            successThreshold: 1
            failureThreshold: 5
          startupProbe:
            httpGet:
              path: $(cfg.health_path)
              port: $(cfg.port)
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30   # allow 5 min for JIT compilation
          volumeMounts:
            - name: model-data
              mountPath: /data/model_registry
            - name: julia-depot
              mountPath: /opt/julia/depot
      volumes:
        - name: model-data
          persistentVolumeClaim:
            claimName: $(cfg.app_name)-pvc
        - name: julia-depot
          emptyDir: {}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: $(cfg.app_name)
                topologyKey: kubernetes.io/hostname
"""
end

# ── Service ───────────────────────────────────────────────────────────────────

function gen_service(cfg::K8sConfig)
    """
apiVersion: v1
kind: Service
metadata:
  name: $(cfg.app_name)-service
  namespace: $(cfg.namespace)
  labels:
$(k8s_labels(cfg))
spec:
  type: ClusterIP
  selector:
    app: $(cfg.app_name)
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: $(cfg.port)
  sessionAffinity: None
"""
end

# ── HPA ───────────────────────────────────────────────────────────────────────

function gen_hpa(cfg::K8sConfig)
    """
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $(cfg.app_name)-hpa
  namespace: $(cfg.namespace)
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $(cfg.app_name)
  minReplicas: $(cfg.min_replicas)
  maxReplicas: $(cfg.max_replicas)
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: $(cfg.target_cpu_pct)
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
"""
end

# ── PodDisruptionBudget ───────────────────────────────────────────────────────

function gen_pdb(cfg::K8sConfig)
    """
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $(cfg.app_name)-pdb
  namespace: $(cfg.namespace)
spec:
  minAvailable: $(cfg.min_replicas)
  selector:
    matchLabels:
      app: $(cfg.app_name)
"""
end

# ── Ingress ───────────────────────────────────────────────────────────────────

function gen_ingress(cfg::K8sConfig)
    """
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $(cfg.app_name)-ingress
  namespace: $(cfg.namespace)
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - $(cfg.ingress_host)
      secretName: $(cfg.tls_secret)
  rules:
    - host: $(cfg.ingress_host)
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: $(cfg.app_name)-service
                port:
                  number: 80
"""
end

# ── PVC (model storage) ───────────────────────────────────────────────────────

function gen_pvc(cfg::K8sConfig)
    """
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $(cfg.app_name)-pvc
  namespace: $(cfg.namespace)
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
"""
end

# ── Main: write all manifests ─────────────────────────────────────────────────

"""
    generate_k8s_manifests(cfg; output_dir) -> Vector{String}

Generate all Kubernetes manifests to `output_dir`.
Returns list of written file paths.
"""
function generate_k8s_manifests(
    cfg        :: K8sConfig = K8sConfig();
    output_dir :: String    = joinpath(tempdir(), "k8s-healthcare-gis"),
    dry_run    :: Bool      = false,
)
    manifests = [
        ("00-namespace.yaml",  gen_namespace(cfg)),
        ("01-configmap.yaml",  gen_configmap(cfg)),
        ("02-pvc.yaml",        gen_pvc(cfg)),
        ("03-deployment.yaml", gen_deployment(cfg)),
        ("04-service.yaml",    gen_service(cfg)),
        ("05-hpa.yaml",        gen_hpa(cfg)),
        ("06-pdb.yaml",        gen_pdb(cfg)),
        ("07-ingress.yaml",    gen_ingress(cfg)),
    ]

    paths = String[]
    if !dry_run
        mkpath(output_dir)
    end

    println("Kubernetes manifests for: $(cfg.app_name) [$(cfg.namespace)]")
    println("Image: $(cfg.image):$(cfg.image_tag)\n")

    for (fname, content) in manifests
        fpath = joinpath(output_dir, fname)
        push!(paths, fpath)
        if !dry_run
            write(fpath, content)
        end
        n_lines = length(split(content, "\n"))
        println("  ✓ $fname ($n_lines lines)")
    end

    println("\nDeploy with:")
    println("  kubectl apply -f $output_dir/")
    println("\nMonitor:")
    println("  kubectl -n $(cfg.namespace) get pods -w")
    println("  kubectl -n $(cfg.namespace) logs -f deploy/$(cfg.app_name)")

    paths
end

"""
    generate_github_workflow_cd(cfg; output_path) -> String

Generate a GitHub Actions CD workflow that builds and pushes the Docker image,
then rolls out the new deployment.
"""
function generate_github_workflow_cd(
    cfg         :: K8sConfig = K8sConfig();
    output_path :: String    = ".github/workflows/deploy.yml",
    dry_run     :: Bool      = false,
)
    content = """
name: Deploy Healthcare GIS API

on:
  push:
    tags:
      - 'v*.*.*'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: \${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Log in to container registry
        uses: docker/login-action@v3
        with:
          registry: \${{ env.REGISTRY }}
          username: \${{ github.actor }}
          password: \${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: \${{ env.REGISTRY }}/\${{ env.IMAGE_NAME }}
          tags: |
            type=semver,pattern={{version}}
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: \${{ steps.meta.outputs.tags }}
          labels: \${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Set up kubectl
        uses: azure/setup-kubectl@v3

      - name: Configure kubeconfig
        run: echo "\${{ secrets.KUBECONFIG_B64 }}" | base64 -d > \$HOME/.kube/config

      - name: Update image tag
        run: |
          kubectl -n $(cfg.namespace) set image \\
            deployment/$(cfg.app_name) \\
            $(cfg.app_name)=$(cfg.image):\${{ github.ref_name }}

      - name: Wait for rollout
        run: |
          kubectl -n $(cfg.namespace) rollout status \\
            deployment/$(cfg.app_name) --timeout=10m

      - name: Verify health
        run: |
          sleep 10
          kubectl -n $(cfg.namespace) exec \\
            deploy/$(cfg.app_name) -- \\
            curl -sf http://localhost:$(cfg.port)$(cfg.health_path)
"""
    if !dry_run && !isempty(output_path)
        mkpath(dirname(output_path))
        write(output_path, content)
        println("  ✓ CD workflow → $output_path")
    end
    content
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    cfg = K8sConfig()
    generate_k8s_manifests(cfg)
end
