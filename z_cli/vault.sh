Wdrażanie całego stacku:
bash
# 1. Zastosuj kustomization
kubectl apply -k .

# 2. Sprawdź status wszystkich zasobów
kubectl get all -n davtrowebdbvault

# 3. Sprawdź szczególnie problematyczne zasoby
kubectl get jobs -n davtrowebdbvault
kubectl get statefulsets -n davtrowebdbvault
kubectl get daemonsets -n davtrowebdbvault

# 4. Sprawdź logi inicjalizacji
kubectl logs -n davtrowebdbvault job/vault-init
kubectl logs -n davtrowebdbvault job/create-kafka-topics
🔧 Rozwiązywanie typowych problemów:
Jeśli Vault Job się nie udaje:
bash
# Sprawdź czy Vault Service działa
kubectl get svc vault -n davtrowebdbvault

# Sprawdź logi Vault Pod
kubectl logs -n davtrowebdbvault -l component=vault

# Ręczna inicjalizacja Vault
kubectl exec -n davtrowebdbvault -it deployment/vault -- /bin/sh
vault status
vault secrets list
Jeśli Kafka Topics Job się nie udaje:
bash
# Sprawdź czy Kafka działa
kubectl logs -n davtrowebdbvault -l component=kafka

# Ręczne utworzenie topic
kubectl exec -n davtrowebdbvault -it kafka-0 -- /bin/sh
/opt/bitnami/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
📊 Testowanie endpointów:
bash
# Przekierowanie portów do testowania
kubectl port-forward -n davtrowebdbvault svc/grafana-service 8080:80 &
kubectl port-forward -n davtrowebdbvault svc/prometheus-service 9090:9090 &
kubectl port-forward -n davtrowebdbvault svc/kafka-ui 8081:8080 &

# Dostęp przez przeglądarkę:
# Grafana: http://localhost:8080 (admin/admin)
# Prometheus: http://localhost:9090
# Kafka UI: http://localhost:8081s