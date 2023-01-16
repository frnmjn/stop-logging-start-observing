#!/bin/sh

set -e

helm repo add grafana https://grafana.github.io/helm-charts 
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add cert-manager https://charts.jetstack.io
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add traefik https://traefik.github.io/charts
helm repo add bitnami https://charts.bitnami.com/bitnami 
helm repo update

echo "########################################"
echo "GRAFANA"
echo "########################################"
kubectl apply -f grafana/secret.yaml
kubectl apply -f grafana/pizzify-dashboard.yaml
helm upgrade --install --wait  grafana grafana/grafana --version 6.52.1 -f grafana/values.yaml

echo "########################################"
echo "SMTP"
echo "########################################"
kubectl apply -f smtp/
kubectl wait pods -n default -l app=smtp4dev --for condition=Ready --timeout=180s


echo "########################################"
echo "PROMETHEUS"
echo "########################################"
helm upgrade --install --wait prometheus-stack prometheus-community/kube-prometheus-stack --version 45.6.0 -f prometheus/values.yaml
kubectl apply -f prometheus/prometheus-auto-discovery.yaml
kubectl apply -f prometheus/prometheus-stack-roles.yaml

echo "########################################"
echo "LOKI"
echo "########################################"
helm upgrade --install --wait loki-stack grafana/loki-stack --version 2.9.9 -f loki/values.yaml

echo "########################################"
echo "CERT MANAGER"
echo "########################################"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml
helm upgrade --install --wait cert-manager cert-manager/cert-manager --version 1.11.0

echo "########################################"
echo "JAEGER"
echo "########################################"
helm upgrade --install --wait jaeger jaegertracing/jaeger-operator --version 2.40.0 --set jaeger.create=true,rbac.clusterRole=true

echo "########################################"
echo "OPENTELEMETRY"
echo "########################################"
helm upgrade --install --wait opentelemetry-operator open-telemetry/opentelemetry-operator --version 0.24.1 
kubectl apply -f opentelemetry/otel-collector.yaml

echo "########################################"
echo "TRAEFIK"
echo "########################################"
helm upgrade --install --wait traefik traefik/traefik --version 21.1.0 -f traefik/values.yaml
kubectl apply -f traefik/traefik-routing.yaml

echo "########################################"
echo "RABBIT OPERATOR"
echo "########################################"
kubectl rabbitmq install-cluster-operator
kubectl wait pods -n rabbitmq-system -l app.kubernetes.io/name=rabbitmq-cluster-operator --for condition=Ready --timeout=180s
echo "########################################"
echo "RABBIT CLUSTER"
echo "########################################"
kubectl rabbitmq create rabbitmq --replicas 1
sleep 5
kubectl wait pods -n default -l app.kubernetes.io/name=rabbitmq --for condition=Ready --timeout=180s
echo "########################################"
echo "RABBIT USER"
echo "########################################"
kubectl exec -it svc/rabbitmq -- rabbitmqctl add_user 'app' 'password'
kubectl exec -it svc/rabbitmq -- rabbitmqctl set_permissions -p "/" app ".*" ".*" ".*"
kubectl exec -it svc/rabbitmq -- rabbitmqctl set_user_tags app  monitoring

echo "########################################"
echo "POSTGRES"
echo "########################################"
helm upgrade --install --wait db-order bitnami/postgresql --version 12.2.2 --set global.postgresql.auth.postgresPassword=postgres --set global.postgresql.auth.database=pizzify_order_dev
helm upgrade --install --wait db-job bitnami/postgresql --version 12.2.2 --set global.postgresql.auth.postgresPassword=postgres --set global.postgresql.auth.database=pizzify_job_dev


echo "########################################"
echo "PIZZIFY"
echo "########################################"
kubectl apply -f pizzify/
kubectl wait pods -n default -l app=pizzify-order --for condition=Ready --timeout=180s
kubectl wait pods -n default -l app=pizzify-job --for condition=Ready --timeout=180s
kubectl wait pods -n default -l app=pizzify-fleet1 --for condition=Ready --timeout=180s
kubectl wait pods -n default -l app=pizzify-fleet2 --for condition=Ready --timeout=180s
kubectl wait pods -n default -l app=pizzify-fleet3 --for condition=Ready --timeout=180s
kubectl wait pods -n default -l app=pizzify-ui --for condition=Ready --timeout=180s

