# Talk conductor — guion ↔ grabaciones

**Hilo:** tres islas → cableado (Skupper) → confianza E-W (Linkerd) → política N-S (429) → sobrevivir (failover) → CTA  
**A** = Francisco · **B** = Sergio  
**Media (fuera de git):** `/home/fmeneses/Videos/kcd-ba-demo-backup/`  
**Regla:** live primero · si se atasca ≤~2 min → **play clip** → seguir narrando (no pelear)

Guion base archivado: [`../archive/2026-09-28-kcd-ba-talk-deck/scripts.md`](../archive/2026-09-28-kcd-ba-talk-deck/scripts.md) · Comandos: [`stage-commands.md`](./stage-commands.md)

---

## Mapa rápido slide → clip

| Slide | Owner | Live (preferido) | Backup a mostrar si falla / como refuerzo | Archivo |
|------:|-------|------------------|-------------------------------------------|---------|
| 1–6 | A/B | Solo slides (sin media) | — | — |
| **7** | B | `make demo-skupper` | Cast Skupper | `kcd-ba-01-skupper.cast` |
| **7** (opc.) | B | Observer UI `:8443` | WebM observer | `kcd-ba-07-ui-c.webm` |
| **8** | B | `make demo-mesh` | Cast mesh | `kcd-ba-02-mesh.cast` |
| **8** (opc.) | B | Viz `:50750` | WebM Viz | `kcd-ba-06-ui-b.webm` |
| **9** | A | `make demo-ratelimit` → **429** | Cast 429 | `kcd-ba-03-ratelimit-429.cast` |
| **9** (opc.) | A | Browser app `:8080` | WebM app | `kcd-ba-05-ui-a.webm` |
| **10** | A | `make failover` | Cast failover | `kcd-ba-04-failover.cast` |
| 11–12 | A+B | CTA / Q&A | — | — |

**Orden narrativo de clips (si hay que “mostrar el film” entero en emergencia):**  
`01-skupper` → `02-mesh` → `03-ratelimit-429` → `04-failover` · UI solo si sobra tiempo: `07` con slide 7, `06` con 8, `05` con 9.

Replay cast: `asciinema play ~/Videos/kcd-ba-demo-backup/kcd-ba-<id>.cast`

---

## Conductor por fase (qué decir + qué poner en pantalla)

### Acto 0 — Framing (slides 1–6) · ~0–9 min · sin grabación

| Slide | Dueño | En pantalla | Qué anclar (1 frase) |
|------:|-------|-------------|----------------------|
| 1 | A+B | Título | “Tres sitios en una laptop: políticas, mesh y failover.” |
| 2 | A+B | Quiénes | A = N-S + failover · B = topo + Skupper + mesh |
| 3 | A | Problema | Sitios rotos / RateLimit / caída del primario |
| 4 | B | Agenda | Interconectar → E-W → N-S → failover · **nunca** `kind-cluster` |
| 5 | B | Diagrama topo | west hub · east spoke · podman-edge (community slide; logo-light) |
| 5× | B (opc.) | Extras aparte | Appendix / speaker-owned: real-world AKS+EKS+edge + nutshell — [`../kcd-ba-arch-diagrams/`](../kcd-ba-arch-diagrams/); visual-only, **no Make cue**; skip on overrun before Option-C |
| 6 | B | Historia | “De tres islas a un fabric — ahora en vivo.” |

**Puente B→live:** “Primero el cableado entre Kind y Podman.”

---

### Acto 1 — Cablear el borde (slide 7) · B · ~9–12 min

**Historia:** sin VAN no hay legacy-emoji / edge en el mismo plano.

| Modo | Pantalla | Acción |
|------|----------|--------|
| **Live** | Terminal | `make demo-skupper` · opcional `curl -sS http://127.0.0.1:18080/` |
| **Backup** | Terminal / player | `asciinema play …/kcd-ba-01-skupper.cast` |
| **Refuerzo UI** (si hay tiempo y `make ui` OK) | Browser | Live `:8443` **o** `kcd-ba-07-ui-c.webm` (sin mostrar secretos) |

**Cierre B:** “Misma app lógica, un hop que cruza el borde.”  
**No pasar a mesh** hasta que Skupper “se vea” (live o cast 01).

---

### Acto 2 — Confiar adentro del cluster (slide 8) · B · ~12–16 min

**Historia:** Skupper une sitios; Linkerd da identidad E-W **dentro** del mesh.

| Modo | Pantalla | Acción |
|------|----------|--------|
| **Live** | Terminal | `make demo-mesh` |
| **Backup** | Player | `…/kcd-ba-02-mesh.cast` |
| **Refuerzo UI** | Browser | Viz `:50750` **o** `kcd-ba-06-ui-b.webm` |

**Contraste verbal:** mesh **dentro** vs Skupper **entre** sitios.  
**Handoff B→A:** “Pasamos al borde north-south.”

---

### Acto 3 — Gobernar la entrada (slide 9) · A · ~16–20 min

**Historia:** el cliente choca con política — RateLimit → **HTTP 429** (wow N-S).

| Modo | Pantalla | Acción |
|------|----------|--------|
| **Live** | Terminal | `make demo-ratelimit` → ver ≥1 **429** |
| **Backup** | Player | `…/kcd-ba-03-ratelimit-429.cast` (**must**) |
| **Refuerzo UI** | Browser | `http://emojivoto.demo.local:8080/` (Host) **o** `kcd-ba-05-ui-a.webm` |

**Cierre A:** “La política vive en el Gateway path — no en la app.”  
**Puente a failover:** “¿Y si cae el primario?”

---

### Acto 4 — Sobrevivir (slide 10) · A · ~20–25 min

**Historia:** west duele → CoreDNS / east sigue en la historia HA.

| Modo | Pantalla | Acción |
|------|----------|--------|
| **Live** | Terminal | `make failover` (≤~120s; script restaura al salir) |
| **Backup** | Player | `…/kcd-ba-04-failover.cast` (**must**) |

**Si flake ~2 min:** cortar live → play **04** → narrar dig/east → takeaways.  
**No** pelear con `weight: 0`.

---

### Acto 5 — Cierre (slides 11–12) · A+B · ~25–30 min

| Slide | Pantalla | Mensaje |
|------:|----------|---------|
| 11 | Slide CTA | `make up` → `make smoke` → optional `make ui` → `make down` · cuatro wows = cuatro clips 01–04 |
| 12 | Gracias | Q&A; ofrecer UI / clips si alguien pregunta “¿cómo se ve?” |

---

## Checklist de operador (pantalla lista)

Antes del talk (off-clock):

- [ ] Carpeta media abierta o playlist lista: `01` `02` `03` `04` (+ opc. `05`–`07`)
- [ ] `asciinema` en PATH (`~/.local/bin`)
- [ ] Terminal grande para live; player listo para casts/webm
- [ ] Stack warm: `smoke` OK; UI pre-warm solo si van a mostrar 05–07
- [ ] Ensayar handoff: fin slide 8 → A toma 9

Durante:

1. Preferir **Make live**.  
2. Si no responde ~2 min → **mismo slide, play clip de la tabla**.  
3. Overrun: cortar UI (05–07) antes que 01–04.

---

## Frases puente (hilo conductor)

1. Slide 6→7: “Primero conectamos las islas.” → **01**  
2. 7→8: “Conectados; ahora confianza adentro.” → **02**  
3. 8→9: “Fuera del mesh: política en el borde.” → **03**  
4. 9→10: “Política no basta si cae el primario.” → **04**  
5. 10→11: “Lo pueden reproducir en casa con Make.” → CTA
