#!/bin/bash

set -e

echo "🔍 Verificando si Docker está activo..."
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker no está activo o no disponible en este entorno."
  exit 1
else
  echo "✅ Docker está activo."
fi

# Función para instalar herramientas si no existen
install_if_missing() {
  local cmd=$1
  local install_cmd=$2
  if ! command -v "$cmd" &> /dev/null; then
    echo "📦 Instalando $cmd..."
    eval "$install_cmd"
  else
    echo "✅ $cmd ya está instalado."
  fi
}

# Instalar herramientas necesarias
install_if_missing "kubectl" "curl -LO https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
install_if_missing "kustomize" "curl -s https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash && sudo mv kustomize /usr/local/bin/"
install_if_missing "argocd" "curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x argocd && sudo mv argocd /usr/local/bin/"
install_if_missing "kind" "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"

echo "🚀 Creando clúster de Kubernetes con kind..."
kind create cluster

echo "📁 Creando namespace para ArgoCD..."
kubectl create namespace argocd || echo "ℹ️ Namespace argocd ya existe."

echo "📥 Instalando ArgoCD en el clúster..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Esperando que los pods de ArgoCD estén listos..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s

echo "🔑 Obteniendo contraseña inicial de ArgoCD..."
ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo "🔐 Contraseña admin: $ARGOCD_PWD"

echo "🔄 Haciendo port-forward al servidor ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 5

echo "🔗 Conectando CLI de ArgoCD al servidor..."
argocd login localhost:8080 --username admin --password "$ARGOCD_PWD" --insecure

# Detectar entornos si existen
for env in dev stage prod; do
  if [ -d "./overlays/$env" ]; then
    echo "📦 Detectado entorno '$env'. Puedes aplicar con:"
    echo "  kustomize build overlays/$env | kubectl apply -f -"
  else
    echo "⚠️ Entorno '$env' no encontrado. Puedes crearlo en ./overlays/$env"
  fi
done

echo "✅ Entorno listo. ArgoCD está corriendo y conectado."