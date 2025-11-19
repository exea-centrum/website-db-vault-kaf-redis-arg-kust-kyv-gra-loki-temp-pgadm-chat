KROKI NAPRAWCZE:
Krok 1: Sprawdź status wszystkich zasobów
bash
kubectl get all -n davtrowebdbvault
kubectl get pvc -n davtrowebdbvault
kubectl get configmaps -n davtrowebdbvault
Krok 2: Zastosuj brakujące Services (jeśli potrzebne)
bash
kubectl apply -f missing-services.yaml
Krok 3: Zaktualizuj Kafka-UI
bash
kubectl delete -f kafka-ui.yaml
kubectl apply -f kafka-ui.yaml
Krok 4: Sprawdź logi initContainers
bash
# Sprawdź dlaczego initContainers nie kończą pracy
kubectl describe pod -n davtrowebdbvault -l component=worker
kubectl describe pod -n davtrowebdbvault -l component=postgres-exporter
kubectl describe pod -n davtrowebdbvault -l component=fastapi

# Sprawdź logi konkretnych initContainers
kubectl logs -n davtrowebdbvault message-processor-69f8d5f75f-dtgdl -c wait-for-services
Krok 5: Sprawdź connectivity między podami
bash
# Sprawdź czy serwisy są dostępne
kubectl run test-connectivity -n davtrowebdbvault --image=busybox:1.35 -it --rm --restart=Never -- sh

# Wewnątrz sprawdź:
nc -z postgres-db 5432 && echo "PostgreSQL OK" || echo "PostgreSQL FAIL"
nc -z redis 6379 && echo "Redis OK" || echo "Redis FAIL" 
nc -z kafka 9092 && echo "Kafka OK" || echo "Kafka FAIL"
nc -z vault 8200 && echo "Vault OK" || echo "Vault FAIL"