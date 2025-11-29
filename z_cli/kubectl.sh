kubectl -n davtrowebdbvault run gen-id --restart=Never --rm -i --image=confluentinc/cp-kafka:7.5.0 -- /opt/confluent/bin/kafka-storage random-uuid
 python3 -c "import uuid; print(str(uuid.uuid4()))"
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui && git add manifests/base/kafka-kraft.yaml lmarena.sh && git commit -m "kafka: set valid CLUSTER_ID (UUID format)" && git push
 kubectl -n davtrowebdbvault rollout restart statefulset/kafka && sleep 3 && kubectl -n davtrowebdbvault get pods -o wide && sleep 2 && kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=20
 kubectl -n davtrowebdbvault set env statefulset/kafka CLUSTER_ID="00b0bc82-e1aa-4de0-8530-7dd209a3af28" KAFKA_CLUSTER_ID="00b0bc82-e1aa-4de0-8530-7dd209a3af28" && sleep 2 && kubectl -n davtrowebdbvault rollout restart statefulset/kafka && sleep 5 && echo "=== Kafka pod status ===" && kubectl -n davtrowebdbvault get pod kafka-0 && echo "=== Last 15 lines of kafka container logs ===" && kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=15 2>&1 || echo "(logs not yet available)"
 echo "Deleting kafka pod and PVC to start fresh..."
 kubectl -n davtrowebdbvault delete pod kafka-0 --wait=true
 sleep 2
 kubectl -n davtrowebdbvault delete pvc kafka-data-kafka-0 --wait=true
 kubectl -n davtrowebdbvault delete pod kafka-0 --wait=true
 sleep 5 && kubectl -n davtrowebdbvault get pods -o wide | grep kafka
 sleep 3 && kubectl -n davtrowebdbvault logs kafka-0 -c kafka 2>&1 | head -40
 kubectl -n davtrowebdbvault delete pod kafka-0 && sleep 2 && kubectl -n davtrowebdbvault get pod kafka-0 -w &
 sleep 10 && kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=30
 sleep 3 && kubectl -n davtrowebdbvault get pod kafka-0 -o wide
 kubectl -n davtrowebdbvault get pod kafka-0
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka 2>&1
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui && git add manifests/base/kafka-kraft.yaml lmarena.sh && git commit -m "kafka: clean data directory on startup and auto-generate CLUSTER_ID" && git push
 git add manifests/base/kafka-kraft.yaml lmarena.sh && git commit -m "kafka: clean data directory on startup and auto-generate CLUSTER_ID" && git push
 kubectl -n davtrowebdbvault delete pod kafka-0 && sleep 5 && kubectl -n davtrowebdbvault logs kafka-0 -c kafka 2>&1 | head -50
 # Zacommituj zmiany
 git add manifests/base/kafka-kraft.yaml lmarena.sh
 git commit -m "kafka: clean data dir on init and auto-generate CLUSTER_ID"
 git push
 # Zrestartuj pod
 kubectl -n davtrowebdbvault delete pod kafka-0
 sleep 10
 # Sprawdź logi
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 # Sprawdź status
 kubectl -n davtrowebdbvault describe pod kafka-0
 git add manifests/base/kafka-kraft.yaml lmarena.sh && git commit -m "kafka: switch to bitnami/kafka:3.6.1 with proper KRaft support" && git push
 kubectl -n davtrowebdbvault delete statefulset kafka && sleep 3 && kubectl -n davtrowebdbvault apply -f manifests/base/kafka-kraft.yaml && sleep 5 && kubectl -n davtrowebdbvault get pod kafka-0
 kubectl -n davtrowebdbvault delete pod kafka-0
 sleep 5 && kubectl -n davtrowebdbvault logs kafka-0 -c kafka 2>&1 | head -50
 kubectl -n davtrowebdbvault get pod kafka-0 2>&1
 sleep 10 && kubectl -n davtrowebdbvault get pod kafka-0 && echo "--- Logi ---" && kubectl -n davtrowebdbvault logs kafka-0 -c kafka 2>&1 | tail -40
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=50 2>&1
 kubectl -n davtrowebdbvault describe pod kafka-0 2>&1 | grep -A 20 "Events:"
 kubectl -n davtrowebdbvault delete pod kafka-0 && sleep 3 && kubectl -n davtrowebdbvault get pod kafka-0
 # Przejdź do katalogu
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
 # Zacommituj zmiany
 git add manifests/base/kafka-kraft.yaml lmarena.sh
 git commit -m "kafka: switch to apache/kafka:3.6.0 with auto-generated cluster ID"
 git push
 # Zrestart pod kafka-0
 kubectl -n davtrowebdbvault delete pod kafka-0
 # Czekaj ~15 sekund na odtworzenie
 sleep 15
 # Sprawdź logi
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 # Sprawdź czy pod działa
 kubectl -n davtrowebdbvault get pod kafka-0
 git add manifests/base/kafka-kraft.yaml lmarena.sh
 git commit -m "kafka: return to confluentinc/cp-kafka:7.5.0, let it auto-generate CLUSTER_ID"
 git push
 kubectl -n davtrowebdbvault delete pod kafka-0
 sleep 20
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault get pod kafka-0
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui && git add -A && git commit -m "Fix Kafka image to confluentinc/cp-kafka:7.5.0 with proper env vars" && git push 2>&1 | tail -20
 kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka --previous
 kubectl -n davtrowebdbvault get statefulset kafka -o yaml
 kubectl -n davtrowebdbvault rollout restart statefulset/kafka
 kubectl -n davtrowebdbvault get pods -w
 ./lmarena.sh
 git add manifests/base/kafka-kraft.yaml lmarena.sh
 git commit -m "kafka: add CLUSTER_ID env for Confluent cp-kafka startup"
 git push
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault patch statefulset kafka --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CLUSTER_ID","value":"4mUj5vFk3tW7pY0iH2gR8qL6eD9oB1cZ"}}]'
 ./lmarena.sh
 git add lmarena.sh manifests/base/kafka-kraft.yaml
 git commit -m "kafka: add securityContext + initContainer to fix PVC permissions"
 git push
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault get pvc kafka-data-kafka-0 -o yaml
 # Zrestartuj StatefulSet tak, by nowy template wszedł w życie
 kubectl -n davtrowebdbvault rollout restart statefulset/kafka
 # Obserwuj status podów (przerwij Ctrl-C)
 kubectl -n davtrowebdbvault get pods -w
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault get pvc kafka-data-kafka-0 -o yaml
 kubectl -n davtrowebdbvault exec -it kafka-0 -- ls -la /var/lib/kafka || true
 kubectl -n davtrowebdbvault rollout restart statefulset/kafka
 kubectl -n davtrowebdbvault get pods -w
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka
 kubectl -n davtrowebdbvault logs kafka-0 -c fix-permissions
 kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault get pvc kafka-data-kafka-0 -o yaml
 # (opcjonalnie, debug pod mounting the PVC)
 kubectl -n davtrowebdbvault run -i --rm debug-pod --image=busybox:1.36 --restart=Never -- /bin/sh -c 'ls -la /var/lib/kafka'   --overrides='
   {"spec":{"volumes":[{"name":"kafka-data","persistentVolumeClaim":{"claimName":"kafka-data-kafka-0"}}],"containers":[{"name":"debug","image":"busybox:1.36","volumeMounts":[{"name":"kafka-data","mountPath":"/var/lib/kafka"}],"command":["sh","-c","ls -la /var/lib/kafka && sleep 3600"]}],"restartPolicy":"Never"}}'
 git add 
 git add .
 git commit -m "kafka: add CLUSTER_ID env for Confluent cp-kafka startup"
 git push
 docker run --rm confluentinc/cp-kafka:7.5.0 /opt/confluent/bin/kafka-storage random-uuid
 # albo
 podman run --rm confluentinc/cp-kafka:7.5.0 /opt/confluent/bin/kafka-storage random-uuid
 # uruchamia tymczasowy pod z obrazem confluent, generuje CLUSTER_ID i wyświetla go
 kubectl -n davtrowebdbvault run gen-kid --restart=Never --rm -i --image=confluentinc/cp-kafka:7.5.0 -- /opt/confluent/bin/kafka-storage random-uuid
 # potem patch StatefulSet (przykład automatyczny, zastąpi/uzupełni env CLUSTER_ID)
 kubectl -n davtrowebdbvault patch statefulset kafka --type=json -p="[ {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/env/-\",\"value\":{\"name\":\"CLUSTER_ID\",\"value\":\"<WYG_GENEROWANY_ID>\"}} ]"
 # restart
 kubectl -n davtrowebdbvault rollout restart statefulset/kafka
 kubectl -n davtrowebdbvault get pods -w
 history
 ledon
 k9s
 rm -f /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui/manifests/base/zookeeper.yaml /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui/manifests/base/kafka-config.yaml
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui && kubectl -n davtrowebdbvault delete statefulset kafka --ignore-not-found=true && sleep 5
 kubectl apply -f manifests/base/kafka-kraft-config.yaml && kubectl apply -f manifests/base/kafka-kraft.yaml
 kubectl -n davtrowebdbvault get pods -w -l component=kafka --max-log-requests=1
 kubectl -n davtrowebdbvault get pods -l component=kafka && sleep 15 && kubectl -n davtrowebdbvault logs kafka-0 --tail=50
 kubectl -n davtrowebdbvault delete statefulset kafka && sleep 3 && kubectl apply -f manifests/base/kafka-kraft.yaml && sleep 20 && kubectl -n davtrowebdbvault logs kafka-0 --tail=100
 kubectl -n davtrowebdbvault delete statefulset kafka && sleep 3 && kubectl apply -f manifests/base/kafka-kraft.yaml && sleep 25 && kubectl -n davtrowebdbvault get pods -l component=kafka && kubectl -n davtrowebdbvault logs kafka-0 --tail=80 | grep -A 20 "started"
 kubectl -n davtrowebdbvault logs kafka-0 --tail=150
 rm -f /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui/manifests/base/kafka-kraft-config.yaml
 rm manifests/base/kafka-topic-job.yaml
 kubectl delete statefulset kafka --ignore-not-found=true && sleep 3 && kubectl apply -f manifests/base/kafka-config.yaml && kubectl apply -f manifests/base/kafka-kraft.yaml && sleep 25 && kubectl -n davtrowebdbvault get pods -l component=kafka && echo "---LOGS---" && kubectl -n davtrowebdbvault logs kafka-0 --tail=100
 kubectl -n davtrowebdbvault delete statefulset kafka --cascade=orphan && sleep 5 && kubectl apply -f manifests/base/kafka-kraft.yaml && sleep 25 && kubectl -n davtrowebdbvault get pods -l component=kafka && echo "---LOGS---" && kubectl -n davtrowebdbvault logs kafka-0 --tail=120
 git add .
 git commit -m "apache:kafka 4.1"
 git push
 git add .
 git commit -m "apache:kafka 4.1"
 git push
 kubectl -n davtrowebdbvault get pods -w
 kubectl -n davtrowebdbvault get pods -w
 git add .
 git add manifests/base/{app-deployment.yaml,message-processor.yaml,kafka-exporter.yaml,kafka-ui.yaml} && git commit -m "fix: use consistent apache/kafka:4.1.0 image and correct script paths in all initContainers" && git push origin main
 git add .
 git commit -m "v197"
 git push
 kubectl -n davtrowebdbvault get pods -l component=kafka-exporter -o name && POD=$(kubectl -n davtrowebdbvault get pods -l component=kafka-exporter -o jsonpath='{.items[0].metadata.name}'); echo "pod=$POD"; kubectl -n davtrowebdbvault describe pod $POD || true; echo '--- initContainer logs ---'; kubectl -n davtrowebdbvault logs $POD -c wait-for-kafka || true; echo '--- main container logs ---'; kubectl -n davtrowebdbvault logs $POD -c kafka-exporter || true
 kubectl -n davtrowebdbvault exec -it kafka-exporter-84b978f7fb-d5r5q -c wait-for-kafka -- /bin/bash -c "echo 'resolv.conf:'; cat /etc/resolv.conf; echo 'hosts lookup:'; getent hosts kafka-0.kafka.davtrowebdbvault.svc.cluster.local || true; echo 'tcp test:'; timeout 3 bash -c '</dev/tcp/kafka-0.kafka.davtrowebdbvault.svc.cluster.local/9092' && echo OPEN || echo CLOSED"
 kubectl -n davtrowebdbvault exec -it kafka-exporter-84b978f7fb-d5r5q -c wait-for-kafka -- /bin/bash -c "echo 'try short kafka:'; getent hosts kafka || true; echo 'try kafka.davtrowebdbvault.svc.cluster.local:'; getent hosts kafka.davtrowebdbvault.svc.cluster.local || true; echo 'try pod dns without service:'; getent hosts kafka-0 || true; echo 'nslookup not available'"
 kubectl -n davtrowebdbvault get svc kafka -o yaml
 kubectl -n davtrowebdbvault get endpoints kafka -o yaml
 kubectl -n davtrowebdbvault get pod kafka-0 -o wide && kubectl -n davtrowebdbvault describe pod kafka-0
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=200
 kubectl -n davtrowebdbvault exec -it kafka-0 -c kafka -- /bin/bash -c 'echo "--- server.properties ---"; cat /etc/kafka-config/server.properties || true; echo "--- /opt/kafka/config/kraft/server.properties ---"; cat /opt/kafka/config/kraft/server.properties || true'
 kubectl -n davtrowebdbvault get configmap kafka-config -o yaml
 git add manifests/base/kafka-config.yaml && git commit -m "fix(kafka): set numeric log.flush.interval.ms to avoid crash" || true && git push || true
 kubectl -n davtrowebdbvault rollout restart deployment kafka-exporter || true; kubectl -n davtrowebdbvault rollout restart statefulset kafka || true; sleep 5; kubectl -n davtrowebdbvault get pods -o wide | sed -n '1,200p'
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=200
 kubectl -n davtrowebdbvault logs kafka-0 -c kafka --tail=200
 kubectl -n davtrowebdbvault describe pod kafka-0
 echo '== PODS ==' && kubectl -n davtrowebdbvault get pods -o wide && echo; echo '== DESCRIBE: fastapi deployment ==' && kubectl -n davtrowebdbvault describe deployment fastapi-web-app || true && echo; for p in fastapi-web-app-5fc5dd9498-fvs7l fastapi-web-app-5fc5dd9498-rdpgk message-processor-56dbd8f767-fb5mz kafka-exporter-99c9cb6d5-llrhs kafka-ui-858998899b-fvxdq pgadmin-64444d459b-jsjrj postgres-exporter-5797b5d55f-56dkx promtail-pjl8b; do echo; echo "== DESCRIBE POD $p =="; kubectl -n davtrowebdbvault describe pod $p || true; echo; echo "== LOGS: pod $p (all containers, last 200 lines) =="; kubectl -n davtrowebdbvault logs $p --all-containers --tail=200 || true; echo; echo "== LOGS: init wait-for-kafka (if present) for $p =="; kubectl -n davtrowebdbvault logs $p -c wait-for-kafka --tail=200 || true; echo "== LOGS: init wait-for-kafka-topics (if present) for $p =="; kubectl -n davtrowebdbvault logs $p -c wait-for-kafka-topics --tail=200 || true; echo "== LOGS: init wait-for-postgres (if present) for $p =="; kubectl -n davtrowebdbvault logs $p -c wait-for-postgres --tail=200 || true; done
 for p in fastapi-web-app-578857796-p7pmr fastapi-web-app-578857796-z4bq8 message-processor-6dcb99c785-47qps kafka-ui-76d95c84c8-sqrj7 pgadmin-64444d459b-pzbsz postgres-exporter-5797b5d55f-cdbf9; do echo; echo "==== DESCRIBE $p ===="; kubectl -n davtrowebdbvault describe pod $p || true; echo; echo "==== LOGS init wait-for-postgres for $p ===="; kubectl -n davtrowebdbvault logs $p -c wait-for-postgres --tail=200 || true; echo; echo "==== LOGS init wait-for-redis for $p ===="; kubectl -n davtrowebdbvault logs $p -c wait-for-redis --tail=200 || true; echo; echo "==== LOGS init wait-for-kafka for $p ===="; kubectl -n davtrowebdbvault logs $p -c wait-for-kafka --tail=200 || true; echo; echo "==== LOGS init wait-for-kafka-topics for $p ===="; kubectl -n davtrowebdbvault logs $p -c wait-for-kafka-topics --tail=200 || true; done
 kubectl -n davtrowebdbvault get svc postgres-db -o wide; echo; kubectl -n davtrowebdbvault get endpoints postgres-db -o yaml || true; echo; kubectl -n davtrowebdbvault exec kafka-0 -- sh -c "echo '--- /etc/resolv.conf ---' && cat /etc/resolv.conf || true"; echo; kubectl -n davtrowebdbvault exec kafka-0 -- sh -c "echo '--- getent hosts postgres-db ---' && getent hosts postgres-db || true"; echo; kubectl -n davtrowebdbvault exec kafka-0 -- sh -c "echo '--- nc to postgres-db:5432 ---' && (nc -zv postgres-db 5432 && echo OK) || (echo NC_FAIL)"
 kubectl -n davtrowebdbvault run --rm -i --tty pgtest --image=postgres:15-alpine --restart=Never --env="PGPASSWORD=testpassword" --command -- sh -c "pg_isready -h postgres-db -p 5432 -U webuser; echo exit:$?"
 git add manifests/base/kafka-ui.yaml manifests/base/pgadmin.yaml && git commit -m "fix(kafka-ui,pgadmin): use apache/kafka:4.1.0 for kafka-ui init and pg_isready for pgadmin init" || true
 git push origin main
 kubectl get pods -n davtrowebdbvault -w 
 kubectl -n davtrowebdbvault get pods -o wide && echo && echo "=== KAFKA-UI INIT LOGS ===" && kubectl -n davtrowebdbvault logs kafka-ui-57d988c4bb-t229b -c wait-for-kafka --tail=50
 kubectl -n davtrowebdbvault get pods -o wide | grep -E "kafka-ui|pgadmin|fastapi|message|postgres-exporter" && echo && echo "=== Current ReplicaSets ===" && kubectl -n davtrowebdbvault get rs -o wide | grep -E "kafka-ui|pgadmin"
 echo "=== KAFKA-UI (new) INIT LOGS ===" && kubectl -n davtrowebdbvault logs kafka-ui-57d988c4bb-t229b -c wait-for-kafka --tail=30 && echo && echo "=== PGADMIN (new) INIT LOGS ===" && kubectl -n davtrowebdbvault logs pgadmin-545f6469fb-wrd9k -c wait-for-postgres --tail=30
 echo "=== KAFKA STATUS ===" && kubectl -n davtrowebdbvault get svc kafka -o wide && echo && kubectl -n davtrowebdbvault describe svc kafka && echo && echo "=== TEST KAFKA FROM RUNNING POD ===" && kubectl -n davtrowebdbvault exec kafka-0 -- /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka:9092 2>&1 | head -20
 kubectl -n davtrowebdbvault exec kafka-ui-57d988c4bb-t229b -c wait-for-kafka -- sh -c "echo '=== nslookup kafka-0.kafka.davtrowebdbvault.svc.cluster.local ===' && nslookup kafka-0.kafka.davtrowebdbvault.svc.cluster.local 2>&1; echo; echo '=== nc test ===' && (nc -zv kafka-0.kafka.davtrowebdbvault.svc.cluster.local 9092 && echo OK) || echo FAIL"
 git add manifests/base/kafka-ui.yaml manifests/base/app-deployment.yaml manifests/base/message-processor.yaml && git commit -m "fix: use kafka Headless Service DNS instead of kafka-0.kafka.* for init containers to avoid DNS timeout issues" && git push origin main
 sleep 5 && kubectl -n davtrowebdbvault get pods | grep -E "kafka-ui|pgadmin|fastapi|message" && echo && echo "=== TEST: nc to kafka.davtrowebdbvault.svc.cluster.local:9092 from kafka-0 ===" && kubectl -n davtrowebdbvault exec kafka-0 -- nc -zv kafka.davtrowebdbvault.svc.cluster.local 9092
 sleep 15 && kubectl -n davtrowebdbvault logs kafka-ui-679bd8d7fc-gfnnx -c wait-for-kafka --tail=20 2>&1 || echo "pod still initializing" && echo && kubectl -n davtrowebdbvault logs fastapi-web-app-555b8f675b-t2z4f -c wait-for-postgres --tail=20 2>&1 || echo "pod still initializing"
 kubectl -n davtrowebdbvault exec kafka-ui-679bd8d7fc-gfnnx -c wait-for-kafka -- sh -c "echo '=== cat /etc/resolv.conf ===' && cat /etc/resolv.conf && echo && echo '=== getent hosts kafka.davtrowebdbvault.svc.cluster.local ===' && (getent hosts kafka.davtrowebdbvault.svc.cluster.local || echo FAIL) && echo && echo '=== nc to kafka:9092 ===' && (nc -zv kafka 9092 && echo OK) || echo FAIL"
 kubectl -n davtrowebdbvault run --rm -i --image=apache/kafka:4.1.0 --restart=Never kafka-test-dns -- sh -c 'echo "=== /etc/resolv.conf ===" && cat /etc/resolv.conf && echo && echo "=== getent kafka ===" && (getent hosts kafka.davtrowebdbvault.svc.cluster.local || echo FAIL) && echo && echo "=== kafka-broker-api-versions ===" && (/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server kafka:9092 2>&1 | head -5)'
 git add manifests/base/kafka-ui.yaml manifests/base/app-deployment.yaml manifests/base/message-processor.yaml manifests/base/pgadmin.yaml && git commit -m "fix: remove init containers to avoid DNS resolution issues; rely on liveness/readiness probes" && git push origin main
 sleep 10 && kubectl -n davtrowebdbvault get pods | grep -E "kafka-ui|pgadmin|fastapi|message|postgres-exporter" && echo && echo "=== Waiting for some pods to reach Running ===" && sleep 20 && kubectl -n davtrowebdbvault get pods -o wide | head -20
 cd /home/david/k8s-all/backu-peexea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-gra-loki-temp-pgui
 kubectl -n davtrowebdbvault logs kafka-0 -c fix-permissions
 kubectl -n davtrowebdbvault get pods -w