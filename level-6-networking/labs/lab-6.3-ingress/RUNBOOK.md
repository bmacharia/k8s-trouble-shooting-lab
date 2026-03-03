# Lab 6.3 — Ingress: 503s and 413s

## Symptoms

- **Symptom A:** `GET /` returns `503 Service Unavailable` from the nginx Ingress controller.
- **Symptom B:** `POST /api/v1/upload` returns `413 Request Entity Too Large` for files > 1MB.
  Small test files succeed. The app itself handles large files fine when called directly.

---

## Lab Setup

```bash
# Requires nginx-ingress-controller installed in your cluster
# Install with: helm upgrade --install ingress-nginx ingress-nginx \
#   --repo https://kubernetes.github.io/ingress-nginx \
#   --namespace ingress-nginx --create-namespace

kubectl apply -f 00-setup.yaml
kubectl apply -f 01-app.yaml
kubectl apply -f 02-ingress-broken.yaml

kubectl rollout status deployment/frontend -n webapp
kubectl rollout status deployment/upload-service -n webapp
```

---

## The Ingress Connection Chain

```
Browser
  │
  ▼
LoadBalancer / NodePort (ingress-nginx Service)
  │
  ▼
nginx-ingress-controller pod
  │  matches host + path rules
  ▼
Backend Service (by name + port)
  │
  ▼
Endpoints → Pod
```

**503** = nginx could not reach the backend (wrong service name, no endpoints, unhealthy pods)
**413** = nginx rejected the request before it reached the app (body size limit)
**502** = nginx reached the backend but got a bad response (app error, wrong port)
**504** = nginx reached the backend but it timed out (app slow, wrong timeout annotation)

---

## Investigation — Symptom A (503 Service Unavailable)

### Step 1 — Check the Ingress resource

```bash
# View ingress details — look at Rules and Backend
kubectl describe ingress webapp-ingress -n webapp

# Key section to read:
# Rules:
#   Host: webapp.local
#   Path: /
#   Backend: frontend:80  <- does this service exist?
```

### Step 2 — Verify the backend service name is correct

```bash
# What service does the Ingress reference?
kubectl get ingress webapp-ingress -n webapp \
  -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'

# Does that service actually exist?
kubectl get svc -n webapp
# Compare the two — any mismatch causes 503
```

### Step 3 — Check nginx-ingress controller logs

```bash
# This is where 503 causes are logged explicitly
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100 | \
  grep -E "error|warn|upstream|503"

# Look for:
# "service not found"     → wrong service name
# "no endpoints"          → service exists but no ready pods
# "upstream timed out"    → pods are slow or wrong port
# "upstream connect error" → pods not accepting connections
```

### Step 4 — Check if the backend service has endpoints

```bash
# First find the actual service name
kubectl get svc -n webapp

# Check endpoints for the correct service
kubectl get endpoints frontend-svc -n webapp

# If Endpoints: <none> → pods are not ready or selector mismatch
# If endpoints exist but 503 persists → Ingress is pointing to wrong name
```

### Step 5 — Test the backend service directly (bypass Ingress)

```bash
# Port-forward the service directly
kubectl port-forward svc/frontend-svc 8888:80 -n webapp &

# Hit it
curl http://localhost:8888/
# If this works → the problem is in the Ingress configuration, not the app
kill %1
```

---

## Investigation — Symptom B (413 Request Entity Too Large)

### Step 1 — Confirm the error is from nginx, not the app

```bash
# 413 from nginx has a specific HTML body:
curl -X POST http://webapp.local/api/v1/upload \
  -F "file=@/path/to/large-file.bin" \
  -v 2>&1 | head -30

# If response body contains "nginx" and status is 413 → nginx limit hit
# Test with a tiny file:
echo "tiny" | curl -X POST http://webapp.local/api/v1/upload -d @-
# If tiny file succeeds → definitely a body size limit issue
```

### Step 2 — Check the Ingress annotations

```bash
# What annotations does the upload Ingress have?
kubectl get ingress upload-ingress -n webapp -o yaml | grep annotations -A 20

# Look for proxy-body-size. If missing or absent → nginx uses its 1MB default.
# The default is set in the nginx configmap but overridden per-ingress via annotation.
```

### Step 3 — Check the nginx global configuration

```bash
# Check the nginx configmap for global defaults
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | \
  grep -i "body-size\|client_max_body_size"

# If not set → default is 1m (1 megabyte)
```

### Step 4 — Check the rendered nginx.conf inside the controller

```bash
# This shows the actual nginx config being used — ground truth
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
  cat /etc/nginx/nginx.conf | grep -i "client_max_body_size"

# Each server block should show the annotation-derived value
# If it shows "client_max_body_size 1m" → annotation is missing or not applied
```

---

## Log Analysis

```bash
# nginx-ingress access logs — see actual requests and response codes
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=200 | \
  grep -E '"(GET|POST|PUT)' | awk '{print $0}' | tail -20

# nginx-ingress error logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=200 | \
  grep -iE "error|crit|emerg"

# Ingress events — configuration errors show here
kubectl get events -n webapp --field-selector reason=Sync | tail -10
kubectl get events -n ingress-nginx | tail -10

# Watch real-time ingress controller logs during a test
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f &
curl http://webapp.local/    # trigger the request
```

---

## Common Causes

| Code | Cause | Where to look |
|------|-------|---------------|
| 503 | Wrong backend service name in Ingress | `kubectl describe ingress` → compare service name to `kubectl get svc` |
| 503 | Backend service has no endpoints | `kubectl get endpoints <svc>` shows `<none>` |
| 503 | Backend pods not Ready (failing readiness probe) | `kubectl describe pod` → Conditions |
| 413 | Missing `proxy-body-size` annotation | `kubectl get ingress -o yaml` → check annotations |
| 413 | Body size in annotation too small | Annotation exists but value is too low |
| 502 | Wrong `targetPort` in backend service | Direct pod test works, service test fails |
| 504 | `proxy-read-timeout` too short | App is slow, need to increase timeout annotation |
| 404 | Wrong `path` or `pathType` in Ingress rule | Test exact path, check `Prefix` vs `Exact` |

---

## Resolution

```bash
# Apply the fixes
kubectl apply -f 03-solution.yaml

# Verify ingress updated
kubectl describe ingress webapp-ingress -n webapp
# Backend should now show: frontend-svc:80

kubectl describe ingress upload-ingress -n webapp
# Annotations should show: proxy-body-size: 50m

# Test fix A
curl -v http://webapp.local/
# Expected: 200 OK with nginx default page

# Test fix B — create a test file > 1MB
dd if=/dev/urandom of=/tmp/test-5mb.bin bs=1M count=5
curl -X POST http://webapp.local/api/v1/upload \
  -F "file=@/tmp/test-5mb.bin" -v
# Expected: 200 OK (or whatever the upload service returns — not 413)
```

---

## Prevention

```bash
# 1. Validate Ingress backend services exist before applying
kubectl get svc -n webapp | grep -E "frontend-svc|upload-svc"

# 2. Use IngressClass explicitly to avoid ambiguity
#    ingressClassName: nginx   (spec field, not annotation)
#    Annotation approach is deprecated

# 3. Always set these annotations for production Ingresses:
#    nginx.ingress.kubernetes.io/proxy-body-size: "10m"     # explicit, not default
#    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
#    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"

# 4. Check Ingress health after every deploy
kubectl describe ingress -n <namespace> | grep -A 5 "Events"
# A healthy ingress shows "Sync" events with no errors

# 5. Use `kubectl ingress-nginx lint` (plugin) to catch annotation typos
```

---

## Cleanup

```bash
kubectl delete namespace webapp
```
