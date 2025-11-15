Widzę, że większość usług działa, ale są problemy:

FastAPI web app ma initContainers, które jeszcze nie zakończyły się (STATUS: Init:0/4). Oznacza to, że initContainers wciąż czekają na gotowość zależności.

Kafka UI w stanie CrashLoopBackOff - prawdopodobnie problem z połączeniem do Kafki.

Redis zgłasza "SECURITY ATTACK" - to może być spowodowane przez probe (health check) które wysyłają komendy HTTP do portu Redis (6379). Redis oczekuje komend Redis, a nie HTTP.

Najpierw sprawdźmy, co się dzieje z initContainers FastAPI:

bash
kubectl logs -n davtrowebdbvault fastapi-web-app-77f568d5c7-6nh5n -c wait-for-dependencies
Jeśli initContainers utknęły, to może być problem z rozpoznawaniem nazw lub z dostępnością usług.

Sprawdźmy też, czy usługi są dostępne z wewnątrz klastra:

bash
# Sprawdźmy, czy initContainer może rozpoznać nazwy usług
kubectl run -it --rm test-nslookup --image=busybox:1.35 --restart=Never -- nslookup kafka
kubectl run -it --rm test-nslookup --image=busybox:1.35 --restart=Never -- nslookup postgres-db
kubectl run -it --rm test-nslookup --image=busybox:1.35 --restart=Never -- nslookup vault
kubectl run -it --rm test-nslookup --image=busybox:1.35 --restart=Never -- nslookup redis

# Sprawdźmy, czy porty są otwarte
kubectl run -it --rm test-netcat --image=busybox:1.35 --restart=Never -- telnet kafka 9092
kubectl run -it --rm test-netcat --image=busybox:1.35 --restart=Never -- telnet postgres-db 5432
kubectl run -it --rm test