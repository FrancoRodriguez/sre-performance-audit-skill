---
name: sre-performance-audit
description: Guía SRE y pautas de rendimiento, arquitectura, observabilidad, base de datos (PostgreSQL), caché (Redis), servidor (Puma) y alertas para Volley Manager.
---

# SRE & Performance Audit Guidelines

Esta skill proporciona la guía técnica, runbooks de diagnóstico, consultas SQL de optimización y la matriz de observabilidad SRE para mantener **Volley Manager** funcionando con alto rendimiento, baja latencia y alta disponibilidad bajo picos de carga síncrona.

---

## 1. Servidor Web (Puma) y Concurrencia

### Reglas de Configuración en Volley Manager
- **Modo Cluster en Producción ([`config/puma.rb`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/config/puma.rb)):**
  - Habilitado dinámicamente mediante `workers_count = ENV.fetch("WEB_CONCURRENCY") { ENV["RAILS_ENV"] == "production" ? 2 : 0 }`.
  - **Copy-on-Write (CoW):** Utiliza `preload_app!` para precargar la aplicación antes de bifurcar los trabajadores, reduciendo el consumo de RAM hasta un 35%.
  - **Reconexión de Socket DB:** Implementa `on_worker_boot { ActiveRecord::Base.establish_connection }` para evitar colisiones de sockets entre trabajadores.
- **Hilos por Worker:** Mantiene `RAILS_MAX_THREADS` (por defecto 3-5) para balancear throughput frente al GVL de Ruby MRI.
- **Asignador de Memoria (`jemalloc`):** En contenedores Linux de producción, precarga `jemalloc` (`LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2`) para prevenir la fragmentación de memoria.
- **Single-Line Logging:** Usa la gema `lograge` configurada en [`config/environments/production.rb`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/config/environments/production.rb) para omitir peticiones a assets/healthcheck y emitir logs limpios de una sola línea.

---

## 2. Base de Datos (PostgreSQL), Índices Compuestos y Observabilidad

### Dashboard de Rendimiento de DB en Tiempo Real
- **Ubicación:** Accesible para Super Admins en `/super_admins/dashboard?tab=db_performance` (controlado por [`SuperAdmins::DashboardController`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/app/controllers/super_admins/dashboard_controller.rb)).
- **Métricas:** Ordenadas por mayor criticidad (`idx_use_pct ASC NULLS FIRST, seq_scan DESC`) con badges visuales (🔴 $<50\%$, 🟡 $50-80\%$, 🟢 $>80\%$).

### Índices Compuestos Creados ([`db/migrate/20260727233000_add_performance_composite_indexes.rb`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/db/migrate/20260727233000_add_performance_composite_indexes.rb))
Todas las adiciones de índices en producción se realizan con `disable_ddl_transaction!` y `algorithm: :concurrently` (Zero Downtime):
1. `teams`: `[:club_id, :active]` (Resuelve ~465k escaneos secuenciales).
2. `roster_entries`: `[:team_id, :season_id, :active]` (Resuelve ~400k escaneos secuenciales).
3. `clubs`: `[:fmvoley_sync_enabled, :trial_period_active]` (Resuelve ~240k escaneos secuenciales).
4. `matches`: `[:team_id, :season_id, :start_time]` (Resuelve ~233k escaneos secuenciales).
5. `users`: `[:club_id, :role]` (Resuelve ~220k escaneos secuenciales).
6. `team_coaches`: `[:team_id, :season_id]` (Resuelve ~104k escaneos secuenciales).
7. `standings`: `[:season_id, :team_id]` (Resuelve ~38k escaneos secuenciales).
8. `attendances`: `[:training_session_id, :player_id, :status]` (Resuelve ~31k escaneos secuenciales).

### Alineación del Pool de Conexiones
- **Regla del Pool:** En [`config/database.yml`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/config/database.yml), `pool` se configura dinámicamente con `ENV.fetch("RAILS_MAX_THREADS") { 5 }`.
- **Fórmula de Conexiones Totales:**
  $$\text{Conexiones a DB} = (\text{Workers Puma} \times \text{RAILS\_MAX\_THREADS}) + \text{Conexiones de Background Workers}$$

---

## 3. Caché e Invalidación Eficiente

### Estrategia de Caché de Estadísticas y Fragmentos
- **Invalidación en Cascada (`touch: true`):** Todo modelo hijo que altere el estado de un partido (ej. `MatchEvent`) DEBE declarar `belongs_to :match, touch: true`. Esto actualiza automáticamente `updated_at` en `Match`, invalidando las claves de caché de `TeamStatsService` y marcadores en directo.
- **Evaporación de Redis Cache:** Configura la instancia de Redis usada para `ActiveSupport::Cache::RedisCacheStore` con la política `maxmemory-policy volatile-lru` para evitar errores de memoria agotada (`OOM`).

---

## 4. Observabilidad y Señales de Oro (SRE Golden Signals)

### Métricas Clave y Objetivos
1. **HTTP P95 Latency:** $< 250\text{ ms}$ para vistas HTML/Turbo Stream; $< 100\text{ ms}$ para respuestas JSON/API.
2. **Tasa de Errores (5xx):** $< 0.1\%$ del total de peticiones.
3. **Apdex Target:** $> 0.95$ con límite de tolerancia $T = 300\text{ ms}$.
4. **Queue Lag de Background Jobs:** Latencia de encolamiento $< 2\text{ s}$.

### Matriz de Alertas Críticas

| Métrica | Warning | Critical | Acción Recomendada |
| :--- | :--- | :--- | :--- |
| **HTTP P95 Latency** | $> 400\text{ ms}$ (5 min) | $> 1000\text{ ms}$ (2 min) | Auto-escalar pods Puma / Diagnosticar slow queries |
| **Error Rate (5xx)** | $> 0.5\%$ (5 min) | $> 2.0\%$ (1 min) | Alertar a guardia Sentry/Slack, revisar DB/Redis |
| **DB Pool Saturation** | $> 75\%$ | $> 90\%$ | Incrementar pool size / Desplegar PgBouncer |
| **CPU Server Web** | $> 70\%$ continuo | $> 85\%$ (5 min) | Escalar horizontalmente instancias Puma |
| **Redis RAM** | $> 80\%$ asignada | $> 92\%$ asignada | Revisar expiración de llaves / Escalar Redis |

---

## 5. Resiliencia y Rate Limiting

### Protección contra Tráfico Abusivo
- **Rack::Attack ([`config/initializers/rack_attack.rb`](file:///Users/franco.rodriguez/Documents/code/personal/volley_manager/config/initializers/rack_attack.rb)):** Limita peticiones de actualización de marcador a 120 req/min por IP y limita tráfico general a 1000 req/5min por IP, bloqueando bots sospechosos.
- **Timeouts en HTTP Externo:** Las integraciones externas (envío de correos por Resend/AWS SES, scraping de FMVOLEY) DEBEN incluir timeouts estrictos (ej. `open_timeout: 2`, `read_timeout: 5`) para evitar bloquear los hilos síncronos de Puma.
- **Descarga Asíncrona:** El procesamiento de background jobs (envío de push notifications, optimización de imágenes, sincronizaciones de tablas) NUNCA debe ejecutarse sincrónicamente en el hilo del controlador de Rails.

---

## 6. Script de Prueba de Carga Simulado (k6)

Utiliza este script de `k6` para verificar la capacidad del servidor antes de eventos masivos o partidos:

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp-up a 50 usuarios
    { duration: '1m', target: 100 },  // Pico de 100 usuarios concurrentes
    { duration: '30s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'], // P95 por debajo de 300ms
    http_req_failed: ['rate<0.01'],    // Menos de 1% de fallos
  },
};

export default function () {
  const res = http.get('https://vmanager.club/matches');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```
