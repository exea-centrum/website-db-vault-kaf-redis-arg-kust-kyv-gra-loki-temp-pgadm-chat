Widzę problem! W katalogu manifests/base/ znajdują się zduplikowane pliki, które powodują konflikt w ArgoCD. Konkretnie, pliki postgres-exporter.copy i postgres-db.copy2 zawierają zduplikowane definicje Service, które już istnieją w oryginalnych plikach.

🔧 Rozwiązanie:
1. Usuń zduplikowane pliki
bash
# Usuń pliki kopii, które powodują konflikty
rm manifests/base/postgres-exporter.copy
rm manifests/base/postgres-db.copy2
2. Sprawdź czy w pliku message-processor.yaml nie ma zduplikowanego Service
Jeśli w message-processor.yaml jest zdefiniowany Service, usuń go, tak aby pozostał tylko Deployment.

3. Zaktualizuj kustomization.yaml
Upewnij się, że w kustomization.yaml nie ma odwołań do usuniętych plików.

4. Synchronizuj ArgoCD
Po usunięciu duplikatów, synchronizuj aplikację w ArgoCD.

🚀 Kroki naprawcze:
Krok 1: Usuń zduplikowane pliki
bash
cd manifests/base/
rm -f postgres-exporter.copy postgres-db.copy2
Krok 2: Sprawdź zawartość message-processor.yaml
bash
cat message-processor.yaml
Upewnij się, że plik zawiera tylko Deployment, a nie Service. Jeśli zawiera Service, usuń tę sekcję.

Krok 3: Sprawdź kustomization.yaml
bash
cat kustomization.yaml
Upewnij się, że nie ma w nim odwołań do usuniętych plików.

Krok 4: Synchronizuj ArgoCD
bash
argocd app sync website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
✅ Po naprawie:
ArgoCD powinien móc wygenerować manifesty bez błędów.

Wszystkie zasoby powinny być unikalne.

Jeśli problem nadal występuje, sprawdź czy nie ma innych zduplikowanych plików lub definicji w pozostałych plikach.

Znaleziono problem! Masz zduplikowane pliki w katalogu manifests/base/:

postgres-exporter.copy

postgres-db.copy2

Te pliki zawierają zduplikowane definicje Service, które powodują konflikt w ArgoCD.

🔧 Rozwiązanie:
1. Usuń zduplikowane pliki
bash
# Przejdź do katalogu manifests
cd manifests/base/

# Usuń zduplikowane pliki
rm postgres-exporter.copy postgres-db.copy2

# Sprawdź czy zostały usunięte
ls -la | grep copy
2. Sprawdź czy message-processor.yaml zawiera Service
bash
# Sprawdź zawartość message-processor.yaml
grep -A 10 "kind: Service" message-processor.yaml

# Jeśli zawiera Service, usuń tę sekcję lub usuń cały plik jeśli to tylko Service
3. Zaktualizuj kustomization.yaml
Sprawdź czy w resources nie ma odwołań do usuniętych plików:

bash
# Sprawdź kustomization.yaml
grep -E "postgres-exporter\.copy|postgres-db\.copy2" kustomization.yaml

# Jeśli są, usuń te linie
4. Synchronizuj ArgoCD
bash
# Synchronizuj aplikację
argocd app sync website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui

# Lub przez UI: Refresh -> Sync
🚀 Szybka naprawa - usuń wszystkie pliki kopii:
bash
# Usuń wszystkie pliki .copy w katalogu manifests/base/
cd manifests/base/
rm -f *.copy*
rm -f *copy*
rm -f *backup*
🔍 Dodatkowe sprawdzenie:
Sprawdź czy nie ma innych zduplikowanych plików:

bash
# Sprawdź wszystkie pliki yaml
ls -la *.yaml

# Sprawdź czy nie ma duplikatów o podobnych nazwach
find . -name "*.yaml" -type f | sort

Najpierw usuń utknięte pody:

bash
kubectl delete pod -n davtrowebdbvault --all --force --grace-period=0
2. Zastosuj wszystkie poprawione manifesty w odpowiedniej kolejności:

Krok 1: Podstawowe usługi

bash
# Najpierw bazy danych i Redis
kubectl apply -f manifests/base/postgres-db.yaml
kubectl apply -f manifests/base/redis.yaml

# Poczekaj aż będą gotowe
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=postgres -n davtrowebdbvault --timeout=300s
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=redis -n davtrowebdbvault --timeout=300s
Krok 2: Vault i Kafka

bash
kubectl apply -f manifests/base/vault.yaml
kubectl apply -f manifests/base/kafka-kraft.yaml

# Poczekaj na Vault i Kafka
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=vault -n davtrowebdbvault --timeout=300s
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui,component=kafka -n davtrowebdbvault --timeout=300s
