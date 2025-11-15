Ważne kroki przed zastosowaniem:
Usuń istniejące zasoby (jeśli były wcześniej tworzone):

bash
kubectl delete -f kafka-kraft.yaml 2>/dev/null || true
kubectl delete pvc -n davtrowebdbvault -l app=kafka 2>/dev/null || true
Zastosuj nową konfigurację:

bash
kubectl apply -f kafka-kraft.yaml
Sprawdź status:

bash
kubectl get pods -n davtrowebdbvault -l app=kafka -w
Sprawdź logi (poczekaj aż pod będzie uruchomiony):

bash
kubectl logs -n davtrowebdbvault kafka-0
Jeśli nadal występują problemy:
Jeśli Kafka nadal nie startuje, sprawdź czy ConfigMap został poprawnie zamontowany:

bash
# Sprawdź czy ConfigMap istnieje
kubectl get configmap -n davtrowebdbvault kafka-kraft-config

# Sprawdź zawartość ConfigMap
kubectl describe configmap -n davtrowebdbvault kafka-kraft-config

# Sprawdź czy plik jest w kontenerze
kubectl exec -it -n davtrowebdbvault kafka-0 -- ls -la /opt/kafka/config/kraft/

# Sprawdź zawartość pliku konfiguracyjnego
kubectl exec -it -n davtrowebdbvault kafka-0 -- cat /opt/kafka/config/kraft/server.properties
Ten plik zawiera wszystko co potrzebne: ConfigMap z konfiguracją KRaft, Service dla dostępu do Kafki, oraz StatefulSet który montuje ConfigMap jako volume. Powinien rozwiązać problem z brakiem konfiguracji KRaft w domyślnym obrazie Apache Kafka.




Główne zmiany:
initContainers - czekają na gotowość wszystkich usług przed startem aplikacji

Pełne FQDN - używają pełnych nazw domenowych Kubernetes (service.namespace.svc.cluster.local)

Bezpośredni adres Kafka - kafka-0.kafka.davtrowebdbvault.svc.cluster.local:9092 zamiast kafka:9092

Dodatkowe zmienne środowiskowe - DATABASE_URL i PYTHONUNBUFFERED

Zwiększone timeouts - dają więcej czasu na inicjalizację

Sprawdź czy usługi są dostępne:
bash
# Sprawdź czy usługi działają
kubectl get services -n davtrowebdbvault

# Sprawdź czy pody są gotowe
kubectl get pods -n davtrowebdbvault

# Sprawdź logi Vault
kubectl logs -n davtrowebdbvault -l app=vault

# Sprawdź logi PostgreSQL
kubectl logs -n davtrowebdbvault -l component=postgres

# Sprawdź logi Redis
kubectl logs -n davtrowebdbvault -l app=redis

# Sprawdź logi Kafka
kubectl logs -n davtrowebdbvault -l app=kafka
Jeśli nadal masz problemy, sprawdź DNS:
bash
# Sprawdź rozpoznawanie nazw z wewnątrz poda
kubectl run -it --rm debug --image=busybox:1.35 --restart=Never -- nslookup postgres-db.davtrowebdbvault.svc.cluster.local
kubectl run -it --rm debug --image=busybox:1.35 --restart=Never -- nslookup vault.davtrowebdbvault.svc.cluster.local
kubectl run -it --rm debug --image=busybox:1.35 --restart=Never -- nslookup kafka-0.kafka.davtrowebdbvault.svc.cluster.local
Zastosuj te poprawione pliki, a problem z kolejnością uruchamiania i rozpoznawaniem nazw powinien zostać rozwiązany.